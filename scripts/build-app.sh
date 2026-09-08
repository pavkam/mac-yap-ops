#!/bin/bash

# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
# SPDX-License-Identifier: MIT

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_dir="$(cd "$script_dir/.." && pwd -P)"
configuration="${CONFIGURATION:-release}"
sign_identity="${SIGN_IDENTITY:-YapOps Local Development}"

cd "$project_dir"
swift build -c "$configuration" --product YapOps
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_path="$project_dir/.build/YapOps.app"
staging_dir="$(mktemp -d "$project_dir/.build/YapOps-package.XXXXXX")"
staged_app="$staging_dir/YapOps.app"
contents_path="$staged_app/Contents"

cleanup() {
    if [[ -d "$staging_dir/previous.app" && ! -e "$app_path" ]]; then
        mv "$staging_dir/previous.app" "$app_path"
    fi
    rm -rf "$staging_dir"
}
trap cleanup EXIT

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$binary_dir/YapOps" "$contents_path/MacOS/YapOps"
cp "$project_dir/Sources/YapOpsApp/Resources/Info.plist" "$contents_path/Info.plist"
cp "$project_dir/Sources/YapOpsApp/Resources/YapOps.icns" "$contents_path/Resources/YapOps.icns"
for sound_name in AgentThinking CaptureEnd CaptureStart ToolComplete ToolFailed ToolStart; do
    cp "$project_dir/Sources/YapOpsApp/Resources/$sound_name.wav" \
        "$contents_path/Resources/$sound_name.wav"
done

plutil -lint "$contents_path/Info.plist"
if ! codesign --force --deep --sign "$sign_identity" "$staged_app"; then
    printf 'Signing failed. The existing app has been preserved.\n' >&2
    if [[ "$sign_identity" == "YapOps Local Development" ]]; then
        printf 'Run make setup-signing once, then retry. Ad-hoc builds require SIGN_IDENTITY=-.\n' >&2
    fi
    exit 1
fi
codesign --verify --deep --strict "$staged_app"

if [[ -e "$app_path" ]]; then
    mv "$app_path" "$staging_dir/previous.app"
fi
mv "$staged_app" "$app_path"

printf 'Built %s\n' "$app_path"
