using System.Diagnostics;
using System.Windows;
using VoiceInk.Windows.Services;

namespace VoiceInk.Windows.UI
{
    /// <summary>
    /// Interaction logic for App.xaml
    /// </summary>
    public partial class App : Application
    {
        private WindowTrackingService? _windowTrackingService;
        private BrowserUrlService? _browserUrlService;
        public static PowerModeService? PowerModeService { get; private set; }

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            // Set up global exception handler
            DispatcherUnhandledException += App_DispatcherUnhandledException;

            var settingsService = SettingsService.Instance;

            if (!settingsService.Settings.HasCompletedOnboarding)
            {
                var onboardingWindow = new Views.OnboardingWindow();
                var result = onboardingWindow.ShowDialog();
                if (result == true)
                {
                    settingsService.Settings.HasCompletedOnboarding = true;
                    // Settings will be saved on exit, so no need to save explicitly here.
                }
                else
                {
                    // User closed the onboarding window without finishing, so shut down.
                    Shutdown();
                    return;
                }
            }

            var startupService = new StartupService();
            startupService.SetLaunchAtLogin(settingsService.Settings.LaunchAtLogin);

            _browserUrlService = new BrowserUrlService();
            _windowTrackingService = new WindowTrackingService();
            PowerModeService = new PowerModeService(settingsService, _windowTrackingService, _browserUrlService);

            PowerModeService.PropertyChanged += (s, args) =>
            {
                if (args.PropertyName == nameof(PowerModeService.CurrentPrompt))
                {
                    Debug.WriteLine($"App-level prompt changed: {PowerModeService.CurrentPrompt}");
                }
            };

            // Programmatically create and show the main window
            var mainWindow = new MainWindow();
            mainWindow.Show();
        }

        private void App_DispatcherUnhandledException(object sender, System.Windows.Threading.DispatcherUnhandledExceptionEventArgs e)
        {
            LogService.Instance.Log(LogLevel.Error, "An unhandled exception occurred.", e.Exception);

            MessageBox.Show("An unexpected error occurred. Please check the log file for details. The application may need to close.", "Unhandled Error", MessageBoxButton.OK, MessageBoxImage.Error);

            // Mark the exception as handled to prevent the application from crashing immediately.
            e.Handled = true;

            // In some critical cases, you might want to force a shutdown anyway.
            // Shutdown();
        }

        protected override void OnExit(ExitEventArgs e)
        {
            // Save settings when the application is closing.
            SettingsService.Instance.SaveSettings();

            base.OnExit(e);
        }
    }
}
