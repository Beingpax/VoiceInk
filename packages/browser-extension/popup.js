let isRecording = false;
let mediaRecorder;
let whisper;

document.addEventListener('DOMContentLoaded', async () => {
  whisper = new Whisper();
  await whisper.init();

  const recordButton = document.getElementById('record');
  recordButton.addEventListener('click', onRecord);
});

const onRecord = async () => {
  if (isRecording) {
    mediaRecorder.stop();
    isRecording = false;
    document.getElementById('record').textContent = 'Record';
  } else {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    mediaRecorder = new MediaRecorder(stream);
    mediaRecorder.start();
    isRecording = true;
    document.getElementById('record').textContent = 'Stop';

    mediaRecorder.ondataavailable = async (e) => {
      const audioContext = new AudioContext();
      const audioBuffer = await audioContext.decodeAudioData(await e.data.arrayBuffer());
      const audioData = audioBuffer.getChannelData(0);
      const transcription = await whisper.transcribe(audioData);
      document.getElementById('transcription').value = transcription;
    };
  }
};
