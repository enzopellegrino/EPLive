#!/bin/bash
#
# EPLive - Script per Build, Firma e Notarizzazione macOS
# 
# Prerequisiti:
# 1. Apple Developer Account attivo
# 2. Certificato "Developer ID Application" nel Keychain
# 3. File .env con le credenziali nella root del progetto
#

set -e

# Configurazione
APP_NAME="EPLive"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/Export"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
ENV_FILE="$PROJECT_DIR/.env"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🚀 EPLive Build & Notarization Script${NC}"
echo "========================================"

# Carica .env se esiste
load_env() {
    if [ -f "$ENV_FILE" ]; then
        echo -e "${GREEN}✅ Caricamento .env${NC}"
        export $(grep -v '^#' "$ENV_FILE" | xargs)
    else
        echo -e "${YELLOW}⚠️  File .env non trovato in $PROJECT_DIR${NC}"
        echo "   Crea un file .env con:"
        echo "   APPLE_ID=tuo@email.com"
        echo "   APPLE_TEAM_ID=XXXXXXXXXX"
        echo "   APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx"
    fi
}

# Verifica variabili ambiente
check_env() {
    load_env
    
    if [ -z "$APPLE_ID" ]; then
        echo -e "${RED}❌ APPLE_ID non configurato${NC}"
        exit 1
    fi
    if [ -z "$APPLE_TEAM_ID" ]; then
        echo -e "${RED}❌ APPLE_TEAM_ID non configurato${NC}"
        exit 1
    fi
    if [ -z "$APPLE_APP_SPECIFIC_PASSWORD" ]; then
        echo -e "${RED}❌ APPLE_APP_SPECIFIC_PASSWORD non configurato${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Credenziali caricate per: $APPLE_ID${NC}"
}

# Pulizia build precedenti
clean() {
    echo -e "\n${YELLOW}🧹 Pulizia build precedenti...${NC}"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
}

# Build e Archive
archive() {
    echo -e "\n${YELLOW}📦 Creazione Archive...${NC}"
    
    xcodebuild archive \
        -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
        -scheme "$APP_NAME" \
        -destination "generic/platform=macOS" \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGN_IDENTITY="Developer ID Application" \
        DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
        CODE_SIGN_STYLE="Manual" \
        -quiet
    
    echo -e "${GREEN}✅ Archive creato${NC}"
}

# Export
export_app() {
    echo -e "\n${YELLOW}📤 Export applicazione...${NC}"
    
    # Crea ExportOptions.plist
    cat > "$BUILD_DIR/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$APPLE_TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF

    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
        -quiet
    
    echo -e "${GREEN}✅ App esportata${NC}"
}

# Notarizzazione
notarize() {
    echo -e "\n${YELLOW}🔐 Notarizzazione...${NC}"
    
    APP_PATH="$EXPORT_PATH/$APP_NAME.app"
    ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
    
    # Comprimi app per notarizzazione
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    
    # Invia per notarizzazione
    echo "Invio a Apple per notarizzazione..."
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait
    
    # Applica staple
    echo -e "\n${YELLOW}📎 Applicazione staple...${NC}"
    xcrun stapler staple "$APP_PATH"
    
    echo -e "${GREEN}✅ Notarizzazione completata${NC}"
    
    # Pulizia
    rm -f "$ZIP_PATH"
}

# Crea DMG
create_dmg() {
    echo -e "\n${YELLOW}💿 Creazione DMG...${NC}"
    
    APP_PATH="$EXPORT_PATH/$APP_NAME.app"
    
    # Rimuovi DMG esistente
    rm -f "$DMG_PATH"
    
    # Crea DMG semplice
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$APP_PATH" \
        -ov -format UDZO \
        "$DMG_PATH"
    
    # Notarizza anche il DMG
    echo "Notarizzazione DMG..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait
    
    xcrun stapler staple "$DMG_PATH"
    
    echo -e "${GREEN}✅ DMG creato: $DMG_PATH${NC}"
}

# Menu principale
case "${1:-all}" in
    "clean")
        clean
        ;;
    "archive")
        archive
        ;;
    "export")
        export_app
        ;;
    "notarize")
        check_env
        notarize
        ;;
    "dmg")
        check_env
        create_dmg
        ;;
    "all")
        check_env
        clean
        archive
        export_app
        notarize
        create_dmg
        echo -e "\n${GREEN}🎉 Build completo!${NC}"
        echo "DMG pronto: $DMG_PATH"
        ;;
    *)
        echo "Uso: $0 [clean|archive|export|notarize|dmg|all]"
        exit 1
        ;;
esac
