#!/usr/bin/env python3
"""Build a Universal macOS app and DMG. No third-party build dependencies."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / 'dist'
VERSION = '0.1.0'
BUILD_NUMBER = '3'
APP_NAME = '1UP'

def run(*args, **kwargs):
    print('+', ' '.join(map(str, args)), flush=True)
    return subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True, **kwargs)

def identity():
    configured = os.environ.get('ONEUP_SIGN_IDENTITY') or os.environ.get('LIFESTATUS_SIGN_IDENTITY')
    if configured:
        return configured
    output = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    found = re.search(r'"(Developer ID Application: [^"]+)"', output)
    if not found:
        raise SystemExit('No Developer ID Application identity found. Install a certificate or use --unsigned for local development.')
    return found.group(1)

def notarize(path, profile):
    result = run('xcrun', 'notarytool', 'submit', path, '--keychain-profile', profile,
                 '--wait', '--output-format', 'json', stdout=subprocess.PIPE, text=True)
    submission = json.loads(result.stdout)
    report = DIST / f'{path.stem}-notarization.json'
    report.write_text(json.dumps(submission, indent=2) + '\n')
    print(f'Notarization {submission.get("id")}: {submission.get("status")}', flush=True)
    if submission.get('status') != 'Accepted':
        raise SystemExit(f'Apple did not accept {path.name}. See {report}; use notarytool log with the submission ID for details.')
    return submission['id']

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--unsigned', action='store_true', help='Ad-hoc sign for local development only')
    parser.add_argument('--host-only', action='store_true', help='Build only the current Mac architecture')
    parser.add_argument('--notary-profile', help='Existing notarytool Keychain profile; notarize app and DMG')
    args = parser.parse_args()
    if args.unsigned and args.notary_profile:
        parser.error('--notary-profile requires Developer ID signing')
    architecture = 'host' if args.host_only else 'universal'
    DIST.mkdir(exist_ok=True)
    (DIST / 'build-info.json').unlink(missing_ok=True)
    (DIST / 'SHA256SUMS').unlink(missing_ok=True)
    arch_args = [] if args.host_only else ['--arch', 'arm64', '--arch', 'x86_64']
    run('swift', 'build', '-c', 'release', *arch_args)
    binary_dir = Path(subprocess.check_output(['swift', 'build', '-c', 'release', *arch_args, '--show-bin-path'], cwd=ROOT, text=True).strip())
    app = DIST / f'{APP_NAME}.app'
    if app.exists():
        shutil.rmtree(app)
    contents = app / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    resources = contents / 'Resources'; resources.mkdir()
    executable = contents / 'MacOS' / APP_NAME
    shutil.copy2(binary_dir / 'LifeStatus', executable)
    # Swift release binaries can retain local build paths in debug symbols.
    # Keep the original symbols in .build/; strip only the distributed copy.
    run('xcrun', 'strip', '-S', executable)
    shutil.copytree(binary_dir / 'LifeStatus_LifeStatus.bundle', resources / 'LifeStatus_LifeStatus.bundle')
    shutil.copy2(ROOT / 'LICENSE', resources / 'LICENSE')
    info = {
        'CFBundleName': APP_NAME, 'CFBundleDisplayName': APP_NAME,
        # Preserve identity and data compatibility with the earlier local builds.
        'CFBundleIdentifier': 'com.xfey.LifeStatus', 'CFBundleExecutable': APP_NAME,
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': VERSION, 'CFBundleVersion': BUILD_NUMBER,
        'CFBundleIconFile': 'AppIcon', 'LSUIElement': True, 'LSMinimumSystemVersion': '14.0',
        'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
        'LSApplicationCategoryType': 'public.app-category.healthcare-fitness',
        'NSHumanReadableCopyright': 'Copyright © 2026 Xiang Fei',
    }
    with (contents / 'Info.plist').open('wb') as handle:
        plistlib.dump(info, handle)
    signing = '-' if args.unsigned else identity()
    submissions = {}
    with tempfile.TemporaryDirectory(prefix='oneup-package-') as temporary:
        work = Path(temporary)
        # The approved device artwork already includes its housing and margins.
        master = ROOT / 'assets' / 'AppIcon.png'
        iconset = work / 'AppIcon.iconset'; iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                pixels = points * scale
                name = f'icon_{points}x{points}' + ('@2x' if scale == 2 else '') + '.png'
                run('sips', '-z', pixels, pixels, master, '--out', iconset / name, stdout=subprocess.DEVNULL)
        run('iconutil', '-c', 'icns', iconset, '-o', resources / 'AppIcon.icns')
        sign_args = ['--force', '--sign', signing]
        if not args.unsigned:
            sign_args += ['--options', 'runtime', '--timestamp']
        run('codesign', *sign_args, app)
        run('codesign', '--verify', '--deep', '--strict', '--verbose=2', app)
        if args.notary_profile:
            archive = work / f'{APP_NAME}.zip'
            run('ditto', '-c', '-k', '--keepParent', app, archive)
            submissions['app'] = notarize(archive, args.notary_profile)
            run('xcrun', 'stapler', 'staple', app)
            run('xcrun', 'stapler', 'validate', app)
        stage = work / 'dmg'; stage.mkdir()
        shutil.copytree(app, stage / app.name, symlinks=True)
        (stage / 'Applications').symlink_to('/Applications')
        requirements = '本机调试版本。' if args.host_only else '包含 Apple Silicon 和 Intel 两种架构。'
        (stage / '安装说明.txt').write_text('将 1UP 拖入 Applications 后打开。\n点击菜单栏图标展开三条状态；右键可设置登录启动、编辑文案和退出。\n若安装过 LifeStatus 预览版，请先退出旧版本，再打开 1UP；原有状态和文案会继续使用。\n支持 macOS 14 及以上。\n' + requirements + '\n', encoding='utf-8')
        shutil.copy2(ROOT / 'LICENSE', stage / 'LICENSE')
        dmg = DIST / f'{APP_NAME}-{VERSION}-{architecture}.dmg'
        run('hdiutil', 'create', '-volname', APP_NAME, '-srcfolder', stage, '-format', 'UDZO', '-ov', dmg)
        if not args.unsigned:
            run('codesign', '--force', '--sign', signing, '--timestamp', dmg)
        if args.notary_profile:
            submissions['dmg'] = notarize(dmg, args.notary_profile)
            run('xcrun', 'stapler', 'staple', dmg)
            run('xcrun', 'stapler', 'validate', dmg)
            run('spctl', '--assess', '--type', 'execute', '--verbose=2', app)
            run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg)
        run('codesign', '--verify', '--deep', '--strict', app)
        if not args.unsigned:
            run('codesign', '--verify', '--strict', dmg)
        run('hdiutil', 'verify', dmg)
    checksum = hashlib.sha256(dmg.read_bytes()).hexdigest()
    (DIST / 'SHA256SUMS').write_text(f'{checksum}  {dmg.name}\n')
    report = {'name': APP_NAME, 'version': VERSION, 'build': BUILD_NUMBER,
              'architectures': architecture, 'signed': not args.unsigned,
              'notarized': bool(args.notary_profile), 'notarization_ids': submissions,
              'app': app.name, 'dmg': dmg.name, 'sha256': checksum}
    (DIST / 'build-info.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Built {app}\nBuilt {dmg}\nNotarized: {bool(args.notary_profile)}')

if __name__ == '__main__':
    main()
