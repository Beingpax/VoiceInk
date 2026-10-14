using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace VoiceInk.App;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
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
