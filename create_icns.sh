#!/bin/bash
set -ex

IMG="/Users/kangwei/.gemini/antigravity/brain/f8fa7511-bae9-46b8-8de4-44713abc1a5b/audx_icon_headset_time_1774070348286.png"

mkdir -p audx.iconset
sips -s format png -z 16 16 "$IMG" --out audx.iconset/icon_16x16.png
sips -s format png -z 32 32 "$IMG" --out audx.iconset/icon_16x16@2x.png
sips -s format png -z 32 32 "$IMG" --out audx.iconset/icon_32x32.png
sips -s format png -z 64 64 "$IMG" --out audx.iconset/icon_32x32@2x.png
sips -s format png -z 128 128 "$IMG" --out audx.iconset/icon_128x128.png
sips -s format png -z 256 256 "$IMG" --out audx.iconset/icon_128x128@2x.png
sips -s format png -z 256 256 "$IMG" --out audx.iconset/icon_256x256.png
sips -s format png -z 512 512 "$IMG" --out audx.iconset/icon_256x256@2x.png
sips -s format png -z 512 512 "$IMG" --out audx.iconset/icon_512x512.png
sips -s format png -z 1024 1024 "$IMG" --out audx.iconset/icon_512x512@2x.png

iconutil -c icns audx.iconset
mv audx.icns AppIcon.icns
rm -rf audx.iconset
./build.sh
echo "AppIcon.icns created and app successfully built"
