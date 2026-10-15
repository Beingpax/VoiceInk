using System.Text;
using System.Text.Json;
using VoiceInk.Core.Config;

namespace VoiceInk.Core;

/// <summary>Protects secrets at rest. The Windows build plugs in DPAPI; elsewhere keys are only encoded.</summary>
public interface ISecretProtector
{
    byte[] Protect(byte[] data);
    byte[] Unprotect(byte[] data);
}

internal sealed class PlainProtector : ISecretProtector
{
    public byte[] Protect(byte[] data) => data;
    public byte[] Unprotect(byte[] data) => data;
}

/// <summary>API keys in <c>keys.json</c>, encrypted per Windows user. Environment variables win over the store.</summary>
public static class Credentials
{
    private static readonly AppJsonContext StoreJson = new(new JsonSerializerOptions { WriteIndented = true });

    private static readonly object Gate = new();

    /// <summary>Set by the Windows platform layer at startup (DPAPI).</summary>
    public static ISecretProtector Protector { get; set; } = new PlainProtector();

    private static string[] EnvNames(string name)
    {
        var upper = name.ToUpperInvariant().Replace('-', '_');
        return [$"VOICEINK_{upper}_API_KEY", $"{upper}_API_KEY"];
    }

    private static SortedDictionary<string, string> LoadStore()
    {
        try
        {
            var path = AppPaths.KeysPath;
            if (!File.Exists(path)) return [];
            var dict = JsonSerializer.Deserialize(File.ReadAllText(path), StoreJson.DictionaryStringString);
            return dict is null ? [] : new SortedDictionary<string, string>(dict, StringComparer.Ordinal);
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    private static void SaveStore(SortedDictionary<string, string> store)
    {
        var path = AppPaths.KeysPath;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(store, StoreJson.SortedDictionaryStringString));
    }

    /// <summary>Returns the API key for a provider key name (<c>"groq"</c>, <c>"openai"</c>, ...).</summary>
    public static string? Get(string name)
    {
        if (string.IsNullOrEmpty(name)) return null;
        foreach (var variable in EnvNames(name))
        {
            var value = Environment.GetEnvironmentVariable(variable);
            if (!string.IsNullOrWhiteSpace(value)) return value.Trim();
        }

        lock (Gate)
        {
            if (!LoadStore().TryGetValue(name, out var encoded)) return null;
            try
            {
                var plain = Encoding.UTF8.GetString(Protector.Unprotect(Convert.FromBase64String(encoded)));
                return plain.Length == 0 ? null : plain;
            }
            catch (Exception e) when (e is FormatException or System.Security.Cryptography.CryptographicException)
            {
                return null;
            }
        }
    }

    public static bool Has(string name) => Get(name) is not null;

    /// <summary>Stores (or, for an empty key, removes) the key.</summary>
    public static void Set(string name, string key)
    {
        lock (Gate)
        {
            var store = LoadStore();
            key = key.Trim();
            if (key.Length == 0)
            {
                store.Remove(name);
            }
            else
            {
                store[name] = Convert.ToBase64String(Protector.Protect(Encoding.UTF8.GetBytes(key)));
            }

            SaveStore(store);
        }
    }

    public static void Remove(string name) => Set(name, "");

    public static IReadOnlyList<string> StoredNames()
    {
        lock (Gate)
        {
            return [.. LoadStore().Keys];
        }
    }

    /// <summary>All key names used by any provider.</summary>
    public static IReadOnlyList<string> KnownNames() =>
    [
        .. TranscriptionProviders.All.Select(p => p.KeyName())
            .Concat(EnhancementProviders.All.Select(p => p.KeyName()))
            .Where(n => n.Length > 0)
            .Distinct()
            .Order(StringComparer.Ordinal),
    ];
}
