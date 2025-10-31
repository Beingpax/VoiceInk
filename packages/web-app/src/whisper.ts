// A simple wrapper for the whisper.js module
// This is not a complete implementation, but it's enough to get started
// See whisper.cpp/examples/whisper.wasm/emscripten.cpp for the full API

declare const Module: any;

export class Whisper {
  private module: any;

  constructor() {
    this.module = new Module();
  }

  public async init() {
    return new Promise<void>((resolve) => {
      this.module.onRuntimeInitialized = () => {
        resolve();
      };
    });
  }

  public async transcribe(audio: Float32Array): Promise<string> {
    const pcmf32 = this.module._malloc(audio.length * 4);
    this.module.HEAPF32.set(audio, pcmf32 / 4);

    const result = this.module.full_transcribe(pcmf32, audio.length);

    this.module._free(pcmf32);

    return result;
  }
}
