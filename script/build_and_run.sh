#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_DISPLAY="Manter Ativo"
BINARY_NAME="ManterAtivo"
BUNDLE_ID="com.guicunha.manterativo.cockpit"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
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
  swift build -c release --product "$BINARY_NAME"
  local built
  built="$(swift build -c release --product "$BINARY_NAME" --show-bin-path)/$BINARY_NAME"
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES/helpers"
  cp "$built" "$APP_BINARY"
  chmod +x "$APP_BINARY"
  cp "$ROOT_DIR/helpers/"* "$APP_RESOURCES/helpers/"
  stage_icon "$APP_RESOURCES"
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
  <string>2.1</string>
  <key>CFBundleVersion</key>
  <string>2.1</string>
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

stage_icon() {
  local resources="$1"
  local source="$ROOT_DIR/Icon/AppIcon.png"
  local iconset="$ROOT_DIR/Icon/AppIcon.iconset"
  [[ -f "$source" ]] || return 0
  rm -rf "$iconset"
  mkdir -p "$iconset"
  local size
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    local retina=$((size * 2))
    sips -z "$retina" "$retina" "$source" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$resources/AppIcon.icns"
  cp "$resources/AppIcon.icns" "$ROOT_DIR/Icon/AppIcon.icns"
  rm -rf "$iconset"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    stop_app
    build_bundle
    open_app
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
    stop_app
    build_bundle
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
    echo "usage: $0 [run|--cockpit|--debug|--logs|--telemetry|--verify|--install]" >&2
    exit 2
    ;;
esac
