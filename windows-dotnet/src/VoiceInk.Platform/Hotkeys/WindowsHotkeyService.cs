using System.Runtime.InteropServices;
using System.Threading.Channels;
using VoiceInk.Core;
using VoiceInk.Core.Config;
using VoiceInk.Core.Dictation;

namespace VoiceInk.Platform.Hotkeys;

/// <summary>
/// Global shortcuts through low-level keyboard/mouse hooks. The hooks live on a dedicated thread with its own
/// message loop, so a busy UI thread never delays (or drops) key events. Shortcut logic is in <see cref="HotkeyEngine"/>.
/// </summary>
public sealed class WindowsHotkeyService : IHotkeyService, IDisposable
{
    private readonly HotkeyEngine _engine = new(vk => (Native.GetAsyncKeyState(vk) & 0x8000) != 0);
    private readonly Native.HookProc _keyboardProc;
    private readonly Native.HookProc _mouseProc;
    private Thread? _thread;
    private uint _threadId;

    // Hook callbacks must return within milliseconds (Windows drops slow hooks), so events are queued and
    // handled in order on a worker instead of running the recording logic inside the hook.
    private readonly Channel<HotkeyEvent> _queue = Channel.CreateUnbounded<HotkeyEvent>(
        new UnboundedChannelOptions { SingleReader = true });

    public WindowsHotkeyService()
    {
        _keyboardProc = KeyboardProc;
        _mouseProc = MouseProc;
        _ = Task.Run(async () =>
        {
            await foreach (var e in _queue.Reader.ReadAllAsync())
            {
                try { Triggered?.Invoke(e); }
                catch (Exception ex) { AppLog.Error("hotkey handler failed", ex); }
            }
        });
    }

    public event Action<HotkeyEvent>? Triggered;

    public IReadOnlyList<string> Apply(HotkeySettings settings, string? commandHotkey)
    {
        var problems = _engine.Configure(settings, commandHotkey);
        Stop();
        Start(_engine.NeedsMouse);
        return problems;
    }

    public void SetActive(bool active) => _engine.Active = active;

    private void Start(bool needsMouse)
    {
        using var ready = new ManualResetEventSlim();
        _thread = new Thread(() => Loop(needsMouse, ready)) { IsBackground = true, Name = "voiceink-hotkeys" };
        _thread.Start();
        ready.Wait(TimeSpan.FromSeconds(2));
    }

    private void Stop()
    {
        if (_thread is null) return;
        Native.PostThreadMessage(_threadId, Native.WM_QUIT, 0, 0);
        _thread.Join(TimeSpan.FromSeconds(2));
        _thread = null;
    }

    private void Loop(bool needsMouse, ManualResetEventSlim ready)
    {
        _threadId = Native.GetCurrentThreadId();
        var module = Native.GetModuleHandle(null);
        var hooks = new List<nint> { Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, _keyboardProc, module, 0) };
        if (needsMouse) hooks.Add(Native.SetWindowsHookEx(Native.WH_MOUSE_LL, _mouseProc, module, 0));
        if (hooks.Contains(0)) AppLog.Error($"installing input hooks failed (error {Marshal.GetLastWin32Error()})");
        ready.Set();

        while (Native.GetMessage(out var msg, 0, 0, 0) > 0)
        {
            Native.TranslateMessage(msg);
            Native.DispatchMessage(msg);
        }

        foreach (var hook in hooks.Where(h => h != 0)) Native.UnhookWindowsHookEx(hook);
    }

    private void Emit(HotkeyEvent e) => _queue.Writer.TryWrite(e);

    private nint KeyboardProc(int code, nint wParam, nint lParam)
    {
        if (code == Native.HC_ACTION)
        {
            var info = Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
            // Ignore synthetic input, including our own Ctrl+V / typing.
            if ((info.flags & Native.LLKHF_INJECTED) == 0)
            {
                var msg = (uint)wParam;
                var down = msg is Native.WM_KEYDOWN or Native.WM_SYSKEYDOWN;
                var up = msg is Native.WM_KEYUP or Native.WM_SYSKEYUP;
                if ((down || up) && _engine.OnKey((ushort)info.vkCode, down, Emit)) return 1;
            }
        }

        return Native.CallNextHookEx(0, code, wParam, lParam);
    }

    private nint MouseProc(int code, nint wParam, nint lParam)
    {
        if (code == Native.HC_ACTION)
        {
            var info = Marshal.PtrToStructure<Native.MSLLHOOKSTRUCT>(lParam);
            if ((info.flags & Native.LLMHF_INJECTED) == 0)
            {
                var msg = (uint)wParam;
                ushort? button = msg switch
                {
                    Native.WM_XBUTTONDOWN or Native.WM_XBUTTONUP => (info.mouseData >> 16) switch
                    {
                        1 => Vk.XButton1,
                        2 => Vk.XButton2,
                        _ => null,
                    },
                    Native.WM_MBUTTONDOWN or Native.WM_MBUTTONUP => Vk.MButton,
                    _ => null,
                };
                if (button is { } b && _engine.OnMouse(b, msg is Native.WM_XBUTTONDOWN or Native.WM_MBUTTONDOWN, Emit)) return 1;
            }
        }

        return Native.CallNextHookEx(0, code, wParam, lParam);
    }

    public void Dispose()
    {
        Stop();
        _queue.Writer.TryComplete();
    }
}
