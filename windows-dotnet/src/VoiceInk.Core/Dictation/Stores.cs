using VoiceInk.Core.Config;

namespace VoiceInk.Core.Dictation;

public sealed class FileHistoryStore : IHistoryStore
{
    public void Append(HistoryEntry entry, int maxEntries)
    {
        History.Append(AppPaths.HistoryPath, entry);
        History.Trim(AppPaths.HistoryPath, maxEntries);
    }

    public string? LastText() => History.LastText(AppPaths.HistoryPath);
}

/// <summary>Config file with change detection, so edits are picked up before the next recording.</summary>
public sealed class FileConfigStore : IConfigStore
{
    private readonly string _path;
    private DateTime _mtime;

    public FileConfigStore(string? path = null)
    {
        _path = path ?? AppPaths.ConfigPath;
        Current = AppConfig.Load(_path);
        _mtime = Mtime();
    }

    public AppConfig Current { get; private set; }

    public event Action? Changed;

    private DateTime Mtime() => File.Exists(_path) ? File.GetLastWriteTimeUtc(_path) : DateTime.MinValue;

    public bool Reload(bool force = false)
    {
        var mtime = Mtime();
        if (!force && mtime == _mtime) return false;
        Current = AppConfig.Load(_path);
        _mtime = mtime;
        Changed?.Invoke();
        return true;
    }

    public void Save()
    {
        Current.Save(_path);
        _mtime = Mtime();
        Changed?.Invoke();
    }
}
