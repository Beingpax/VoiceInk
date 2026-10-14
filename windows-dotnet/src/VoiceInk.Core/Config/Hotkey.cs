namespace VoiceInk.Core.Config;

/// <summary>Virtual-key codes used by the parser (values from <c>WinUser.h</c>).</summary>
public static class Vk
{
    public const ushort Back = 0x08;
    public const ushort Tab = 0x09;
    public const ushort Return = 0x0D;
    public const ushort Shift = 0x10;
    public const ushort Control = 0x11;
    public const ushort Menu = 0x12;
    public const ushort Pause = 0x13;
    public const ushort Capital = 0x14;
    public const ushort Escape = 0x1B;
    public const ushort Space = 0x20;
    public const ushort Prior = 0x21;
    public const ushort Next = 0x22;
    public const ushort End = 0x23;
    public const ushort Home = 0x24;
    public const ushort Left = 0x25;
    public const ushort Up = 0x26;
    public const ushort Right = 0x27;
    public const ushort Down = 0x28;
    public const ushort Snapshot = 0x2C;
    public const ushort Insert = 0x2D;
    public const ushort Delete = 0x2E;
    public const ushort LWin = 0x5B;
    public const ushort RWin = 0x5C;
    public const ushort Apps = 0x5D;
    public const ushort F1 = 0x70;
    public const ushort Scroll = 0x91;
    public const ushort LShift = 0xA0;
    public const ushort RShift = 0xA1;
    public const ushort LControl = 0xA2;
    public const ushort RControl = 0xA3;
    public const ushort LMenu = 0xA4;
    public const ushort RMenu = 0xA5;
    public const ushort XButton1 = 0x05;
    public const ushort XButton2 = 0x06;
    public const ushort MButton = 0x04;
}

public readonly record struct Modifiers(bool Ctrl = false, bool Alt = false, bool Shift = false, bool Win = false)
{
    public bool IsEmpty => !(Ctrl || Alt || Shift || Win);
}

/// <summary>A parsed hotkey.</summary>
public abstract record Hotkey
{
    /// <summary>A modifier pressed and released on its own, e.g. <c>RightCtrl</c>.</summary>
    public sealed record ModifierOnly(ushort Vk) : Hotkey;

    /// <summary>A regular key with optional modifiers, e.g. <c>Ctrl+Shift+Space</c> or <c>F9</c>.</summary>
    public sealed record Key(ushort Vk, Modifiers Modifiers) : Hotkey;

    /// <summary>A mouse button (<c>Mouse4</c>, <c>Mouse5</c>, <c>MiddleMouse</c>).</summary>
    public sealed record Mouse(ushort Button) : Hotkey;
}

public static class HotkeyParser
{
    public static bool IsModifierVk(ushort code) => code is
        Vk.Shift or Vk.Control or Vk.Menu or Vk.LShift or Vk.RShift or Vk.LControl or Vk.RControl
        or Vk.LMenu or Vk.RMenu or Vk.LWin or Vk.RWin;

    private static string Normalize(string name) =>
        name.Trim().ToLowerInvariant().Replace(" ", "").Replace("_", "").Replace("-", "");

    private static ushort? KeyNameToVk(string name)
    {
        var n = Normalize(name);
        switch (n)
        {
            case "rightctrl" or "rctrl" or "rightcontrol": return Vk.RControl;
            case "leftctrl" or "lctrl" or "leftcontrol": return Vk.LControl;
            case "rightalt" or "ralt" or "altgr": return Vk.RMenu;
            case "leftalt" or "lalt": return Vk.LMenu;
            case "rightshift" or "rshift": return Vk.RShift;
            case "leftshift" or "lshift": return Vk.LShift;
            case "rightwin" or "rwin": return Vk.RWin;
            case "leftwin" or "lwin": return Vk.LWin;
            case "space": return Vk.Space;
            case "enter" or "return": return Vk.Return;
            case "tab": return Vk.Tab;
            case "esc" or "escape": return Vk.Escape;
            case "backspace": return Vk.Back;
            case "pause" or "break": return Vk.Pause;
            case "capslock": return Vk.Capital;
            case "scrolllock": return Vk.Scroll;
            case "printscreen" or "prtsc": return Vk.Snapshot;
            case "insert" or "ins": return Vk.Insert;
            case "delete" or "del": return Vk.Delete;
            case "home": return Vk.Home;
            case "end": return Vk.End;
            case "pageup" or "pgup": return Vk.Prior;
            case "pagedown" or "pgdn": return Vk.Next;
            case "left": return Vk.Left;
            case "right": return Vk.Right;
            case "up": return Vk.Up;
            case "down": return Vk.Down;
            case "menu" or "apps": return Vk.Apps;
            case "`" or "backtick" or "grave": return 0xC0;
            case "," or "comma": return 0xBC;
            case "." or "period": return 0xBE;
            case "/" or "slash": return 0xBF;
            case ";" or "semicolon": return 0xBA;
        }

        if (n.Length > 1 && n[0] == 'f' && ushort.TryParse(n.AsSpan(1), out var num))
        {
            return num is >= 1 and <= 24 ? (ushort)(Vk.F1 + num - 1) : null;
        }

        if (n.Length == 1 && char.IsAsciiLetterOrDigit(n[0]))
        {
            return char.ToUpperInvariant(n[0]);
        }

        return null;
    }

    private static ushort? MouseName(string name) => Normalize(name) switch
    {
        "mouse4" or "xbutton1" or "mouseback" => Vk.XButton1,
        "mouse5" or "xbutton2" or "mouseforward" => Vk.XButton2,
        "middlemouse" or "mouse3" or "mbutton" => Vk.MButton,
        _ => null,
    };

    /// <summary>Parses <c>RightCtrl</c>, <c>F9</c>, <c>Ctrl+Shift+Space</c>, <c>Mouse4</c>, ...</summary>
    public static Hotkey Parse(string spec)
    {
        var parts = spec.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0)
        {
            throw new FormatException("empty hotkey");
        }

        if (parts.Length == 1)
        {
            if (MouseName(parts[0]) is { } button)
            {
                return new Hotkey.Mouse(button);
            }

            var code = KeyNameToVk(parts[0]) ?? throw new FormatException($"unknown key '{parts[0]}'");
            return IsModifierVk(code)
                ? new Hotkey.ModifierOnly(code)
                : new Hotkey.Key(code, default);
        }

        var modifiers = default(Modifiers);
        foreach (var part in parts[..^1])
        {
            modifiers = part.ToLowerInvariant() switch
            {
                "ctrl" or "control" => modifiers with { Ctrl = true },
                "alt" => modifiers with { Alt = true },
                "shift" => modifiers with { Shift = true },
                "win" or "super" or "meta" => modifiers with { Win = true },
                var other => throw new FormatException($"unknown modifier '{other}'"),
            };
        }

        var last = parts[^1];
        var key = KeyNameToVk(last) ?? throw new FormatException($"unknown key '{last}'");
        if (IsModifierVk(key))
        {
            throw new FormatException("the last part of a key combination must be a non-modifier key");
        }

        return new Hotkey.Key(key, modifiers);
    }

    public static bool TryParse(string spec, out Hotkey hotkey, out string error)
    {
        try
        {
            hotkey = Parse(spec);
            error = "";
            return true;
        }
        catch (FormatException e)
        {
            hotkey = null!;
            error = e.Message;
            return false;
        }
    }
}
