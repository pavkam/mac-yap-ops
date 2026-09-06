#!/bin/bash

# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
# SPDX-License-Identifier: MIT

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
target="all"
online=0

usage() {
    cat <<'USAGE'
Usage: probe-local-clients.sh [all|cursor|codex|claude] [--online]

The default probe sends no credentials and calls only ACP initialize. It never
calls authenticate, session/new, session/load, session/resume, session/prompt,
or a permission method. Providers still inherit their normal ambient
configuration. Adapter probes use the npm cache by default; --online also reads
current registry metadata.
USAGE
}

for argument in "$@"; do
    case "$argument" in
        all | cursor | codex | claude)
            target="$argument"
            ;;
        --online)
            online=1
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$argument" >&2
            usage >&2
            exit 2
            ;;
    esac
done

has_target() {
    [[ "$target" == "all" || "$target" == "$1" ]]
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Missing required command for %s: %s\n' "$2" "$1" >&2
        exit 1
    fi
}

probe_initialize() {
    local label="$1"
    shift
    printf '\n%s initialize probe\n' "$label"
    NO_BROWSER=1 python3 "$script_dir/probe-initialize.py" "$@"
}

if has_target cursor; then
    require_command cursor-agent Cursor
    probe_initialize Cursor cursor-agent acp
fi

if has_target codex; then
    require_command npx Codex
    probe_initialize Codex \
        npx --offline -y @agentclientprotocol/codex-acp@1.8.0
fi

if has_target claude; then
    require_command npx Claude
    probe_initialize Claude \
        npx --offline -y @agentclientprotocol/claude-agent-acp@0.73.0
fi

if ((online)); then
    require_command npm registry
    printf '\nCurrent npm registry metadata (not project pins)\n'
    if has_target codex; then
        npm view @agentclientprotocol/codex-acp version dist-tags --json
    fi
    if has_target claude; then
        npm view @agentclientprotocol/claude-agent-acp version dist-tags engines --json
    fi
fi
