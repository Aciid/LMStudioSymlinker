#!/usr/bin/env zsh
# Builds a release .app bundle for distribution (e.g. GitHub Releases).
# Run from the repository root: ./scripts/build-app.sh

setopt LOCAL_OPTIONS ERR_EXIT
cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD_DIR="${ROOT}/build"
APP_NAME="LMStudioSymlinker"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

echo "Building release binary..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Generate app icon from SF Symbol "link"
ICON_GENERATOR="${BUILD_DIR}/render-link-icon"
ICON_1024="${BUILD_DIR}/icon_1024.png"
ICONSET="${BUILD_DIR}/AppIcon.iconset"
echo "Generating app icon (SF Symbol: link)..."
swiftc -framework AppKit -framework Foundation -o "$ICON_GENERATOR" "${ROOT}/scripts/render-link-icon.swift"
"$ICON_GENERATOR" "$ICON_1024"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$ICON_1024" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null 2>&1
  sips -z $((size*2)) $((size*2)) "$ICON_1024" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null 2>&1
done
iconutil -c icns "$ICONSET" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
rm -f "$ICON_GENERATOR" "$ICON_1024"
rm -rf "$ICONSET"

if [[ ! -f "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" ]] || [[ ! -s "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" ]]; then
  echo "error: AppIcon.icns was not created" >&2
  exit 1
fi

cp "${ROOT}/.build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Info.plist: replace $(EXECUTABLE_NAME) with actual executable name
sed 's/\$(EXECUTABLE_NAME)/'"${APP_NAME}"'/g' \
  "${ROOT}/LMStudioSymlinker/Resources/Info.plist" \
  > "${APP_BUNDLE}/Contents/Info.plist"

touch "$APP_BUNDLE"
echo "Created: ${APP_BUNDLE}"
echo ""
echo "To zip for GitHub Release:"
echo "  cd build && zip -r LMStudioSymlinker-macOS.zip ${APP_NAME}.app && cd .."
echo "  # Upload build/LMStudioSymlinker-macOS.zip to a GitHub Release"
