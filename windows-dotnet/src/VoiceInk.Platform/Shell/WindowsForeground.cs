using System.Text;
using VoiceInk.Core;
using VoiceInk.Core.Dictation;
using static VoiceInk.Platform.Native;

namespace VoiceInk.Platform.Shell;

/// <summary>
/// Knows which application should receive the text. While VoiceInk itself or the taskbar has focus, the last
/// external window (tracked through a foreground-change hook) is used instead.
/// </summary>
public sealed class WindowsForeground : IForeground, IDisposable
{
    private static readonly HashSet<string> ShellClasses =
        ["Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow", "TopLevelWindowForOverflowXamlIsland"];

    private readonly WinEventProc _callback;
    private readonly nint _hook;
    private nint _lastExternal;

    /// <summary>Create on a thread with a message loop (the UI thread); the hook is delivered through it.</summary>
    public WindowsForeground()
    {
        _callback = OnForegroundChanged;
        _hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, 0, _callback, 0, 0, WINEVENT_OUTOFCONTEXT);
        var current = GetForegroundWindow();
        if (!IsOwnOrShell(current)) _lastExternal = current;
    }

    private void OnForegroundChanged(nint hook, uint eventId, nint hwnd, int idObject, int idChild, uint thread, uint time)
    {
        if (!IsOwnOrShell(hwnd)) _lastExternal = hwnd;
    }

    public ForegroundTarget Capture()
    {
        var hwnd = GetForegroundWindow();
        if (IsOwnOrShell(hwnd) && _lastExternal != 0 && IsWindow(_lastExternal)) hwnd = _lastExternal;
        return hwnd == 0
            ? new ForegroundTarget(0, new ForegroundInfo())
            : new ForegroundTarget(hwnd, new ForegroundInfo(ProcessName(hwnd), WindowTitle(hwnd)));
    }

    public void Restore(nint handle)
    {
        if (handle == 0 || !IsWindow(handle)) return;
        if (GetForegroundWindow() != handle)
        {
            SetForegroundWindow(handle);
            Thread.Sleep(50);
        }
    }

    private static bool IsOwnOrShell(nint hwnd)
    {
        if (hwnd == 0) return true;
        GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == GetCurrentProcessId()) return true;
        var buffer = new StringBuilder(64);
        GetClassName(hwnd, buffer, buffer.Capacity);
        return ShellClasses.Contains(buffer.ToString());
    }

    private static string WindowTitle(nint hwnd)
    {
        var length = GetWindowTextLength(hwnd);
        if (length <= 0) return "";
        var buffer = new StringBuilder(length + 1);
        GetWindowText(hwnd, buffer, buffer.Capacity);
        return buffer.ToString();
    }

    private static string ProcessName(nint hwnd)
    {
        GetWindowThreadProcessId(hwnd, out var pid);
        if (pid == 0) return "";
        var process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (process == 0) return "";
        try
        {
            var buffer = new StringBuilder(1024);
            var size = (uint)buffer.Capacity;
            return QueryFullProcessImageName(process, 0, buffer, ref size)
                ? Path.GetFileName(buffer.ToString()).ToLowerInvariant()
                : "";
        }
        finally
        {
            CloseHandle(process);
        }
    }

    public void Dispose()
    {
        if (_hook != 0) UnhookWinEvent(_hook);
    }
}
