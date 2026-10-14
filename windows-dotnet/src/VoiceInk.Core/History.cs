using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using VoiceInk.Core.Config;

namespace VoiceInk.Core;

public enum EntryStatus
{
    [JsonStringEnumMemberName("completed")] Completed,
    [JsonStringEnumMemberName("failed")] Failed,
    [JsonStringEnumMemberName("canceled")] Canceled,
}

public sealed class HistoryEntry
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.Now;
    public EntryStatus Status { get; set; } = EntryStatus.Completed;

    /// <summary>Cleaned transcript (after filtering, formatting and replacements).</summary>
    public string Text { get; set; } = "";

    public string? EnhancedText { get; set; }

    /// <summary>Recording length in seconds.</summary>
    public double Duration { get; set; }

    public string TranscriptionModel { get; set; } = "";
    public double TranscriptionSecs { get; set; }
    public string? EnhancementModel { get; set; }
    public string? PromptName { get; set; }
    public double? EnhancementSecs { get; set; }

    /// <summary>Text that was actually inserted when it differs from Text and EnhancedText (snippets, Command Mode).</summary>
    public string? DeliveredText { get; set; }

    /// <summary>Why AI enhancement failed (the plain transcript was delivered instead).</summary>
    public string? EnhancementError { get; set; }

    public string? ModeName { get; set; }
    public string? App { get; set; }
    public string? AudioFile { get; set; }

    /// <summary>The text that was delivered to the user.</summary>
    [JsonIgnore]
    public string FinalText =>
        !string.IsNullOrEmpty(DeliveredText) ? DeliveredText
        : !string.IsNullOrEmpty(EnhancedText) ? EnhancedText
        : Text;
}

/// <summary>Append-only <c>history.jsonl</c>, compatible with the Rust version.</summary>
public static class History
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter() },
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private static readonly object Gate = new();

    public static void Append(string path, HistoryEntry entry)
    {
        lock (Gate)
        {
            var dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.AppendAllText(path, JsonSerializer.Serialize(entry, Options) + "\n", new UTF8Encoding(false));
        }
    }

    /// <summary>Loads every readable entry, oldest first. Corrupt lines are skipped.</summary>
    public static List<HistoryEntry> Load(string path)
    {
        lock (Gate)
        {
            if (!File.Exists(path)) return [];
            var result = new List<HistoryEntry>();
            foreach (var line in ReadLinesShared(path))
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                try
                {
                    if (JsonSerializer.Deserialize<HistoryEntry>(line, Options) is { } e) result.Add(e);
                }
                catch (JsonException)
                {
                    // Skip corrupt lines.
                }
            }

            return result;
        }
    }

    private static IEnumerable<string> ReadLinesShared(string path)
    {
        using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var reader = new StreamReader(fs, Encoding.UTF8);
        while (reader.ReadLine() is { } line) yield return line;
    }

    /// <summary>Most recent successfully delivered text.</summary>
    public static string? LastText(string path) => Load(path)
        .AsEnumerable().Reverse()
        .FirstOrDefault(e => e.Status == EntryStatus.Completed && e.FinalText.Length > 0)?.FinalText;

    /// <summary>Drops the oldest entries (and their audio files) beyond <paramref name="maxEntries"/>.</summary>
    public static void Trim(string path, int maxEntries)
    {
        if (maxEntries <= 0) return;
        var entries = Load(path);
        if (entries.Count <= maxEntries) return;
        var old = entries.Take(entries.Count - maxEntries);
        foreach (var e in old)
        {
            if (e.AudioFile is { } audio)
            {
                try { File.Delete(audio); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
        }

        lock (Gate)
        {
            var tmp = path + ".tmp";
            File.WriteAllLines(tmp, entries.Skip(entries.Count - maxEntries).Select(e => JsonSerializer.Serialize(e, Options)), new UTF8Encoding(false));
            File.Move(tmp, path, overwrite: true);
        }
    }

    public static void Clear(string path)
    {
        lock (Gate)
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }

    private static string Esc(string s) => "\"" + s.Replace("\"", "\"\"", StringComparison.Ordinal) + "\"";

    /// <summary>Writes history as CSV (like the macOS "Export" action).</summary>
    public static void ExportCsv(IEnumerable<HistoryEntry> entries, TextWriter output)
    {
        output.Write("timestamp,status,duration_s,mode,app,model,text,enhanced_text\n");
        foreach (var e in entries)
        {
            output.Write(string.Join(',',
                e.Timestamp.ToString("o", CultureInfo.InvariantCulture),
                e.Status.ToString(),
                e.Duration.ToString("F1", CultureInfo.InvariantCulture),
                Esc(e.ModeName ?? ""),
                Esc(e.App ?? ""),
                Esc(e.TranscriptionModel),
                Esc(e.Text),
                Esc(e.EnhancedText ?? "")));
            output.Write('\n');
        }
    }
}
