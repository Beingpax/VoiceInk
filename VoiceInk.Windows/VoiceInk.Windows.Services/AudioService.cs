using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NAudio.Wave;

namespace VoiceInk.Windows.Services
{
    /// <summary>
    /// A service for managing audio devices and recording.
    /// </summary>
    public class AudioService : IDisposable
    {
        private WaveInEvent? _waveIn;
        private MemoryStream? _recordedAudioStream;

        public event EventHandler<DataAvailableEventArgs>? RecordingStopped;

        /// <summary>
        /// Gets a list of available audio input devices.
        /// </summary>
        public IEnumerable<AudioDevice> GetInputDevices()
        {
            return Enumerable.Range(0, WaveIn.DeviceCount)
                .Select(i =>
                {
                    var caps = WaveIn.GetCapabilities(i);
                    return new AudioDevice(i, caps.ProductName);
                });
        }

        public void StartRecording(int deviceId)
        {
            if (_waveIn != null) return; // Already recording

            _recordedAudioStream = new MemoryStream();
            _waveIn = new WaveInEvent
            {
                DeviceNumber = deviceId,
                WaveFormat = new WaveFormat(16000, 16, 1) // Whisper expects 16kHz, 16-bit, mono
            };

            _waveIn.DataAvailable += OnDataAvailable;
            _waveIn.RecordingStopped += OnRecordingStopped;
            _waveIn.StartRecording();
        }

        public void StopRecording()
        {
            _waveIn?.StopRecording();
        }

        private void OnDataAvailable(object? sender, WaveInEventArgs e)
        {
            _recordedAudioStream?.Write(e.Buffer, 0, e.BytesRecorded);
        }

        private void OnRecordingStopped(object? sender, StoppedEventArgs e)
        {
            // Pass the completed stream with the event
            RecordingStopped?.Invoke(this, new DataAvailableEventArgs(_recordedAudioStream ?? new MemoryStream()));
            Dispose();
        }

        public void Dispose()
        {
            if (_waveIn != null)
            {
                _waveIn.DataAvailable -= OnDataAvailable;
                _waveIn.RecordingStopped -= OnRecordingStopped;
                _waveIn.Dispose();
                _waveIn = null;
            }
            _recordedAudioStream?.Dispose();
            _recordedAudioStream = null;
            GC.SuppressFinalize(this);
        }
    }

    /// <summary>
    /// Represents an audio device.
    /// </summary>
    public record AudioDevice(int Id, string Name);

    /// <summary>
    /// Event arguments for when a recording is complete and the audio data is available.
    /// </summary>
    public class DataAvailableEventArgs : EventArgs
    {
        public MemoryStream AudioStream { get; }

        public DataAvailableEventArgs(MemoryStream audioStream)
        {
            AudioStream = audioStream;
        }
    }
}
