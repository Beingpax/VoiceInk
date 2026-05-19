# FunASR OpenAI-Compatible Wrapper

This folder contains a small HTTP service that lets VoiceInk call an existing FunASR websocket backend through an OpenAI-compatible transcription endpoint.

VoiceInk custom cloud models send `multipart/form-data` to an endpoint and expect a JSON response with a `text` field. This wrapper implements:

- `POST /v1/audio/transcriptions`
- `GET /v1/models`
- `GET /health`

## Run

```bash
cd funasr-openai-wrapper
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

By default the wrapper connects to `wss://localhost:10095/asr`, matching the sample FunASR client defaults.

## Configure

Environment variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `FUNASR_HOST` | `localhost` | FunASR websocket host |
| `FUNASR_PORT` | `10095` | FunASR websocket port |
| `FUNASR_SSL` | `1` | Use `wss` when true, `ws` when false |
| `FUNASR_PATH` | `/asr` | FunASR websocket path |
| `FUNASR_HOST_HEADER` | empty | Optional websocket `Host` header override |
| `FUNASR_MODE` | `2pass` | FunASR mode: `offline`, `online`, or `2pass` |
| `FUNASR_CHUNK_SIZE` | `5,10,5` | Chunk size sent in the initial FunASR message |
| `FUNASR_CHUNK_INTERVAL` | `10` | Chunk interval sent in the initial FunASR message |
| `FUNASR_AUDIO_FS` | `16000` | Default sample rate for raw PCM uploads |
| `FUNASR_USE_ITN` | `1` | Enable inverse text normalization |
| `FUNASR_SEND_WITHOUT_SLEEP` | `1` | Send file chunks as fast as possible |
| `FUNASR_RECEIVE_TIMEOUT_SECONDS` | `30` | Maximum wait for a final FunASR response |
| `WRAPPER_API_KEY` | empty | Optional API key required from VoiceInk |

Copy `.env.example` to `.env` and edit it for your FunASR deployment. The app automatically loads `funasr-openai-wrapper/.env` at startup. Real environment variables still win over values in `.env`.

## VoiceInk setup

In VoiceInk, add a custom model:

- Display Name: `FunASR`
- API Endpoint: `http://127.0.0.1:8000/v1/audio/transcriptions`
- API Key: any non-empty value if `WRAPPER_API_KEY` is empty; otherwise use the configured value
- Model Name: `funasr`
- Multilingual Model: enabled

## Quick test

```bash
curl -sS http://127.0.0.1:8010/v1/audio/transcriptions \
  -H "Authorization: Bearer local-dev" \
  -F file=@/Users/zbg/.codex/worktrees/c887/VoiceInk/funasr-openai-wrapper/scripts/1776250007699.wav \
  -F model=funasr \
  -F response_format=json
```

Expected response:

```json
{"text":"transcribed text"}
```

## Benchmark

Use the benchmark script to measure latency, success rate, throughput, and real-time factor:

```bash
python scripts/bench_asr.py /path/to/audio.wav \
  --endpoint http://127.0.0.1:8001/v1/audio/transcriptions \
  --repeat 5 \
  --concurrency 1 \
  --warmup 1 \
  --verbose
```

Benchmark a directory of audio files with parallel requests:

```bash
python scripts/bench_asr.py /path/to/audio-dir \
  --endpoint http://127.0.0.1:8001/v1/audio/transcriptions \
  --repeat 3 \
  --concurrency 4 \
  --json-out benchmark.json \
  --csv-out benchmark.csv
```

RTF is reported for WAV files where duration can be read. Lower RTF is faster; for example, `0.5` means processing is twice as fast as real time.

## Notes

The wrapper accepts mono 16-bit PCM WAV files and raw PCM files directly. Other file types are forwarded to FunASR with `wav_format=others`, matching the behavior of the sample FunASR websocket client.
