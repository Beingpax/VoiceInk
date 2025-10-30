import React, { useState, useEffect } from 'react';
import { Whisper } from './whisper';

const App: React.FC = () => {
  const [whisper, setWhisper] = useState<Whisper | null>(null);
  const [isRecording, setIsRecording] = useState(false);
  const [transcription, setTranscription] = useState('');
  const [mediaRecorder, setMediaRecorder] = useState<MediaRecorder | null>(null);

  useEffect(() => {
    const initWhisper = async () => {
      const whisper = new Whisper();
      await whisper.init();
      setWhisper(whisper);
    };
    initWhisper();
  }, []);

  const onRecord = async () => {
    if (isRecording) {
      mediaRecorder?.stop();
      setIsRecording(false);
    } else {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new MediaRecorder(stream);
      setMediaRecorder(recorder);
      recorder.start();
      setIsRecording(true);

      recorder.ondataavailable = async (e) => {
        const audioContext = new AudioContext();
        const audioBuffer = await audioContext.decodeAudioData(await e.data.arrayBuffer());
        const audioData = audioBuffer.getChannelData(0);
        const transcription = await whisper?.transcribe(audioData);
        setTranscription(transcription || '');
      };
    }
  };

  return (
    <div>
      <h1>VoiceInk</h1>
      <button onClick={onRecord}>{isRecording ? 'Stop' : 'Record'}</button>
      <textarea value={transcription} readOnly />
    </div>
  );
};

export default App;
