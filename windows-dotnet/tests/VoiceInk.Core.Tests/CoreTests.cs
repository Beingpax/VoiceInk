using System.Net;
using System.Text;
using VoiceInk.Core.Config;
using VoiceInk.Core.Text;

namespace VoiceInk.Core.Tests;

public class CoreTests
{
    [Fact]
    public void Config_round_trips_and_fills_defaults()
    {
        var cfg = AppConfig.FromJson("""{"transcription":{"provider":"deepgram"},"enhancement":{"enabled":true}}""");
        Assert.Equal(TranscriptionProvider.Deepgram, cfg.Transcription.Provider);
        Assert.Equal("nova-3", cfg.Transcription.ModelName);
        Assert.Equal(5, cfg.Prompts.Count);
        Assert.Equal("RightCtrl", cfg.Hotkeys.Record);
        Assert.Contains("\"hybrid_threshold_ms\"", cfg.ToJson());
        Assert.Equal(cfg.ToJson(), AppConfig.FromJson(cfg.ToJson()).ToJson());
    }

    [Theory]
    [InlineData("RightCtrl", typeof(Hotkey.ModifierOnly))]
    [InlineData("Ctrl+Shift+Space", typeof(Hotkey.Key))]
    [InlineData("Mouse4", typeof(Hotkey.Mouse))]
    public void Hotkeys_parse(string spec, Type expected) =>
        Assert.IsType(expected, HotkeyParser.Parse(spec));

    [Theory]
    [InlineData("Ctrl+Shift")]
    [InlineData("Hyper+K")]
    [InlineData("F25")]
    public void Invalid_hotkeys_are_rejected(string spec) =>
        Assert.Throws<FormatException>(() => HotkeyParser.Parse(spec));

    [Fact]
    public void Filter_removes_hallucinations_and_fillers() =>
        Assert.Equal("hello there world.",
            TextFilter.FilterTranscription("Um, hello [MUSIC] there (laughs) uh world.", TextFilter.DefaultFillerWords));

    [Fact]
    public void Replacements_respect_word_boundaries_and_cjk()
    {
        var rules = new[] { new WordReplacement { Original = "voice ink, voiceink", Replacement = "VoiceInk" } };
        Assert.Equal("I love VoiceInk. VoiceInk rocks, voiceinks no.",
            Replacements.Apply("I love voice ink. Voiceink rocks, voiceinks no.", rules));
        var cjk = new[] { new WordReplacement { Original = "東京", Replacement = "Tokyo" } };
        Assert.Equal("私はTokyoに", Replacements.Apply("私は東京に", cjk));
    }

    [Fact]
    public void Snippets_match_exactly_and_expand_inline()
    {
        var snippets = new List<Snippet> { new() { Trigger = "my link", Text = "https://x.test {date}" } };
        var now = new DateTime(2026, 10, 14, 9, 5, 0);
        Assert.NotNull(Snippets.ExactMatch("My link.", snippets));
        Assert.Null(Snippets.ExactMatch("send my link", snippets));
        Assert.Equal("Use https://x.test 2026-10-14 now", Snippets.ExpandInline("Use my link now", snippets, now));
    }

    [Fact]
    public void Trigger_words_switch_modes()
    {
        var modes = new List<ModeConfig> { new() { Name = "Email", TriggerWords = ["email"] } };
        var hit = Modes.DetectTrigger("Email, hi John", modes);
        Assert.Equal("Hi John", hit?.ProcessedText);
        Assert.Null(Modes.DetectTrigger("emails are great", modes));
    }

    [Fact]
    public void Wav_round_trips() =>
        Assert.Equal(16_000, Audio.Wav.Decode(Audio.Wav.EncodeI16(new[] { 0f, 0.5f, -0.5f }, 16_000)).SampleRate);

    [Fact]
    public async Task Pipeline_transcribes_enhances_and_expands()
    {
        using var home = new TempHome();
        using var server = new FakeServer(
            ("/stt", """{"text":"Um, hello [MUSIC] voice ink."}""", 200),
            ("/chat", """{"choices":[{"message":{"content":"<think>x</think>Hello, VoiceInk!"}}]}""", 200));

        var cfg = new AppConfig();
        cfg.History.Enabled = false;
        cfg.Transcription.Provider = TranscriptionProvider.Custom;
        cfg.Transcription.CustomEndpoint = server.Url + "/stt";
        cfg.Enhancement.Enabled = true;
        cfg.Enhancement.Provider = EnhancementProvider.Custom;
        cfg.Enhancement.CustomEndpoint = server.Url + "/chat";
        cfg.Enhancement.MaxAttempts = 1;
        cfg.Replacements.Add(new WordReplacement { Original = "voice ink", Replacement = "VoiceInk" });

        var output = await Pipeline.RunAsync(cfg, new PipelineInput { Samples = new float[8000] }, CancellationToken.None);

        Assert.Null(output.Error);
        Assert.Equal("hello VoiceInk.", output.Entry.Text);
        Assert.Equal("Hello, VoiceInk!", output.Delivery?.Text);
        Assert.Contains("<TRANSCRIPT>\\nhello VoiceInk.\\n</TRANSCRIPT>", server.Bodies[1]);
    }

    [Fact]
    public async Task Failed_command_pastes_nothing()
    {
        using var home = new TempHome();
        using var server = new FakeServer(("/stt", """{"text":"translate to German"}""", 200), ("/chat", """{"error":{"message":"bad"}}""", 400));
        var cfg = new AppConfig();
        cfg.Transcription.Provider = TranscriptionProvider.Custom;
        cfg.Transcription.CustomEndpoint = server.Url + "/stt";
        cfg.Enhancement.Provider = EnhancementProvider.Custom;
        cfg.Enhancement.CustomEndpoint = server.Url + "/chat";
        cfg.Enhancement.MaxAttempts = 1;

        var output = await Pipeline.RunAsync(
            cfg, new PipelineInput { Samples = new float[8000], SelectedText = "hello", Command = true }, CancellationToken.None);

        Assert.Null(output.Delivery);
        Assert.Equal(EntryStatus.Failed, output.Entry.Status);
        Assert.StartsWith("Command failed", output.Error);
    }

    [Fact]
    public void Stats_aggregate_history()
    {
        var today = new DateOnly(2026, 10, 13);
        HistoryEntry Entry(int day, string text, double secs) => new()
        {
            Timestamp = new DateTimeOffset(2026, 10, day, 9, 0, 0, DateTimeOffset.Now.Offset),
            Text = text,
            Duration = secs,
        };
        var stats = Stats.Compute([Entry(13, "one two three", 6), Entry(12, "a b", 2)], 7, today);
        Assert.Equal(2, stats.Sessions);
        Assert.Equal(5, stats.Words);
        Assert.Equal(2, stats.StreakDays);
        Assert.Equal(3, stats.DailyWords[^1].Words);
    }

    private sealed class TempHome : IDisposable
    {
        private readonly string _dir = Path.Combine(Path.GetTempPath(), "voiceink-test-" + Guid.NewGuid());

        public TempHome() => Environment.SetEnvironmentVariable("VOICEINK_HOME", _dir);

        public void Dispose()
        {
            Environment.SetEnvironmentVariable("VOICEINK_HOME", null);
            if (Directory.Exists(_dir)) Directory.Delete(_dir, true);
        }
    }

    /// <summary>Minimal HTTP server answering fixed JSON per path and recording request bodies.</summary>
    private sealed class FakeServer : IDisposable
    {
        private readonly HttpListener _listener = new();
        private readonly Dictionary<string, (string Reply, int Status)> _routes;

        public string Url { get; }
        public List<string> Bodies { get; } = [];

        public FakeServer(params (string Path, string Reply, int Status)[] routes)
        {
            _routes = routes.ToDictionary(r => r.Path, r => (r.Reply, r.Status));
            var port = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
            port.Start();
            var number = ((IPEndPoint)port.LocalEndpoint).Port;
            port.Stop();
            Url = $"http://127.0.0.1:{number}";
            _listener.Prefixes.Add(Url + "/");
            _listener.Start();
            _ = Task.Run(Serve);
        }

        private async Task Serve()
        {
            while (_listener.IsListening)
            {
                try
                {
                    var ctx = await _listener.GetContextAsync();
                    using var reader = new StreamReader(ctx.Request.InputStream, Encoding.UTF8);
                    var body = await reader.ReadToEndAsync();
                    var (reply, status) = _routes[ctx.Request.Url!.AbsolutePath];
                    lock (Bodies) Bodies.Add(body);
                    var bytes = Encoding.UTF8.GetBytes(reply);
                    ctx.Response.StatusCode = status;
                    ctx.Response.ContentType = "application/json";
                    await ctx.Response.OutputStream.WriteAsync(bytes);
                    ctx.Response.Close();
                }
                catch (Exception e) when (e is HttpListenerException or ObjectDisposedException) { return; }
            }
        }

        public void Dispose() => _listener.Close();
    }
}
