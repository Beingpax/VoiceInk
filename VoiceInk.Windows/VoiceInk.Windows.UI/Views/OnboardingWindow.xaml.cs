using System;
using System.Collections.Generic;
using System.Windows;

namespace VoiceInk.Windows.UI.Views
{
    public partial class OnboardingWindow : Window
    {
        private readonly List<Uri> _pages = new List<Uri>
        {
            new Uri("OnboardingPages/WelcomePage.xaml", UriKind.Relative),
            new Uri("OnboardingPages/HotkeyInfoPage.xaml", UriKind.Relative),
            new Uri("OnboardingPages/ModelDownloadPage.xaml", UriKind.Relative)
        };
        private int _currentPageIndex = 0;

        public OnboardingWindow()
        {
            InitializeComponent();
            OnboardingFrame.Navigate(_pages[_currentPageIndex]);
            UpdateButto-nState();
        }

        private void BackButton_Click(object sender, RoutedEventArgs e)
        {
            if (_currentPageIndex > 0)
            {
                _currentPageIndex--;
                OnboardingFrame.Navigate(_pages[_currentPageIndex]);
                UpdateButtonState();
            }
        }

        private void NextButton_Click(object sender, RoutedEventArgs e)
        {
            if (_currentPageIndex < _pages.Count - 1)
            {
                _currentPageIndex++;
                OnboardingFrame.Navigate(_pages[_currentPageIndex]);
                UpdateButtonState();
            }
            else
            {
                // Finish button clicked
                DialogResult = true;
                Close();
            }
        }

        private void UpdateButtonState()
        {
            BackButton.IsEnabled = _currentPageIndex > 0;
            NextButton.Content = _currentPageIndex == _pages.Count - 1 ? "Finish" : "Next";
        }
    }
}
