using System;
using System.IO;
using System.Text.Json;
using VoiceInk.Windows.Core.Models;

namespace VoiceInk.Windows.Services
{
    /// <summary>
    /// A service to manage loading and saving application settings.
    /// Implemented as a singleton to ensure a single source of truth for settings.
    /// </summary>
    public class SettingsService
    {
        private static readonly Lazy<SettingsService> _instance = new Lazy<SettingsService>(() => new SettingsService());
        public static SettingsService Instance => _instance.Value;

        private readonly string _settingsFilePath;
        private const string AppName = "VoiceInk";

        public AppSettings Settings { get; private set; }

        private SettingsService()
        {
            // Determine the path for the settings file in the user's AppData folder.
            var appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var appFolderPath = Path.Combine(appDataPath, AppName);
            _settingsFilePath = Path.Combine(appFolderPath, "settings.json");

            // Load settings on initialization.
            Settings = LoadSettings();
        }

        private AppSettings LoadSettings()
        {
            try
            {
                if (File.Exists(_settingsFilePath))
                {
                    var json = File.ReadAllText(_settingsFilePath);
                    var settings = JsonSerializer.Deserialize<AppSettings>(json);
                    return settings ?? new AppSettings(); // Return default if file is corrupt/empty
                }
            }
            catch (Exception ex)
            {
                LogService.Instance.Log(LogLevel.Error, "Failed to load settings.", ex);
            }

            // Return default settings if file doesn't exist or an error occurred.
            return new AppSettings();
        }

        public void SaveSettings()
        {
            try
            {
                // Ensure the directory exists.
                var directory = Path.GetDirectoryName(_settingsFilePath);
                if (directory != null && !Directory.Exists(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                var options = new JsonSerializerOptions { WriteIndented = true };
                var json = JsonSerializer.Serialize(Settings, options);
                File.WriteAllText(_settingsFilePath, json);
            }
            catch (Exception ex)
            {
                LogService.Instance.Log(LogLevel.Error, "Failed to save settings.", ex);
            }
        }
    }
}
