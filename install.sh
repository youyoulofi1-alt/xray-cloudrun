#!/usr/bin/env bash
set -e

echo "=========================================="
echo "  XRAY Cloud Run (VLESS / VMESS / TROJAN)"
echo "=========================================="

# ===== Generate UUID automatically =====
UUID="$(cat /proc/sys/kernel/random/uuid)"

# ===== Check gcloud =====
if ! command -v gcloud >/dev/null 2>&1; then
  echo "❌ gcloud not found"
  echo "➡️ Use Cloud Shell or Linux with gcloud installed"
  exit 1
fi

PROJECT="$(gcloud config get-value project 2>/dev/null)"
if [[ -z "$PROJECT" ]]; then
  echo "❌ No active GCP project"
  echo "Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"

# ===== User Inputs =====
read -rp "🔐 Choose Protocol (vless/vmess/trojan): " PROTO
PROTO="${PROTO,,}"

if [[ ! "$PROTO" =~ ^(vless|vmess|trojan)$ ]]; then
  echo "❌ Invalid protocol"
  exit 1
fi

read -rp "📡 WebSocket Path (default: /ws): " WS_PATH
WS_PATH="${WS_PATH:-/ws}"

read -rp "🌐 Custom Domain (empty = run.app): " CUSTOM_DOMAIN || true

read -rp "🪪 Service Name (default: xray-ws): " SERVICE
SERVICE="${SERVICE:-xray-ws}"

echo ""
echo "🌍 Choose Region:"
echo "1) us-central1"
echo "2) europe-west1"
echo "3) asia-southeast1"
read -rp "Select [1-3]: " R

case "$R" in
  2) REGION="europe-west1" ;;
  3) REGION="asia-southeast1" ;;
  *) REGION="us-central1" ;;
esac

# ===== Enable APIs =====
echo "⚙️ Enabling required APIs..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# ===== Deploy =====
echo "🚀 Deploying XRAY to Cloud Run..."

gcloud run deploy "$SERVICE" \
  --source . \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --port 8080 \
  --memory 1Gi \
  --cpu 1 \
  --timeout 3600 \
  --min-instances 1 \
  --set-env-vars \
PROTO="$PROTO",USER_ID="$UUID",WS_PATH="$WS_PATH" \
  --quiet

# ===== Host =====
if [[ -n "$CUSTOM_DOMAIN" ]]; then
  HOST="$CUSTOM_DOMAIN"
  echo "⚠️ Make sure domain is mapped in Cloud Run"
else
  HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
fi

# ===== Generate Config =====
case "$PROTO" in
  vless)
    URI="vless://${UUID}@vpn.googleapis.com:443?encryption=none&security=tls&type=ws&host=${HOST}&path=${WS_PATH}&sni=${HOST}#XRAY-VLESS"
    ;;
  vmess)
    VMESS_JSON=$(cat <<EOF
{"v":"2","ps":"XRAY-VMESS","add":"vpn.googleapis.com","port":"443","id":"$UUID","aid":"0","net":"ws","type":"none","host":"$HOST","path":"$WS_PATH","tls":"tls"}
EOF
)
    URI="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
    ;;
  trojan)
    URI="trojan://${UUID}@vpn.googleapis.com:443?security=tls&type=ws&host=${HOST}&path=${WS_PATH}&sni=${HOST}#XRAY-TROJAN"
    ;;
esac

echo ""
echo "=========================================="
echo "✅ DEPLOYMENT SUCCESS"
echo "=========================================="
echo "Protocol : $PROTO"
echo "UUID     : $UUID"
echo "Path     : $WS_PATH"
echo "Host     : $HOST"
echo ""
echo "🔗 CONFIG:"
echo "$URI"