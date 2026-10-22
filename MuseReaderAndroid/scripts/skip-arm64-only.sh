#!/bin/bash
# Runs Skip with "--arch automatic" turned into "--arch aarch64".
#
# Release builds otherwise compile the Swift code for x86_64 too, and the MuseScore engine
# (libaria_engine.so) is built for arm64-v8a only, so linking fails. Skip's generated Gradle
# task takes the skip command from SKIP_COMMAND_OVERRIDE:
#
#   cd MuseReaderAndroid/Aria/Android
#   SKIP_COMMAND_OVERRIDE="$PWD/../../scripts/skip-arm64-only.sh" gradle :app:bundleRelease
args=()
previous=""
for argument in "$@"; do
    if [ "$previous" = "--arch" ] && [ "$argument" = "automatic" ]; then
        argument="aarch64"
    fi
    args+=("$argument")
    previous="$argument"
done
# Skip's build plugins also run this, in a sandbox that blocks Homebrew's skip launcher
# (it runs xattr), so prefer the package's own skip binary, as the plugins do.
script_dir="$(cd "$(dirname "$0")" && pwd)"
package_skip="$script_dir/../Aria/.build/artifacts/skip/skip/skip.artifactbundle/macos/skip"
real_skip="${ARIA_REAL_SKIP:-}"
if [ -z "$real_skip" ] && [ -x "$package_skip" ]; then
    real_skip="$package_skip"
fi
[ -z "$real_skip" ] && real_skip="$(command -v skip)"
for candidate in /opt/homebrew/bin/skip /usr/local/bin/skip; do
    [ -n "$real_skip" ] && break
    [ -x "$candidate" ] && real_skip="$candidate"
done
exec "${real_skip:-skip}" "${args[@]}"
