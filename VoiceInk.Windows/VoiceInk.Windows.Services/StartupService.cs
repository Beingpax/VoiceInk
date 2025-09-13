using Microsoft.Win32;
using System.Reflection;

namespace VoiceInk.Windows.Services
{
    /// <summary>
    /// A service to manage the application's launch-at-login setting by interacting with the Windows Registry.
    /// </summary>
    public class StartupService
    {
        private const string AppName = "VoiceInk";
        private const string RegistryRunPath = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";

        /// <summary>
        /// Enables or disables the application from launching when the user logs in.
        /// </summary>
        /// <param name="shouldLaunchAtLogin">True to enable launch at login, false to disable.</param>
        public void SetLaunchAtLogin(bool shouldLaunchAtLogin)
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(RegistryRunPath, true))
                {
                    if (key == null) return; // Should not happen on a standard Windows system

                    if (shouldLaunchAtLogin)
                    {
                        // Get the path to the current executable
                        var executablePath = Assembly.GetEntryAssembly()?.Location;
                        if (!string.IsNullOrEmpty(executablePath))
                        {
                            // Set the registry value. The path needs to be quoted in case it contains spaces.
                            key.SetValue(AppName, $"\"{executablePath}\"");
                        }
                    }
                    else
                    {
                        // Remove the registry value if it exists.
                        if (key.GetValue(AppName) != null)
                        {
                            key.DeleteValue(AppName);
                        }
                    }
                }
            }
            catch (System.Exception ex)
            {
                LogService.Instance.Log(LogLevel.Error, "Failed to update registry for startup.", ex);
            }
        }
    }
}
