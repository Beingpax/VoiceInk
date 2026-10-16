namespace VoiceInk.Core.Transcription.Local;

public sealed record LocalRequest(string ModelsDir, string ModelId, float[] Samples, string? Language, IReadOnlyList<string> Vocabulary);

/// <summary>One offline engine. Add a new model family by implementing this and registering it in <see cref="LocalTranscriber"/>.</summary>
public interface ILocalRecognizer
{
    LocalEngine Engine { get; }

    Task<string> TranscribeAsync(LocalRequest request, CancellationToken ct);

    /// <summary>Frees loaded models (before deleting their files, or on shutdown).</summary>
    void Unload();
}

/// <summary>Routes a model id to the engine that can run it.</summary>
public static class LocalTranscriber
{
    private static readonly IReadOnlyDictionary<LocalEngine, ILocalRecognizer> Recognizers =
        new ILocalRecognizer[]
        {
            new WhisperRecognizer(),
            new SherpaRecognizer(LocalEngine.Moonshine),
            new SherpaRecognizer(LocalEngine.Canary),
            new SherpaRecognizer(LocalEngine.Qwen3Asr),
        }.ToDictionary(r => r.Engine);

    public static Task<string> TranscribeAsync(LocalRequest request, CancellationToken ct) =>
        Recognizers[ModelCatalog.EngineOf(request.ModelId)].TranscribeAsync(request, ct);

    public static void Unload()
    {
        foreach (var recognizer in Recognizers.Values) recognizer.Unload();
    }
}
