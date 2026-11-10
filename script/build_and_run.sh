#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_DISPLAY="Manter Ativo"
BINARY_NAME="ManterAtivo"
BUNDLE_ID="com.guicunha.manterativo.cockpit"
MIN_SYSTEM_VERSION="15.0"
APP_VERSION="2.1"
APP_BUILD="211"
BETA_NUMBER="1"
RELEASE_CHANNEL="Beta $BETA_NUMBER"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_ARGS=(-c release --product "$BINARY_NAME")
case "$MODE" in
  --bundle|bundle|--install|install|--package)
    BUILD_ARGS+=(--arch arm64 --arch x86_64 --scratch-path "$ROOT_DIR/.build/universal")
    ;;
esac
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$BINARY_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

stop_app() {
  pkill -x "$BINARY_NAME" >/dev/null 2>&1 || true
}

build_bundle() {
  cd "$ROOT_DIR"
  swift build "${BUILD_ARGS[@]}"
  local built
  built="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/$BINARY_NAME"
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES/helpers"
  cp "$built" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  cp "$ROOT_DIR/helpers/"* "$APP_RESOURCES/helpers/"
  stage_icon "$APP_RESOURCES"
  cp "$ROOT_DIR/LICENSE" "$APP_RESOURCES/LICENSE"
  chmod 755 "$APP_RESOURCES/helpers/"*.sh "$APP_RESOURCES/helpers/install-helper.sh" "$APP_RESOURCES/helpers/manter-ativo-on" "$APP_RESOURCES/helpers/manter-ativo-off"
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$BINARY_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>ManterAtivoReleaseChannel</key>
  <string>$RELEASE_CHANNEL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST
  codesign --force --sign - "$APP_BUNDLE" >/dev/null
}

verify_bundle() {
  codesign --verify --strict --all-architectures "$APP_BUNDLE"
  lipo "$APP_BINARY" -verify_arch arm64
  lipo "$APP_BINARY" -verify_arch x86_64
}

stage_icon() {
  local resources="$1"
  cp "$ROOT_DIR/Icon/AppIcon.icns" "$resources/AppIcon.icns"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE" --args --menu-bar
}

case "$MODE" in
  run)
    stop_app
    build_bundle
    open_app
    ;;
  --bundle|bundle)
    build_bundle
    verify_bundle
    ;;
  --package)
    build_bundle
    verify_bundle
    archive="Manter-Ativo-$APP_VERSION-beta.$BETA_NUMBER-macOS-universal.zip"
    (
      cd "$DIST_DIR"
      work="$(mktemp -d "./.package.XXXXXXXX")"
      trap 'rm -f "$work/$archive" "$work/$archive.sha256"; rmdir "$work"' EXIT
      ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP_DISPLAY.app" "$work/$archive"
      (cd "$work" && shasum -a 256 "$archive" > "$archive.sha256")
      mv -f "$work/$archive" "$work/$archive.sha256" .
    )
    ;;
  --debug|debug)
    stop_app
    build_bundle
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stop_app
    build_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$BINARY_NAME\""
    ;;
  --telemetry|telemetry)
    stop_app
    build_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    stop_app
    build_bundle
    open_app
    sleep 2
    pgrep -x "$BINARY_NAME" >/dev/null
    ;;
  --cockpit|cockpit)
    stop_app
    build_bundle
    /usr/bin/open -n "$APP_BUNDLE" --args --cockpit
    ;;
  --install|install)
    build_bundle
    verify_bundle
    stop_app
    if [[ -d "/Applications/$APP_DISPLAY.app" ]]; then
      if [[ ! -d "/Applications/$APP_DISPLAY (anterior).app" ]]; then
        mv "/Applications/$APP_DISPLAY.app" "/Applications/$APP_DISPLAY (anterior).app"
      else
        rm -rf "/Applications/$APP_DISPLAY.app"
      fi
    fi
    cp -R "$APP_BUNDLE" "/Applications/$APP_DISPLAY.app"
    /usr/bin/open -n "/Applications/$APP_DISPLAY.app" --args --cockpit
    ;;
  *)
    echo "usage: $0 [run|--bundle|--package|--cockpit|--debug|--logs|--telemetry|--verify|--install]" >&2
    exit 2
    ;;
esac
