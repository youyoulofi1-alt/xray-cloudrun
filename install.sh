#!/usr/bin/env bash
set -e

echo "=========================================="
echo "  XRAY Cloud Run (VLESS / VMESS / TROJAN)"
echo "=========================================="

# -------- Protocol --------
read -rp "🔐 Choose Protocol (vless/vmess/trojan) [vless]: " PROTO
PROTO="${PROTO,,}"
PROTO="${PROTO:-vless}"

if [[ ! "$PROTO" =~ ^(vless|vmess|trojan)$ ]]; then
  echo "❌ Invalid protocol"
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

# -------- Region Detect --------
echo ""
echo "🔍 Detecting available Cloud Run regions..."

ALL_REGIONS=$(gcloud run regions list --format="value(name)")
AVAILABLE_REGIONS=()

for r in $ALL_REGIONS; do
  if gcloud run services list --region "$r" --platform=managed &>/dev/null; then
    AVAILABLE_REGIONS+=("$r")
  fi
done

# Qwiklabs fallback
if [ ${#AVAILABLE_REGIONS[@]} -eq 0 ]; then
  echo "⚠️ Region auto-detection blocked (Qwiklabs detected)"
  AVAILABLE_REGIONS=("us-central1" "europe-west4")
fi

echo ""
echo "🌍 Available regions:"
i=1
for r in "${AVAILABLE_REGIONS[@]}"; do
  echo "$i) $r"
  ((i++))
done

read -rp "Select region [1-${#AVAILABLE_REGIONS[@]}]: " IDX
REGION="${AVAILABLE_REGIONS[$((IDX-1))]}"

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