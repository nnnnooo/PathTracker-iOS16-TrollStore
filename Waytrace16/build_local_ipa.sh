#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
OUTPUT_IPA="$SCRIPT_DIR/Waytrace-iOS16-TrollStore.ipa"

echo "=========================================="
echo "🚀 开始本地编译 漫迹16 (Waytrace16) IPA..."
echo "=========================================="

# 1. 自动探测可用的 iPhoneOS SDK（优先使用当前 DEVELOPER_DIR / xcode-select）
SDK_PATH=""
if SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)" && [ -n "$SDK_PATH" ]; then
    :
else
    for CANDIDATE in /Applications/Xcode*.app "$HOME"/Applications/Xcode*.app /Volumes/*/Xcode*.app; do
        if [ -d "$CANDIDATE/Contents/Developer" ]; then
            export DEVELOPER_DIR="$CANDIDATE/Contents/Developer"
            if SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)" && [ -n "$SDK_PATH" ]; then
                echo "🔎 已自动定位 Xcode: $CANDIDATE"
                break
            fi
        fi
    done
fi

if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
    echo "❌ 未找到 iPhoneOS SDK！"
    echo ""
    echo "原因：当前环境仅检测到 macOS Command Line Tools（不含 iPhoneOS.sdk），"
    echo "      本地编译 iOS 应用必须依赖 Xcode 内置的 iPhoneOS.sdk。"
    echo ""
    echo "解决方法："
    echo "  1. 如果你的 Xcode 装在其他目录，请指定路径后重跑："
    echo "     DEVELOPER_DIR=/你的路径/Xcode.app/Contents/Developer bash \"$0\""
    echo "  2. 如果本机尚未安装 Xcode，请先从 App Store 或 Apple Developer 安装 Xcode，"
    echo "     然后执行：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

echo "📱 使用 iOS SDK: $SDK_PATH"

# 2. 自动补全 AppIcon.png（复用原版高清图标）
APPICON_DST="$SCRIPT_DIR/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
APPICON_SRC="$REPO_ROOT/RecordPath/Assets.xcassets/AppIcon.appiconset/AppIcon-light.png"
if [ ! -f "$APPICON_DST" ] && [ -f "$APPICON_SRC" ]; then
    cp "$APPICON_SRC" "$APPICON_DST"
    echo "🎨 已同步原版应用图标 AppIcon.png"
fi

# 3. 在 /tmp 准备干净的临时构建目录（避免 ~/Documents 附带 com.apple.provenance 导致 codesign 失败）
WORK_DIR="/tmp/Waytrace16_build_$(date +%s)"
APP_DIR="$WORK_DIR/Payload/Waytrace16.app"
mkdir -p "$APP_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

# 4. 收集全部 Swift 源文件并编译 Release 二进制
SWIFT_FILES=()
while IFS= read -r file; do
    SWIFT_FILES+=("$file")
done < <(find "$SCRIPT_DIR/Sources" -name "*.swift" | sort)

if [ "${#SWIFT_FILES[@]}" -eq 0 ]; then
    echo "❌ 未在 $SCRIPT_DIR/Sources 下找到任何 .swift 文件"
    exit 1
fi

echo "📦 正在编译 ${#SWIFT_FILES[@]} 个 Swift 源文件 (arm64-apple-ios16.0, Release)..."
xcrun swiftc \
    -O \
    -swift-version 5 \
    -target arm64-apple-ios16.0 \
    -sdk "$SDK_PATH" \
    -Xcc -isysroot -Xcc "$SDK_PATH" \
    -parse-as-library \
    -module-name Waytrace16 \
    -lsqlite3 \
    "${SWIFT_FILES[@]}" \
    -o "$APP_DIR/Waytrace16"

# 5. 生成替换完构建变量的 Info.plist 与 PkgInfo
echo "📝 正在写入 Info.plist..."
sed \
    -e 's/\$(EXECUTABLE_NAME)/Waytrace16/g' \
    -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.waytrace.ios16/g' \
    -e 's/\$(PRODUCT_NAME)/Waytrace16/g' \
    -e 's/\$(MARKETING_VERSION)/1.0.0/g' \
    -e 's/\$(CURRENT_PROJECT_VERSION)/1/g' \
    "$SCRIPT_DIR/Sources/Info.plist" > "$APP_DIR/Info.plist"

/usr/libexec/PlistBuddy -c "Delete :MinimumOSVersion" "$APP_DIR/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string 16.0" "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleSupportedPlatforms" "$APP_DIR/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms array" "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms:0 string iPhoneOS" "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :UIDeviceFamily" "$APP_DIR/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :UIDeviceFamily array" "$APP_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :UIDeviceFamily:0 integer 1" "$APP_DIR/Info.plist"

printf "APPL????" > "$APP_DIR/PkgInfo"

# 6. 编译 Assets.xcassets 并将生成的 CFBundleIcons 合并进 Info.plist
PARTIAL_PLIST="$WORK_DIR/assetcatalog_generated_info.plist"
if [ -d "$SCRIPT_DIR/Resources/Assets.xcassets" ] && xcrun --find actool >/dev/null 2>&1; then
    echo "🎨 正在编译 Assets.xcassets 与 AppIcon..."
    if xcrun actool "$SCRIPT_DIR/Resources/Assets.xcassets" \
        --compile "$APP_DIR" \
        --platform iphoneos \
        --minimum-deployment-target 16.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "$PARTIAL_PLIST" >/dev/null 2>&1; then
        if [ -f "$PARTIAL_PLIST" ]; then
            /usr/libexec/PlistBuddy -c "Merge $PARTIAL_PLIST" "$APP_DIR/Info.plist" 2>/dev/null || true
        fi
    fi
fi

# 兜底：若 actool 未生成图标声明，则手动生成 AppIcon60x60@2x/3x 并写入 CFBundleIcons
if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIcons" "$APP_DIR/Info.plist" >/dev/null 2>&1; then
    if [ -f "$APPICON_DST" ]; then
        echo "🎨 使用 sips 生成桌面图标兜底..."
        sips -z 120 120 "$APPICON_DST" --out "$APP_DIR/AppIcon60x60@2x.png" >/dev/null 2>&1 || true
        sips -z 180 180 "$APPICON_DST" --out "$APP_DIR/AppIcon60x60@3x.png" >/dev/null 2>&1 || true
        /usr/libexec/PlistBuddy -c "Add :CFBundleIcons dict" "$APP_DIR/Info.plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon dict" "$APP_DIR/Info.plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles array" "$APP_DIR/Info.plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconFiles:0 string AppIcon60x60" "$APP_DIR/Info.plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName string AppIcon" "$APP_DIR/Info.plist" 2>/dev/null || true
    fi
fi

# 7. 打包国家边界矢量轮廓 CountryBorders.json（用于护照深色世界地图点亮国家轮廓）
BORDERS_SRC="$REPO_ROOT/RecordPath/Resources/CountryBorders.json"
if [ -f "$BORDERS_SRC" ]; then
    cp -X "$BORDERS_SRC" "$APP_DIR/CountryBorders.json" 2>/dev/null || cp "$BORDERS_SRC" "$APP_DIR/CountryBorders.json"
    echo "🗺️ 已打包 CountryBorders.json 国家轮廓数据"
fi

# 7.5 打包中国省市县 GeoJSON 与历史 visited_areas.json（来自 MyTravelsChina）
CHINA_WEB_ASSETS="$REPO_ROOT/../MyTravelsChina/MyTravelsChina/WebAssets"
if [ -d "$CHINA_WEB_ASSETS/data" ]; then
    mkdir -p "$APP_DIR/ChinaGeoJSON"
    cp -X "$CHINA_WEB_ASSETS/data/"*.json "$APP_DIR/ChinaGeoJSON/" 2>/dev/null || cp "$CHINA_WEB_ASSETS/data/"*.json "$APP_DIR/ChinaGeoJSON/"
    if [ -f "$CHINA_WEB_ASSETS/visited_areas.json" ]; then
        cp -X "$CHINA_WEB_ASSETS/visited_areas.json" "$APP_DIR/ChinaGeoJSON/visited_areas.json" 2>/dev/null || cp "$CHINA_WEB_ASSETS/visited_areas.json" "$APP_DIR/ChinaGeoJSON/visited_areas.json"
    fi
    echo "🇨🇳 已打包中国省市县 GeoJSON 轮廓与预置历史记录 visited_areas.json"
fi

find "$APP_DIR" -name ".DS_Store" -delete 2>/dev/null || true

# 8. Ad-Hoc 伪签名（TrollStore 兼容）
echo "🔏 正在进行 Ad-Hoc 伪签名..."
codesign --force --deep --sign - "$APP_DIR"

# 9. 打包为 IPA
echo "📦 正在打包 IPA..."
rm -f "$OUTPUT_IPA"
(cd "$WORK_DIR" && zip -qr "$OUTPUT_IPA" Payload)

echo "=========================================="
echo "🎉 本地编译成功！"
echo "📍 IPA 路径: $OUTPUT_IPA"
echo "📦 文件大小: $(du -h "$OUTPUT_IPA" | cut -f1)"
echo "💡 可直接传到 iPhone 用 TrollStore 安装。"
echo "=========================================="
