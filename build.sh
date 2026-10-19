#!/bin/zsh
# Собирает NotchHub.app и установщик NotchHub.dmg в ./build
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME=NotchHub
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
BUILD=build
APP="$BUILD/$APP_NAME.app"
ART="$BUILD/art"
DMG="$BUILD/$APP_NAME-$VERSION.dmg"

step() { print -P "%F{magenta}▸%f %B$1%b" }

step "Компиляция приложения"
swift build -c release

step "Компиляция модуля «Сейчас играет»"
mkdir -p "$BUILD"
clang -dynamiclib -fobjc-arc -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
    -framework Foundation -o "$BUILD/libNowPlaying.dylib" Helper/NowPlaying.m

step "Иконка и фон установщика"
swift scripts/make_art.swift "$ART" >/dev/null
iconutil -c icns "$ART/AppIcon.iconset" -o "$ART/AppIcon.icns"
tiffutil -cathidpicheck "$ART/background.png" "$ART/background@2x.png" -out "$ART/background.tiff" 2>/dev/null

step "Сборка $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP/Contents/Info.plist"
cp "$ART/AppIcon.icns" "$APP/Contents/Resources/"
cp "$BUILD/libNowPlaying.dylib" Helper/NowPlaying.pl "$APP/Contents/Resources/"
codesign --force --sign - "$APP/Contents/Resources/libNowPlaying.dylib"
codesign --force --sign - "$APP"

step "Создание DMG"
STAGE="$BUILD/dmg"
RW="$BUILD/rw.dmg"
rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Программы"
cp "$ART/background.tiff" "$STAGE/.background/background.tiff"

hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1}')
VOLUME="/Volumes/$APP_NAME"
sleep 1

# Оформление окна: фон, крупные иконки, расположение «приложение → Программы».
osascript <<OSA || print -P "%F{yellow}  (оформление окна пропущено — нет доступа к Finder)%f"
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 568}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "$APP_NAME.app" of container window to {170, 230}
        set position of item "Программы" of container window to {490, 230}
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA

cp "$ART/AppIcon.icns" "$VOLUME/.VolumeIcon.icns"
SetFile -c icnC "$VOLUME/.VolumeIcon.icns" 2>/dev/null || true
SetFile -a C "$VOLUME" 2>/dev/null || true
chmod -Rf go-w "$VOLUME" || true
sync
hdiutil detach -quiet "$DEVICE"

hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$RW" "$STAGE"

print -P "%F{green}✔%f Готово: %B$DMG%b"
