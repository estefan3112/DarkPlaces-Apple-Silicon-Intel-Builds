#!/bin/bash
# Turn the freshly built darkplaces-sdl into a self-contained Darkplaces.app.
#
# - copies the executable into Darkplaces.app/Contents/MacOS
# - copies libvorbis/libvorbisfile into Contents/Frameworks (DarkPlaces loads
#   them at runtime with dlopen for .ogg support, see snd_ogg.c)
# - uses dylibbundler to copy every other Homebrew library they need
#   (SDL2, libogg, ...) and rewrite all paths to @executable_path/../Frameworks
# - ad-hoc signs everything (required on Apple Silicon after paths are changed)
#
# Usage: scripts/bundle-macos.sh   (run from the repository root after make)

set -euo pipefail

APP="Darkplaces.app"
MACOS="$APP/Contents/MacOS"
FRAMEWORKS="$APP/Contents/Frameworks"
BREW="$(brew --prefix)"

mkdir -p "$MACOS" "$FRAMEWORKS"
cp -f darkplaces-sdl "$MACOS/"

# Libraries that are dlopen'ed (not linked), so dylibbundler can't find them by itself
cp -f "$BREW/opt/libvorbis/lib/libvorbis.0.dylib" \
      "$BREW/opt/libvorbis/lib/libvorbisfile.3.dylib" \
      "$FRAMEWORKS/"
chmod u+w "$FRAMEWORKS"/*.dylib

dylibbundler -of -b -cd \
  -x "$MACOS/darkplaces-sdl" \
  -x "$FRAMEWORKS/libvorbis.0.dylib" \
  -x "$FRAMEWORKS/libvorbisfile.3.dylib" \
  -d "$FRAMEWORKS/" \
  -p "@executable_path/../Frameworks/"

# Give the two dlopen'ed libraries bundle-relative IDs as well
for lib in libvorbis.0.dylib libvorbisfile.3.dylib; do
  install_name_tool -id "@executable_path/../Frameworks/$lib" "$FRAMEWORKS/$lib"
done

echo "=== Remaining non-system library references (should be none) ==="
if otool -L "$MACOS/darkplaces-sdl" "$FRAMEWORKS"/*.dylib | grep -E "$BREW|/usr/local/(opt|Cellar|lib)"; then
  echo "ERROR: Homebrew paths still present"
  exit 1
fi

echo "=== Signing (ad-hoc) ==="
xattr -cr "$APP"
codesign --force --sign - "$FRAMEWORKS"/*.dylib
codesign --force --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "=== Bundle contents ==="
ls -l "$MACOS" "$FRAMEWORKS"
