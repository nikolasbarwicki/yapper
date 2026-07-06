#!/bin/bash
# Build and package Yapper for distribution
# Usage: ./scripts/build-release.sh

set -e  # Exit on error

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/dist"
APP_NAME="Yapper"

echo "🔨 Building $APP_NAME..."

# Clean previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build release version
xcodebuild -project "$PROJECT_DIR/Yapper.xcodeproj" \
    -scheme Yapper \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    build

# Find the built app
APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build failed - app not found"
    exit 1
fi

echo "✅ Build successful!"

# Copy to dist folder
cp -R "$APP_PATH" "$BUILD_DIR/"

# Create ZIP
echo "📦 Creating ZIP..."
cd "$BUILD_DIR"
zip -r "$APP_NAME.zip" "$APP_NAME.app"

# Create DMG
echo "💿 Creating DMG..."
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$APP_NAME.app" \
    -ov -format UDZO \
    "$APP_NAME.dmg"

# Cleanup
rm -rf "$BUILD_DIR/DerivedData"

echo ""
echo "✅ Done! Distribution files:"
echo "   📁 $BUILD_DIR/$APP_NAME.app"
echo "   📦 $BUILD_DIR/$APP_NAME.zip"
echo "   💿 $BUILD_DIR/$APP_NAME.dmg"
echo ""
echo "Share the .zip or .dmg file with others!"
echo ""
echo "⚠️  Note: Recipients will need to right-click → Open"
echo "    to bypass Gatekeeper (unsigned app warning)"
