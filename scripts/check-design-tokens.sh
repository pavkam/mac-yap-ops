#!/bin/bash

# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
# SPDX-License-Identifier: MIT

# Fails when a view reintroduces a styling literal that the design token layer
# already owns. See .agents/skills/design/references/adoption.md.
#
# The rule set is deliberately narrow. A gate with false positives gets disabled
# rather than obeyed, so it covers only literals that are unambiguously styling:
# corner radii, font point sizes, and colours built from raw components. Opacity
# is excluded because the views use it for animated state as well as for fills.
#
# Suppress a genuine exception with a comment on the preceding line:
#
#     // design-token-exempt: sized to the host NSImage, not to the type ramp
#     .font(.system(size: measuredHeight))

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_dir="$(cd "$script_dir/.." && pwd -P)"
failed=0

cd "$project_dir"

# Each rule is a description and an extended regular expression.
rule_descriptions=(
    "raw corner radius; use a Design.Radius tier"
    "raw font point size; use a Design.Text role or Design.Text.glyph"
    "colour built from components; name a macOS system colour instead"
)
rule_patterns=(
    'cornerRadius: [0-9]'
    '\.system\(size: [0-9]'
    'Color\((red|white|hue):'
)

exempt_marker='design-token-exempt:'

report() {
    printf '%s:%s: %s\n    %s\n' "$1" "$2" "$3" "$4" >&2
    failed=1
}

for index in "${!rule_patterns[@]}"; do
    pattern="${rule_patterns[$index]}"
    description="${rule_descriptions[$index]}"

    while IFS=: read -r path line _; do
        [[ -z "${path:-}" ]] && continue

        # An exemption comment on the line above suppresses the finding.
        if ((line > 1)); then
            previous="$(sed -n "$((line - 1))p" "$path")"
            if [[ "$previous" == *"$exempt_marker"* ]]; then
                reason="${previous#*"$exempt_marker"}"
                if [[ -z "${reason// /}" ]]; then
                    report "$path" "$((line - 1))" \
                        "design-token-exempt needs a reason" "$previous"
                fi
                continue
            fi
        fi

        report "$path" "$line" "$description" "$(sed -n "${line}p" "$path")"
    done < <(
        rg --line-number --no-heading --type swift \
            --glob '!Sources/YapOpsApp/Design/**' \
            -e "$pattern" Sources/YapOpsApp || true
    )
done

if ((failed)); then
    printf '\nDesign tokens live in Sources/YapOpsApp/Design/.\n' >&2
    exit 1
fi

printf 'Design tokens verified: no unexempted styling literals in views.\n'
