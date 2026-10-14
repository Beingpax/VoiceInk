using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using VoiceInk.Core;
using VoiceInk.Core.Dictation;
using static VoiceInk.Platform.Native;

namespace VoiceInk.Platform.Shell;

public enum TrayState { Idle, Recording, Busy }

/// <param name="Text">Menu label.</param>
/// <param name="OnClick">Runs when the item is chosen.</param>
public sealed record TrayMenuItem(string Text, Action? OnClick = null, bool Checked = false, bool Enabled = true)
{
    public static readonly TrayMenuItem Separator = new("");

    public bool IsSeparator => Text.Length == 0;
}

/// <summary>
/// Notification-area icon with a native context menu and balloon notices. Create it on the UI thread: it owns a
/// hidden window whose messages are dispatched by that thread's message loop.
/// </summary>
public sealed class TrayIcon : INotifier, IDisposable
{
    private const uint CallbackMessage = WM_USER + 1;
    private const string ClassName = "VoiceInkTrayWindow";

    private readonly WndProc _wndProc;
    private readonly nint _hwnd;
    private readonly uint _taskbarCreated;
    private readonly Dictionary<TrayState, nint> _icons;
    private TrayState _state = TrayState.Idle;
    private string _tooltip = "VoiceInk";

    public TrayIcon()
    {
        _wndProc = WindowProc;
        var instance = GetModuleHandle(null);
        var wc = new WNDCLASS { lpfnWndProc = _wndProc, hInstance = instance, lpszClassName = ClassName };
        RegisterClass(ref wc);
        _hwnd = CreateWindowEx(0, ClassName, "VoiceInk", 0, 0, 0, 0, 0, 0, 0, instance, 0);
        _taskbarCreated = RegisterWindowMessage("TaskbarCreated");
        _icons = new()
        {
            [TrayState.Idle] = IconFactory.Create(Color.FromArgb(0x2B, 0x7B, 0xFF)),
            [TrayState.Recording] = IconFactory.Create(Color.FromArgb(0xE5, 0x39, 0x35)),
            [TrayState.Busy] = IconFactory.Create(Color.FromArgb(0xF5, 0xA6, 0x23)),
        };
        TryEnableDarkMenus();
        Shell(NIM_ADD, NIF_MESSAGE | NIF_ICON | NIF_TIP);
    }

    /// <summary>Raised on a left click of the icon.</summary>
    public event Action? Clicked;

    /// <summary>Builds the menu each time it opens, so labels reflect the current state.</summary>
    public Func<IReadOnlyList<TrayMenuItem>>? MenuProvider { get; set; }

    [DllImport("user32.dll", EntryPoint = "RegisterWindowMessageW", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string name);

    private static void TryEnableDarkMenus()
    {
        try
        {
            SetPreferredAppMode(1); // AllowDark: follow the system theme
            FlushMenuThemes();
        }
        catch (Exception e) when (e is EntryPointNotFoundException or DllNotFoundException)
        {
            // Older Windows builds keep the light menu.
        }
    }

    public void SetState(TrayState state, string tooltip)
    {
        _state = state;
        _tooltip = tooltip;
        Shell(NIM_MODIFY, NIF_ICON | NIF_TIP);
    }

    public void Notify(string title, string message, NoticeKind kind)
    {
        AppLog.Info($"notice: {title}: {message}");
        var data = Data(NIF_INFO);
        data.szInfoTitle = Truncate(title, 63);
        data.szInfo = Truncate(message.Length == 0 ? title : message, 255);
        data.dwInfoFlags = kind switch { NoticeKind.Error => NIIF_ERROR, NoticeKind.Warning => NIIF_WARNING, _ => NIIF_INFO };
        Shell_NotifyIcon(NIM_MODIFY, ref data);
    }

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max];

    private NOTIFYICONDATA Data(uint flags) => new()
    {
        cbSize = (uint)Marshal.SizeOf<NOTIFYICONDATA>(),
        hWnd = _hwnd,
        uID = 1,
        uFlags = flags,
        uCallbackMessage = CallbackMessage,
        hIcon = _icons[_state],
        szTip = Truncate(_tooltip, 127),
        szInfo = "",
        szInfoTitle = "",
    };

    private void Shell(uint message, uint flags)
    {
        var data = Data(flags);
        Shell_NotifyIcon(message, ref data);
    }

    private nint WindowProc(nint hwnd, uint msg, nint wParam, nint lParam)
    {
        if (msg == CallbackMessage)
        {
            switch ((uint)(lParam & 0xFFFF))
            {
                case WM_LBUTTONUP: Clicked?.Invoke(); break;
                case WM_RBUTTONUP or WM_CONTEXTMENU: ShowMenu(); break;
            }

            return 0;
        }

        if (msg == _taskbarCreated) Shell(NIM_ADD, NIF_MESSAGE | NIF_ICON | NIF_TIP); // Explorer restarted
        return DefWindowProc(hwnd, msg, wParam, lParam);
    }

    private void ShowMenu()
    {
        var items = MenuProvider?.Invoke() ?? [];
        var menu = CreatePopupMenu();
        try
        {
            for (var i = 0; i < items.Count; i++)
            {
                var item = items[i];
                var flags = item.IsSeparator ? MF_SEPARATOR
                    : MF_STRING | (item.Checked ? MF_CHECKED : 0u) | (item.Enabled ? 0u : MF_GRAYED);
                AppendMenu(menu, flags, (nuint)(i + 1), item.IsSeparator ? null : item.Text);
            }

            GetCursorPos(out var p);
            SetForegroundWindow(_hwnd); // required so the menu closes when clicking elsewhere
            var chosen = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, p.x, p.y, 0, _hwnd, 0);
            PostMessage(_hwnd, 0, 0, 0);
            if (chosen > 0) items[chosen - 1].OnClick?.Invoke();
        }
        finally
        {
            DestroyMenu(menu);
        }
    }

    public void Dispose()
    {
        Shell(NIM_DELETE, 0);
        DestroyWindow(_hwnd);
        foreach (var icon in _icons.Values) DestroyIcon(icon);
    }
}

/// <summary>Draws the microphone icon at runtime, so no image assets are needed.</summary>
internal static class IconFactory
{
    public static nint Create(Color background)
    {
        using var bitmap = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using var fill = new SolidBrush(background);
            g.FillEllipse(fill, 1, 1, 30, 30);
            using var white = new SolidBrush(Color.White);
            using var pen = new Pen(Color.White, 2.2f) { StartCap = LineCap.Round, EndCap = LineCap.Round };

            using var capsule = new GraphicsPath();
            capsule.AddArc(11.5f, 6f, 9f, 9f, 180, 180);
            capsule.AddArc(11.5f, 12f, 9f, 9f, 0, 180);
            capsule.CloseFigure();
            g.FillPath(white, capsule);
            g.DrawArc(pen, 8.5f, 11f, 15f, 12f, 0, 180);
            g.DrawLine(pen, 16f, 23f, 16f, 26f);
            g.DrawLine(pen, 12f, 26f, 20f, 26f);
        }

        return bitmap.GetHicon();
    }
}
