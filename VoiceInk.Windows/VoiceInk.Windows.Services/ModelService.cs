using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Whisper.net.Ggml;

namespace VoiceInk.Windows.Services
{
    public record SelectableModel(string Name, string FileName, GgmlType GgmlType, QuantizationType QuantizationType);

    public class ModelService : INotifyPropertyChanged
    {
        private double _downloadProgress;
        private bool _isDownloading;

        public List<SelectableModel> AvailableModels { get; }

        public double DownloadProgress
        {
            get => _downloadProgress;
            set { _downloadProgress = value; OnPropertyChanged(); }
        }

        public bool IsDownloading
        {
            get => _isDownloading;
            set { _isDownloading = value; OnPropertyChanged(); }
        }

        public ModelService()
        {
            AvailableModels = new List<SelectableModel>
            {
                new("Tiny (English)",     "ggml-tiny.en.bin", GgmlType.Tiny,   QuantizationType.Q5_1),
                new("Base (English)",     "ggml-base.en.bin", GgmlType.Base,   QuantizationType.Q5_1),
                new("Small (English)",    "ggml-small.en.bin",GgmlType.Small,  QuantizationType.Q5_1),
                new("Medium (English)",   "ggml-medium.en.bin",GgmlType.Medium, QuantizationType.Q5_1),
                new("Base (Multilingual)","ggml-base.bin",    GgmlType.Base,   QuantizationType.Q5_1),
                new("Small (Multilingual)","ggml-small.bin",  GgmlType.Small,  QuantizationType.Q5_1),
            };
        }

        public bool ModelExists(SelectableModel model)
        {
            return File.Exists(model.FileName);
        }

        public async Task DownloadModelAsync(SelectableModel model)
        {
            if (IsDownloading || ModelExists(model)) return;

            IsDownloading = true;
            DownloadProgress = 0;

            try
            {
                var downloader = WhisperGgmlDownloader.Default;

                using var modelStream = await downloader.GetGgmlModelAsync(model.GgmlType, model.QuantizationType, true);

                // Use a progress-reporting stream to update the UI
                var progress = new Progress<double>(p => DownloadProgress = p);
                var progressStream = new ProgressStream(modelStream, progress);

                await using var fileWriter = File.OpenWrite(model.FileName);
                await progressStream.CopyToAsync(fileWriter);
            }
            finally
            {
                IsDownloading = false;
                DownloadProgress = 0;
                OnPropertyChanged(nameof(ModelExists)); // Notify that the model's existence might have changed
            }
        }

        public event PropertyChangedEventHandler? PropertyChanged;

        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }

    // Helper class to report progress on a stream
    public class ProgressStream : Stream
    {
        private readonly Stream _baseStream;
        private readonly IProgress<double> _progress;
        private long _bytesRead;

        public ProgressStream(Stream baseStream, IProgress<double> progress)
        {
            _baseStream = baseStream;
            _progress = progress;
        }

        public override bool CanRead => _baseStream.CanRead;
        public override bool CanSeek => _baseStream.CanSeek;
        public override bool CanWrite => _baseStream.CanWrite;
        public override long Length => _baseStream.Length;
        public override long Position { get => _baseStream.Position; set => _baseStream.Position = value; }
        public override void Flush() => _baseStream.Flush();
        public override long Seek(long offset, SeekOrigin origin) => _baseStream.Seek(offset, origin);
        public override void SetLength(long value) => _baseStream.SetLength(value);
        public override void Write(byte[] buffer, int offset, int count) => _baseStream.Write(buffer, offset, count);

        public override int Read(byte[] buffer, int offset, int count)
        {
            int bytesRead = _baseStream.Read(buffer, offset, count);
            _bytesRead += bytesRead;
            _progress.Report((double)_bytesRead / Length * 100.0);
            return bytesRead;
        }
    }
}
