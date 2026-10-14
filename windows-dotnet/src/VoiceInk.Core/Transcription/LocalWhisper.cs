using System.Text;
using Whisper.net;

namespace VoiceInk.Core.Transcription;

/// <summary>Offline transcription with whisper.cpp through Whisper.net. The loaded model is cached.</summary>
public static class LocalWhisper
{
    private static readonly SemaphoreSlim Gate = new(1, 1);
    private static string? _loadedPath;
    private static WhisperFactory? _factory;

    public static async Task<string> TranscribeAsync(
        string modelPath, float[] samples, string? language, IReadOnlyList<string> vocabulary, CancellationToken ct)
    {
        if (!File.Exists(modelPath))
        {
            throw new FileNotFoundException(
                $"model not found: {modelPath} (download one in Settings › Models or put a ggml model into this folder)");
        }

        await Gate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            if (_loadedPath != modelPath || _factory is null)
            {
                _factory?.Dispose();
                _factory = WhisperFactory.FromPath(modelPath);
                _loadedPath = modelPath;
            }

            var builder = _factory.CreateBuilder()
                .WithLanguage(language ?? "auto")
                .WithThreads(Math.Min(8, Math.Max(1, Environment.ProcessorCount)));
            var prompt = string.Join(", ", vocabulary.Select(w => w.Trim()).Where(w => w.Length > 0));
            if (prompt.Length > 0) builder = builder.WithPrompt(prompt);

            await using var processor = builder.Build();
            var text = new StringBuilder();
            await foreach (var segment in processor.ProcessAsync(samples, ct).ConfigureAwait(false))
            {
                text.Append(segment.Text);
            }

            return text.ToString().Trim();
        }
        finally
        {
            Gate.Release();
        }
    }

    /// <summary>Frees the cached model (e.g. before deleting its file).</summary>
    public static void Unload()
    {
        Gate.Wait();
        try
        {
            _factory?.Dispose();
            _factory = null;
            _loadedPath = null;
        }
        finally
        {
            Gate.Release();
        }
    }
}
