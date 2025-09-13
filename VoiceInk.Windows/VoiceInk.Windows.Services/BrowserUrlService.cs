using System;
using System.Diagnostics;
using System.Linq;
using System.Windows.Automation;

namespace VoiceInk.Windows.Services
{
    /// <summary>
    /// A service to retrieve the current URL from supported web browsers using UI Automation.
    /// </summary>
    public class BrowserUrlService
    {
        public bool TryGetBrowserUrl(string processName, IntPtr windowHandle, out string? url)
        {
            url = null;
            if (windowHandle == IntPtr.Zero) return false;

            try
            {
                var rootElement = AutomationElement.FromHandle(windowHandle);
                if (rootElement == null) return false;

                switch (processName.ToLower())
                {
                    case "chrome":
                    case "msedge": // Edge is Chromium-based and often has the same UI structure
                        url = GetChromiumUrl(rootElement);
                        return url != null;

                    case "firefox":
                        url = GetFirefoxUrl(rootElement);
                        return url != null;

                    default:
                        return false;
                }
            }
            catch (Exception ex)
            {
                // UIA can be fragile and throw exceptions. We log this as a warning
                // because it's not a critical failure of the whole application.
                LogService.Instance.Log(LogLevel.Warning, "UI Automation error while getting browser URL.", ex);
                return false;
            }
        }

        private string? GetChromiumUrl(AutomationElement rootElement)
        {
            // The "Address and search bar" is an edit control.
            var addressBar = rootElement.FindFirst(TreeScope.Descendants,
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit));

            if (addressBar != null && addressBar.TryGetCurrentPattern(ValuePattern.Pattern, out var pattern))
            {
                return ((ValuePattern)pattern).Current.Value;
            }

            return null;
        }

        private string? GetFirefoxUrl(AutomationElement rootElement)
        {
            // Firefox has a more complex structure. The URL bar is often in a toolbar.
            // This is a common pattern but may need adjustment for different Firefox versions.
            var doc = rootElement.FindFirst(TreeScope.Descendants,
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Document));

            if (doc == null) return null;

            // Find the navigation toolbar
            var navToolbar = doc.FindFirst(TreeScope.Children,
                new PropertyCondition(AutomationElement.NameProperty, "Navigation"));

            if (navToolbar == null) return null;

            // Find the URL edit box within the toolbar
            var urlBox = navToolbar.FindFirst(TreeScope.Children,
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit));

            if (urlBox != null && urlBox.TryGetCurrentPattern(ValuePattern.Pattern, out var pattern))
            {
                return ((ValuePattern)pattern).Current.Value;
            }

            return null;
        }
    }
}
