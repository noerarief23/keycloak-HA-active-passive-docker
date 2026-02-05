#!/bin/bash
#
# Generate Self-Signed SSL Certificate for HAProxy
# This script creates a self-signed certificate for testing purposes
# For production, use Let's Encrypt or a proper CA-signed certificate
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CERT_DIR="$(dirname "$0")/../certs"
CERT_NAME="keycloak"
DAYS_VALID=365
KEY_SIZE=2048

# Certificate details
COUNTRY="ID"
STATE="Jakarta"
CITY="Jakarta"
ORG="Keycloak HA"
OU="IT Department"
CN="${1:-keycloak.local}"  # Use first argument or default

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}HAProxy SSL Certificate Generator${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if openssl is installed
if ! command -v openssl &> /dev/null; then
    echo -e "${RED}Error: openssl is not installed${NC}"
    echo "Please install openssl first:"
    echo "  Ubuntu/Debian: sudo apt-get install openssl"
    echo "  CentOS/RHEL: sudo yum install openssl"
    echo "  macOS: brew install openssl"
    exit 1
fi

# Create certs directory if it doesn't exist
mkdir -p "$CERT_DIR"

echo -e "${YELLOW}Certificate Configuration:${NC}"
echo "  Common Name (CN): $CN"
echo "  Organization: $ORG"
echo "  Country: $COUNTRY"
echo "  Valid for: $DAYS_VALID days"
echo "  Key Size: $KEY_SIZE bits"
echo ""

# Check if certificate already exists
if [ -f "$CERT_DIR/$CERT_NAME.pem" ]; then
    echo -e "${YELLOW}Warning: Certificate already exists at $CERT_DIR/$CERT_NAME.pem${NC}"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo -e "${GREEN}Step 1: Generating RSA private key...${NC}"
openssl genrsa -out "$CERT_DIR/$CERT_NAME.key" $KEY_SIZE 2>/dev/null
echo "✓ Private key generated: $CERT_DIR/$CERT_NAME.key"

echo -e "${GREEN}Step 2: Generating self-signed certificate...${NC}"
openssl req -new -x509 -days $DAYS_VALID \
    -key "$CERT_DIR/$CERT_NAME.key" \
    -out "$CERT_DIR/$CERT_NAME.crt" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=$CN" \
    2>/dev/null
echo "✓ Certificate generated: $CERT_DIR/$CERT_NAME.crt"

echo -e "${GREEN}Step 3: Combining certificate and key into PEM format...${NC}"
cat "$CERT_DIR/$CERT_NAME.crt" "$CERT_DIR/$CERT_NAME.key" > "$CERT_DIR/$CERT_NAME.pem"
echo "✓ Combined PEM file created: $CERT_DIR/$CERT_NAME.pem"

echo -e "${GREEN}Step 4: Generating DH parameters (this may take a while)...${NC}"
if [ ! -f "$CERT_DIR/dhparam.pem" ]; then
    openssl dhparam -out "$CERT_DIR/dhparam.pem" 2048 2>/dev/null
    echo "✓ DH parameters generated: $CERT_DIR/dhparam.pem"
else
    echo "✓ DH parameters already exist: $CERT_DIR/dhparam.pem"
fi

echo -e "${GREEN}Step 5: Setting file permissions...${NC}"
chmod 600 "$CERT_DIR/$CERT_NAME.key"
chmod 600 "$CERT_DIR/$CERT_NAME.pem"
chmod 644 "$CERT_DIR/$CERT_NAME.crt"
chmod 644 "$CERT_DIR/dhparam.pem"
echo "✓ Permissions set (key files: 600, certificates: 644)"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Certificate Generation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Certificate Details:"
openssl x509 -in "$CERT_DIR/$CERT_NAME.crt" -noout -subject -dates
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo "1. This is a SELF-SIGNED certificate for TESTING only"
echo "2. Browsers will show security warnings"
echo "3. For production, use Let's Encrypt or a CA-signed certificate"
echo "4. Certificate files:"
echo "   - Private key: $CERT_DIR/$CERT_NAME.key"
echo "   - Certificate: $CERT_DIR/$CERT_NAME.crt"
echo "   - Combined PEM: $CERT_DIR/$CERT_NAME.pem (used by HAProxy)"
echo "   - DH params: $CERT_DIR/dhparam.pem"
echo ""
echo -e "${GREEN}You can now start HAProxy with:${NC}"
echo "  docker compose -f docker-compose-lb.yml up -d"
echo ""
