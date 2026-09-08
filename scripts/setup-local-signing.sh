#!/bin/bash

# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
# SPDX-License-Identifier: MIT

# Explicit, one-time provisioning. Builds never generate or rotate signing keys.
set -euo pipefail
umask 077

identity_name="YapOps Local Development"
keychain="$(/usr/bin/security default-keychain -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
if [[ -z "$keychain" || ! -f "$keychain" ]]; then
    printf 'A user Keychain is required for local signing.\n' >&2
    exit 1
fi

has_identity() {
    /usr/bin/security find-identity -v -p codesigning "$keychain" \
        | grep -Fq "\"$identity_name\""
}

if has_identity; then
    printf 'Reusing %s from your Keychain.\n' "$identity_name"
    exit 0
fi

# Never replace an existing certificate with a new key just because validation failed.
if /usr/bin/security find-certificate -c "$identity_name" "$keychain" >/dev/null 2>&1; then
    printf 'The existing %s identity needs its private key or code-signing trust repaired.\n' \
        "$identity_name" >&2
    printf 'No replacement key was created. Check the identity in Keychain Access.\n' >&2
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/yapops-signing.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

cat > "$work_dir/certificate.cnf" <<'CONFIG'
# SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
# SPDX-License-Identifier: MIT
[req]
distinguished_name = subject
x509_extensions = signing
prompt = no
[subject]
CN = YapOps Local Development
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG

printf 'Creating a persistent local signing identity in your user Keychain.\n'
/usr/bin/openssl req -new -newkey rsa:3072 -x509 -sha256 -nodes -days 3650 \
    -config "$work_dir/certificate.cnf" \
    -keyout "$work_dir/private-key.pem" -out "$work_dir/certificate.pem" \
    >/dev/null 2>&1
transport_password="$(/usr/bin/openssl rand -base64 32)"
/usr/bin/openssl pkcs12 -export -name "$identity_name" \
    -inkey "$work_dir/private-key.pem" -in "$work_dir/certificate.pem" \
    -out "$work_dir/identity.p12" -passout fd:3 \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    3<<< "$transport_password"

# The temporary PKCS#12 is owner-only, uses a disposable password, and is removed
# on exit. Only codesign is preauthorized; the imported private key is non-exportable.
/usr/bin/security import "$work_dir/identity.p12" -k "$keychain" \
    -f pkcs12 -P "$transport_password" -x -T /usr/bin/codesign
unset transport_password
# Trust is limited to code signing in this user's domain, never TLS or system trust.
/usr/bin/security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" \
    "$work_dir/certificate.pem"

if ! has_identity; then
    printf 'The identity was imported but code-signing trust is not ready.\n' >&2
    printf 'Check %s in Keychain Access; do not regenerate the key.\n' "$identity_name" >&2
    exit 1
fi
printf 'Ready: make app will reuse %s.\n' "$identity_name"
