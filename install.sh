#!/usr/bin/env bash
set -e

echo "=========================================="
echo "  XRAY Cloud Run (VLESS / VMESS / TROJAN)"
echo "=========================================="

# -------- Protocol --------
read -rp "🔐 Choose Protocol (vless/vmess/trojan) [vless]: " PROTO
# Remove leading/trailing whitespace and convert to lowercase
PROTO="${PROTO## }"
PROTO="${PROTO%% }"
PROTO="${PROTO,,}"
PROTO="${PROTO:-vless}"

# Validate protocol
if [[ ! "$PROTO" =~ ^(vless|vmess|trojan)$ ]]; then
  echo "❌ Invalid protocol: '$PROTO'"
  exit 1
fi

# -------- WS Path --------
read -rp "📡 WebSocket Path (default: /ws): " WSPATH
WSPATH="${WSPATH:-/ws}"

# -------- Domain --------
read -rp "🌐 Custom Domain (empty = run.app): " DOMAIN

# -------- Service Name --------
read -rp "🪪 Service Name (default: xray-ws): " SERVICE
SERVICE="${SERVICE:-xray-ws}"

# -------- UUID --------
UUID=$(cat /proc/sys/kernel/random/uuid)

# -------- Region Select --------
echo ""
AVAILABLE_REGIONS=("us-central1" "us-east1" "us-west1" "us-south1" "europe-west1" "europe-west4" "asia-east1" "asia-northeast1" "asia-southeast1")

echo "🌍 Available regions:"
i=1
for r in "${AVAILABLE_REGIONS[@]}"; do
  echo "$i) $r"
  ((i++))
done

read -rp "Select region [1-${#AVAILABLE_REGIONS[@]}] (default: 1): " IDX
IDX="${IDX:-1}"

# Validate region selection
if [[ ! "$IDX" =~ ^[0-9]+$ ]] || [ "$IDX" -lt 1 ] || [ "$IDX" -gt ${#AVAILABLE_REGIONS[@]} ]; then
  echo "❌ Invalid region selection"
  exit 1
fi
REGION="${AVAILABLE_REGIONS[$((IDX-1))]}"
echo "✅ Selected region: $REGION"

# -------- APIs --------
echo "⚙️ Enabling required APIs..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# -------- Dockerfile --------
cat > Dockerfile <<EOF
FROM ghcr.io/xtls/xray-core:latest
COPY config.json /etc/xray/config.json
CMD ["xray", "run", "-config", "/etc/xray/config.json"]
EOF

# -------- Xray Config --------
cat > config.json <<EOF
{
  "inbounds": [{
    "port": 8080,
    "protocol": "$PROTO",
    "settings": {
      "clients": [{
        "id": "$UUID"
      }]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "$WSPATH"
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom"
  }]
}
EOF

# -------- Deploy --------
echo "🚀 Deploying XRAY to Cloud Run..."
gcloud run deploy "$SERVICE" \
  --source . \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --quiet

# -------- Get URL --------
URL=$(gcloud run services describe "$SERVICE" --region "$REGION" --format="value(status.url)")

HOST=${DOMAIN:-${URL#https://}}

# -------- Output --------
echo ""
echo "=========================================="
echo "✅ DEPLOYMENT SUCCESS"
echo "=========================================="
echo "Protocol : $PROTO"
echo "Address  : $HOST"
echo "Port     : 443"
echo "UUID     : $UUID"
echo "Path     : $WSPATH"
echo "TLS      : ON"
echo "=========================================="

if [ "$PROTO" = "vmess" ]; then
  VMESS_JSON=$(cat <<EOF
{
  "v": "2",
  "ps": "$SERVICE",
  "add": "$HOST",
  "port": "443",
  "id": "$UUID",
  "aid": "0",
  "net": "ws",
  "type": "none",
  "host": "$HOST",
  "path": "$WSPATH",
  "tls": "tls"
}
EOF
)

  VMESS_LINK="vmess://$(echo "$VMESS_JSON" | base64 -w 0)"
  echo ""
  echo "📎 VMESS LINK:"
  echo "$VMESS_LINK"
fi