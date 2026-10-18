#!/usr/bin/env bash
#
# Creates a self-signed code-signing certificate in the login keychain, for
# Scripts/build-app.sh to sign Mousecape with.
#
# Why: an ad-hoc signature is the build's code hash, so every build has a different
# identity. With a certificate, every build has the same designated requirement
# ("identifier … and certificate leaf = …"), so what macOS ties to the app's identity
# (privacy permissions, keychain access) stays valid across updates. It does not make
# Gatekeeper trust the app: that still needs right-click → Open (or a Developer ID and
# notarization). The login agent doesn't depend on it: launchd pinned SMAppService agents
# to the exact build even with this certificate, so the agent is a plain launch agent now.
#
# Usage:
#   Scripts/make-signing-certificate.sh                 # "Mousecape Code Signing"
#   CERT_NAME="Other Name" Scripts/make-signing-certificate.sh
#
# Keep a backup of the identity (Keychain Access → My Certificates → Export, as .p12):
# releases must keep being signed with the same certificate.
#
set -euo pipefail

CERT_NAME="${CERT_NAME:-Mousecape Code Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl          # LibreSSL: writes PKCS#12 files the keychain imports

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "A certificate named \"$CERT_NAME\" is already in the login keychain."
    security find-certificate -c "$CERT_NAME" -Z "$KEYCHAIN" | grep SHA-1
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CERT_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

echo "==> Key and certificate (valid 10 years)…"
"$OPENSSL" req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.conf" 2>/dev/null

# A throwaway password: the .p12 only lives until the import below.
P12_PASSWORD="$(uuidgen)"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$CERT_NAME" -out "$WORK/identity.p12" -passout "pass:$P12_PASSWORD"

echo "==> Import into the login keychain…"
# -T lets codesign use the key without asking each time.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "==> Done: \"$CERT_NAME\""
security find-certificate -c "$CERT_NAME" -Z "$KEYCHAIN" | grep SHA-1
