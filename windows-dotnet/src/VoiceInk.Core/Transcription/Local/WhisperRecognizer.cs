using System.Text;
using Whisper.net;

namespace VoiceInk.Core.Transcription.Local;

/// <summary>whisper.cpp through Whisper.net. The loaded model is cached.</summary>
internal sealed class WhisperRecognizer : ILocalRecognizer
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private string? _loadedPath;
    private WhisperFactory? _factory;

    public LocalEngine Engine => LocalEngine.Whisper;

    public async Task<string> TranscribeAsync(LocalRequest request, CancellationToken ct)
    {
        var modelPath = ModelCatalog.PathOf(request.ModelsDir, request.ModelId);
        if (!File.Exists(modelPath))
        {
            throw new FileNotFoundException($"model not found: {modelPath} (download one in Settings › Local models)");
        }

        await _gate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            if (_loadedPath != modelPath || _factory is null)
            {
                _factory?.Dispose();
                _factory = WhisperFactory.FromPath(modelPath);
                _loadedPath = modelPath;
            }

            var builder = _factory.CreateBuilder()
                .WithLanguage(request.Language ?? "auto")
                .WithThreads(Math.Clamp(Environment.ProcessorCount, 1, 8));
            var prompt = string.Join(", ", request.Vocabulary.Select(w => w.Trim()).Where(w => w.Length > 0));
            if (prompt.Length > 0) builder = builder.WithPrompt(prompt);

            await using var processor = builder.Build();
            var text = new StringBuilder();
            await foreach (var segment in processor.ProcessAsync(request.Samples, ct).ConfigureAwait(false))
            {
                text.Append(segment.Text);
            }

            return text.ToString().Trim();
        }
        finally
        {
            _gate.Release();
        }
    }

    public void Unload()
    {
        _gate.Wait();
        try
        {
            _factory?.Dispose();
            _factory = null;
            _loadedPath = null;
        }
        finally
        {
            _gate.Release();
        }
    }
}
