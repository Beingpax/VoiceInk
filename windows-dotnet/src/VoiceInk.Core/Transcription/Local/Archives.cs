using System.Diagnostics;
using System.Text;
using SharpCompress.Compressors;
using SharpCompress.Compressors.BZip2;

namespace VoiceInk.Core.Transcription.Local;

internal static class Archives
{
    /// <summary>
    /// Extracts a <c>.tar.bz2</c> into <paramref name="targetDir"/>, dropping the archive's top-level folder. The folder
    /// appears only when extraction is complete. bzip2 is single-threaded and slow, so the system <c>tar</c> (bsdtar on
    /// Windows 10+, about twice as fast) is preferred; a managed extractor is the fallback.
    /// </summary>
    public static void ExtractTarBz2(string archivePath, string targetDir, bool preferNative = true)
    {
        var staging = targetDir + ".extracting";
        if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true);
        Directory.CreateDirectory(staging);
        try
        {
            if (!(preferNative && TryNativeTar(archivePath, staging))) ManagedExtract(archivePath, staging);
            if (Directory.Exists(targetDir)) Directory.Delete(targetDir, recursive: true);
            Directory.Move(staging, targetDir);
        }
        catch
        {
            if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true);
            throw;
        }
    }

    /// <summary>Both bsdtar and GNU tar refuse or neutralize absolute and <c>..</c> paths, so nothing escapes <c>-C</c>.</summary>
    private static bool TryNativeTar(string archivePath, string staging)
    {
        var tar = OperatingSystem.IsWindows() ? Path.Combine(Environment.SystemDirectory, "tar.exe") : "tar";
        if (OperatingSystem.IsWindows() && !File.Exists(tar)) return false;
        try
        {
            var info = new ProcessStartInfo(tar)
            {
                ArgumentList = { "-xjf", archivePath, "-C", staging, "--strip-components=1" },
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                CreateNoWindow = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(info);
            if (process is null) return false;
            _ = process.StandardOutput.ReadToEndAsync();
            var error = process.StandardError.ReadToEndAsync();
            process.WaitForExit();
            if (process.ExitCode == 0) return true;
            AppLog.Warn($"tar failed ({process.ExitCode}): {error.Result.Trim()}; using the managed extractor");
            return false;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return false; // no tar installed
        }
    }

    /// <summary>
    /// Minimal tar reader over a bzip2 stream. SharpCompress' own tar reader sniffs the format by rewinding, which fails
    /// on real model archives (incompressible data overflows its 900 KB look-back), so the stream is read directly.
    /// </summary>
    private static void ManagedExtract(string archivePath, string staging)
    {
        var root = Path.GetFullPath(staging) + Path.DirectorySeparatorChar;
        using var file = File.OpenRead(archivePath);
        using var tar = BZip2Stream.Create(file, CompressionMode.Decompress, false, false, false);
        var header = new byte[512];
        string? longName = null;
        while (true)
        {
            if (!ReadBlock(tar, header) || header.All(b => b == 0)) break;
            var size = ParseOctal(header.AsSpan(124, 12));
            var type = (char)header[156];
            var padded = (size + 511) / 512 * 512;

            if (type is 'L' or 'x')
            {
                // GNU long name / pax extended header: only the path matters.
                var data = new byte[size];
                tar.ReadExactly(data);
                tar.ReadExactly(new byte[padded - size]);
                longName = type == 'L' ? Encoding.UTF8.GetString(data).TrimEnd('\0') : PaxPath(data) ?? longName;
                continue;
            }

            var name = longName ?? TarName(header);
            longName = null;
            if (type is '0' or '\0')
            {
                var relative = StripTopLevel(name);
                if (relative.Length == 0)
                {
                    Skip(tar, padded);
                    continue;
                }

                var destination = Path.GetFullPath(Path.Combine(staging, relative));
                if (!destination.StartsWith(root, StringComparison.Ordinal))
                {
                    throw new InvalidDataException($"archive entry escapes the target folder: {name}");
                }

                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                using var output = File.Create(destination);
                Copy(tar, output, size);
                Skip(tar, padded - size);
            }
            else
            {
                Skip(tar, padded); // directories, links, ...
            }
        }
    }

    private static bool ReadBlock(Stream stream, byte[] block)
    {
        var read = 0;
        while (read < block.Length)
        {
            var n = stream.Read(block, read, block.Length - read);
            if (n == 0) return false;
            read += n;
        }

        return true;
    }

    private static void Copy(Stream from, Stream to, long bytes)
    {
        var buffer = new byte[1 << 20];
        while (bytes > 0)
        {
            var n = from.Read(buffer, 0, (int)Math.Min(buffer.Length, bytes));
            if (n <= 0) throw new EndOfStreamException("the archive is truncated");
            to.Write(buffer, 0, n);
            bytes -= n;
        }
    }

    private static void Skip(Stream from, long bytes)
    {
        var buffer = new byte[1 << 16];
        while (bytes > 0)
        {
            var n = from.Read(buffer, 0, (int)Math.Min(buffer.Length, bytes));
            if (n <= 0) throw new EndOfStreamException("the archive is truncated");
            bytes -= n;
        }
    }

    private static long ParseOctal(ReadOnlySpan<byte> field)
    {
        var text = Encoding.ASCII.GetString(field).Trim('\0', ' ');
        return text.Length == 0 ? 0 : Convert.ToInt64(text, 8);
    }

    private static string TarName(byte[] header)
    {
        var name = Encoding.UTF8.GetString(header, 0, 100).TrimEnd('\0');
        var isUstar = Encoding.ASCII.GetString(header, 257, 5) == "ustar";
        var prefix = isUstar ? Encoding.UTF8.GetString(header, 345, 155).TrimEnd('\0') : "";
        return prefix.Length > 0 ? $"{prefix}/{name}" : name;
    }

    private static string? PaxPath(byte[] data)
    {
        foreach (var record in Encoding.UTF8.GetString(data).Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            var eq = record.IndexOf("path=", StringComparison.Ordinal);
            if (eq >= 0) return record[(eq + 5)..];
        }

        return null;
    }

    private static string StripTopLevel(string name)
    {
        var parts = name.Replace('\\', '/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length <= 1 ? "" : string.Join('/', parts[1..]);
    }
}
