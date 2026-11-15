"""Offline per-request worker. Loads only bundled code and verified local model data."""
import argparse
import ctypes as c
import json
import os
from pathlib import Path
import struct
import sys
import threading
import time

# -I excludes both the working directory and PYTHONPATH; allow only this bundled directory.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from horizon_punctuation import Punctuator


def read_wave(path):
    import numpy as np
    # The app passes PCM WAV; handle integer, float and WAVE_FORMAT_EXTENSIBLE from imports too.
    with open(path, 'rb') as stream:
        if stream.read(4) != b'RIFF': raise ValueError('Expected PCM WAVE audio')
        stream.read(4)
        if stream.read(4) != b'WAVE': raise ValueError('Expected WAVE audio')
        fmt, audio = None, None
        while header := stream.read(8):
            if len(header) != 8: raise ValueError('Truncated WAVE header')
            kind, size = struct.unpack('<4sI', header)
            if kind == b'fmt ': fmt = stream.read(size)
            elif kind == b'data': audio = stream.read(size)
            else: stream.seek(size, 1)
            if size % 2: stream.seek(1, 1)
            if fmt is not None and audio is not None: break
    if fmt is None or audio is None: raise ValueError('Missing WAVE data')
    kind, channels, rate, _, _, bits = struct.unpack_from('<HHIIHH', fmt)
    if kind == 0xfffe and len(fmt) >= 40: kind = struct.unpack_from('<H', fmt, 24)[0]
    if channels < 1 or rate < 1: raise ValueError('Invalid WAVE format')
    if kind == 3 and bits == 32: samples = np.frombuffer(audio, dtype='<f4')
    elif kind == 1 and bits in (16, 32):
        samples = np.frombuffer(audio, dtype='<i2' if bits == 16 else '<i4').astype(np.float32) / (2 ** (bits - 1))
    elif kind == 1 and bits == 24:
        raw = np.frombuffer(audio, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        values = raw[:, 0] | (raw[:, 1] << 8) | (raw[:, 2] << 16)
        samples = ((values ^ 0x800000) - 0x800000).astype(np.float32) / 8388608
    else: raise ValueError('Unsupported PCM WAVE format')
    samples = np.ascontiguousarray(samples.reshape(-1, channels).mean(axis=1), dtype=np.float32)
    if not samples.size or not np.isfinite(samples).all(): raise ValueError('Invalid audio samples')
    return samples, rate


def recognize(library, model_path, audio_path):
    import numpy as np
    lib = c.CDLL(str(library))
    def bind(name, args, result=c.c_int):
        function = getattr(lib, name)
        function.argtypes, function.restype = args, result
        return function
    ptr, ptrptr = c.c_void_p, c.POINTER(c.c_void_p)
    last_error = bind('speech_last_error', [], c.c_char_p)
    load = bind('speech_model_load', [c.c_char_p, ptr, ptrptr])
    free_model = bind('speech_model_free', [ptr], None)
    new_request = bind('speech_request_new', [ptr, ptrptr])
    free_request = bind('speech_request_free', [ptr], None)
    audio = bind('speech_request_set_audio', [ptr, c.POINTER(c.c_float), c.c_size_t, c.c_int])
    transcribe = bind('speech_transcribe', [ptr])
    result = bind('speech_request_result', [ptr], ptr)
    text = bind('speech_result_text', [ptr], c.c_char_p)
    if lib.speech_api_version_major() != 4: raise RuntimeError('Unsupported speech API')
    def check(status):
        if status != 0: raise RuntimeError((last_error() or b'Recognition failed').decode())
    samples, rate = read_wave(audio_path)
    model, request = ptr(), ptr()
    try:
        check(load(os.fsencode(model_path), None, c.byref(model)))
        check(new_request(model, c.byref(request)))
        check(audio(request, samples.ctypes.data_as(c.POINTER(c.c_float)), samples.size, rate))
        check(transcribe(request))
        return (text(result(request)) or b'').decode('utf-8')
    finally:
        free_request(request)
        free_model(model)


def monitor_parent(parent):
    while True:
        time.sleep(1)
        if os.getppid() != parent: os._exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--models', type=Path, required=True)
    parser.add_argument('--audio', type=Path, required=True)
    args = parser.parse_args()
    threading.Thread(target=monitor_parent, args=(os.getppid(),), daemon=True).start()
    root = Path(__file__).resolve().parent
    original = recognize(root / 'libspeech.4.dylib',
                         args.models / 'HaaS/Haas-616M-ja-v1.0-Q4_K.gguf', args.audio)
    # Never silently mark incomplete punctuation as success.
    punctuated = Punctuator(args.models / 'Horizon')(original)
    print(json.dumps({'text': punctuated, 'punctuation': 'applied' if original != punctuated else 'unchanged'},
                     ensure_ascii=False), flush=True)

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Do not emit recognized text or arbitrary input values in diagnostics.
        print(json.dumps({'error': type(error).__name__}), flush=True)
        sys.exit(1)
