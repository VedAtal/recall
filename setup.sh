#!/usr/bin/env bash
#
# One-step build + install for Recall.
#
#   ./setup.sh               build, install to ~/Applications, and launch
#   ./setup.sh --build-only  just build build/Recall.app
#   ./setup.sh --uninstall   remove the app, its history, settings, login item, and signing key
#
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"

APP_NAME="Recall"
BUNDLE_ID="local.recall"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
DATA_DIR="$HOME/Library/Application Support/Recall"

# macOS ties the Accessibility permission to the app's code signature. An ad-hoc signature
# changes with every build, which silently breaks the permission. So we keep a self-signed
# certificate in its own keychain and sign every build with it. The password only protects
# this throwaway key, which nothing outside this Mac uses.
KEYCHAIN="${RECALL_KEYCHAIN:-$HOME/Library/Keychains/recall-codesign.keychain-db}"
KEYCHAIN_PASSWORD="recall"
CERT_NAME="Recall Local Code Signing"
SIGN_ID="-"

# Colors only in a terminal. Recall's "Update Recall" menu item runs this with output going to a log file.
if [[ -t 1 ]]; then
  BOLD=$'\033[1m' BLUE=$'\033[1;34m' YELLOW=$'\033[1;33m' RED=$'\033[1;31m' GREEN=$'\033[1;32m' RESET=$'\033[0m'
else
  BOLD="" BLUE="" YELLOW="" RED="" GREEN="" RESET=""
fi

step() { printf '%s==>%s %s%s%s\n' "$BLUE" "$RESET" "$BOLD" "$*" "$RESET"; }
warn() { printf '%swarning:%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

check_requirements() {
  [[ "$(uname)" == "Darwin" ]] || die "Recall only runs on macOS."
  local major
  major=$(sw_vers -productVersion | cut -d. -f1)
  (( major >= 14 )) || die "Recall needs macOS 14 (Sonoma) or newer."
  if ! xcrun --find swift >/dev/null 2>&1; then
    xcode-select --install >/dev/null 2>&1 || true
    die "Swift isn't installed. Finish installing the Command Line Tools in the window that just opened, then run ./setup.sh again."
  fi
}

# --- Code signing ---------------------------------------------------------------------------

create_signing_identity() {
  local tmp status=0
  tmp=$(mktemp -d)
  # /usr/bin/openssl (LibreSSL) on purpose: a Homebrew OpenSSL 3 writes .p12 files that
  # `security import` can't read.
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$CERT_NAME" \
      -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
      -addext "basicConstraints=critical,CA:false" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1 \
    && /usr/bin/openssl pkcs12 -export -name "$CERT_NAME" -passout pass:recall \
      -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/identity.p12" \
    && security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" \
    && security set-keychain-settings "$KEYCHAIN" \
    && security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" \
    && security import "$tmp/identity.p12" -k "$KEYCHAIN" -P recall -T /usr/bin/codesign >/dev/null \
    && security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null \
    || status=1
  rm -rf "$tmp"
  return $status
}

# Sets SIGN_ID to the certificate's SHA-1, or leaves it as "-" (ad-hoc) if anything goes wrong.
ensure_signing_identity() {
  if [[ ! -f "$KEYCHAIN" ]]; then
    echo "    Creating a local code-signing certificate (one time)…"
    if ! create_signing_identity; then
      security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || rm -f "$KEYCHAIN"
      warn "Couldn't create a signing certificate. Using an ad-hoc signature, so you'll need to re-grant Accessibility after each rebuild."
      return 0
    fi
  fi
  # Custom keychains lock at logout, so unlock before every build.
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 || true
  local id
  id=$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
       | awk -v name="\"$CERT_NAME\"" 'index($0, name) { print $2; exit }')
  if [[ -n "$id" ]]; then
    SIGN_ID="$id"
  else
    warn "Signing certificate not found in $KEYCHAIN. Using an ad-hoc signature."
  fi
}

# --- Build ----------------------------------------------------------------------------------

make_icon() {
  local icns="$BUILD_DIR/AppIcon.icns" iconset="$BUILD_DIR/AppIcon.iconset"
  # Reuse the last icon unless the script that draws it has changed since.
  [[ "$icns" -nt scripts/make-icon.swift ]] && return 0
  rm -rf "$iconset"
  mkdir -p "$iconset"
  if swift scripts/make-icon.swift "$iconset" && iconutil -c icns "$iconset" -o "$icns"; then
    rm -rf "$iconset"
  else
    rm -rf "$iconset"
    warn "Couldn't generate the app icon. Continuing without it."
  fi
}

build_app() {
  step "Building ${APP_NAME}…"
  # The filter hides harmless linker warnings that only show up with the Command Line Tools.
  # It always succeeds, so with pipefail the status is swift's.
  local status=0
  swift build -c release --product "$APP_NAME" 2>&1 \
    | { grep --line-buffered -v "ld: warning: search path" || true; } || status=$?
  (( status == 0 )) || die "Build failed. See the errors above."
  local bin
  bin="$(swift build -c release --show-bin-path)/$APP_NAME"

  step "Assembling $APP_NAME.app…"
  mkdir -p "$BUILD_DIR"
  make_icon
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp "$bin" "$APP/Contents/MacOS/$APP_NAME"
  cp Resources/Info.plist "$APP/Contents/Info.plist"
  # The "Update Recall" menu item runs this script from here. The build time shows in the menu.
  plutil -insert RecallSourceDirectory -string "$ROOT" "$APP/Contents/Info.plist"
  plutil -insert RecallBuildDate -string "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$APP/Contents/Info.plist"
  if [[ -f "$BUILD_DIR/AppIcon.icns" ]]; then
    cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  fi

  step "Signing…"
  ensure_signing_identity
  if [[ "$SIGN_ID" == "-" ]]; then
    codesign --force --sign - "$APP"
  else
    codesign --force --sign "$SIGN_ID" --keychain "$KEYCHAIN" "$APP"
  fi
}

# --- Install / uninstall --------------------------------------------------------------------

stop_running_app() {
  pgrep -x "$APP_NAME" >/dev/null || return 0
  pkill -x "$APP_NAME" || true
  for _ in {1..50}; do
    pgrep -x "$APP_NAME" >/dev/null || return 0
    sleep 0.1
  done
  pkill -9 -x "$APP_NAME" || true
}

install_app() {
  step "Installing to ${INSTALLED_APP}…"
  stop_running_app
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALLED_APP"
  ditto "$APP" "$INSTALLED_APP"
  if [[ "$SIGN_ID" == "-" ]]; then
    # An old Accessibility grant won't match the new ad-hoc signature. Clear it so macOS asks again.
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  fi

  step "Launching…"
  open "$INSTALLED_APP"

  cat <<EOF

${GREEN}✓ Recall is running.${RESET} Look for the clipboard icon in the menu bar.

  • The first time, macOS asks you to allow Recall in Accessibility settings. Recall needs
    that to paste for you. Turn it on in System Settings → Privacy & Security → Accessibility.
  • Copy a few things, then hold ⇧⌘ and tap V to go through your history. Let go to paste.
  • Recall starts automatically at login. Change that and other options in Settings…

EOF
}

uninstall() {
  step "Uninstalling ${APP_NAME}…"
  stop_running_app
  if [[ -x "$INSTALLED_APP/Contents/MacOS/$APP_NAME" ]]; then
    "$INSTALLED_APP/Contents/MacOS/$APP_NAME" --unregister-login-item || true
  fi
  rm -rf "$INSTALLED_APP" "$BUILD_DIR" "$DATA_DIR"
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  if [[ -f "$KEYCHAIN" ]]; then
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || rm -f "$KEYCHAIN"
  fi
  echo "Recall has been removed."
}

case "${1:-}" in
  "")           check_requirements; build_app; install_app ;;
  --build-only) check_requirements; build_app; echo "Built $APP" ;;
  --uninstall)  uninstall ;;
  -h|--help)    sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)            die "Unknown option: $1 (try --help)" ;;
esac
