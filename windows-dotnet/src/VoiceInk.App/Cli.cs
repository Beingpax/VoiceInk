using VoiceInk.Core;
using VoiceInk.Core.Audio;
using VoiceInk.Core.Config;
using VoiceInk.Platform.Audio;
using VoiceInk.Platform.Shell;

namespace VoiceInk.App;

/// <summary>Command-line subcommands of the same executable (<c>voiceink transcribe memo.wav</c>, ...).</summary>
internal static class Cli
{
    private const string Help = """
        VoiceInk for Windows — voice to text in any app

        USAGE:
            voiceink                          Start the tray app (default)
            voiceink dashboard                Open the dashboard (starts the app if needed)
            voiceink settings                 Open the settings
            voiceink set-key <provider> <key> Store an API key (encrypted with DPAPI)
            voiceink remove-key <provider>    Delete a stored API key
            voiceink keys                     List providers that have a key
            voiceink transcribe <file.wav>    Run the full pipeline on a WAV file and print the result
            voiceink devices                  List microphones
            voiceink history [count]          Print recent transcriptions
            voiceink export-history <out.csv> Export the history as CSV
            voiceink config-path              Print the settings file location
            voiceink --version
        """;

    /// <summary>Runs a CLI command. Returns null when the arguments start the GUI instead.</summary>
    public static int? TryRun(string[] args)
    {
        if (args.Length == 0 || args[0] is "dashboard" or "settings") return null;

        WindowInterop.AttachParentConsole();
        Credentials.Protector = new DpapiProtector();
        try
        {
            RunAsync(args).GetAwaiter().GetResult();
            return 0;
        }
        catch (Exception e) when (e is not OutOfMemoryException)
        {
            Console.Error.WriteLine($"error: {e.Message}");
            return 1;
        }
    }

    private static async Task RunAsync(string[] args)
    {
        switch (args[0])
        {
            case "-h" or "--help" or "help":
                Console.WriteLine(Help);
                break;
            case "-V" or "--version":
                Console.WriteLine($"VoiceInk for Windows {AppInfo.Version}");
                break;
            case "config-path":
                Console.WriteLine(AppPaths.ConfigPath);
                break;
            case "set-key":
                SetKey(args);
                break;
            case "remove-key":
                var name = args.ElementAtOrDefault(1) ?? throw new ArgumentException("usage: voiceink remove-key <provider>");
                Credentials.Remove(name.ToLowerInvariant());
                Console.WriteLine($"Removed API key for {name}.");
                break;
            case "keys":
                foreach (var key in Credentials.KnownNames()) Console.WriteLine($"{key,-22} {(Credentials.Has(key) ? "configured" : "-")}");
                break;
            case "transcribe":
                await TranscribeAsync(args);
                break;
            case "history":
                PrintHistory(int.TryParse(args.ElementAtOrDefault(1), out var n) ? n : 10);
                break;
            case "export-history":
                var path = args.ElementAtOrDefault(1) ?? throw new ArgumentException("usage: voiceink export-history <out.csv>");
                var entries = History.Load(AppPaths.HistoryPath);
                using (var writer = new StreamWriter(path, false, new System.Text.UTF8Encoding(true))) History.ExportCsv(entries, writer);
                Console.WriteLine($"Exported {entries.Count} entries to {path}");
                break;
            case "devices":
                foreach (var (device, isDefault) in WasapiAudioCapture.ListInputDevices()) Console.WriteLine($"{(isDefault ? "* " : "  ")}{device}");
                break;
            default:
                throw new ArgumentException($"unknown command '{args[0]}'\n\n{Help}");
        }
    }

    private static void SetKey(string[] args)
    {
        if (args.Length < 3) throw new ArgumentException("usage: voiceink set-key <provider> <key>");
        var name = args[1].ToLowerInvariant();
        if (!Credentials.KnownNames().Contains(name))
        {
            throw new ArgumentException($"unknown provider '{name}'. Known: {string.Join(", ", Credentials.KnownNames())}");
        }

        Credentials.Set(name, args[2]);
        Console.WriteLine($"Stored API key for {name}.");
    }

    private static async Task TranscribeAsync(string[] args)
    {
        var file = args.ElementAtOrDefault(1) ?? throw new ArgumentException("usage: voiceink transcribe <file.wav>");
        var samples = Wav.Load16k(await File.ReadAllBytesAsync(file));
        var config = AppConfig.Load(AppPaths.ConfigPath);
        var output = await Pipeline.RunAsync(
            config, new PipelineInput { Samples = samples }, CancellationToken.None, stage => Console.Error.WriteLine($"{stage}…"));
        if (output.Error is { } error) throw new InvalidOperationException(error);
        if (output.Warning is { } warning) Console.Error.WriteLine($"warning: {warning}");
        Console.WriteLine(output.Entry.FinalText);
        if (config.History.Enabled) History.Append(AppPaths.HistoryPath, output.Entry);
    }

    private static void PrintHistory(int count)
    {
        foreach (var e in History.Load(AppPaths.HistoryPath).AsEnumerable().Reverse().Take(count))
        {
            Console.WriteLine($"{e.Timestamp.LocalDateTime:yyyy-MM-dd HH:mm:ss} [{e.Status}] {e.Duration:F1}s {e.ModeName}\n  {e.FinalText.Replace("\n", "\n  ")}\n");
        }
    }
}

internal static class AppInfo
{
    public static string Version { get; } = typeof(AppInfo).Assembly.GetName().Version?.ToString(3) ?? "0.1.0";
}
