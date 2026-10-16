using SherpaOnnx;

namespace VoiceInk.Core.Transcription.Local;

/// <summary>Moonshine, NVIDIA Canary and Qwen3-ASR through sherpa-onnx (ONNX Runtime). The loaded model is cached.</summary>
internal sealed class SherpaRecognizer(LocalEngine engine) : ILocalRecognizer
{
    private static readonly string[] CanaryLanguages = ["en", "es", "de", "fr"];

    private readonly SemaphoreSlim _gate = new(1, 1);
    private OfflineRecognizer? _recognizer;
    private OfflineRecognizerConfig _config;
    private string? _loadedDir;

    public LocalEngine Engine => engine;

    public async Task<string> TranscribeAsync(LocalRequest request, CancellationToken ct)
    {
        var dir = ModelCatalog.PathOf(request.ModelsDir, request.ModelId);
        if (!Directory.Exists(dir))
        {
            throw new FileNotFoundException($"model not found: {dir} (download it in Settings › Local models)");
        }

        await _gate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            // Model loading and decoding are CPU-bound native calls; keep them off the caller's thread.
            return await Task.Run(() => Decode(dir, request), ct).ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    private string Decode(string dir, LocalRequest request)
    {
        var language = request.Language is { } l ? l.ToLowerInvariant() : null;
        if (_recognizer is null || _loadedDir != dir)
        {
            _recognizer?.Dispose();
            _config = BuildConfig(dir, language);
            _recognizer = new OfflineRecognizer(_config);
            _loadedDir = dir;
        }
        else if (engine == LocalEngine.Canary)
        {
            // Canary translates between its languages, so source and target follow the language setting.
            var code = CanaryLanguage(language);
            if (_config.ModelConfig.Canary.SrcLang != code)
            {
                _config.ModelConfig.Canary.SrcLang = code;
                _config.ModelConfig.Canary.TgtLang = code;
                _recognizer.SetConfig(_config);
            }
        }

        using var stream = _recognizer.CreateStream();
        stream.AcceptWaveform(Audio.AudioConvert.TargetSampleRate, request.Samples);
        _recognizer.Decode(stream);
        return stream.Result.Text.Trim();
    }

    private static string CanaryLanguage(string? language) =>
        language is not null && CanaryLanguages.Contains(language) ? language : "en";

    private OfflineRecognizerConfig BuildConfig(string dir, string? language)
    {
        string File(string name) => Path.Combine(dir, name);
        var config = new OfflineRecognizerConfig();
        var model = config.ModelConfig;
        model.NumThreads = Math.Clamp(Environment.ProcessorCount, 1, 8);
        model.Provider = "cpu";
        model.Tokens = File("tokens.txt");

        switch (engine)
        {
            case LocalEngine.Moonshine when System.IO.File.Exists(File("encoder_model.ort")):
                // Moonshine v2: one encoder, one merged decoder.
                model.Moonshine.Encoder = File("encoder_model.ort");
                model.Moonshine.MergedDecoder = File("decoder_model_merged.ort");
                break;
            case LocalEngine.Moonshine:
                model.Moonshine.Preprocessor = File("preprocess.onnx");
                model.Moonshine.Encoder = File("encode.int8.onnx");
                model.Moonshine.UncachedDecoder = File("uncached_decode.int8.onnx");
                model.Moonshine.CachedDecoder = File("cached_decode.int8.onnx");
                break;
            case LocalEngine.Canary:
                model.Canary.Encoder = File("encoder.int8.onnx");
                model.Canary.Decoder = File("decoder.int8.onnx");
                model.Canary.SrcLang = model.Canary.TgtLang = CanaryLanguage(language);
                break;
            case LocalEngine.Qwen3Asr:
                model.Tokens = "";
                model.Qwen3Asr.ConvFrontend = File("conv_frontend.onnx");
                model.Qwen3Asr.Encoder = File("encoder.int8.onnx");
                model.Qwen3Asr.Decoder = File("decoder.int8.onnx");
                model.Qwen3Asr.Tokenizer = File("tokenizer");
                model.Qwen3Asr.Hotwords = "";
                break;
            default:
                throw new NotSupportedException($"{engine} is not a sherpa-onnx engine");
        }

        config.ModelConfig = model;
        return config;
    }

    public void Unload()
    {
        _gate.Wait();
        try
        {
            _recognizer?.Dispose();
            _recognizer = null;
            _config = default;
            _loadedDir = null;
        }
        finally
        {
            _gate.Release();
        }
    }
}
