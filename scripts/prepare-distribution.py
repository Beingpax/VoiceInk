#!/usr/bin/env python3
"""固定リビジョンの依存ソースと告知文書を、配布用にオフラインでも読める形へまとめる。"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


def run(args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def git(repo, *args):
    return run(['git', '-C', str(repo), *args])


def export_tree(repo, destination, revision='HEAD', excluded=()):
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix='.tar') as archive:
        subprocess.run(['git', '-C', str(repo), 'archive', '--format=tar',
                        '--output', archive.name, revision], check=True)
        with tarfile.open(archive.name) as source:
            members = [m for m in source.getmembers()
                       if not any(m.name == prefix or m.name.startswith(prefix + '/') for prefix in excluded)]
            source.extractall(destination, members=members, filter='data')
    for entry in git(repo, 'ls-tree', '-r', revision).splitlines():
        metadata, name = entry.split('\t', 1)
        mode, _, sha = metadata.split()
        if mode != '160000':
            continue
        submodule = repo / name
        if git(submodule, 'rev-parse', 'HEAD') != sha:
            raise RuntimeError('Submodule revision mismatch: ' + name)
        export_tree(submodule, destination / name, sha)


def notice_file(path):
    return re.match(r'^(licen[sc]es?|copying|copyright|notices?|authors|third[-_]party[-_]licenses?)([._-].*)?$', path.name, re.I) is not None or any(p.name.lower() in {'licenses', 'licences'} for p in path.parents)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def build(root, checkouts, whisper, cache, output, app, extra_sources=None):
    extra_sources = extra_sources or {}
    if git(root, 'status', '--porcelain', '--untracked-files=no'):
        raise RuntimeError('Commit tracked changes before preparing a distribution')
    pins = json.loads((root / 'VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())['pins']
    catalog = json.loads((root / 'scripts/distribution-dependencies.json').read_text())
    cache.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    records = []
    with tempfile.TemporaryDirectory(prefix='voiceink-source-') as temporary:
        stage = Path(temporary)
        sources = stage / 'Sources'
        sources.mkdir()
        licenses = output / 'Licenses'
        if licenses.exists():
            shutil.rmtree(licenses)
        licenses.mkdir()
        app_sha = git(root, 'rev-parse', 'HEAD')
        export_tree(root, sources / 'VoiceInk', app_sha)
        components = [('VoiceInk', root, 'https://github.com/RyoyaYahagi/VoiceInk', app_sha, False)]
        directories = {p.name.lower(): p for p in checkouts.iterdir() if p.is_dir()}
        for pin in pins:
            name = pin['identity']
            repo = directories.get(name)
            if repo is None:
                raise RuntimeError('Missing checkout: ' + name)
            revision = pin['state']['revision']
            if git(repo, 'rev-parse', 'HEAD') != revision:
                raise RuntimeError('Pinned revision mismatch: ' + name)
            components.append((name, repo, pin['location'], revision, False))
        for name, info in catalog.items():
            if info.get('license_only'):
                continue
            repo = whisper if name == 'whisper' else extra_sources.get(name, cache / name)
            if not repo.exists():
                subprocess.run(['git', 'clone', '--filter=blob:none', '--no-checkout', info['url'], str(repo)], check=True)
                subprocess.run(['git', '-C', str(repo), 'checkout', '--detach', info['revision']], check=True)
                subprocess.run(['git', '-C', str(repo), 'submodule', 'update', '--init', '--recursive'], check=True)
            if git(repo, 'rev-parse', 'HEAD') != info['revision']:
                raise RuntimeError('Native dependency revision mismatch: ' + name)
            components.append((name, repo, info['url'], info['revision'], info.get('cargo', False)))
        for name, repo, url, revision, cargo in components:
            if git(repo, 'status', '--porcelain', '--untracked-files=no'):
                raise RuntimeError('Modified dependency checkout: ' + name)
            target = sources / name
            # Sparkle's test resources embed unsigned/obsolete apps, DMGs and installers.
            # They are not used to build the distributed library or VoiceInk.
            excluded = ['Tests/Resources'] if name == 'sparkle' else []
            if name != 'VoiceInk':
                export_tree(repo, target, revision, excluded=excluded)
            if cargo:
                vendor = cache / (name + '-cargo-vendor')
                config = subprocess.check_output(['cargo', 'vendor', '--locked', '--versioned-dirs', str(vendor)], cwd=repo, text=True)
                shutil.copytree(vendor, target / 'vendor', dirs_exist_ok=True)
                (target / '.cargo').mkdir(exist_ok=True)
                (target / '.cargo/config.toml').write_text(config.replace(str(vendor), 'vendor'))
            notice_paths = []
            for path in sorted(target.rglob('*')):
                if path.is_file() and not path.is_symlink() and notice_file(path):
                    # Preserve upstream text verbatim; only the surrounding index is Japanese.
                    try:
                        path.read_text(encoding='utf-8')
                    except (UnicodeError, OSError):
                        continue
                    relative = path.relative_to(target)
                    saved = licenses / name / relative
                    saved.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(path, saved)
                    notice_paths.append(str(Path(name) / relative))
            if not notice_paths:
                raise RuntimeError('No license or notice files found: ' + name)
            records.append(dict(name=name, source=url, revision=revision, notices=notice_paths, omitted_test_fixtures=excluded))
        silero = catalog['silero-vad']
        silero_license = cache / 'silero-vad-LICENSE'
        if not silero_license.exists():
            subprocess.run(['curl', '-fL', '--max-time', '60',
                'https://raw.githubusercontent.com/snakers4/silero-vad/v5.1.2/LICENSE', '-o', str(silero_license)], check=True)
        if 'MIT License' not in silero_license.read_text():
            raise RuntimeError('Invalid Silero license document')
        (licenses / 'silero-vad').mkdir(exist_ok=True)
        shutil.copy2(silero_license, licenses / 'silero-vad/LICENSE')
        models = list(app.rglob('ggml-silero-v5.1.2.bin'))
        if len(models) != 1:
            raise RuntimeError('Expected exactly one bundled Silero model')
        records.append(dict(name='silero-vad', source=silero['url'], revision=silero['revision'],
            model_sha256=sha256(models[0]), notices=['silero-vad/LICENSE']))
        runtime = app / 'Contents/Resources/LocalHaas'
        if not (runtime / 'runtime.json').exists():
            raise RuntimeError('Bundled HaaS runtime missing from distribution')
        shutil.copytree(runtime / 'Licenses', licenses / 'local-haas-runtime', dirs_exist_ok=True)
        shutil.copy2(runtime / 'runtime.json', output / 'LOCAL_HAAS_RUNTIME.json')
        shutil.copy2(runtime / 'requirements.txt', output / 'LOCAL_HAAS_REQUIREMENTS.txt')
        for path in (runtime / 'python').rglob('*'):
            if path.is_file() and notice_file(path):
                target = licenses / 'local-haas-runtime' / path.relative_to(runtime)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
        manifest = dict(app_revision=app_sha, components=records,
            excluded_models=['HaaS-ja', 'Horizon'], platform='Apple Silicon / macOS 15+')
        (output / 'DEPENDENCIES.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
        (stage / 'DEPENDENCIES.json').write_text((output / 'DEPENDENCIES.json').read_text())
        instructions = '''# 対応ソースとビルド手順\n\nSources/VoiceInkがこの配布のアプリ本体、他のディレクトリが依存物の固定ソースです。\n各リビジョンはDEPENDENCIES.jsonに記録しています。Swiftのサブモジュールも含みます。\nSparkleのTests/Resourcesにある既成のテスト用アプリ・インストーラー等は、配布アプリのビルドに不要なため除外します。\nこのテスト用配布物はDEPENDENCIES.jsonのSparkleの出所とリビジョンから入手できます。\nライブラリ本体、ビルド手順、テストのソースコード、ライセンス原文は保持します。\n\nアプリのビルドはSources/VoiceInk/README.mdとBUILDING.mdを参照してください。\nXcode・macOS SDK・署名用証明書は別途用意します。個人の秘密鍵は含めません。\n\nネイティブ依存物:\n- Sources/whisper: ./build-xcframework.sh でWhisperをビルドします。\n- Sources/transcribe: TRANSCRIBE_XCFRAMEWORK_SLICES=macos ./scripts/ci/build_xcframework.sh\n- Sources/nemo: ./build-xcframework.sh。Rustターゲットの導入は同スクリプトを参照します。\nCargo.lockに従うRust依存ソースは各ディレクトリのvendorへ収録し、.cargo/config.tomlで参照します。\nSPMラッパーの元のバイナリURL・チェックサムはPackage.swiftに残っています。\n再生成したXCFrameworkを使う場合は、対応するbinaryTargetをローカルパスへ変更します。\nほかのSwift依存物はSources以下のPackage.swiftとロック済みリビジョンを参照してください。\n\nHaaS/Horizonの実行環境はアプリに同梱し、モデルは初回に取得します。Silero VADの重みはアプリに同梱しています。\n各プロジェクトのライセンス・著作権表示は元のソースとDMGのLicensesに保持しています。\n'''
        (stage / 'ソースの利用方法.md').write_text(instructions)
        archive = output / 'CorrespondingSource.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            for path in sorted(stage.iterdir()):
                tar.add(path, arcname=path.name)
        text = ['# 第三者ソフトウェアとモデルの告知\n',
            'ライセンス・著作権表示はLicenses内の原文を参照してください。',
            '対応ソースは同梱のCorrespondingSource.tar.gzにあります。',
            'HaaS/Horizonの実行環境を同梱し、モデルは初回に取得します。Silero VADはMITライセンスのモデルを同梱します。\n']
        for record in records:
            text += ['## '+record['name'], '出所: '+record['source'], 'リビジョン: `'+record['revision']+'`',
                     '原文: '+', '.join('`Licenses/'+p+'`' for p in record['notices'])+'\n']
        (output / '第三者ソフトウェアの告知.md').write_text('\n\n'.join(text)+'\n')
        (output / 'ソースの利用方法.md').write_text(instructions)
        hashes = {str(p.relative_to(output)): sha256(p) for p in output.rglob('*') if p.is_file() and p.name != 'SHA256SUMS'}
        (output / 'SHA256SUMS').write_text(''.join(value+'  '+name+'\n' for name, value in sorted(hashes.items())))
        print('Prepared', len(records), 'components;', sum(len(r['notices']) for r in records), 'notice files')


if __name__ == '__main__':
    if sys.version_info < (3, 12):
        raise SystemExit('Python 3.12以降が必要です')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-packages', type=Path, required=True)
    parser.add_argument('--whisper-source', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--extra-source', action='append', default=[], metavar='NAME=PATH')
    args = parser.parse_args()
    build(Path(__file__).resolve().parents[1], args.source_packages, args.whisper_source,
          args.cache, args.output, args.app, {k: Path(v) for k, v in (x.split('=', 1) for x in args.extra_source)})
