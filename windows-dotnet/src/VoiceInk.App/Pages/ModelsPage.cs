using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.App.Ui;
using VoiceInk.Core.Config;
using VoiceInk.Core.Transcription.Local;

namespace VoiceInk.App.Pages;

/// <summary>Download, select and delete offline Whisper models.</summary>
internal static class ModelsPage
{
    public static UIElement Build(AppServices s)
    {
        var host = new ContentControl { HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch };
        void Render() => host.Content = Create(s, Render);
        Render();
        return host;
    }

    private static UIElement Create(AppServices s, Action refresh)
    {
        var dir = s.Cfg.Transcription.ResolvedModelsDir;
        var active = s.Cfg.Transcription.Provider == TranscriptionProvider.Local ? s.Cfg.Transcription.ModelName : null;

        var content = new List<UIElement>
        {
            Fluent.Info("Offline dictation", "Models run on your PC. Nothing leaves your device. Whisper uses whisper.cpp (Vulkan GPU when available); the others run on ONNX Runtime."),
        };
        foreach (var group in ModelCatalog.All.GroupBy(m => m.Engine))
        {
            content.Add(Fluent.Section(GroupTitle(group.Key), [.. group.Select(m => ModelRow(s, m, dir, active, refresh))]));
        }

        content.Add(Fluent.Section("Storage", Fluent.Row("Models folder", dir, Fluent.Button("Open", () =>
        {
            Directory.CreateDirectory(dir);
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(dir) { UseShellExecute = true });
        }, glyph: "\uE838"))));
        return Fluent.Page("Local models", [.. content]);
    }

    private static string GroupTitle(LocalEngine engine) => engine switch
    {
        LocalEngine.Whisper => "OpenAI Whisper",
        LocalEngine.Qwen3Asr => "Qwen3-ASR",
        LocalEngine.Canary => "NVIDIA Canary",
        _ => "Moonshine",
    };

    private static UIElement ModelRow(AppServices s, LocalModel model, string dir, string? active, Action refresh)
    {
        var installed = ModelCatalog.IsInstalled(dir, model);
        var size = model.SizeBytes > 0 ? $", {model.SizeBytes / 1024.0 / 1024.0:F0} MB" : "";
        var description = string.Join("  ", new[] { model.Description, $"({model.Languages}{size})" }.Where(t => t.Length > 0));
        var title = model.Id == active ? $"{model.Title}  ·  in use" : model.Title;
        var actions = Fluent.Horizontal(8);
        var progress = new ProgressBar { Width = 140, Minimum = 0, Maximum = 1, Visibility = Visibility.Collapsed, VerticalAlignment = VerticalAlignment.Center };
        var status = Fluent.Caption("");
        status.VerticalAlignment = VerticalAlignment.Center;
        status.MinWidth = 90;
        actions.Children.Add(status);
        actions.Children.Add(progress);

        if (installed)
        {
            actions.Children.Add(Fluent.Button("Use", () =>
            {
                s.Update(c => { c.Transcription.Provider = TranscriptionProvider.Local; c.Transcription.Model = model.Id; });
                refresh();
            }, accent: model.Id != active));
            actions.Children.Add(Fluent.Button("Delete", () =>
            {
                ModelCatalog.Delete(dir, model);
                refresh();
            }));
        }
        else
        {
            Button? download = null;
            download = Fluent.Button("Download", () =>
            {
                download!.IsEnabled = false;
                progress.Visibility = Visibility.Visible;
                _ = DownloadAsync(s, model, dir, progress, status, refresh);
            }, glyph: "\uE896");
            actions.Children.Add(download);
        }

        return Fluent.Row(title, description, actions);
    }

    private static async Task DownloadAsync(AppServices s, LocalModel model, string dir, ProgressBar bar, TextBlock status, Action refresh)
    {
        // Created on the UI thread, so reports (a few per second) update the controls directly.
        var progress = new Progress<DownloadProgress>(p =>
        {
            if (p.Phase == DownloadPhase.Unpacking)
            {
                bar.IsIndeterminate = true;
                status.Text = "Unpacking…";
                return;
            }

            bar.Value = p.Fraction;
            status.Text = $"{p.Fraction:P0}  ·  {p.BytesPerSecond / 1024 / 1024:F1} MB/s";
        });
        try
        {
            await ModelCatalog.DownloadAsync(model, dir, progress, CancellationToken.None);
        }
        catch (Exception e) when (e is HttpRequestException or IOException or UnauthorizedAccessException or InvalidDataException)
        {
            s.Tray.Notify("Download failed", e.Message, VoiceInk.Core.Dictation.NoticeKind.Error);
        }

        refresh();
    }
}
