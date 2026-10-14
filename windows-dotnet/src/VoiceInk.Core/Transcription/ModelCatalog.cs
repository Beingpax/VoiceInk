namespace VoiceInk.Core.Transcription;

public sealed record WhisperModel(string FileName, string Title, string Description, long SizeBytes)
{
    public string Url => $"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{FileName}";
}

/// <summary>Whisper (ggml) models that can be downloaded from the whisper.cpp repository on Hugging Face.</summary>
public static class ModelCatalog
{
    private const long Mb = 1024 * 1024;

    public static readonly IReadOnlyList<WhisperModel> All =
    [
        new("ggml-tiny.bin", "Tiny", "Fastest, lowest accuracy. Multilingual.", 75 * Mb),
        new("ggml-tiny.en.bin", "Tiny (English)", "Fastest, English only.", 75 * Mb),
        new("ggml-base.bin", "Base", "Good balance for short dictation. Multilingual.", 142 * Mb),
        new("ggml-base.en.bin", "Base (English)", "Good balance, English only.", 142 * Mb),
        new("ggml-small.bin", "Small", "Noticeably more accurate. Multilingual.", 466 * Mb),
        new("ggml-small.en.bin", "Small (English)", "More accurate, English only.", 466 * Mb),
        new("ggml-medium.bin", "Medium", "High accuracy, needs a fast CPU or GPU.", 1533 * Mb),
        new("ggml-large-v3-turbo-q5_0.bin", "Large v3 Turbo (Q5)", "Near large-v3 quality at a fraction of the size.", 574 * Mb),
        new("ggml-large-v3-turbo.bin", "Large v3 Turbo", "Best speed/quality trade-off for a GPU.", 1624 * Mb),
        new("ggml-large-v3.bin", "Large v3", "Highest accuracy, slowest.", 3095 * Mb),
    ];

    public static bool IsInstalled(string modelsDir, string fileName) =>
        File.Exists(Path.Combine(modelsDir, fileName));

    public static IEnumerable<string> InstalledFiles(string modelsDir) =>
        Directory.Exists(modelsDir)
            ? Directory.EnumerateFiles(modelsDir, "ggml-*.bin").Select(f => Path.GetFileName(f)!).Order(StringComparer.OrdinalIgnoreCase)
            : [];

    /// <summary>Downloads a model to <paramref name="modelsDir"/> (via a <c>.part</c> file) and reports progress in 0..1.</summary>
    public static async Task DownloadAsync(
        WhisperModel model, string modelsDir, IProgress<double>? progress, CancellationToken ct)
    {
        Directory.CreateDirectory(modelsDir);
        var target = Path.Combine(modelsDir, model.FileName);
        var part = target + ".part";
        try
        {
            using var response = await Http.Client.GetAsync(model.Url, HttpCompletionOption.ResponseHeadersRead, ct)
                .ConfigureAwait(false);
            response.EnsureSuccessStatusCode();
            var total = response.Content.Headers.ContentLength ?? model.SizeBytes;
            await using (var source = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false))
            await using (var destination = new FileStream(part, FileMode.Create, FileAccess.Write, FileShare.None, 81920, useAsync: true))
            {
                var buffer = new byte[81920];
                long done = 0;
                int read;
                while ((read = await source.ReadAsync(buffer, ct).ConfigureAwait(false)) > 0)
                {
                    await destination.WriteAsync(buffer.AsMemory(0, read), ct).ConfigureAwait(false);
                    done += read;
                    progress?.Report(Math.Min(1.0, (double)done / total));
                }
            }

            File.Move(part, target, overwrite: true);
            progress?.Report(1.0);
        }
        catch
        {
            try { File.Delete(part); } catch (IOException) { }
            throw;
        }
    }
}
