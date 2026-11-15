#!/usr/bin/env python3
"""Build-only: assemble a relocatable arm64 runtime; never fetch model weights."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ASSETS = {
    'speech.zip': ('https://github.com/nyosegawa/speech.cpp/releases/download/v0.10.0/speech-0.10.0-macos-arm64-metal.zip',
                   '4f48ac4aefe65a00e2724e94749f01f7993de6190998c49bb347662f96f7af6d'),
    'python.tar.gz': ('https://github.com/astral-sh/python-build-standalone/releases/download/20261110/cpython-3.13.18%2B20261110-aarch64-apple-darwin-install_only.tar.gz',
                      '1afd3983237c2a10277345f235be730e9cb49a123e0574ed252dbf3a841a24e4'),
}

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def prepare(destination, cache):
    if platform.machine() != 'arm64':
        raise RuntimeError('The bundled runtime currently supports Apple Silicon only')
    inputs = [p for p in sorted((ROOT / 'runtime/local-haas').rglob('*'))
              if p.is_file() and '__pycache__' not in p.parts]
    fingerprint = hashlib.sha256(Path(__file__).read_bytes() + b''.join(p.read_bytes() for p in inputs)).hexdigest()
    stamp = destination / 'runtime.json'
    if stamp.exists() and json.loads(stamp.read_text()).get('fingerprint') == fingerprint:
        # Always refresh our own scripts, including after source-only edits.
        for p in (ROOT / 'runtime/local-haas').glob('*'):
            if p.is_file() and p.suffix in (".py", ".json"): shutil.copy2(p, destination / p.name)
        return
    cache.mkdir(parents=True, exist_ok=True)
    for name, (url, sha) in ASSETS.items():
        path = cache / name
        if not path.exists() or digest(path) != sha:
            temporary = path.with_suffix('.download')
            print('Downloading build dependency:', url, flush=True)
            urllib.request.urlretrieve(url, temporary)
            if digest(temporary) != sha:
                temporary.unlink()
                raise RuntimeError('Runtime archive checksum mismatch: ' + name)
            temporary.replace(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temp:
        stage = Path(temp) / 'LocalHaas'
        stage.mkdir()
        with tarfile.open(cache / 'python.tar.gz') as archive:
            archive.extractall(stage, filter='data')
        with zipfile.ZipFile(cache / 'speech.zip') as archive:
            archive.extractall(Path(temp) / 'speech')
        library = next((Path(temp) / 'speech').rglob('libspeech.4.dylib'))
        shutil.copy2(library, stage / library.name)
        notices = stage / 'Licenses'
        notices.mkdir()
        for p in (Path(temp) / 'speech').rglob('*'):
            if p.is_file() and p.name.upper().startswith(('LICENSE', 'NOTICE', 'COPYING')):
                shutil.copy2(p, notices / ('speech-' + p.name))
        # Isolated portable Python: no Homebrew, uv, user site-packages or shell activation on the target Mac.
        executable = stage / 'python/bin/python3.13'
        executable.chmod(0o755)
        subprocess.run([str(executable), '-I', '-m', 'pip', 'install', '--only-binary=:all:', '--no-compile',
                        '-r', str(ROOT / 'runtime/local-haas/requirements.txt')], check=True)
        for p in stage.rglob('__pycache__'):
            shutil.rmtree(p)
        for pattern in ['python/lib/python3.13/test', 'python/lib/python3.13/site-packages/pip',
                        'python/include', 'python/lib/pkgconfig',
                        'python/lib/python3.13/site-packages/onnxruntime/datasets']:
            shutil.rmtree(stage / pattern, ignore_errors=True)
        # All Python console scripts contain the staging prefix. Only the interpreter is used.
        for p in (stage / 'python/bin').iterdir():
            if p.name != 'python3.13':
                if p.is_dir(): shutil.rmtree(p)
                else: p.unlink()
        for p in stage.rglob('*.a'):
            p.unlink()
        for p in (ROOT / 'runtime/local-haas').glob('*'):
            if p.is_file() and p.suffix in (".py", ".json"): shutil.copy2(p, stage / p.name)
        shutil.copy2(ROOT / 'runtime/local-haas/requirements.txt', stage / 'requirements.txt')
        shutil.copytree(ROOT / 'runtime/local-haas/licenses', notices, dirs_exist_ok=True)
        (notices / 'SOURCES.txt').write_text(
            'speech.cpp v0.10.0: https://github.com/nyosegawa/speech.cpp/tree/v0.10.0\n'
            'CPython standalone 20261110: https://github.com/astral-sh/python-build-standalone/releases/tag/20261110\n'
            'Python and wheel notices are also retained within python/ and each *.dist-info/licenses directory.\n')
        (stage / 'runtime.json').write_text(json.dumps({'version': 1, 'architecture': 'arm64',
            'fingerprint': fingerprint, 'assets': ASSETS}, indent=2))
        # Relocate before import validation: staging prefixes must not be necessary at runtime.
        if destination.exists(): shutil.rmtree(destination)
        shutil.move(stage, destination)
    subprocess.run([str(destination / 'python/bin/python3.13'), '-I', '-B', '-c',
                    'import numpy, onnxruntime, tokenizers, ctypes; '
                    'assert ctypes.CDLL(__import__("sys").argv[1]).speech_api_version_major() == 4',
                    str(destination / 'libspeech.4.dylib')], check=True)

def sign_runtime(destination, identity):
    stamp = destination / 'signing.json'
    if stamp.exists() and json.loads(stamp.read_text()).get('identity') == identity:
        return
    magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}
    for path in sorted(destination.rglob('*')):
        if path.is_symlink() or not path.is_file(): continue
        with path.open('rb') as stream:
            native = stream.read(4) in magic
        if native:
            args = ['codesign', '--force', '--sign', identity]
            if identity != '-': args += ['--options', 'runtime', '--timestamp']
            subprocess.run(args + [str(path)], check=True, capture_output=True)
    stamp.write_text(json.dumps({'identity': identity}))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / '.local-haas-build/LocalHaas')
    parser.add_argument('--cache', type=Path, default=ROOT / '.local-haas-cache')
    parser.add_argument('--sign-identity', default='-')
    args = parser.parse_args()
    prepare(args.output.resolve(), args.cache.resolve())
    sign_runtime(args.output.resolve(), args.sign_identity)
