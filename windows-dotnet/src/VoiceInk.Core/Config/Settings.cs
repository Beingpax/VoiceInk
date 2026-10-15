using System.Text.Json;
using System.Text.Json.Serialization;
using VoiceInk.Core.Text;

namespace VoiceInk.Core.Config;

public enum HotkeyMode
{
    /// <summary>Press to start, press again to stop.</summary>
    [JsonStringEnumMemberName("toggle")] Toggle,

    /// <summary>Hold to record, release to stop.</summary>
    [JsonStringEnumMemberName("push_to_talk")] PushToTalk,

    /// <summary>Short press toggles, holding longer than <c>HybridThresholdMs</c> acts as push-to-talk.</summary>
    [JsonStringEnumMemberName("hybrid")] Hybrid,
}

public enum PasteMethod
{
    /// <summary>Clipboard + Ctrl+V (default, like the macOS CGEvent paste).</summary>
    [JsonStringEnumMemberName("ctrl_v")] CtrlV,

    /// <summary>Clipboard + Shift+Insert (terminals, some legacy apps).</summary>
    [JsonStringEnumMemberName("shift_insert")] ShiftInsert,

    /// <summary>Types the text with Unicode <c>SendInput</c> events, leaving the clipboard alone.</summary>
    [JsonStringEnumMemberName("type")] Type,
}

public enum SendKey
{
    [JsonStringEnumMemberName("none")] None,
    [JsonStringEnumMemberName("enter")] Enter,
    [JsonStringEnumMemberName("shift_enter")] ShiftEnter,
    [JsonStringEnumMemberName("ctrl_enter")] CtrlEnter,
}

public enum OverlayPosition
{
    [JsonStringEnumMemberName("bottom_center")] BottomCenter,
    [JsonStringEnumMemberName("top_center")] TopCenter,
    [JsonStringEnumMemberName("hidden")] Hidden,
}

public enum OutputMode
{
    [JsonStringEnumMemberName("paste")] Paste,

    /// <summary>Runs <c>CustomCommand</c> with the text on stdin and in <c>VOICEINK_TRANSCRIPT</c>.</summary>
    [JsonStringEnumMemberName("custom_command")] CustomCommand,
}

public sealed class HotkeySettings
{
    /// <summary>e.g. <c>"RightCtrl"</c>, <c>"F9"</c>, <c>"Ctrl+Shift+Space"</c>, <c>"Alt+Q"</c>.</summary>
    public string Record { get; set; } = "RightCtrl";

    public HotkeyMode Mode { get; set; } = HotkeyMode.Hybrid;
    public ulong HybridThresholdMs { get; set; } = 500;

    /// <summary>Cancels an active recording or a running transcription.</summary>
    public string Cancel { get; set; } = "Escape";

    /// <summary>Optional hotkey that pastes the last transcription again.</summary>
    public string? PasteLast { get; set; } = "Alt+Shift+V";
}

public sealed class TranscriptionSettings
{
    public TranscriptionProvider Provider { get; set; } = TranscriptionProvider.OpenAI;

    /// <summary><c>null</c> uses the provider default.</summary>
    public string? Model { get; set; }

    /// <summary>ISO-639-1 code or <c>"auto"</c>.</summary>
    public string Language { get; set; } = "auto";

    /// <summary>Full URL of the <c>/audio/transcriptions</c> endpoint for the <c>custom</c> provider.</summary>
    public string CustomEndpoint { get; set; } = "http://127.0.0.1:8080/v1/audio/transcriptions";

    /// <summary>Folder with <c>ggml-*.bin</c> models for the <c>local</c> provider (default: <c>%APPDATA%\VoiceInk\models</c>).</summary>
    public string? LocalModelsDir { get; set; }

    public ulong TimeoutSecs { get; set; } = 120;

    /// <summary>Remove <c>[MUSIC]</c>, <c>(laughs)</c>, tag blocks and filler words.</summary>
    public bool FilterOutput { get; set; } = true;

    /// <summary>Group sentences into paragraphs (<c>ParagraphFormatter</c>).</summary>
    public bool TextFormatting { get; set; }

    [JsonIgnore]
    public string ModelName => string.IsNullOrWhiteSpace(Model) ? Provider.DefaultModel() : Model;

    [JsonIgnore]
    public string? LanguageCode
    {
        get
        {
            var lang = Language.Trim();
            return lang.Length > 0 && !lang.Equals("auto", StringComparison.OrdinalIgnoreCase) ? lang : null;
        }
    }

    [JsonIgnore]
    public string ResolvedModelsDir =>
        string.IsNullOrWhiteSpace(LocalModelsDir) ? Path.Combine(AppPaths.DataDir, "models") : LocalModelsDir;
}

public sealed class EnhancementSettings
{
    public bool Enabled { get; set; }
    public EnhancementProvider Provider { get; set; } = EnhancementProvider.OpenAI;
    public string? Model { get; set; }
    public string PromptId { get; set; } = PromptTemplates.DefaultPromptId;

    /// <summary>Base URL for Ollama (<c>/v1/chat/completions</c> is appended).</summary>
    public string OllamaBaseUrl { get; set; } = "http://localhost:11434";

    /// <summary>Full chat-completions URL for the <c>custom</c> provider.</summary>
    public string CustomEndpoint { get; set; } = "http://127.0.0.1:1234/v1/chat/completions";

    public bool UseClipboardContext { get; set; }

    /// <summary>Sends the focused window's title and process name as context.</summary>
    public bool UseWindowContext { get; set; } = true;

    /// <summary>Copies the current selection (Ctrl+C) before recording and sends it as context.</summary>
    public bool UseSelectedTextContext { get; set; }

    public ulong TimeoutSecs { get; set; } = 30;
    public uint MaxAttempts { get; set; } = 3;
    public bool RetryOnTimeout { get; set; } = true;
    public bool SkipShortTranscripts { get; set; }
    public int ShortTranscriptWordThreshold { get; set; } = 3;

    [JsonIgnore]
    public string ModelName => string.IsNullOrWhiteSpace(Model) ? Provider.DefaultModel() : Model;

    public string EndpointFor(EnhancementProvider provider) => provider switch
    {
        EnhancementProvider.Ollama => $"{OllamaBaseUrl.TrimEnd('/')}/v1/chat/completions",
        EnhancementProvider.Custom => CustomEndpoint,
        var p => p.Endpoint() ?? "",
    };

    public string Endpoint() => EndpointFor(Provider);
}

/// <summary>
/// Command Mode: select text, hold the command shortcut and say what to do with it ("make this more formal",
/// "translate to German"). Without a selection the instruction writes new text at the cursor.
/// </summary>
public sealed class CommandSettings
{
    public bool Enabled { get; set; } = true;

    /// <summary>Uses the same behaviour (hybrid / toggle / push-to-talk) as the record shortcut.</summary>
    public string Hotkey { get; set; } = "Ctrl+Shift+Space";

    /// <summary><c>null</c> uses the AI Enhancement provider and model.</summary>
    public EnhancementProvider? Provider { get; set; }

    public string? Model { get; set; }

    /// <summary>Effective provider and model, falling back to the enhancement settings.</summary>
    public (EnhancementProvider Provider, string Model) Resolve(EnhancementSettings enhancement)
    {
        var provider = Provider ?? enhancement.Provider;
        var model = !string.IsNullOrWhiteSpace(Model)
            ? Model
            : Provider is null ? enhancement.ModelName : provider.DefaultModel();
        return (provider, model);
    }
}

public sealed class OutputSettings
{
    public PasteMethod Method { get; set; } = PasteMethod.CtrlV;
    public bool RestoreClipboard { get; set; } = true;
    public ulong ClipboardRestoreDelayMs { get; set; } = 600;

    /// <summary>Key pressed after pasting ("Finish &amp; Send").</summary>
    public SendKey SendKey { get; set; } = SendKey.None;

    /// <summary>Appends a trailing space so consecutive dictations don't run together.</summary>
    public bool AppendSpace { get; set; }
}

public sealed class AudioSettings
{
    /// <summary>Substring of the microphone's friendly name; <c>null</c> = system default.</summary>
    public string? InputDevice { get; set; }

    public bool PlaySounds { get; set; } = true;

    /// <summary>Custom WAV files; built-in sounds are used when unset.</summary>
    public string? StartSound { get; set; }

    public string? StopSound { get; set; }

    /// <summary>Mutes system output while recording (restored afterwards).</summary>
    public bool MuteSystemAudio { get; set; }

    /// <summary>Recordings shorter than this are discarded.</summary>
    public ulong MinRecordingMs { get; set; } = 300;
}

public sealed class HistorySettings
{
    public bool Enabled { get; set; } = true;
    public bool SaveAudio { get; set; }

    /// <summary>Oldest entries beyond this count are dropped (0 = unlimited).</summary>
    public int MaxEntries { get; set; } = 1000;
}

public enum AppTheme
{
    [JsonStringEnumMemberName("system")] System,
    [JsonStringEnumMemberName("light")] Light,
    [JsonStringEnumMemberName("dark")] Dark,
}

/// <summary>Per-application overrides (the macOS "Modes"/Power Mode feature).</summary>
public sealed class ModeConfig
{
    public string Name { get; set; } = "";
    public bool Enabled { get; set; } = true;

    /// <summary>Executable names, e.g. <c>["slack.exe", "teams.exe"]</c> (case-insensitive).</summary>
    public List<string> ProcessNames { get; set; } = [];

    /// <summary>Matched against the focused window title, e.g. browser tabs: <c>["Gmail", "github.com"]</c>.</summary>
    public List<string> WindowTitleContains { get; set; } = [];

    /// <summary>Spoken at the beginning of a dictation to force this mode ("email ...").</summary>
    public List<string> TriggerWords { get; set; } = [];

    public bool? EnhancementEnabled { get; set; }
    public string? PromptId { get; set; }
    public EnhancementProvider? EnhancementProvider { get; set; }
    public string? EnhancementModel { get; set; }
    public string? Language { get; set; }
    public bool? TextFormatting { get; set; }
    public bool? UseClipboardContext { get; set; }
    public bool? UseSelectedTextContext { get; set; }
    public OutputMode Output { get; set; } = OutputMode.Paste;
    public string? CustomCommand { get; set; }
    public SendKey? SendKey { get; set; }
}

/// <summary>
/// User configuration, persisted as pretty JSON in <c>%APPDATA%\VoiceInk\config.json</c>. The format is the same as
/// the Rust version's, so an existing file keeps working. Every field has a default so older files keep loading.
/// </summary>
public sealed class AppConfig
{
    public HotkeySettings Hotkeys { get; set; } = new();
    public TranscriptionSettings Transcription { get; set; } = new();
    public EnhancementSettings Enhancement { get; set; } = new();
    public CommandSettings Command { get; set; } = new();
    public OutputSettings Output { get; set; } = new();
    public AudioSettings Audio { get; set; } = new();
    public HistorySettings History { get; set; } = new();
    public OverlayPosition Overlay { get; set; } = OverlayPosition.BottomCenter;
    public AppTheme Theme { get; set; } = AppTheme.System;
    public bool StartWithWindows { get; set; }
    public List<CustomPrompt> Prompts { get; set; } = PromptTemplates.Seed();
    public List<string> FillerWords { get; set; } = [.. TextFilter.DefaultFillerWords];

    /// <summary>Custom vocabulary passed to the AI (and to Deepgram/ElevenLabs as keyterms).</summary>
    public List<string> Vocabulary { get; set; } = [];

    public List<WordReplacement> Replacements { get; set; } = [];

    /// <summary>Voice shortcuts expanded to saved text.</summary>
    public List<Snippet> Snippets { get; set; } = [];

    public List<ModeConfig> Modes { get; set; } = [];

    public CustomPrompt? Prompt(string id) => Prompts.FirstOrDefault(p => p.Id == id);

    /// <summary>Selected prompt, falling back to the first prompt (like <c>repairModePromptSelections</c>).</summary>
    public CustomPrompt? ActivePrompt(string? id) =>
        (id is null ? null : Prompt(id)) ?? Prompt(Enhancement.PromptId) ?? Prompts.FirstOrDefault();

    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        WriteIndented = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        Converters = { new JsonStringEnumConverter<HotkeyMode>(), new JsonStringEnumConverter<PasteMethod>(),
            new JsonStringEnumConverter<SendKey>(), new JsonStringEnumConverter<OverlayPosition>(),
            new JsonStringEnumConverter<OutputMode>(), new JsonStringEnumConverter<AppTheme>(),
            new JsonStringEnumConverter<TranscriptionProvider>(), new JsonStringEnumConverter<EnhancementProvider>() },
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private static readonly AppJsonContext ConfigJson = new(JsonOptions);

    public AppConfig Clone() => FromJson(ToJson());

    public string ToJson() => JsonSerializer.Serialize(this, ConfigJson.AppConfig);

    public static AppConfig FromJson(string json)
    {
        var cfg = JsonSerializer.Deserialize(json, ConfigJson.AppConfig) ?? new AppConfig();
        if (cfg.Prompts.Count == 0)
        {
            cfg.Prompts = PromptTemplates.Seed();
        }

        return cfg;
    }

    /// <summary>Loads the file, creating it with defaults on first run.</summary>
    public static AppConfig Load(string path)
    {
        if (!File.Exists(path))
        {
            var fresh = new AppConfig();
            fresh.Save(path);
            return fresh;
        }

        try
        {
            return FromJson(File.ReadAllText(path));
        }
        catch (JsonException e)
        {
            throw new InvalidDataException($"{path}: {e.Message}", e);
        }
    }

    public void Save(string path)
    {
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir))
        {
            Directory.CreateDirectory(dir);
        }

        // Write-then-rename so a crash never leaves a truncated config behind.
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, ToJson());
        File.Move(tmp, path, overwrite: true);
    }
}

public static class AppPaths
{
    public const string AppName = "VoiceInk";

    /// <summary><c>%APPDATA%\VoiceInk</c> (or <c>$XDG_CONFIG_HOME/VoiceInk</c> when testing elsewhere).</summary>
    public static string DataDir
    {
        get
        {
            var overrideDir = Environment.GetEnvironmentVariable("VOICEINK_HOME");
            if (!string.IsNullOrEmpty(overrideDir))
            {
                return overrideDir;
            }

            var appData = Environment.GetEnvironmentVariable("APPDATA");
            if (string.IsNullOrEmpty(appData))
            {
                appData = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
            }

            if (string.IsNullOrEmpty(appData))
            {
                var home = Environment.GetEnvironmentVariable("HOME");
                appData = string.IsNullOrEmpty(home) ? "." : Path.Combine(home, ".config");
            }

            return Path.Combine(appData, AppName);
        }
    }

    public static string ConfigPath => Path.Combine(DataDir, "config.json");
    public static string HistoryPath => Path.Combine(DataDir, "history.jsonl");
    public static string RecordingsDir => Path.Combine(DataDir, "recordings");
    public static string KeysPath => Path.Combine(DataDir, "keys.json");
    public static string LogPath => Path.Combine(DataDir, "voiceink.log");
}
