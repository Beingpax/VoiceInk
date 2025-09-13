using System;
using System.IO;
using System.Text;

namespace VoiceInk.Windows.Services
{
    public enum LogLevel
    {
        Info,
        Warning,
        Error
    }

    /// <summary>
    /// A simple singleton service for logging messages to a file.
    /// </summary>
    public class LogService
    {
        private static readonly Lazy<LogService> _instance = new Lazy<LogService>(() => new LogService());
        public static LogService Instance => _instance.Value;

        private readonly string _logFilePath;
        private readonly object _lock = new object();
        private const string AppName = "VoiceInk";

        private LogService()
        {
            var appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var appFolderPath = Path.Combine(appDataPath, AppName);
            _logFilePath = Path.Combine(appFolderPath, "log.txt");
        }

        public void Log(LogLevel level, string message, Exception? ex = null)
        {
            lock (_lock)
            {
                try
                {
                    var logBuilder = new StringBuilder();
                    logBuilder.Append($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}]");
                    logBuilder.Append($"[{level.ToString().ToUpper()}]");
                    logBuilder.Append($" {message}");

                    if (ex != null)
                    {
                        logBuilder.AppendLine();
                        logBuilder.AppendLine("--- Exception Details ---");
                        logBuilder.AppendLine(ex.ToString());
                        logBuilder.AppendLine("-------------------------");
                    }

                    // Ensure the directory exists
                    var directory = Path.GetDirectoryName(_logFilePath);
                    if (directory != null && !Directory.Exists(directory))
                    {
                        Directory.CreateDirectory(directory);
                    }

                    File.AppendAllText(_logFilePath, logBuilder.ToString() + Environment.NewLine);
                }
                catch (Exception fileEx)
                {
                    // If logging fails, there's not much we can do other than write to debug console.
                    System.Diagnostics.Debug.WriteLine($"Failed to write to log file: {fileEx.Message}");
                }
            }
        }
    }
}
