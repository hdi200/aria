#!/usr/bin/env python3
"""Validate the release bundle's identity, asset split and native ELF alignment."""
import argparse
import hashlib
from pathlib import Path
import re
import struct
import subprocess
import zipfile


def load_alignments(data):
    if data[:4] != b'\x7fELF' or data[4:6] != b'\x02\x01':
        raise ValueError('Expected little-endian ELF64')
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    segments = [struct.unpack_from('<IIQQQQQQ', data, header[5] + i * header[9])
                for i in range(header[10])]
    return [(s[2], s[3], s[7]) for s in segments if s[0] == 1]


def inspect(bundle, tool):
    def bt(*args):
        return subprocess.check_output(['java', '-jar', str(tool), *args], text=True).strip()
    print(bt('validate', '--bundle=' + str(bundle)))
    manifest = bt('dump', 'manifest', '--bundle=' + str(bundle), '--module=base')
    assert 'package="com.hdi200.ariascore"' in manifest, 'Wrong application ID'
    assert 'android:debuggable="true"' not in manifest, 'Debuggable release'
    assert 'android:targetSdkVersion="36"' in manifest, 'Expected target API 36'
    env = (Path(__file__).resolve().parents[1] / 'Aria/Skip.env').read_text()
    for prop, attr in [('CURRENT_PROJECT_VERSION', 'versionCode'), ('MARKETING_VERSION', 'versionName')]:
        expected = re.search(r'^' + prop + r'\s*=\s*(.+)$', env, re.M).group(1).strip()
        assert f'android:{attr}="{expected}"' in manifest, f'Wrong {attr}'
    pack_manifest = bt('dump', 'manifest', '--bundle=' + str(bundle), '--module=soundbank')
    assert 'install-time' in pack_manifest, 'Sound bank must be install-time'
    with zipfile.ZipFile(bundle) as archive:
        names = archive.namelist()
        bank = 'soundbank/assets/ios/MuseScore_General.sf2'
        banks = [n for n in names if n.endswith('.sf2')]
        assert banks == [bank], f'Missing/duplicate sound bank: {banks}'
        assert 'base/assets/ios/Legal/GPL-3.0.txt' in names, 'Missing existing legal resource'
        native = [n for n in names if n.startswith('base/lib/') and n.endswith('.so')]
        assert native and {n.split('/')[2] for n in native} == {'arm64-v8a'}, 'Wrong/missing ABIs'
        for name in native:
            for offset, address, alignment in load_alignments(archive.read(name)):
                assert alignment >= 16384 and (address - offset) % 16384 == 0, f'16 KB alignment: {name}'
        print(f'Native ELF alignment: {len(native)} libraries PASS (runtime still required)')
        print(f'Sound bank: {archive.getinfo(bank).file_size:,} bytes, only in install-time pack')
    result = subprocess.run(['jarsigner', '-J-Duser.language=en', '-verify', str(bundle)],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
    assert 'jar verified.' in result.stdout, 'Bundle signature not verified'
    print('Bundle JAR signature verified; owner must compare upload-certificate fingerprint.')
    print('SHA-256:', hashlib.sha256(bundle.read_bytes()).hexdigest())
    print('Bundle ZIP bytes:', bundle.stat().st_size, '(NOT Play download size)')
    print('PASS: structural checks. Measure get-size total and perform split-install/runtime tests next.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--bundletool', type=Path, required=True)
    args = parser.parse_args()
    inspect(args.bundle, args.bundletool)
