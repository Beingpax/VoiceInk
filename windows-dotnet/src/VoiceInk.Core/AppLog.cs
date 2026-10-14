using System.Text;
using VoiceInk.Core.Config;

namespace VoiceInk.Core;

/// <summary>Tiny append-only file log (<c>voiceink.log</c>); failures to log are ignored.</summary>
public static class AppLog
{
    private static readonly object Gate = new();

    public static void Info(string message) => Write("INFO", message);
    public static void Warn(string message) => Write("WARN", message);
    public static void Error(string message, Exception? e = null) => Write("ERROR", e is null ? message : $"{message}: {e}");

    private static void Write(string level, string message)
    {
        try
        {
            lock (Gate)
            {
                var path = AppPaths.LogPath;
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                // Start fresh once the log grows large.
                if (File.Exists(path) && new FileInfo(path).Length > 2 * 1024 * 1024) File.Delete(path);
                File.AppendAllText(path, $"{DateTimeOffset.Now:o} {level} {message}\n", Encoding.UTF8);
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // Logging must never take the app down.
        }
    }
}
