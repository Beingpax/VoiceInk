from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

try:
    from dotenv import load_dotenv
except ModuleNotFoundError:
    load_dotenv = None


if load_dotenv is not None:
    load_dotenv(Path(__file__).resolve().parents[1] / ".env")


def _parse_chunk_size(value: str) -> list[int]:
    chunks = [part.strip() for part in value.split(",")]
    if len(chunks) != 3:
        raise ValueError("FUNASR_CHUNK_SIZE must contain three comma-separated integers")
    return [int(part) for part in chunks]


@dataclass(frozen=True)
class Settings:
    funasr_host: str = os.getenv("FUNASR_HOST", "localhost")
    funasr_port: int = int(os.getenv("FUNASR_PORT", "10095"))
    funasr_ssl: bool = os.getenv("FUNASR_SSL", "1").lower() in {"1", "true", "yes", "on"}
    funasr_path: str = os.getenv("FUNASR_PATH", "/")
    funasr_host_header: str = os.getenv("FUNASR_HOST_HEADER", "")
    funasr_mode: str = os.getenv("FUNASR_MODE", "2pass")
    chunk_size: list[int] = None  # type: ignore[assignment]
    chunk_interval: int = int(os.getenv("FUNASR_CHUNK_INTERVAL", "10"))
    audio_fs: int = int(os.getenv("FUNASR_AUDIO_FS", "16000"))
    use_itn: bool = os.getenv("FUNASR_USE_ITN", "1").lower() in {"1", "true", "yes", "on"}
    hotwords: str = os.getenv("FUNASR_HOTWORDS", "")
    send_without_sleep: bool = os.getenv("FUNASR_SEND_WITHOUT_SLEEP", "1").lower() in {"1", "true", "yes", "on"}
    receive_timeout_seconds: float = float(os.getenv("FUNASR_RECEIVE_TIMEOUT_SECONDS", "30"))
    api_key: str = os.getenv("WRAPPER_API_KEY", "")

    def __post_init__(self) -> None:
        if self.chunk_size is None:
            object.__setattr__(self, "chunk_size", _parse_chunk_size(os.getenv("FUNASR_CHUNK_SIZE", "5,10,5")))

    @property
    def websocket_url(self) -> str:
        scheme = "wss" if self.funasr_ssl else "ws"
        path = self.funasr_path if self.funasr_path.startswith("/") else f"/{self.funasr_path}"
        return f"{scheme}://{self.funasr_host}:{self.funasr_port}{path}"


settings = Settings()
