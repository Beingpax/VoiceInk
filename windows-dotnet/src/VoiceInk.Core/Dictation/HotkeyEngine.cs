using VoiceInk.Core.Config;

namespace VoiceInk.Core.Dictation;

/// <summary>
/// Pure shortcut logic: turns raw key/mouse transitions into <see cref="HotkeyEvent"/>s. The Windows layer feeds it
/// from low-level hooks; keeping it free of Win32 makes it testable and independent of the input source.
/// </summary>
public sealed class HotkeyEngine(Func<ushort, bool> isKeyDown)
{
    private sealed class Trigger(TriggerKind kind, Hotkey? hotkey)
    {
        public TriggerKind Kind { get; } = kind;
        public Hotkey? Hotkey { get; } = hotkey;
        public bool Held { get; set; }
        public bool Clean { get; set; }
    }

    private readonly object _gate = new();
    private Trigger[] _triggers = [];
    private Hotkey? _cancel;
    private Hotkey? _pasteLast;
    private HotkeyMode _mode = HotkeyMode.Hybrid;

    /// <summary>While active (recording/processing) the cancel key is swallowed and reported.</summary>
    public volatile bool Active;

    public bool NeedsMouse { get; private set; }

    /// <summary>Applies new settings and returns problems with individual shortcuts.</summary>
    public IReadOnlyList<string> Configure(HotkeySettings settings, string? commandHotkey)
    {
        var problems = new List<string>();
        var record = ParseOptional(settings.Record, "record", problems);
        var command = ParseOptional(commandHotkey, "command", problems);
        if (command is not null && command == record)
        {
            problems.Add("the Command Mode shortcut must differ from the record shortcut");
            command = null;
        }

        lock (_gate)
        {
            _triggers = [new Trigger(TriggerKind.Dictation, record), new Trigger(TriggerKind.Command, command)];
            _cancel = ParseOptional(settings.Cancel, "cancel", problems);
            _pasteLast = ParseOptional(settings.PasteLast, "paste-last", problems);
            _mode = settings.Mode;
            NeedsMouse = record is Hotkey.Mouse || command is Hotkey.Mouse;
        }

        return problems;
    }

    private static Hotkey? ParseOptional(string? spec, string what, List<string> problems)
    {
        if (string.IsNullOrWhiteSpace(spec)) return null;
        if (HotkeyParser.TryParse(spec.Trim(), out var hotkey, out var error)) return hotkey;
        problems.Add($"{what} hotkey '{spec}': {error}");
        return null;
    }

    /// <summary>Handles a physical key transition. Returns true when the key must be swallowed.</summary>
    public bool OnKey(ushort vk, bool down, Action<HotkeyEvent> emit)
    {
        lock (_gate)
        {
            var swallow = false;
            foreach (var trigger in _triggers) swallow |= OnKey(trigger, vk, down, emit);

            if (down && !HotkeyParser.IsModifierVk(vk) && !swallow)
            {
                if (Active && IsCancel(vk))
                {
                    emit(new HotkeyEvent(HotkeyEventKind.Cancel));
                    swallow = true;
                }
                else if (Matches(_pasteLast, vk))
                {
                    emit(new HotkeyEvent(HotkeyEventKind.PasteLast));
                    swallow = true;
                }
            }

            return swallow;
        }
    }

    /// <summary>Handles a mouse button transition. Returns true when the click must be swallowed.</summary>
    public bool OnMouse(ushort button, bool down, Action<HotkeyEvent> emit)
    {
        lock (_gate)
        {
            var swallow = false;
            foreach (var t in _triggers)
            {
                if (t.Hotkey is not Hotkey.Mouse m || m.Button != button) continue;
                if (down && !t.Held)
                {
                    t.Held = true;
                    emit(new HotkeyEvent(HotkeyEventKind.Down, t.Kind));
                }
                else if (!down && t.Held)
                {
                    t.Held = false;
                    emit(new HotkeyEvent(HotkeyEventKind.Up, t.Kind));
                }

                swallow = true;
            }

            return swallow;
        }
    }

    private bool OnKey(Trigger t, ushort code, bool down, Action<HotkeyEvent> emit)
    {
        switch (t.Hotkey)
        {
            case Hotkey.ModifierOnly m when SameModifier(m.Vk, code):
                if (down && !t.Held)
                {
                    t.Held = true;
                    t.Clean = true;
                    if (_mode != HotkeyMode.Toggle) emit(new HotkeyEvent(HotkeyEventKind.Down, t.Kind));
                }
                else if (!down && t.Held)
                {
                    t.Held = false;
                    if (_mode == HotkeyMode.Toggle)
                    {
                        if (t.Clean) emit(new HotkeyEvent(HotkeyEventKind.Down, t.Kind));
                    }
                    else
                    {
                        emit(new HotkeyEvent(HotkeyEventKind.Up, t.Kind));
                    }
                }

                return false; // Never swallow modifiers: other shortcuts still need them.

            case Hotkey.ModifierOnly when down && t.Held:
                // Another key while the modifier is held: it's a regular shortcut, not ours.
                if (t.Clean)
                {
                    t.Clean = false;
                    if (_mode != HotkeyMode.Toggle) emit(new HotkeyEvent(HotkeyEventKind.Abort, t.Kind));
                }

                return false;

            case Hotkey.Key k when k.Vk == code:
                if (down && !t.Held && Matches(t.Hotkey, code))
                {
                    t.Held = true;
                    emit(new HotkeyEvent(HotkeyEventKind.Down, t.Kind));
                    return true;
                }

                if (down && t.Held) return true; // auto-repeat
                if (!down && t.Held)
                {
                    t.Held = false;
                    emit(new HotkeyEvent(HotkeyEventKind.Up, t.Kind));
                    return true;
                }

                return false;

            default:
                return false;
        }
    }

    private Modifiers CurrentModifiers() => new(
        Ctrl: isKeyDown(Vk.Control),
        Alt: isKeyDown(Vk.Menu),
        Shift: isKeyDown(Vk.Shift),
        Win: isKeyDown(Vk.LWin) || isKeyDown(Vk.RWin));

    private bool Matches(Hotkey? hotkey, ushort code) =>
        hotkey is Hotkey.Key k && k.Vk == code && k.Modifiers == CurrentModifiers();

    private bool IsCancel(ushort code) => _cancel switch
    {
        // A bare cancel key (Escape) also fires while modifiers are held.
        Hotkey.Key { Modifiers.IsEmpty: true } k => k.Vk == code,
        var other => Matches(other, code),
    };

    private static bool SameModifier(ushort configured, ushort pressed) =>
        configured == pressed || (configured, pressed) is
            (Vk.Control, Vk.LControl or Vk.RControl) or (Vk.Menu, Vk.LMenu or Vk.RMenu) or (Vk.Shift, Vk.LShift or Vk.RShift);
}
