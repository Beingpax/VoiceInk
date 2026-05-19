from __future__ import annotations

import asyncio
import inspect
import json
import ssl
import wave
from dataclasses import dataclass
from io import BytesIO
from typing import Any

from .config import Settings


class FunASRError(RuntimeError):
    """Raised when the FunASR websocket service cannot return a transcript."""


@dataclass(frozen=True)
class AudioPayload:
    data: bytes
    sample_rate: int
    wav_format: str
    duration_seconds: float | None


@dataclass(frozen=True)
class TranscriptionResult:
    text: str
    language: str | None = None
    duration: float | None = None


def normalize_audio(audio: bytes, filename: str, default_sample_rate: int) -> AudioPayload:
    lower_name = filename.lower()
    if lower_name.endswith(".wav") or audio[:4] == b"RIFF":
        with wave.open(BytesIO(audio), "rb") as wav_file:
            sample_rate = wav_file.getframerate()
            channels = wav_file.getnchannels()
            sample_width = wav_file.getsampwidth()
            frames_count = wav_file.getnframes()
            frames = wav_file.readframes(frames_count)
            duration = frames_count / sample_rate if sample_rate else None

        if sample_width != 2:
            raise FunASRError("Only 16-bit PCM WAV files are supported by the wrapper.")
        if channels != 1:
            raise FunASRError("Only mono WAV files are supported by the wrapper.")

        return AudioPayload(
            data=frames,
            sample_rate=sample_rate,
            wav_format="pcm",
            duration_seconds=duration,
        )

    sample_rate = default_sample_rate
    bytes_per_sample = 2
    duration = len(audio) / (sample_rate * bytes_per_sample) if sample_rate else None
    return AudioPayload(
        data=audio,
        sample_rate=sample_rate,
        wav_format="pcm" if lower_name.endswith(".pcm") else "others",
        duration_seconds=duration,
    )


class FunASRClient:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    async def transcribe(
        self,
        audio: bytes,
        filename: str,
        *,
        language: str | None = None,
        prompt: str | None = None,
        model: str | None = None,
    ) -> TranscriptionResult:
        payload = normalize_audio(audio, filename, self.settings.audio_fs)
        ssl_context = self._ssl_context()
        text = await self._send_and_receive(payload, filename, language=language, prompt=prompt, model=model, ssl_context=ssl_context)
        return TranscriptionResult(text=text.strip(), language=language, duration=payload.duration_seconds)

    def _ssl_context(self) -> ssl.SSLContext | None:
        if not self.settings.funasr_ssl:
            return None
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        return context

    async def _send_and_receive(
        self,
        payload: AudioPayload,
        filename: str,
        *,
        language: str | None,
        prompt: str | None,
        model: str | None,
        ssl_context: ssl.SSLContext | None,
    ) -> str:
        import websockets

        connect_kwargs: dict[str, Any] = {
            "subprotocols": ["binary"],
            "ping_interval": None,
            "ssl": ssl_context,
        }
        if self.settings.funasr_host_header:
            header_name = "additional_headers" if "additional_headers" in inspect.signature(websockets.connect).parameters else "extra_headers"
            connect_kwargs[header_name] = {"Host": self.settings.funasr_host_header}

        try:
            async with websockets.connect(self.settings.websocket_url, **connect_kwargs) as websocket:
                receive_task = asyncio.create_task(self._receive_text(websocket))
                await self._send_audio(websocket, payload, filename, language=language, prompt=prompt, model=model)
                try:
                    return await asyncio.wait_for(receive_task, timeout=self.settings.receive_timeout_seconds)
                except asyncio.TimeoutError as exc:
                    receive_task.cancel()
                    raise FunASRError("Timed out waiting for FunASR transcription result.") from exc
        except (OSError, ssl.SSLError) as exc:
            raise FunASRError(
                f"Could not connect to FunASR websocket at {self.settings.websocket_url}: {exc}. "
                "Check FUNASR_HOST, FUNASR_PORT, and FUNASR_SSL."
            ) from exc

    async def _send_audio(
        self,
        websocket: Any,
        payload: AudioPayload,
        filename: str,
        *,
        language: str | None,
        prompt: str | None,
        model: str | None,
    ) -> None:
        init_message: dict[str, Any] = {
            "mode": self.settings.funasr_mode,
            "chunk_size": self.settings.chunk_size,
            "chunk_interval": self.settings.chunk_interval,
            "audio_fs": payload.sample_rate,
            "wav_name": filename,
            "wav_format": payload.wav_format,
            "is_speaking": True,
            "hotwords": self.settings.hotwords,
            "itn": self.settings.use_itn,
        }
        if language:
            init_message["language"] = language
        if prompt:
            init_message["prompt"] = prompt
        if model:
            init_message["model"] = model

        await websocket.send(json.dumps(init_message, ensure_ascii=False))

        stride = int(60 * self.settings.chunk_size[1] / self.settings.chunk_interval / 1000 * payload.sample_rate * 2)
        stride = max(stride, 1)
        for offset in range(0, len(payload.data), stride):
            await websocket.send(payload.data[offset : offset + stride])
            if not self.settings.send_without_sleep and self.settings.funasr_mode != "offline":
                await asyncio.sleep(60 * self.settings.chunk_size[1] / self.settings.chunk_interval / 1000)

        await websocket.send(json.dumps({"is_speaking": False}))

    async def _receive_text(self, websocket: Any) -> str:
        online_text = ""
        offline_text = ""
        last_text = ""

        async for raw_message in websocket:
            try:
                message = json.loads(raw_message)
            except json.JSONDecodeError:
                continue

            text = str(message.get("text", ""))
            mode = message.get("mode")
            is_final = bool(message.get("is_final", False))

            if mode == "online":
                online_text += text
                last_text = online_text
            elif mode == "offline":
                offline_text += text
                last_text = offline_text
                is_final = True
            elif mode == "2pass-online":
                online_text += text
                last_text = offline_text + online_text
            elif mode:
                online_text = ""
                offline_text += text
                last_text = offline_text
            elif text:
                last_text += text

            if is_final:
                return last_text

        if last_text:
            return last_text
        raise FunASRError("FunASR websocket closed without returning text.")
