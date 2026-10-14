using System.Diagnostics;
using VoiceInk.Core.Audio;
using VoiceInk.Core.Config;
using VoiceInk.Core.Enhancement;
using VoiceInk.Core.Text;
using VoiceInk.Core.Transcription;

namespace VoiceInk.Core;

public enum Stage { Transcribing, Enhancing }

public sealed class PipelineInput
{
    /// <summary>16 kHz mono samples.</summary>
    public float[] Samples { get; init; } = [];

    public ForegroundInfo Foreground { get; init; } = new();
    public string? ClipboardText { get; init; }
    public string? SelectedText { get; init; }

    /// <summary>Command Mode: the transcript is an instruction for the LLM, applied to the selection.</summary>
    public bool Command { get; init; }
}

/// <summary>What to do with the finished text.</summary>
public sealed record Delivery(string Text, OutputMode Output, string? CustomCommand, SendKey SendKey);

public sealed class PipelineOutput
{
    public required HistoryEntry Entry { get; init; }
    public Delivery? Delivery { get; set; }
    public string? Warning { get; init; }
    public string? Error { get; init; }
}

/// <summary>
/// The dictation pipeline: transcribe → filter → trigger words → format → replace → snippets → enhance,
/// plus Command Mode. Mirrors <c>pipeline.rs</c> step by step.
/// </summary>
public static class Pipeline
{
    private static PipelineOutput Canceled(HistoryEntry entry)
    {
        entry.Status = EntryStatus.Canceled;
        return new PipelineOutput { Entry = entry };
    }

    internal static string? WindowContext(ForegroundInfo fg)
    {
        var lines = new List<string>();
        if (fg.ProcessName.Length > 0) lines.Add($"Application: {fg.ProcessName}");
        if (fg.WindowTitle.Trim().Length > 0) lines.Add($"Window title: {fg.WindowTitle.Trim()}");
        return lines.Count == 0 ? null : string.Join('\n', lines);
    }

    public static async Task<PipelineOutput> RunAsync(
        AppConfig config, PipelineInput input, CancellationToken ct, Action<Stage>? onStage = null)
    {
        var entry = new HistoryEntry
        {
            Status = EntryStatus.Completed,
            Duration = AudioConvert.DurationSecs(input.Samples.Length),
            TranscriptionModel = $"{config.Transcription.Provider.DisplayName()} {config.Transcription.ModelName}",
        };
        if (input.Foreground.ProcessName.Length > 0) entry.App = input.Foreground.ProcessName;

        var mode = Modes.Match(config.Modes, input.Foreground);
        var resolved = Modes.Resolve(config, mode);

        var wav = Wav.EncodeI16(input.Samples, AudioConvert.TargetSampleRate);
        if (config.History.Enabled && config.History.SaveAudio)
        {
            try
            {
                Directory.CreateDirectory(AppPaths.RecordingsDir);
                var path = Path.Combine(AppPaths.RecordingsDir, $"{entry.Id}.wav");
                await File.WriteAllBytesAsync(path, wav, CancellationToken.None).ConfigureAwait(false);
                entry.AudioFile = path;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                // Recording the audio is optional.
            }
        }

        if (ct.IsCancellationRequested) return Canceled(entry);

        // 1. Transcribe.
        onStage?.Invoke(Stage.Transcribing);
        var clock = Stopwatch.StartNew();
        string raw;
        try
        {
            raw = await Transcriber.TranscribeAsync(
                config.Transcription,
                new TranscriptionRequest(wav, input.Samples, resolved.Language, config.Vocabulary),
                ct).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            return Canceled(entry);
        }
        catch (TranscriptionException e)
        {
            entry.Status = EntryStatus.Failed;
            entry.Text = $"Transcription Failed: {e.Message}";
            entry.TranscriptionSecs = clock.Elapsed.TotalSeconds;
            return new PipelineOutput { Entry = entry, Error = e.Message };
        }

        entry.TranscriptionSecs = clock.Elapsed.TotalSeconds;
        if (ct.IsCancellationRequested)
        {
            entry.Text = raw;
            return Canceled(entry);
        }

        // 2. Filter hallucinations and filler words.
        var text = config.Transcription.FilterOutput
            ? TextFilter.FilterTranscription(raw, config.FillerWords)
            : raw.Trim();

        if (input.Command)
        {
            return await RunCommandAsync(config, input, entry, text, ct, onStage).ConfigureAwait(false);
        }

        // 3. Spoken trigger words switch the mode.
        if (Modes.DetectTrigger(text, config.Modes) is { } trigger)
        {
            mode = config.Modes[trigger.ModeIndex];
            resolved = Modes.Resolve(config, mode);
            text = trigger.ProcessedText;
        }

        // 4. Paragraph formatting and 5. dictionary replacements.
        if (resolved.TextFormatting) text = ParagraphFormatter.Format(text);
        text = Replacements.Apply(text, config.Replacements);
        entry.Text = text;
        entry.ModeName = resolved.ModeName;

        var finalText = text;
        string? warning = null;
        var now = DateTime.Now;

        // 6. Saying just a snippet's trigger inserts the snippet verbatim.
        var snippet = Snippets.ExactMatch(text, config.Snippets);
        if (snippet is not null)
        {
            finalText = Snippets.Render(snippet.Text, now);
            entry.DeliveredText = finalText;
        }

        // 7. AI enhancement.
        var skipShort = snippet is not null
            || (config.Enhancement.SkipShortTranscripts
                && Words.Count(text) <= Math.Max(1, config.Enhancement.ShortTranscriptWordThreshold));
        var prompt = config.ActivePrompt(resolved.PromptId);
        if (resolved.EnhancementEnabled && !skipShort && text.Length > 0 && prompt is not null)
        {
            if (Enhancer.IsConfigured(config.Enhancement, resolved.Provider))
            {
                if (ct.IsCancellationRequested) return Canceled(entry);
                onStage?.Invoke(Stage.Enhancing);
                var request = new EnhancementRequest(
                    config.Enhancement,
                    resolved.Provider,
                    resolved.Model,
                    prompt,
                    new PromptContext(
                        SelectedText: resolved.UseSelectedTextContext ? input.SelectedText : null,
                        ClipboardText: resolved.UseClipboardContext ? input.ClipboardText : null,
                        WindowContext: resolved.UseWindowContext ? WindowContext(input.Foreground) : null,
                        Vocabulary: config.Vocabulary));
                entry.EnhancementModel = $"{resolved.Provider.DisplayName()} {resolved.Model}";
                entry.PromptName = prompt.Title;
                try
                {
                    var result = await Enhancer.EnhanceAsync(text, request, ct).ConfigureAwait(false);
                    entry.EnhancementSecs = result.Duration.TotalSeconds;
                    entry.EnhancedText = result.Text;
                    finalText = result.Text;
                }
                catch (OperationCanceledException)
                {
                    return Canceled(entry);
                }
                catch (EnhancementException e)
                {
                    entry.EnhancementError = e.Message;
                    warning = $"Enhancement failed: {e.Message}";
                }
            }
            else
            {
                warning = $"Enhancement skipped: {resolved.Provider.DisplayName()} is not configured";
            }
        }

        if (ct.IsCancellationRequested) return Canceled(entry);

        // 8. Snippet triggers inside a longer dictation are expanded after the LLM ran, so it never rewrites them.
        if (snippet is null && config.Snippets.Count > 0)
        {
            var expanded = Snippets.ExpandInline(finalText, config.Snippets, now);
            if (expanded != finalText)
            {
                entry.DeliveredText = expanded;
                finalText = expanded;
            }
        }

        // A failed enhancement still delivers the cleaned transcript.
        var delivery = finalText.Trim().Length > 0
            ? new Delivery(finalText, resolved.Output, resolved.CustomCommand, resolved.SendKey)
            : null;
        return new PipelineOutput { Entry = entry, Delivery = delivery, Warning = warning };
    }

    private static async Task<PipelineOutput> RunCommandAsync(
        AppConfig config, PipelineInput input, HistoryEntry entry, string transcript, CancellationToken ct,
        Action<Stage>? onStage)
    {
        PipelineOutput Fail(string message)
        {
            entry.Status = EntryStatus.Failed;
            entry.EnhancementError = message;
            return new PipelineOutput { Entry = entry, Error = message };
        }

        var instruction = Replacements.Apply(transcript, config.Replacements);
        entry.Text = instruction;
        entry.ModeName = "Command";
        if (instruction.Trim().Length == 0) return Fail("No instruction was recognized.");

        var (provider, model) = config.Command.Resolve(config.Enhancement);
        if (!Enhancer.IsConfigured(config.Enhancement, provider))
        {
            return Fail($"Command Mode needs an AI provider: add a {provider.DisplayName()} API key.");
        }

        if (ct.IsCancellationRequested) return Canceled(entry);

        onStage?.Invoke(Stage.Enhancing);
        var selected = string.IsNullOrWhiteSpace(input.SelectedText) ? null : input.SelectedText;
        var (system, user) = PromptTemplates.BuildCommandMessages(instruction, selected, config.Vocabulary);
        entry.EnhancementModel = $"{provider.DisplayName()} {model}";
        entry.PromptName = selected is not null ? "Command (edit selection)" : "Command (write)";

        try
        {
            var result = await Enhancer.CompleteMessagesAsync(
                config.Enhancement, provider, model, "Command Mode", system, user, ct).ConfigureAwait(false);
            entry.EnhancementSecs = result.Duration.TotalSeconds;
            entry.DeliveredText = result.Text;
            if (ct.IsCancellationRequested) return Canceled(entry);
            var delivery = result.Text.Trim().Length > 0
                ? new Delivery(result.Text, OutputMode.Paste, null, SendKey.None)
                : null;
            return new PipelineOutput { Entry = entry, Delivery = delivery };
        }
        catch (OperationCanceledException)
        {
            return Canceled(entry);
        }
        catch (EnhancementException e)
        {
            return Fail($"Command failed: {e.Message}");
        }
    }
}
