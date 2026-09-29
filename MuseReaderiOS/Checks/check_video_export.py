#!/usr/bin/env python3
"""Check the real Swift exporter without building Xcode or the render core."""
import argparse
import pathlib
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--run", action="store_true", help="Also run short Catalyst pipeline correctness checks")
args = parser.parse_args()
checks = pathlib.Path(__file__).resolve().parent
exporter = checks.parent / "MuseReaderiOS/Services/ScoreVideoExporter.swift"


def sdk(name):
    return pathlib.Path(subprocess.check_output(["xcrun", "--sdk", name, "--show-sdk-path"], text=True).strip())


with tempfile.TemporaryDirectory(prefix="aria-video-check-") as temporary:
    work = pathlib.Path(temporary)
    sources = [str(checks / "VideoExportStubs.swift"), str(exporter), str(checks / "VideoExportChecks.swift")]
    common = ["xcrun", "swiftc", "-swift-version", "5", "-module-cache-path", str(work / "modules")]
    subprocess.run(common + ["-typecheck", "-target", "arm64-apple-ios17.0", "-sdk", str(sdk("iphoneos"))] + sources, check=True)
    if args.run:
        root = sdk("macosx")
        support = root / "System/iOSSupport"
        binary = work / "video-export-checks"
        subprocess.run(common + ["-O", "-target", "arm64-apple-ios17.0-macabi", "-sdk", str(root),
                                 "-F", str(support / "System/Library/Frameworks"),
                                 "-I", str(support / "usr/lib/swift")] + sources + ["-o", str(binary)], check=True)
        subprocess.run([str(binary), str(work / "outputs")], check=True)
    print("Swift exporter checks passed")
