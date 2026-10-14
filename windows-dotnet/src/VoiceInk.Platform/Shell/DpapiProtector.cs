using System.Security.Cryptography;
using System.Text;
using VoiceInk.Core;

namespace VoiceInk.Platform.Shell;

/// <summary>Encrypts API keys for the current Windows user only (DPAPI).</summary>
public sealed class DpapiProtector : ISecretProtector
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("VoiceInk for Windows");

    public byte[] Protect(byte[] data) => ProtectedData.Protect(data, Entropy, DataProtectionScope.CurrentUser);

    public byte[] Unprotect(byte[] data) => ProtectedData.Unprotect(data, Entropy, DataProtectionScope.CurrentUser);
}
