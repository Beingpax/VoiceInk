using System.Text.Json.Serialization;
using VoiceInk.Core.Config;

namespace VoiceInk.Core;

[JsonSerializable(typeof(AppConfig))]
[JsonSerializable(typeof(HistoryEntry))]
[JsonSerializable(typeof(Dictionary<string, string>))]
[JsonSerializable(typeof(SortedDictionary<string, string>))]
internal partial class AppJsonContext : JsonSerializerContext
{
}
