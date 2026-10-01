# Prepared audio input regression

The recorder caches a prepared AUHAL between recordings. A device can remain alive with the same ID while another audio app changes its sample rate. Reusing the old client format can make `AudioOutputUnitStart` succeed while the resulting WAV contains no frames.

This hardware regression exercises the production `CoreAudioRecorder.swift` directly, using the Swift Atomics checkout resolved by the local Xcode build. It requires a Mac with a built-in microphone and microphone access for the launching application.

Run when temporarily changing the built-in microphone sample rate will not disrupt other recording work:

```sh
scripts/test-audio-capture.sh --allow-sample-rate-changes
```

The test checks initial capture, unchanged reuse, reuse after a 44.1/48 kHz rate change, and reuse after restoring the original rate. Each recording must contain more than one second of 16 kHz mono audio. It restores the original hardware rate and removes its temporary recordings on normal completion or a thrown error. Do not forcibly terminate it during a rate change. No audio is uploaded.

The unmodified recorder produces a zero-frame WAV at `changed-rate-reuse`; the fixed recorder rebuilds its preparation and passes all four cases. This test verifies the stale-format defect. End-to-end acceptance should additionally use the app's selected microphone and transcription provider with the originally reported audio apps and Bluetooth devices active.

Apple's [AUHAL technical note](https://developer.apple.com/library/archive/technotes/tn2091/_index.html) requires the client and device sample rates to match. The fix rechecks that requirement before reusing a prepared unit; it also checks channel count and buffer capacity. It does not change the user's selected device or sample rate in normal app use.
