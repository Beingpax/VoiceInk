export class Whisper {
  public async init() {
    return Promise.resolve();
  }

  public async transcribe(audio: Float32Array): Promise<string> {
    return Promise.resolve('This is a mock transcription.');
  }
}
