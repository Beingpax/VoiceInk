using System.Windows;

namespace VoiceInk.Windows.UI.Views
{
    public partial class FloatingRecorderWindow : Window
    {
        public FloatingRecorderWindow()
        {
            InitializeComponent();
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            // Position the window in the bottom-right corner of the primary screen's work area.
            var workArea = SystemParameters.WorkArea;
            this.Left = workArea.Right - this.Width - 20; // 20px padding
            this.Top = workArea.Bottom - this.Height - 20; // 20px padding
        }
    }
}
