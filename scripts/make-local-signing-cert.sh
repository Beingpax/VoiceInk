#!/bin/zsh
#
# Creates a stable self-signed code-signing identity for local VoiceInk builds.
#
# WHY THIS EXISTS
# ---------------
# `make local` signs ad-hoc (CODE_SIGN_IDENTITY = "-"), which produces a *different* code
# signature on every build. macOS records privacy grants (Accessibility, Screen Recording,
# Microphone) against an app's code signature, not its path — so every rebuild looks like a
# brand-new app and silently loses its permissions. The symptom is VoiceInk asking for
# Accessibility again even though System Settings shows it already enabled.
#
# Signing with a fixed self-signed certificate keeps the signature identical across rebuilds,
# so you grant permissions once and they stick.
#
# This is only for local development. Release builds use the real Developer ID identity.
#
# Usage:  ./scripts/make-local-signing-cert.sh
# Undo:   security delete-certificate -c "VoiceInk Local Dev"
#
set -euo pipefail

CERT_NAME="VoiceInk Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "✓ Signing identity '$CERT_NAME' already exists — nothing to do."
  echo
  echo "  Rebuild with 'make local' and it will be used automatically."
  exit 0
fi

# A certificate may already exist but be unusable because it carries no code-signing trust
# setting — this is what Keychain Access's Certificate Assistant leaves behind, and it shows up
# as CSSMERR_TP_NOT_TRUSTED. That only needs the trust step, not a whole new certificate.
if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  if security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "Found '$CERT_NAME', but it is not trusted for code signing."
    echo
    echo "==> Adding the code-signing trust setting"
    echo "    macOS will ask you to authorise a change to Certificate Trust Settings."
    security find-certificate -c "$CERT_NAME" -p > "$WORK/existing.pem"

    if ! security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/existing.pem"; then
      echo
      echo "✗ Could not set the trust setting. Do it by hand instead:"
      echo "    1. Open Keychain Access › login › Certificates"
      echo "    2. Double-click '$CERT_NAME' and expand 'Trust'"
      echo "    3. Set 'Code Signing' to 'Always Trust', then close the window"
      exit 1
    fi

    echo
    if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
      echo "✓ Done — '$CERT_NAME' is now a valid signing identity:"
      security find-identity -v -p codesigning
      exit 0
    fi
    echo "✗ Trust was set but the identity still is not valid. Check it in Keychain Access."
    exit 1
  fi

  echo "A certificate named '$CERT_NAME' exists but has no matching private key."
  echo "Remove it and re-run this script:"
  echo "    security delete-certificate -c \"$CERT_NAME\""
  exit 1
fi

cat > "$WORK/cert.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions    = codesign
prompt             = no

[ dn ]
CN = VoiceInk Local Dev
O  = VoiceInk Local Development
C  = US

[ codesign ]
basicConstraints     = critical,CA:false
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
subjectKeyIdentifier = hash
CNF

echo "==> Generating a self-signed code-signing certificate (valid 10 years)"
if ! openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 3650 -config "$WORK/cert.cnf" 2>"$WORK/openssl.log"; then
  echo "✗ Certificate generation failed:"
  cat "$WORK/openssl.log"
  exit 1
fi

# macOS Security.framework cannot read OpenSSL 3.x's default PKCS#12 encryption, so pin the
# legacy PBE algorithms and MAC that it can import.
P12_PASS="voiceink-local-dev"
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout "pass:$P12_PASS" -name "$CERT_NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg SHA1

# `security import` fails with "User interaction is not allowed" when the login keychain is
# locked and the process cannot raise a prompt. Unlocking it up front avoids that; this reads the
# password from the terminal, so the script must be run from a real shell.
echo "==> Unlocking your login keychain"
echo "    Enter your macOS login password at the prompt."
if ! security unlock-keychain "$KEYCHAIN"; then
  echo
  echo "✗ Could not unlock the login keychain."
  echo "  Run this script directly from Terminal.app — it needs a terminal to read the password."
  exit 1
fi

# -A grants every application access to this key without a confirmation dialog. That dialog is
# what fails with "User interaction is not allowed" in shells detached from the GUI session, and
# it would otherwise interrupt every build. Acceptable here: this is a throwaway local-dev signing
# key with no value outside this machine.
echo "==> Importing into your login keychain"
if ! security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -A \
  2>"$WORK/import.log"; then
  echo
  cat "$WORK/import.log"
  if grep -q "User interaction is not allowed" "$WORK/import.log"; then
    echo
    echo "✗ The keychain would not allow a prompt."
    echo "  Run this script directly from Terminal.app rather than from an editor or IDE shell."
  else
    echo
    echo "✗ Keychain import failed (see the error above)."
  fi
  exit 1
fi

echo "==> Trusting it for code signing"
echo "    macOS will ask for your login password again."
if ! security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"; then
  echo
  echo "✗ Could not set the trust setting automatically."
  echo "  The certificate IS imported. Finish it by hand:"
  echo "    1. Open Keychain Access › login › My Certificates"
  echo "    2. Double-click '$CERT_NAME' › expand 'Trust'"
  echo "    3. Set 'Code Signing' to 'Always Trust', then close the window"
  exit 1
fi

echo
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
  echo "✓ Done. Available signing identities:"
  security find-identity -v -p codesigning
  echo
  echo "Next steps:"
  echo "  1. make local"
  echo "  2. Open System Settings › Privacy & Security › Accessibility"
  echo "     Remove any existing VoiceInk entry, then re-add the build you run."
  echo "  3. Grant once — it now survives rebuilds."
else
  echo "✗ The certificate was created but is not showing as a valid signing identity."
  echo "  Open Keychain Access, find '$CERT_NAME', and set 'Code Signing' to 'Always Trust'."
  exit 1
fi
