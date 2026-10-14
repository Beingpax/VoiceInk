using System.Runtime.InteropServices;
using System.Text;
using static VoiceInk.Platform.Native;

namespace VoiceInk.Platform.Input;

/// <summary>Raw Win32 clipboard: exact multi-format snapshots and history-excluded text.</summary>
public static class ClipboardApi
{
    private static readonly uint[] NonGlobalFormats = [2, 3, 9, 14, 0x80, 0x82, 0x83, 0x8E];

    private sealed class Opened : IDisposable
    {
        private Opened() { }

        public static Opened Acquire()
        {
            var deadline = DateTime.UtcNow.AddMilliseconds(500);
            while (!OpenClipboard(0))
            {
                if (DateTime.UtcNow > deadline) throw new IOException("the clipboard is in use by another application");
                Thread.Sleep(15);
            }

            return new Opened();
        }

        public void Dispose() => CloseClipboard();
    }

    private static void SetBytes(uint format, byte[] bytes)
    {
        var mem = GlobalAlloc(GMEM_MOVEABLE, (nuint)Math.Max(1, bytes.Length));
        var ptr = mem == 0 ? 0 : GlobalLock(mem);
        if (ptr == 0)
        {
            if (mem != 0) GlobalFree(mem);
            throw new IOException("could not allocate clipboard memory");
        }

        Marshal.Copy(bytes, 0, ptr, bytes.Length);
        GlobalUnlock(mem);
        if (SetClipboardData(format, mem) == 0)
        {
            GlobalFree(mem);
            throw new IOException("SetClipboardData failed");
        }
    }

    private static byte[]? ReadBytes(uint format)
    {
        var handle = GetClipboardData(format);
        if (handle == 0) return null;
        var size = (int)GlobalSize(handle);
        var ptr = GlobalLock(handle);
        if (ptr == 0) return null;
        var data = new byte[size];
        Marshal.Copy(ptr, data, 0, size);
        GlobalUnlock(handle);
        return data;
    }

    public static uint SequenceNumber => GetClipboardSequenceNumber();

    public static string? GetText()
    {
        if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) return null;
        try
        {
            using var _ = Opened.Acquire();
            return ReadBytes(CF_UNICODETEXT) is { } bytes ? Encoding.Unicode.GetString(bytes).TrimEnd('\0') : null;
        }
        catch (IOException)
        {
            return null;
        }
    }

    /// <summary>Replaces the clipboard. <paramref name="transient"/> keeps it out of Win+V history and cloud sync.</summary>
    public static uint SetText(string text, bool transient)
    {
        using (Opened.Acquire())
        {
            EmptyClipboard();
            SetBytes(CF_UNICODETEXT, Encoding.Unicode.GetBytes(text + "\0"));
            if (transient)
            {
                var zero = new byte[4];
                foreach (var name in new[]
                         {
                             "ExcludeClipboardContentFromMonitorProcessing", "CanIncludeInClipboardHistory", "CanUploadToCloudClipboard",
                         })
                {
                    try { SetBytes(RegisterClipboardFormat(name), zero); } catch (IOException) { }
                }
            }
        }

        return SequenceNumber;
    }

    /// <summary>All clipboard formats at one moment, to be put back after a paste.</summary>
    public sealed class Snapshot
    {
        private readonly List<(uint Format, byte[] Data)> _items = [];

        public static Snapshot Capture()
        {
            var snapshot = new Snapshot();
            try
            {
                using var _ = Opened.Acquire();
                for (var format = EnumClipboardFormats(0); format != 0; format = EnumClipboardFormats(format))
                {
                    if (Array.IndexOf(NonGlobalFormats, format) >= 0) continue;
                    if (ReadBytes(format) is { } bytes) snapshot._items.Add((format, bytes));
                }
            }
            catch (IOException)
            {
                // An unreadable clipboard simply isn't restored.
            }

            return snapshot;
        }

        public void Restore()
        {
            using var _ = Opened.Acquire();
            EmptyClipboard();
            foreach (var (format, data) in _items)
            {
                // Synthesized formats (e.g. CF_TEXT from CF_UNICODETEXT) may fail; that's fine.
                try { SetBytes(format, data); } catch (IOException) { }
            }
        }
    }
}
