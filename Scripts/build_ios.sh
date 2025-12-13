#!/bin/bash
#
# EPLive - Script per Build iOS e distribuzione TestFlight/App Store
#
# Prerequisiti:
# 1. Apple Developer Account attivo
# 2. Certificato "Apple Distribution" nel Keychain
# 3. Provisioning Profile configurato
#

set -e

APP_NAME="EPLive"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/${APP_NAME}_iOS.xcarchive"
EXPORT_PATH="$BUILD_DIR/Export_iOS"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 EPLive iOS Build Script${NC}"
echo "============================"

# Pulizia
clean() {
    echo -e "\n${YELLOW}🧹 Pulizia...${NC}"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
}

# Archive iOS
archive_ios() {
    echo -e "\n${YELLOW}📦 Creazione Archive iOS...${NC}"
    
    xcodebuild archive \
        -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
        -scheme "$APP_NAME" \
        -destination "generic/platform=iOS" \
        -archivePath "$ARCHIVE_PATH" \
        -quiet
    
    echo -e "${GREEN}✅ Archive iOS creato${NC}"
}

# Export per App Store / TestFlight
export_appstore() {
    echo -e "\n${YELLOW}📤 Export per App Store...${NC}"
    
    cat > "$BUILD_DIR/ExportOptions_iOS.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions_iOS.plist" \
        -quiet
    
    echo -e "${GREEN}✅ App esportata per App Store${NC}"
}

# Export per distribuzione Ad Hoc
export_adhoc() {
    echo -e "\n${YELLOW}📤 Export Ad Hoc...${NC}"
    
    cat > "$BUILD_DIR/ExportOptions_AdHoc.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>thinning</key>
    <string>&lt;none&gt;</string>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions_AdHoc.plist" \
        -quiet
    
    echo -e "${GREEN}✅ IPA Ad Hoc creato: $EXPORT_PATH/$APP_NAME.ipa${NC}"
}

# Upload a TestFlight
upload_testflight() {
    echo -e "\n${YELLOW}🚀 Upload a TestFlight...${NC}"
    
    IPA_PATH="$EXPORT_PATH/$APP_NAME.ipa"
    
    if [ ! -f "$IPA_PATH" ]; then
        echo -e "${RED}❌ IPA non trovato. Esegui prima 'export_appstore'${NC}"
        exit 1
    fi
    
    xcrun altool --upload-app \
        --type ios \
        --file "$IPA_PATH" \
        --apiKey "$APP_STORE_API_KEY" \
        --apiIssuer "$APP_STORE_API_ISSUER"
    
    echo -e "${GREEN}✅ Upload a TestFlight completato${NC}"
}

case "${1:-help}" in
    "clean")
        clean
        ;;
    "archive")
        archive_ios
        ;;
    "appstore")
        clean
        archive_ios
        export_appstore
        ;;
    "adhoc")
        clean
        archive_ios
        export_adhoc
        ;;
    "upload")
        upload_testflight
        ;;
    *)
        echo "Uso: $0 [clean|archive|appstore|adhoc|upload]"
        echo ""
        echo "Comandi:"
        echo "  clean     - Pulisce la cartella build"
        echo "  archive   - Crea archive iOS"
        echo "  appstore  - Build + Export per App Store/TestFlight"
        echo "  adhoc     - Build + Export IPA Ad Hoc"
        echo "  upload    - Upload a TestFlight"
        ;;
esac
