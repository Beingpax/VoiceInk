using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using VoiceInk.Windows.Services;

namespace VoiceInk.Windows.UI.Views.SettingsPages
{
    public partial class ModelSettingsPage : Page, INotifyPropertyChanged
    {
        private readonly ModelService _modelService;
        private readonly SettingsService _settingsService;

        private bool _isDownloadButtonEnabled;
        public bool IsDownloadButtonEnabled
        {
            get => _isDownloadButtonEnabled;
            set { _isDownloadButtonEnabled = value; OnPropertyChanged(); }
        }

        public ObservableCollection<SelectableModelViewModel> AvailableModels { get; }

        public ModelSettingsPage()
        {
            InitializeComponent();
            DataContext = this;

            _modelService = new ModelService();
            _settingsService = SettingsService.Instance;

            Languages = new List<string>
            {
                "auto", "en", "es", "fr", "de", "it", "ja", "ko", "zh", "ru", "pt"
            };

            // We wrap the models in a ViewModel to add UI-specific properties like IsDownloaded
            AvailableModels = new ObservableCollection<SelectableModelViewModel>(
                _modelService.AvailableModels.Select(m => new SelectableModelViewModel(m, _modelService.ModelExists(m)))
            );

            // Bind the model service's properties to this view model
            _modelService.PropertyChanged += (s, e) =>
            {
                if (e.PropertyName == nameof(ModelService.IsDownloading))
                {
                    OnPropertyChanged(nameof(IsDownloading));
                    UpdateDownloadButtonState();
                }
                if (e.PropertyName == nameof(ModelService.DownloadProgress))
                {
                    OnPropertyChanged(nameof(DownloadProgress));
                }
            };

            Loaded += (s, e) => SelectSavedModel();
        }

        public bool IsDownloading => _modelService.IsDownloading;
        public double DownloadProgress => _modelService.DownloadProgress;

        public List<string> Languages { get; }

        public string SelectedLanguage
        {
            get => _settingsService.Settings.Language;
            set
            {
                if (_settingsService.Settings.Language != value)
                {
                    _settingsService.Settings.Language = value;
                    OnPropertyChanged();
                }
            }
        }

        private void SelectSavedModel()
        {
            var savedModelName = _settingsService.Settings.ModelName;
            var modelToSelect = AvailableModels.FirstOrDefault(m => m.Model.FileName == savedModelName);
            if (modelToSelect != null)
            {
                ModelListView.SelectedItem = modelToSelect;
            }
        }

        private void ModelListView_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (ModelListView.SelectedItem is SelectableModelViewModel selectedVM)
            {
                // Save the selection to settings if it's already downloaded
                if (selectedVM.IsDownloaded)
                {
                    _settingsService.Settings.ModelName = selectedVM.Model.FileName;
                }
            }
            UpdateDownloadButtonState();
        }

        private async void DownloadButton_Click(object sender, RoutedEventArgs e)
        {
            if (ModelListView.SelectedItem is SelectableModelViewModel selectedVM)
            {
                await _modelService.DownloadModelAsync(selectedVM.Model);
                // Refresh the status after download
                selectedVM.IsDownloaded = _modelService.ModelExists(selectedVM.Model);
                UpdateDownloadButtonState();

                // If the newly downloaded model is the one we want, save it to settings
                if(selectedVM.IsDownloaded)
                {
                    _settingsService.Settings.ModelName = selectedVM.Model.FileName;
                }
            }
        }

        private void UpdateDownloadButtonState()
        {
            if (ModelListView.SelectedItem is SelectableModelViewModel selectedVM)
            {
                IsDownloadButtonEnabled = !selectedVM.IsDownloaded && !IsDownloading;
            }
            else
            {
                IsDownloadButtonEnabled = false;
            }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }

    // ViewModel wrapper for the SelectableModel to add UI-specific state
    public class SelectableModelViewModel : INotifyPropertyChanged
    {
        public SelectableModel Model { get; }

        private bool _isDownloaded;
        public bool IsDownloaded
        {
            get => _isDownloaded;
            set { _isDownloaded = value; OnPropertyChanged(); }
        }

        public SelectableModelViewModel(SelectableModel model, bool isDownloaded)
        {
            Model = model;
            _isDownloaded = isDownloaded;
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
