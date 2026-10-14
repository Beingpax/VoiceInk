using static VoiceInk.Platform.Native;

namespace VoiceInk.Platform.Input;

/// <summary>Synthesizes keystrokes with <c>SendInput</c>.</summary>
internal static class Keyboard
{
    public const ushort VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12, VK_RETURN = 0x0D, VK_INSERT = 0x2D;
    public const ushort VK_C = 0x43, VK_V = 0x56;
    private static readonly ushort[] HeldModifiers = [0xA0, 0xA1, 0xA4, 0xA5, 0x5B, 0x5C, VK_SHIFT, VK_MENU];
    private static readonly TimeSpan KeyDelay = TimeSpan.FromMilliseconds(8);

    private static INPUT Key(ushort vk, bool up)
    {
        var extended = vk is VK_INSERT or 0xA3 or 0xA5;
        var flags = (up ? KEYEVENTF_KEYUP : 0u) | (extended ? KEYEVENTF_EXTENDEDKEY : 0u);
        return new INPUT { type = INPUT_KEYBOARD, u = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = flags } } };
    }

    private static INPUT Unicode(ushort unit, bool up) => new()
    {
        type = INPUT_KEYBOARD,
        u = new InputUnion { ki = new KEYBDINPUT { wScan = unit, dwFlags = KEYEVENTF_UNICODE | (up ? KEYEVENTF_KEYUP : 0u) } },
    };

    private static bool Send(params INPUT[] inputs) =>
        SendInput((uint)inputs.Length, inputs, System.Runtime.InteropServices.Marshal.SizeOf<INPUT>()) == inputs.Length;

    /// <summary>Releases Shift/Alt/Win still held from the shortcut so they don't change the next key combination.</summary>
    public static void ReleaseHeldModifiers()
    {
        var held = HeldModifiers
            .Where(vk => (GetAsyncKeyState(vk) & 0x8000) != 0)
            .Select(vk => Key(vk, up: true))
            .ToArray();
        if (held.Length > 0) Send(held);
    }

    /// <summary>A complete modifier+key chord, with small pauses so slow apps see every step.</summary>
    public static bool Chord(ushort modifier, ushort key)
    {
        INPUT[] steps = [Key(modifier, false), Key(key, false), Key(key, true), Key(modifier, true)];
        var ok = true;
        foreach (var step in steps)
        {
            ok &= Send(step);
            Thread.Sleep(KeyDelay);
        }

        return ok;
    }

    public static bool Tap(ushort key) => Send(Key(key, false), Key(key, true));

    /// <summary>Types text as Unicode key events; newlines become Return presses (bare "\n" is ignored by many apps).</summary>
    public static bool TypeText(string text)
    {
        var ok = true;
        var batch = new List<INPUT>();

        bool Flush()
        {
            var sent = batch.Count == 0 || Send([.. batch]);
            batch.Clear();
            return sent;
        }

        foreach (var ch in text.Replace("\r\n", "\n", StringComparison.Ordinal))
        {
            if (ch == '\n')
            {
                ok &= Flush();
                ok &= Tap(VK_RETURN);
                continue;
            }

            batch.Add(Unicode(ch, false));
            batch.Add(Unicode(ch, true));
            if (batch.Count >= 200)
            {
                ok &= Flush();
                Thread.Sleep(KeyDelay);
            }
        }

        return ok & Flush();
    }
}
