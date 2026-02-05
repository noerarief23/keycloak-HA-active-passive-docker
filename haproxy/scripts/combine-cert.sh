#!/bin/bash
#
# Combine Existing Certificate and Key for HAProxy
# Use this script if you already have .crt and .key files
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CERT_DIR="$(dirname "$0")/../certs"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}HAProxy Certificate Combiner${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check arguments
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <certificate.crt> <private.key> [output-name]"
    echo ""
    echo "Examples:"
    echo "  $0 mycert.crt mykey.key"
    echo "  $0 /path/to/cert.crt /path/to/key.key keycloak"
    echo ""
    exit 1
fi

CERT_FILE="$1"
KEY_FILE="$2"
OUTPUT_NAME="${3:-keycloak}"

# Verify files exist
if [ ! -f "$CERT_FILE" ]; then
    echo -e "${RED}Error: Certificate file not found: $CERT_FILE${NC}"
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    echo -e "${RED}Error: Key file not found: $KEY_FILE${NC}"
    exit 1
fi

echo -e "${YELLOW}Input Files:${NC}"
echo "  Certificate: $CERT_FILE"
echo "  Private Key: $KEY_FILE"
echo "  Output Name: $OUTPUT_NAME"
echo ""

# Create certs directory if it doesn't exist
mkdir -p "$CERT_DIR"

# Verify certificate
echo -e "${GREEN}Step 1: Verifying certificate...${NC}"
if openssl x509 -in "$CERT_FILE" -noout -text &>/dev/null; then
    echo -e "${GREEN}✓ Certificate is valid${NC}"
    openssl x509 -in "$CERT_FILE" -noout -subject -dates
else
    echo -e "${RED}✗ Invalid certificate file${NC}"
    exit 1
fi

# Verify private key
echo ""
echo -e "${GREEN}Step 2: Verifying private key...${NC}"
if openssl rsa -in "$KEY_FILE" -check -noout &>/dev/null; then
    echo -e "${GREEN}✓ Private key is valid${NC}"
else
    echo -e "${RED}✗ Invalid private key file${NC}"
    exit 1
fi

# Verify certificate and key match
echo ""
echo -e "${GREEN}Step 3: Verifying certificate and key match...${NC}"
CERT_MODULUS=$(openssl x509 -noout -modulus -in "$CERT_FILE" | openssl md5)
KEY_MODULUS=$(openssl rsa -noout -modulus -in "$KEY_FILE" | openssl md5)

if [ "$CERT_MODULUS" = "$KEY_MODULUS" ]; then
    echo -e "${GREEN}✓ Certificate and key match${NC}"
else
    echo -e "${RED}✗ Certificate and key do NOT match${NC}"
    echo "The certificate and private key must be a matching pair."
    exit 1
fi

# Combine into PEM format
echo ""
echo -e "${GREEN}Step 4: Combining into PEM format...${NC}"
cat "$CERT_FILE" "$KEY_FILE" > "$CERT_DIR/$OUTPUT_NAME.pem"
echo -e "${GREEN}✓ Combined PEM created: $CERT_DIR/$OUTPUT_NAME.pem${NC}"

# Copy individual files
cp "$CERT_FILE" "$CERT_DIR/$OUTPUT_NAME.crt"
cp "$KEY_FILE" "$CERT_DIR/$OUTPUT_NAME.key"
echo -e "${GREEN}✓ Files copied to certs directory${NC}"

# Generate DH parameters if not exists
echo ""
echo -e "${GREEN}Step 5: Checking DH parameters...${NC}"
if [ ! -f "$CERT_DIR/dhparam.pem" ]; then
    echo -e "${YELLOW}Generating DH parameters (this may take a while)...${NC}"
    openssl dhparam -out "$CERT_DIR/dhparam.pem" 2048 2>/dev/null
    echo -e "${GREEN}✓ DH parameters generated${NC}"
else
    echo -e "${GREEN}✓ DH parameters already exist${NC}"
fi

# Set permissions
echo ""
echo -e "${GREEN}Step 6: Setting file permissions...${NC}"
chmod 600 "$CERT_DIR/$OUTPUT_NAME.key"
chmod 600 "$CERT_DIR/$OUTPUT_NAME.pem"
chmod 644 "$CERT_DIR/$OUTPUT_NAME.crt"
chmod 644 "$CERT_DIR/dhparam.pem"
echo -e "${GREEN}✓ Permissions set${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Certificate Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Files created:"
echo "  - $CERT_DIR/$OUTPUT_NAME.crt (certificate)"
echo "  - $CERT_DIR/$OUTPUT_NAME.key (private key)"
echo "  - $CERT_DIR/$OUTPUT_NAME.pem (combined - used by HAProxy)"
echo "  - $CERT_DIR/dhparam.pem (DH parameters)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Verify HAProxy configuration references the correct certificate:"
echo "   bind *:443 ssl crt /etc/haproxy/certs/$OUTPUT_NAME.pem"
echo ""
echo "2. Start or reload HAProxy:"
echo "   docker compose -f docker-compose-lb.yml up -d"
echo "   # or reload without downtime:"
echo "   docker exec haproxy-lb kill -HUP 1"
echo ""
