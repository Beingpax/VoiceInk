#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import csv
import json
import mimetypes
import statistics
import time
import urllib.error
import urllib.request
import wave
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


AUDIO_EXTENSIONS = {".wav", ".pcm", ".mp3", ".m4a", ".flac", ".ogg", ".webm", ".aac"}


@dataclass(frozen=True)
class AudioCase:
    path: Path
    duration_seconds: float | None


@dataclass
class RequestResult:
    index: int
    path: str
    ok: bool
    status_code: int | None
    latency_seconds: float
    audio_duration_seconds: float | None
    rtf: float | None
    text_length: int
    error: str


def discover_audio_cases(input_path: Path) -> list[AudioCase]:
    if input_path.is_file():
        paths = [input_path]
    else:
        paths = sorted(path for path in input_path.rglob("*") if path.suffix.lower() in AUDIO_EXTENSIONS)

    if not paths:
        raise SystemExit(f"No audio files found under {input_path}")

    return [AudioCase(path=path, duration_seconds=audio_duration_seconds(path)) for path in paths]


def audio_duration_seconds(path: Path) -> float | None:
    if path.suffix.lower() == ".wav":
        try:
            with wave.open(str(path), "rb") as wav:
                frame_rate = wav.getframerate()
                return wav.getnframes() / frame_rate if frame_rate else None
        except wave.Error:
            return None
    return None


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * pct / 100
    lower = int(rank)
    upper = min(lower + 1, len(ordered) - 1)
    weight = rank - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def summarize(results: list[RequestResult], wall_seconds: float) -> dict[str, Any]:
    successful = [result for result in results if result.ok]
    failed = [result for result in results if not result.ok]
    latencies = [result.latency_seconds for result in successful]
    rtfs = [result.rtf for result in successful if result.rtf is not None]
    audio_seconds = sum(result.audio_duration_seconds or 0 for result in successful)

    return {
        "requests": len(results),
        "successful": len(successful),
        "failed": len(failed),
        "success_rate": len(successful) / len(results) if results else 0,
        "wall_seconds": wall_seconds,
        "requests_per_second": len(results) / wall_seconds if wall_seconds > 0 else 0,
        "audio_seconds": audio_seconds,
        "audio_hours_per_wall_hour": audio_seconds / wall_seconds if wall_seconds > 0 else 0,
        "latency_seconds": {
            "min": min(latencies) if latencies else 0,
            "mean": statistics.fmean(latencies) if latencies else 0,
            "p50": percentile(latencies, 50),
            "p90": percentile(latencies, 90),
            "p95": percentile(latencies, 95),
            "p99": percentile(latencies, 99),
            "max": max(latencies) if latencies else 0,
        },
        "rtf": {
            "mean": statistics.fmean(rtfs) if rtfs else None,
            "p50": percentile(rtfs, 50) if rtfs else None,
            "p90": percentile(rtfs, 90) if rtfs else None,
            "p95": percentile(rtfs, 95) if rtfs else None,
        },
    }


async def transcribe_once(
    endpoint: str,
    case: AudioCase,
    index: int,
    model: str,
    response_format: str,
    language: str | None,
    prompt: str | None,
    api_key: str,
    timeout: float,
) -> RequestResult:
    started = time.perf_counter()
    status_code: int | None = None
    try:
        status_code, body = await asyncio.to_thread(
            post_transcription,
            endpoint,
            case.path,
            model,
            response_format,
            language,
            prompt,
            api_key,
            timeout,
        )
        elapsed = time.perf_counter() - started

        text = body
        if response_format in {"json", "verbose_json"}:
            text = json.loads(body).get("text", "")

        rtf = elapsed / case.duration_seconds if case.duration_seconds else None
        return RequestResult(
            index=index,
            path=str(case.path),
            ok=True,
            status_code=status_code,
            latency_seconds=elapsed,
            audio_duration_seconds=case.duration_seconds,
            rtf=rtf,
            text_length=len(text),
            error="",
        )
    except Exception as exc:
        elapsed = time.perf_counter() - started
        status_code = getattr(exc, "code", status_code)
        return RequestResult(
            index=index,
            path=str(case.path),
            ok=False,
            status_code=status_code,
            latency_seconds=elapsed,
            audio_duration_seconds=case.duration_seconds,
            rtf=None,
            text_length=0,
            error=str(exc),
        )


def post_transcription(
    endpoint: str,
    path: Path,
    model: str,
    response_format: str,
    language: str | None,
    prompt: str | None,
    api_key: str,
    timeout: float,
) -> tuple[int, str]:
    fields = {
        "model": model,
        "response_format": response_format,
    }
    if language:
        fields["language"] = language
    if prompt:
        fields["prompt"] = prompt

    body, content_type = build_multipart_body(path, fields)
    headers = {"Content-Type": content_type}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    request = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code}: {detail}") from exc


def build_multipart_body(path: Path, fields: dict[str, str]) -> tuple[bytes, str]:
    boundary = f"BenchBoundary{time.time_ns()}"
    content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    chunks: list[bytes] = []

    for name, value in fields.items():
        chunks.append(f"--{boundary}\r\n".encode())
        chunks.append(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode())
        chunks.append(value.encode())
        chunks.append(b"\r\n")

    chunks.append(f"--{boundary}\r\n".encode())
    chunks.append(f'Content-Disposition: form-data; name="file"; filename="{path.name}"\r\n'.encode())
    chunks.append(f"Content-Type: {content_type}\r\n\r\n".encode())
    chunks.append(path.read_bytes())
    chunks.append(b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode())

    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


async def run_benchmark(args: argparse.Namespace) -> tuple[list[RequestResult], dict[str, Any]]:
    cases = discover_audio_cases(Path(args.input).expanduser())
    planned_cases = [case for _ in range(args.repeat) for case in cases]
    semaphore = asyncio.Semaphore(args.concurrency)

    for warmup_index, case in enumerate(planned_cases[: args.warmup]):
        result = await transcribe_once(
            args.endpoint,
            case,
            warmup_index,
            args.model,
            args.response_format,
            args.language,
            args.prompt,
            args.api_key,
            args.timeout,
        )
        if args.verbose:
            print_result("warmup", result)

    async def guarded(index: int, case: AudioCase) -> RequestResult:
        async with semaphore:
            result = await transcribe_once(
                args.endpoint,
                case,
                index,
                args.model,
                args.response_format,
                args.language,
                args.prompt,
                args.api_key,
                args.timeout,
            )
            if args.verbose:
                print_result("run", result)
            return result

    started = time.perf_counter()
    results = await asyncio.gather(*(guarded(index, case) for index, case in enumerate(planned_cases, start=1)))
    wall_seconds = time.perf_counter() - started

    return results, summarize(results, wall_seconds)


def print_result(prefix: str, result: RequestResult) -> None:
    status = "ok" if result.ok else "fail"
    rtf = f", rtf={result.rtf:.3f}" if result.rtf is not None else ""
    error = f", error={result.error}" if result.error else ""
    print(f"[{prefix}] #{result.index} {status} {result.latency_seconds:.3f}s{rtf} {result.path}{error}")


def write_json(path: Path, results: list[RequestResult], summary: dict[str, Any]) -> None:
    payload = {
        "summary": summary,
        "results": [asdict(result) for result in results],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def write_csv(path: Path, results: list[RequestResult]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(asdict(results[0]).keys()) if results else [])
        writer.writeheader()
        for result in results:
            writer.writerow(asdict(result))


def print_summary(summary: dict[str, Any]) -> None:
    latency = summary["latency_seconds"]
    rtf = summary["rtf"]
    print("\nSummary")
    print(f"  requests: {summary['requests']} total, {summary['successful']} ok, {summary['failed']} failed")
    print(f"  success rate: {summary['success_rate'] * 100:.2f}%")
    print(f"  wall time: {summary['wall_seconds']:.3f}s")
    print(f"  throughput: {summary['requests_per_second']:.3f} req/s")
    print(f"  audio throughput: {summary['audio_hours_per_wall_hour']:.3f} audio-hours/wall-hour")
    print(
        "  latency: "
        f"mean={latency['mean']:.3f}s p50={latency['p50']:.3f}s "
        f"p90={latency['p90']:.3f}s p95={latency['p95']:.3f}s p99={latency['p99']:.3f}s"
    )
    if rtf["mean"] is not None:
        print(f"  RTF: mean={rtf['mean']:.3f} p50={rtf['p50']:.3f} p90={rtf['p90']:.3f} p95={rtf['p95']:.3f}")
    else:
        print("  RTF: unavailable because audio duration could not be detected")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Benchmark an OpenAI-compatible ASR transcription endpoint.")
    parser.add_argument("input", help="Audio file or directory of audio files.")
    parser.add_argument("--endpoint", default="http://127.0.0.1:8001/v1/audio/transcriptions")
    parser.add_argument("--api-key", default="")
    parser.add_argument("--model", default="funasr")
    parser.add_argument("--language", default=None)
    parser.add_argument("--prompt", default=None)
    parser.add_argument("--response-format", default="json", choices=["json", "verbose_json", "text"])
    parser.add_argument("--concurrency", type=int, default=1)
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--warmup", type=int, default=0)
    parser.add_argument("--timeout", type=float, default=120)
    parser.add_argument("--json-out", type=Path, default=None)
    parser.add_argument("--csv-out", type=Path, default=None)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    if args.concurrency < 1:
        parser.error("--concurrency must be >= 1")
    if args.repeat < 1:
        parser.error("--repeat must be >= 1")
    if args.warmup < 0:
        parser.error("--warmup must be >= 0")
    return args


def main() -> None:
    args = parse_args()
    results, summary = asyncio.run(run_benchmark(args))
    print_summary(summary)
    if args.json_out:
        write_json(args.json_out, results, summary)
        print(f"  wrote JSON: {args.json_out}")
    if args.csv_out:
        write_csv(args.csv_out, results)
        print(f"  wrote CSV: {args.csv_out}")


if __name__ == "__main__":
    main()
