from __future__ import annotations

from typing import Annotated

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import JSONResponse, PlainTextResponse

from .config import settings
from .funasr_client import FunASRClient, FunASRError

app = FastAPI(title="FunASR OpenAI-Compatible Wrapper", version="0.1.0")


def require_auth(authorization: Annotated[str | None, Header()] = None) -> None:
    if not settings.api_key:
        return
    expected = settings.api_key
    supplied = authorization or ""
    if supplied.startswith("Bearer "):
        supplied = supplied.removeprefix("Bearer ").strip()
    if supplied != expected:
        raise HTTPException(status_code=401, detail="Invalid API key")


def get_client() -> FunASRClient:
    return FunASRClient(settings)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "funasr_url": settings.websocket_url}


@app.get("/v1/models")
async def models(_: Annotated[None, Depends(require_auth)]) -> dict[str, object]:
    return {
        "object": "list",
        "data": [
            {
                "id": "funasr",
                "object": "model",
                "owned_by": "funasr-openai-wrapper",
            }
        ],
    }


@app.post("/v1/audio/transcriptions")
async def create_transcription(
    _: Annotated[None, Depends(require_auth)],
    file: Annotated[UploadFile, File()],
    model: Annotated[str, Form()] = "funasr",
    language: Annotated[str | None, Form()] = None,
    prompt: Annotated[str | None, Form()] = None,
    response_format: Annotated[str, Form()] = "json",
    temperature: Annotated[float | None, Form()] = None,
    client: Annotated[FunASRClient, Depends(get_client)] = None,  # type: ignore[assignment]
):
    del temperature
    audio = await file.read()
    if not audio:
        raise HTTPException(status_code=400, detail="Uploaded audio file is empty")

    try:
        result = await client.transcribe(
            audio,
            file.filename or "audio.wav",
            language=language,
            prompt=prompt,
            model=model,
        )
    except FunASRError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    if response_format == "json":
        return {"text": result.text}
    if response_format == "verbose_json":
        return {
            "task": "transcribe",
            "language": result.language,
            "duration": result.duration,
            "text": result.text,
            "segments": [],
        }
    if response_format == "text":
        return PlainTextResponse(result.text)

    return JSONResponse(
        status_code=400,
        content={"error": {"message": f"Unsupported response_format: {response_format}", "type": "invalid_request_error"}},
    )
