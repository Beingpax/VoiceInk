using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace VoiceInkPoC.Services
{
    public class HotkeyService : IDisposable
    {
        // P/Invoke declarations for Windows API functions
        [DllImport("user32.dll")]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        private const int HOTKEY_ID = 9000;

        // Modifiers for the hotkey (e.g., Alt, Ctrl, Shift)
        public enum ModifierKeys : uint
        {
            None = 0,
            Alt = 1,
            Control = 2,
            Shift = 4,
            WinKey = 8
        }

        private HwndSource? _source;
        private readonly IntPtr _windowHandle;
        private Action? _hotkeyAction;

        public HotkeyService(Window window)
        {
            // Get the window handle to associate the hotkey with
            _windowHandle = new WindowInteropHelper(window).EnsureHandle();
            _source = HwndSource.FromHwnd(_windowHandle);
            _source?.AddHook(HwndHook);
        }

        public void Register(ModifierKeys modifier, uint virtualKey, Action action)
        {
            _hotkeyAction = action;
            if (!RegisterHotKey(_windowHandle, HOTKEY_ID, (uint)modifier, virtualKey))
            {
                // Handle registration failure
                throw new InvalidOperationException("Failed to register hotkey. It might be in use by another application.");
            }
        }

        public void Unregister()
        {
            UnregisterHotKey(_windowHandle, HOTKEY_ID);
        }

        private IntPtr HwndHook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            const int WM_HOTKEY = 0x0312;
            if (msg == WM_HOTKEY && wParam.ToInt32() == HOTKEY_ID)
            {
                // Hotkey was pressed, invoke the associated action
                _hotkeyAction?.Invoke();
                handled = true;
            }
            return IntPtr.Zero;
        }

        public void Dispose()
        {
            _source?.RemoveHook(HwndHook);
            _source = null;
            Unregister();
            GC.SuppressFinalize(this);
        }
    }
}
