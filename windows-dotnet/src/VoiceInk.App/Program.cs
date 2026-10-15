using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace VoiceInk.App;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            VoiceInk.Core.AppLog.Error("fatal startup exception", e.ExceptionObject as Exception);
        try
        {
            return Run(args);
        }
        catch (Exception e)
        {
            VoiceInk.Core.AppLog.Error("startup failed", e);
            return 1;
        }
    }

    private static int Run(string[] args)
    {
        if (Cli.TryRun(args) is { } exitCode) return exitCode;

        using var instance = SingleInstance.TryAcquire();
        if (instance is null)
        {
            SingleInstance.Forward(args.FirstOrDefault() ?? "dashboard");
            return 0;
        }

        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(callback =>
        {
            SynchronizationContext.SetSynchronizationContext(
                new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            new VoiceInkApp(instance, args.FirstOrDefault());
        });
        return 0;
    }
}
