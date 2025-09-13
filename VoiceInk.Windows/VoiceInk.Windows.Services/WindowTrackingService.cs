using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace VoiceInk.Windows.Services
{
    /// <summary>
    /// A service that tracks the active foreground window using Windows events.
    /// </summary>
    public class WindowTrackingService : IDisposable
    {
        public event EventHandler<ActiveWindowChangedEventArgs>? ActiveWindowChanged;

        private delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);
        private readonly WinEventDelegate _delegate;
        private readonly IntPtr _hook;

        public WindowTrackingService()
        {
            // The delegate must be stored as a field to prevent it from being garbage collected.
            _delegate = new WinEventDelegate(WinEventProc);
            // Listen for foreground window changes
            _hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, IntPtr.Zero, _delegate, 0, 0, WINEVENT_OUTOFCONTEXT);
        }

        private void WinEventProc(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
        {
            var activeWindowInfo = GetActiveWindowInfo(hwnd);
            ActiveWindowChanged?.Invoke(this, new ActiveWindowChangedEventArgs(activeWindowInfo));
        }

        private ActiveWindowInfo GetActiveWindowInfo(IntPtr hwnd)
        {
            GetWindowThreadProcessId(hwnd, out var pid);
            var process = Process.GetProcessById((int)pid);

            var windowTitle = new StringBuilder(256);
            GetWindowText(hwnd, windowTitle, windowTitle.Capacity);

            var processName = process.ProcessName;
            var executablePath = process.MainModule?.FileName ?? "Unknown";

            return new ActiveWindowInfo(processName, executablePath, windowTitle.ToString(), hwnd);
        }

        public void Dispose()
        {
            UnhookWinEvent(_hook);
            GC.SuppressFinalize(this);
        }

        #region P/Invoke Definitions

        [DllImport("user32.dll")]
        private static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc, WinEventDelegate lpfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

        [DllImport("user32.dll")]
        private static extern bool UnhookWinEvent(IntPtr hWinEventHook);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        private const uint WINEVENT_OUTOFCONTEXT = 0;
        private const uint EVENT_SYSTEM_FOREGROUND = 3;

        #endregion
    }

    /// <summary>
    /// Contains information about the currently active window.
    /// </summary>
    public class ActiveWindowChangedEventArgs : EventArgs
    {
        public ActiveWindowInfo ActiveWindow { get; }

        public ActiveWindowChangedEventArgs(ActiveWindowInfo activeWindow)
        {
            ActiveWindow = activeWindow;
        }
    }

    /// <summary>
    /// A record to hold information about the active window.
    /// </summary>
    public record ActiveWindowInfo(string ProcessName, string ExecutablePath, string WindowTitle, IntPtr WindowHandle);
}
