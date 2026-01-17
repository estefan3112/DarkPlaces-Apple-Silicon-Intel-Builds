#!/bin/bash

set -e

echo "=== DarkPlaces macOS post-build script ==="

APP="Darkplaces.app"
MACOS="$APP/Contents/MacOS"
FRAMEWORKS="$APP/Contents/Frameworks"

# Detect Homebrew prefix (ARM vs Intel)
if [ -d /opt/homebrew ]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

echo "Using Homebrew prefix: $BREW_PREFIX"

# Ensure bundle directories exist
mkdir -p "$MACOS"
mkdir -p "$FRAMEWORKS"

# Copy the freshly built binary
echo "Copying darkplaces-sdl into app bundle..."
cp -f ./darkplaces-sdl "$MACOS/darkplaces-sdl"

# List of dylibs to bundle
DYLIBS=(
    "$BREW_PREFIX/opt/libogg/lib/libogg.0.dylib"
    "$BREW_PREFIX/opt/libvorbis/lib/libvorbis.0.dylib"
    "$BREW_PREFIX/opt/libvorbis/lib/libvorbisfile.3.dylib"
)

echo "Copying required dylibs into Frameworks..."
for dylib in "${DYLIBS[@]}"; do
    cp -f "$dylib" "$FRAMEWORKS/"
done

# Fix the binary's load paths
echo "Patching binary load commands..."
for dylib in "${DYLIBS[@]}"; do
    base=$(basename "$dylib")
    install_name_tool -change "$dylib" "@executable_path/../Frameworks/$base" "$MACOS/darkplaces-sdl"
done

# Fix the dylibs' own IDs
echo "Fixing dylib install names..."
for dylib in "${DYLIBS[@]}"; do
    base=$(basename "$dylib")
    install_name_tool -id "@executable_path/../Frameworks/$base" "$FRAMEWORKS/$base"
done

echo "=== Post-build complete. App bundle is ready. ==="