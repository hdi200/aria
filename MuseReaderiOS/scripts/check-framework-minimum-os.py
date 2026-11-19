#!/usr/bin/env python3
"""Check iOS bundle deployment metadata and fix Xcode's ONNX static-framework stub.

The ONNX package contains a static archive. Xcode embeds an empty dylib stub using
the app deployment target, but retains the package's older MinimumOSVersion.
Correct the embedded copy only, then re-sign it before Xcode signs the app.
"""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess
import sys


def version(value):
    parts = tuple(int(part) for part in str(value).split('.'))
    return parts + (0,) * (3 - len(parts))


def minimum(bundle):
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    binary = bundle / info['CFBundleExecutable']
    result = subprocess.run(['xcrun', 'vtool', '-show-build', str(binary)],
                            check=True, capture_output=True, text=True)
    platforms = re.findall(r'^\s*platform\s+(\S+)\s*$', result.stdout, re.M)
    values = re.findall(r'^\s*minos\s+(\d+(?:\.\d+)*)\s*$', result.stdout, re.M)
    if not values or not platforms or any(p != 'IOS' for p in platforms):
        raise ValueError(f'{bundle.name}: expected iOS LC_BUILD_VERSION in every executable slice')
    return info, max(values, key=version)


def check_app(app):
    info, _ = minimum(app)
    app_minimum = info['MinimumOSVersion']
    bundles = [app] + sorted(p for p in app.rglob('*')
                            if p.is_dir() and p.suffix in {'.framework', '.appex'})
    errors = []
    for bundle in bundles:
        metadata, binary_minimum = minimum(bundle)
        declared = metadata.get('MinimumOSVersion')
        label = bundle.name if bundle == app else str(bundle.relative_to(app))
        print(f'{label}: plist={declared}, binary={binary_minimum}, app={app_minimum}')
        if not declared or version(declared) < version(binary_minimum):
            errors.append(f'{label}: MinimumOSVersion understates executable requirement')
        if version(binary_minimum) > version(app_minimum):
            errors.append(f'{label}: executable requires a newer iOS than the app supports')
        if declared and version(declared) > version(app_minimum):
            errors.append(f'{label}: declared minimum exceeds app minimum')
    if errors:
        raise ValueError('; '.join(errors))


def fix_framework(bundle, app_minimum, identity):
    if bundle.name != 'onnxruntime.framework':
        raise ValueError('The packaging workaround is restricted to onnxruntime.framework')
    info, binary_minimum = minimum(bundle)
    if version(binary_minimum) > version(app_minimum):
        raise ValueError('ONNX executable requires a newer iOS; metadata correction is insufficient')
    declared = info.get('MinimumOSVersion')
    if declared and version(declared) > version(app_minimum):
        raise ValueError('ONNX declared minimum exceeds the app minimum')
    if declared and version(declared) >= version(binary_minimum):
        print(f'{bundle.name}: MinimumOSVersion {declared} already supports binary {binary_minimum}')
        return
    # Never lower a binary requirement or alter the downloaded SwiftPM artifact.
    info['MinimumOSVersion'] = binary_minimum
    plist = bundle / 'Info.plist'
    original = plist.read_bytes()
    fmt = plistlib.FMT_BINARY if original.startswith(b'bplist') else plistlib.FMT_XML
    plist.write_bytes(plistlib.dumps(info, fmt=fmt, sort_keys=False))
    if identity:
        subprocess.run(['codesign', '--force', '--sign', identity,
                        '--preserve-metadata=identifier,entitlements,flags',
                        '--generate-entitlement-der', str(bundle)], check=True)
    print(f'{bundle.name}: corrected MinimumOSVersion {declared} -> {binary_minimum}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check-app', type=Path)
    mode.add_argument('--fix-framework', type=Path)
    parser.add_argument('--app-minimum')
    parser.add_argument('--sign-identity')
    args = parser.parse_args()
    try:
        if args.check_app:
            check_app(args.check_app)
        else:
            if not args.app_minimum:
                parser.error('--fix-framework requires --app-minimum')
            fix_framework(args.fix_framework, args.app_minimum, args.sign_identity)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f'error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
