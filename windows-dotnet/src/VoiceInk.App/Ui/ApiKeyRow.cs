using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using VoiceInk.Core;

namespace VoiceInk.App.Ui;

/// <summary>Password field with Save/Remove that stores the key DPAPI-encrypted.</summary>
internal static class ApiKeyRow
{
    public static Border Create(string keyName, string providerName)
    {
        var box = new PasswordBox { Width = 260, PlaceholderText = "Paste API key" };
        var status = Fluent.Caption("");

        void Refresh() => status.Text = Credentials.Has(keyName) ? "A key is stored for your Windows account." : "No key stored.";
        Refresh();

        var save = Fluent.Button("Save", () =>
        {
            if (string.IsNullOrWhiteSpace(box.Password)) return;
            Credentials.Set(keyName, box.Password);
            box.Password = "";
            Refresh();
        }, accent: true);
        var remove = Fluent.Button("Remove", () =>
        {
            Credentials.Remove(keyName);
            Refresh();
        });

        var controls = new StackPanel { Spacing = 6, HorizontalAlignment = HorizontalAlignment.Right };
        controls.Children.Add(Fluent.Horizontal(8, box, save, remove));
        controls.Children.Add(status);
        status.HorizontalAlignment = HorizontalAlignment.Right;
        return Fluent.Row($"{providerName} API key", "Stored encrypted for the current Windows user. Environment variables VOICEINK_<NAME>_API_KEY also work.", controls);
    }
}
