using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.App.Ui;
using VoiceInk.Core.Config;
using VoiceInk.Core.Transcription;

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
        var rows = ModelCatalog.All.Select(m => ModelRow(s, m, dir, active, refresh)).ToArray();

        return Fluent.Page("Local models",
            Fluent.Info("Offline dictation", "Models run on your PC with whisper.cpp (Vulkan GPU acceleration when available). Nothing leaves your device."),
            Fluent.Section("Whisper models", rows),
            Fluent.Section("Storage", Fluent.Row("Models folder", dir, Fluent.Button("Open", () =>
            {
                Directory.CreateDirectory(dir);
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(dir) { UseShellExecute = true });
            }, glyph: ""))));
    }

    private static UIElement ModelRow(AppServices s, WhisperModel model, string dir, string? active, Action refresh)
    {
        var installed = ModelCatalog.IsInstalled(dir, model.FileName);
        var size = $"{model.SizeBytes / 1024.0 / 1024.0:F0} MB";
        var description = $"{model.Description}  ({size})";
        var title = model.FileName == active ? $"{model.Title}  ·  in use" : model.Title;
        var actions = Fluent.Horizontal(8);
        var progress = new ProgressBar { Width = 140, Minimum = 0, Maximum = 1, Visibility = Visibility.Collapsed, VerticalAlignment = VerticalAlignment.Center };
        actions.Children.Add(progress);

        if (installed)
        {
            actions.Children.Add(Fluent.Button("Use", () =>
            {
                s.Update(c => { c.Transcription.Provider = TranscriptionProvider.Local; c.Transcription.Model = model.FileName; });
                refresh();
            }, accent: model.FileName != active));
            actions.Children.Add(Fluent.Button("Delete", () =>
            {
                LocalWhisper.Unload();
                File.Delete(Path.Combine(dir, model.FileName));
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
                _ = DownloadAsync(s, model, dir, progress, refresh);
            }, glyph: "");
            actions.Children.Add(download);
        }

        return Fluent.Row(title, description, actions);
    }

    private static async Task DownloadAsync(AppServices s, WhisperModel model, string dir, ProgressBar bar, Action refresh)
    {
        var progress = new Progress<double>(v => bar.Value = v);
        try
        {
            await ModelCatalog.DownloadAsync(model, dir, progress, CancellationToken.None);
            refresh();
        }
        catch (Exception e) when (e is HttpRequestException or IOException or UnauthorizedAccessException)
        {
            bar.Visibility = Visibility.Collapsed;
            s.Tray.Notify("Download failed", e.Message, VoiceInk.Core.Dictation.NoticeKind.Error);
            refresh();
        }
    }
}
