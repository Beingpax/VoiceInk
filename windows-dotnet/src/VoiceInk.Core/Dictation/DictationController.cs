using System.Diagnostics;
using VoiceInk.Core.Config;

namespace VoiceInk.Core.Dictation;

public enum Phase { Idle, Recording, Transcribing, Enhancing }

/// <summary>What the UI (tray icon, recorder pill) should show.</summary>
public sealed record DictationStatus(
    Phase Phase,
    string? ModeLabel = null,
    Func<float>? Level = null,
    Func<TimeSpan>? Elapsed = null,
    string? Message = null);

/// <summary>
/// The recording state machine: Idle → Recording → Processing → Idle. It owns no platform code; everything it
/// touches is injected, so it can be driven by any UI and tested without Windows.
/// </summary>
public sealed class DictationController(
    IConfigStore config,
    IAudioCapture capture,
    IForeground foreground,
    ITextOutput output,
    ISoundPlayer sounds,
    ISystemMuter muter,
    IHistoryStore history,
    INotifier notifier)
{
    private static readonly TimeSpan MuteDelay = TimeSpan.FromMilliseconds(250);

    private readonly object _gate = new();
    private Recording? _recording;
    private Job? _job;
    private long _nextJob;

    public event Action<DictationStatus>? StatusChanged;

    /// <summary>Raised after a pipeline run finished, so dashboards can refresh.</summary>
    public event Action<HistoryEntry>? EntryAdded;

    public DictationStatus Status { get; private set; } = new(Phase.Idle);

    public bool IsBusy => Status.Phase != Phase.Idle;

    private sealed class Recording
    {
        public required IRecordingSession Recorder { get; init; }
        public required ForegroundTarget Target { get; init; }
        public required TriggerKind Kind { get; init; }
        public required Task<string?>? Selection { get; init; }
        public string? ClipboardText { get; init; }
        public bool StartedByPress { get; set; }
        public IDisposable? Mute { get; set; }
        public CancellationTokenSource Lifetime { get; } = new();
    }

    private sealed class Job(long id, nint target, TriggerKind kind)
    {
        public long Id { get; } = id;
        public nint Target { get; } = target;
        public TriggerKind Kind { get; } = kind;
        public CancellationTokenSource Cancel { get; } = new();
    }

    private AppConfig Config => config.Current;

    private void SetStatus(DictationStatus status)
    {
        Status = status;
        StatusChanged?.Invoke(status);
    }

    // -- hotkeys ------------------------------------------------------------

    public void HandleHotkey(HotkeyEvent e)
    {
        lock (_gate)
        {
            var threshold = TimeSpan.FromMilliseconds(Config.Hotkeys.HybridThresholdMs);
            switch (e.Kind)
            {
                case HotkeyEventKind.Down:
                    if (_recording is not null) StopRecording();
                    else if (_job is null) StartRecording(byPress: true, e.Trigger);
                    break;

                case HotkeyEventKind.Up:
                    if (_recording is { StartedByPress: true } r && r.Kind == e.Trigger)
                    {
                        var stop = Config.Hotkeys.Mode switch
                        {
                            HotkeyMode.PushToTalk => true,
                            HotkeyMode.Hybrid => r.Recorder.Elapsed >= threshold,
                            _ => false,
                        };
                        // Short tap: keep recording until the next press.
                        if (stop) StopRecording();
                        else r.StartedByPress = false;
                    }

                    break;

                case HotkeyEventKind.Abort:
                    if (_recording is { StartedByPress: true } a && a.Kind == e.Trigger && a.Recorder.Elapsed < threshold)
                    {
                        CancelRecording(playSound: false);
                    }

                    break;

                case HotkeyEventKind.Cancel:
                    CancelAll();
                    break;

                case HotkeyEventKind.PasteLast:
                    if (!IsBusy) PasteLast();
                    break;
            }
        }
    }

    /// <summary>Tray "Start/Stop/Cancel": starts, stops or cancels depending on the state.</summary>
    public void Toggle()
    {
        lock (_gate)
        {
            if (_recording is not null) StopRecording();
            else if (_job is not null) CancelAll();
            else StartRecording(byPress: false, TriggerKind.Dictation);
        }
    }

    public void CancelAll()
    {
        lock (_gate)
        {
            if (_recording is not null) CancelRecording(playSound: true);
            else if (_job is not null) CancelJob();
        }
    }

    public void PasteLast()
    {
        var text = history.LastText();
        if (text is null)
        {
            notifier.Notify("Nothing to paste", "There is no transcription yet.", NoticeKind.Info);
            return;
        }

        _ = DeliverAsync(new Delivery(text, OutputMode.Paste, null, SendKey.None), 0);
    }

    // -- recording ----------------------------------------------------------

    private void StartRecording(bool byPress, TriggerKind kind)
    {
        config.Reload();
        var cfg = Config;
        var target = foreground.Capture();
        foreground.Restore(target.Handle);

        var resolved = Modes.Resolve(cfg, Modes.Match(cfg.Modes, target.Info));
        var clipboard = resolved.UseClipboardContext ? output.ClipboardText() : null;

        if (cfg.Audio.PlaySounds) sounds.Play(Cue.Start, cfg.Audio.StartSound);

        IRecordingSession recorder;
        try
        {
            recorder = capture.Start(cfg.Audio.InputDevice);
        }
        catch (Exception ex)
        {
            notifier.Notify("Could not start recording", ex.Message, NoticeKind.Error);
            return;
        }

        // Command Mode always needs the selection; dictation only as AI context.
        var command = kind == TriggerKind.Command;
        var selection = command || resolved.UseSelectedTextContext ? Task.Run(output.CopySelectionAsync) : null;

        var recording = new Recording
        {
            Recorder = recorder,
            Target = target,
            Kind = kind,
            Selection = selection,
            ClipboardText = clipboard,
            StartedByPress = byPress,
        };
        _recording = recording;

        if (cfg.Audio.MuteSystemAudio) _ = MuteAfterDelayAsync(recording);

        SetStatus(new DictationStatus(
            Phase.Recording,
            ModeLabel: command ? "Command" : resolved.ModeName,
            Level: () => recorder.Level,
            Elapsed: () => recorder.Elapsed));
    }

    private async Task MuteAfterDelayAsync(Recording recording)
    {
        try
        {
            await Task.Delay(MuteDelay, recording.Lifetime.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        lock (_gate)
        {
            if (_recording == recording) recording.Mute = muter.Mute();
        }
    }

    private void EndRecording(Recording recording)
    {
        _recording = null;
        recording.Lifetime.Cancel();
        recording.Mute?.Dispose();
    }

    private void CancelRecording(bool playSound)
    {
        if (_recording is not { } recording) return;
        EndRecording(recording);
        recording.Recorder.Cancel();
        if (playSound && Config.Audio.PlaySounds) sounds.Play(Cue.Cancel, null);
        SetStatus(new DictationStatus(Phase.Idle));
    }

    private void StopRecording()
    {
        if (_recording is not { } recording) return;
        EndRecording(recording);

        var elapsed = recording.Recorder.Elapsed;
        float[] samples;
        try
        {
            samples = recording.Recorder.Finish();
        }
        catch (Exception ex)
        {
            SetStatus(new DictationStatus(Phase.Idle));
            notifier.Notify("Recording failed", ex.Message, NoticeKind.Error);
            return;
        }

        if (Config.Audio.PlaySounds) sounds.Play(Cue.Stop, Config.Audio.StopSound);
        if (elapsed < TimeSpan.FromMilliseconds(Config.Audio.MinRecordingMs) || samples.Length == 0)
        {
            SetStatus(new DictationStatus(Phase.Idle));
            return;
        }

        var job = new Job(++_nextJob, recording.Target.Handle, recording.Kind);
        _job = job;
        SetStatus(new DictationStatus(Phase.Transcribing));
        _ = RunJobAsync(job, recording, samples);
    }

    // -- processing ---------------------------------------------------------

    private async Task RunJobAsync(Job job, Recording recording, float[] samples)
    {
        var command = recording.Kind == TriggerKind.Command;
        PipelineOutput result;
        try
        {
            // Copying usually finishes within ~100 ms; Command Mode waits a bit longer for it.
            var wait = TimeSpan.FromMilliseconds(command ? 600 : 50);
            string? selected = null;
            if (recording.Selection is { } selection && await Task.WhenAny(selection, Task.Delay(wait)) == selection)
            {
                selected = await selection;
            }

            var input = new PipelineInput
            {
                Samples = samples,
                Foreground = recording.Target.Info,
                ClipboardText = recording.ClipboardText,
                SelectedText = selected,
                Command = command,
            };
            AppConfig snapshot;
            lock (_gate) snapshot = Config;
            result = await Pipeline.RunAsync(snapshot, input, job.Cancel.Token, stage =>
            {
                lock (_gate)
                {
                    if (_job == job) SetStatus(new DictationStatus(stage == Stage.Enhancing ? Phase.Enhancing : Phase.Transcribing));
                }
            });
        }
        catch (Exception ex)
        {
            result = new PipelineOutput
            {
                Entry = new HistoryEntry { Status = EntryStatus.Failed, Text = ex.Message },
                Error = ex.Message,
            };
        }

        Complete(job, result);
    }

    private void Complete(Job job, PipelineOutput result)
    {
        Delivery? delivery;
        lock (_gate)
        {
            var current = _job == job && !job.Cancel.IsCancellationRequested;
            if (!current)
            {
                result.Entry.Status = EntryStatus.Canceled;
                result.Delivery = null;
            }

            if (Config.History.Enabled) history.Append(result.Entry, Config.History.MaxEntries);
            if (!current)
            {
                EntryAdded?.Invoke(result.Entry);
                return;
            }

            _job = null;
            delivery = result.Delivery;
            if (result.Error is { } error)
            {
                var title = job.Kind == TriggerKind.Command ? "Command failed" : "Transcription failed";
                SetStatus(new DictationStatus(Phase.Idle, Message: title));
                notifier.Notify(title, error, NoticeKind.Error);
            }
            else
            {
                SetStatus(new DictationStatus(Phase.Idle));
            }

            if (result.Warning is { } warning) notifier.Notify("VoiceInk", warning, NoticeKind.Warning);
        }

        EntryAdded?.Invoke(result.Entry);
        if (delivery is not null) _ = DeliverAsync(delivery, job.Target);
    }

    private void CancelJob()
    {
        if (_job is not { } job) return;
        job.Cancel.Cancel();
        _job = null;
        if (Config.Audio.PlaySounds) sounds.Play(Cue.Cancel, null);
        SetStatus(new DictationStatus(Phase.Idle));
    }

    private async Task DeliverAsync(Delivery delivery, nint target)
    {
        try
        {
            if (delivery.Output == OutputMode.Paste) foreground.Restore(target);
            await output.DeliverAsync(delivery, Config.Output, target, CancellationToken.None).ConfigureAwait(false);
        }
        catch (OutputException e)
        {
            notifier.Notify("Could not insert text", e.Message, NoticeKind.Warning);
        }
    }
}
