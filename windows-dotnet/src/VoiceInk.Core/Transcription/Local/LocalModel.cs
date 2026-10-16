namespace VoiceInk.Core.Transcription.Local;

/// <summary>The inference engine behind an offline model.</summary>
public enum LocalEngine { Whisper, Moonshine, Canary, Qwen3Asr }

/// <param name="Id">Whisper: the ggml file name. Others: the folder name inside the models folder.</param>
/// <param name="Url">Direct file (Whisper) or a <c>.tar.bz2</c> archive (everything else).</param>
/// <param name="SizeBytes">Approximate download size; 0 when unknown.</param>
/// <param name="Languages">Short language note for the UI.</param>
public sealed record LocalModel(
    string Id, string Title, string Description, LocalEngine Engine, string Url, string Languages, long SizeBytes = 0)
{
    public bool IsArchive => Url.EndsWith(".tar.bz2", StringComparison.OrdinalIgnoreCase);
}

/// <summary>Everything that can be downloaded for offline dictation, plus install/delete bookkeeping.</summary>
public static class ModelCatalog
{
    private const long Mb = 1024 * 1024;
    private const string WhisperBase = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/";
    private const string SherpaBase = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/";

    private static LocalModel Whisper(string file, string title, string description, string languages, long mb) =>
        new(file, title, description, LocalEngine.Whisper, WhisperBase + file, languages, mb * Mb);

    private static LocalModel Sherpa(string id, string title, string description, LocalEngine engine, string languages) =>
        new(id, title, description, engine, $"{SherpaBase}{id}.tar.bz2", languages);

    public static readonly IReadOnlyList<LocalModel> All =
    [
        Whisper("ggml-tiny.bin", "Whisper Tiny", "Fastest, lowest accuracy.", "99 languages", 75),
        Whisper("ggml-base.bin", "Whisper Base", "Good balance for short dictation.", "99 languages", 142),
        Whisper("ggml-small.bin", "Whisper Small", "Noticeably more accurate.", "99 languages", 466),
        Whisper("ggml-medium.bin", "Whisper Medium", "High accuracy, needs a fast CPU or GPU.", "99 languages", 1533),
        Whisper("ggml-large-v3-turbo-q5_0.bin", "Whisper Large v3 Turbo (Q5)", "Near large-v3 quality at a fraction of the size.", "99 languages", 574),
        Whisper("ggml-large-v3-turbo.bin", "Whisper Large v3 Turbo", "Best speed/quality trade-off for a GPU.", "99 languages", 1624),
        Whisper("ggml-large-v3.bin", "Whisper Large v3", "Highest Whisper accuracy, slowest.", "99 languages", 3095),
        Whisper("ggml-base.en.bin", "Whisper Base (English)", "English only.", "English", 142),
        Whisper("ggml-small.en.bin", "Whisper Small (English)", "English only, more accurate.", "English", 466),

        Sherpa("sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25", "Qwen3-ASR 0.6B (int8)",
            "Alibaba's multilingual ASR with automatic language detection.", LocalEngine.Qwen3Asr, "~50 languages, auto-detect"),

        Sherpa("sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8", "NVIDIA Canary 180M Flash (int8)",
            "Fast NeMo model. Dictate in the language set under Transcription (it cannot auto-detect).",
            LocalEngine.Canary, "English, Spanish, German, French"),

        Sherpa("sherpa-onnx-moonshine-tiny-en-int8", "Moonshine Tiny (int8)",
            "Tiny and very fast on CPU.", LocalEngine.Moonshine, "English"),
        Sherpa("sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27", "Moonshine v2 Tiny",
            "Newer Moonshine generation.", LocalEngine.Moonshine, "English"),
        Sherpa("sherpa-onnx-moonshine-base-en-quantized-2026-02-27", "Moonshine v2 Base",
            "More accurate Moonshine.", LocalEngine.Moonshine, "English"),
        Sherpa("sherpa-onnx-moonshine-base-es-quantized-2026-02-27", "Moonshine v2 Base (Spanish)", "", LocalEngine.Moonshine, "Spanish"),
        Sherpa("sherpa-onnx-moonshine-base-ja-quantized-2026-02-27", "Moonshine v2 Base (Japanese)", "", LocalEngine.Moonshine, "Japanese"),
        Sherpa("sherpa-onnx-moonshine-base-zh-quantized-2026-02-27", "Moonshine v2 Base (Chinese)", "", LocalEngine.Moonshine, "Chinese"),
    ];

    public static LocalModel? Find(string id) =>
        All.FirstOrDefault(m => m.Id.Equals(id, StringComparison.OrdinalIgnoreCase));

    /// <summary>Whisper files end in .bin; everything unknown is treated as such for models dropped in by hand.</summary>
    public static LocalEngine EngineOf(string id) => Find(id)?.Engine ?? LocalEngine.Whisper;

    public static string PathOf(string modelsDir, string id) => Path.Combine(modelsDir, id);

    public static bool IsInstalled(string modelsDir, LocalModel model) =>
        model.Engine == LocalEngine.Whisper
            ? File.Exists(PathOf(modelsDir, model.Id))
            : Directory.Exists(PathOf(modelsDir, model.Id));

    /// <summary>Ids of everything usable in the folder, including Whisper files that are not in the catalog.</summary>
    public static IReadOnlyList<string> Installed(string modelsDir)
    {
        if (!Directory.Exists(modelsDir)) return [];
        var files = Directory.EnumerateFiles(modelsDir, "ggml-*.bin").Select(f => Path.GetFileName(f)!);
        var folders = All.Where(m => m.Engine != LocalEngine.Whisper && IsInstalled(modelsDir, m)).Select(m => m.Id);
        return [.. files.Concat(folders).Order(StringComparer.OrdinalIgnoreCase)];
    }

    public static void Delete(string modelsDir, LocalModel model)
    {
        LocalTranscriber.Unload();
        var path = PathOf(modelsDir, model.Id);
        if (model.Engine == LocalEngine.Whisper) File.Delete(path);
        else if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
    }

    /// <summary>Downloads (and for archives, unpacks) a model.</summary>
    public static async Task DownloadAsync(LocalModel model, string modelsDir, IProgress<DownloadProgress>? progress, CancellationToken ct)
    {
        Directory.CreateDirectory(modelsDir);
        var target = PathOf(modelsDir, model.Id);
        var part = target + ".part";
        try
        {
            await FileDownloader.DownloadAsync(model.Url, part, progress, ct, model.SizeBytes).ConfigureAwait(false);
            if (model.IsArchive)
            {
                progress?.Report(new DownloadProgress(DownloadPhase.Unpacking, 1, 0));
                await Task.Run(() => Archives.ExtractTarBz2(part, target), ct).ConfigureAwait(false);
                File.Delete(part);
            }
            else
            {
                File.Move(part, target, overwrite: true);
            }
        }
        catch
        {
            try { File.Delete(part); } catch (IOException) { }
            throw;
        }
    }
}
