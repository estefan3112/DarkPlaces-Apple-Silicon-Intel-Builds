#!/bin/bash

set -e

echo "=== DarkPlaces macOS post-build script ==="

APP="Darkplaces.app"
MACOS="$APP/Contents/MacOS"
FRAMEWORKS="$APP/Contents/Frameworks"
VORBISFILE="$FRAMEWORKS/libvorbisfile.3.dylib"
VORBIS="$FRAMEWORKS/libvorbis.0.dylib"

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

echo "=== Fixing libvorbisfile internal deps (dynamic) ==="

OLD_VORBIS_PATH="$(otool -L "$VORBISFILE" | awk '/libvorbis\.0/ {print $1}')"
OLD_OGG_PATH="$(otool -L "$VORBISFILE" | awk '/libogg\.0/ {print $1}')"

install_name_tool -change "$OLD_VORBIS_PATH" "@executable_path/../Frameworks/libvorbis.0.dylib" "$VORBISFILE"
install_name_tool -change "$OLD_OGG_PATH"    "@executable_path/../Frameworks/libogg.0.dylib"    "$VORBISFILE"

echo "=== Fixing libvorbis internal deps (dynamic) ==="

OLD_OGG_IN_VORBIS="$(otool -L "$VORBIS" | awk '/libogg\.0/ {print $1}')"
install_name_tool -change "$OLD_OGG_IN_VORBIS" "@executable_path/../Frameworks/libogg.0.dylib" "$VORBIS"

echo "=== Clearing attributes and signing ==="
sudo xattr -cr "$APP"

# Force Finder/Spotlight to refresh bundle metadata
touch Darkplaces.app
touch Darkplaces.app/Contents

echo "=== Post-build complete. App bundle is ready. ==="