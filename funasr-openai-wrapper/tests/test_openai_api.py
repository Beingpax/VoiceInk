import asyncio
import io
import sys
import wave
from pathlib import Path

import pytest
from starlette.datastructures import Headers
from starlette.responses import PlainTextResponse
from starlette.datastructures import UploadFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.funasr_client import TranscriptionResult, normalize_audio
from app.main import create_transcription


def wav_bytes() -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16000)
        wav.writeframes(b"\x01\x00" * 160)
    return buffer.getvalue()


class FakeClient:
    async def transcribe(self, audio, filename, *, language=None, prompt=None, model=None):
        assert audio
        assert filename == "sample.wav"
        assert language == "zh"
        assert prompt == "domain terms"
        assert model == "funasr"
        return TranscriptionResult(text="你好 VoiceInk", language=language, duration=0.01)


@pytest.fixture
def upload_file():
    return UploadFile(
        file=io.BytesIO(wav_bytes()),
        filename="sample.wav",
        headers=Headers({"content-type": "audio/wav"}),
    )


def test_transcription_json_response(upload_file):
    response = asyncio.run(create_transcription(
        None,
        upload_file,
        model="funasr",
        language="zh",
        prompt="domain terms",
        response_format="json",
        client=FakeClient(),
    ))

    assert response == {"text": "你好 VoiceInk"}


def test_transcription_text_response(upload_file):
    response = asyncio.run(create_transcription(
        None,
        upload_file,
        model="funasr",
        language="zh",
        prompt="domain terms",
        response_format="text",
        client=FakeClient(),
    ))

    assert isinstance(response, PlainTextResponse)
    assert response.body.decode() == "你好 VoiceInk"


def test_normalize_wav_extracts_pcm_frames():
    payload = normalize_audio(wav_bytes(), "sample.wav", 16000)

    assert payload.sample_rate == 16000
    assert payload.wav_format == "pcm"
    assert payload.data == b"\x01\x00" * 160
    assert payload.duration_seconds == 0.01
