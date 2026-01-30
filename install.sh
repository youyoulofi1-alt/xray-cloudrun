#!/usr/bin/env bash
set -euo pipefail

# ===== Interactive reads =====
# We will read from /dev/tty on each prompt (do not change the script's stdin).
# This avoids executing typed input as shell commands when running `curl | bash`.

# ===== Logging & error handler =====
LOG_FILE="/tmp/vless_deploy_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO: ${BASH_COMMAND}" | tee -a "$LOG_FILE" >&2
  echo "—— LOG (last 50 lines) ——" >&2
  tail -n 50 "$LOG_FILE" >&2 || true
  echo "📄 Log File: $LOG_FILE" >&2
  exit $rc
}
trap on_err ERR

# =================== Custom UI Colors ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'
  C_RED=$'\e[38;5;196m'
  C_BLUE=$'\e[38;5;39m'
  C_GREEN=$'\e[38;5;46m'
  C_YELLOW=$'\e[38;5;226m'
  C_PURPLE=$'\e[38;5;93m'
  C_GRAY=$'\e[38;5;214m'
  C_CYAN=$'\e[38;5;51m'
else
  RESET= BOLD= C_RED= C_BLUE= C_GREEN= C_YELLOW= C_PURPLE= C_GRAY= C_CYAN=
fi

# =================== Banner ===================
show_banner() {
  clear
  printf "\n\n"
  printf "${C_RED}${BOLD}"
  printf "╔══════════════════════════════════════════════════════════════════╗\n"
  printf "║                                                                  ║\n"
  printf "║        ${C_CYAN}VLESS WebSocket Cloud Run Deployment System${C_RED}           ║\n"
  printf "║        ${C_GREEN}⚡ Version 2.0 - Optimized & Secure${C_RED}                    ║\n"
  printf "║                                                                  ║\n"
  printf "╚══════════════════════════════════════════════════════════════════╝${RESET}\n"
  printf "\n\n"
}

# =================== UI Functions ===================
show_step() {
  local step_num="$1"
  local step_title="$2"
  printf "\n${C_PURPLE}${BOLD}┌─── STEP %s ──────────────────────────────────────────┐${RESET}\n" "$step_num"
  printf "${C_PURPLE}${BOLD}│${RESET} ${C_CYAN}%s${RESET}\n" "$step_title"
  printf "${C_PURPLE}${BOLD}└──────────────────────────────────────────────────────┘${RESET}\n"
}

show_success() {
  printf "${C_GREEN}${BOLD}✓${RESET} ${C_GREEN}%s${RESET}\n" "$1"
}

show_info() {
  printf "${C_BLUE}${BOLD}ℹ${RESET} ${C_BLUE}%s${RESET}\n" "$1"
}

show_warning() {
  printf "${C_YELLOW}${BOLD}⚠${RESET} ${C_YELLOW}%s${RESET}\n" "$1"
}

show_error() {
  printf "${C_RED}${BOLD}✗${RESET} ${C_RED}%s${RESET}\n" "$1"
}

show_divider() {
  printf "${C_GRAY}%s${RESET}\n" "──────────────────────────────────────────────────────────"
}

show_kv() {
  printf "   ${C_GRAY}%s${RESET}  ${C_CYAN}%s${RESET}\n" "$1" "$2"
}

# =================== Progress Spinner ===================
run_with_progress() {
  local label="$1"; shift
  ( "$@" ) >>"$LOG_FILE" 2>&1 &
  local pid=$!
  local pct=5
  
  if [[ -t 1 ]]; then
    printf "\e[?25l"
    while kill -0 "$pid" 2>/dev/null; do
      local step=$(( (RANDOM % 9) + 2 ))
      pct=$(( pct + step ))
      (( pct > 95 )) && pct=95
      printf "\r${C_PURPLE}⟳${RESET} ${C_CYAN}%s...${RESET} [${C_YELLOW}%s%%${RESET}]" "$label" "$pct"
      sleep "$(awk -v r=$RANDOM 'BEGIN{s=0.08+(r%7)/100; printf "%.2f", s }')"
    done
    wait "$pid"; local rc=$?
    printf "\r"
    if (( rc==0 )); then
      printf "${C_GREEN}✓${RESET} ${C_GREEN}%s...${RESET} [${C_GREEN}100%%${RESET}]\n" "$label"
    else
      printf "${C_RED}✗${RESET} ${C_RED}%s failed (see %s)${RESET}\n" "$label" "$LOG_FILE"
      return $rc
    fi
    printf "\e[?25h"
  else
    wait "$pid"
  fi
}

# Detect interactive mode (use /dev/tty for prompts when available)
INTERACTIVE=false
if [[ -c /dev/tty && -r /dev/tty ]]; then
  INTERACTIVE=true
fi

# Show banner
show_banner

# =================== Step 1: Project ===================
show_step "01" "GCP Project Configuration"

PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  show_error "No active GCP project found."
  show_info "Please run: ${C_CYAN}gcloud config set project <YOUR_PROJECT_ID>${RESET}"
  exit 1
fi

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)' 2>/dev/null || true)"
show_success "Project loaded successfully"
show_kv "Project ID:" "$PROJECT"
show_kv "Project Number:" "$PROJECT_NUMBER"

# =================== Step 2: Region ===================
show_step "02" "Region Selection"

printf "\n${C_YELLOW}┌──────────────────────────────────────────────────────┐${RESET}\n"
printf "${C_YELLOW}│${RESET} ${C_CYAN}🌍 Select Deployment Region${RESET}                            ${C_YELLOW}│${RESET}\n"
printf "${C_YELLOW}└──────────────────────────────────────────────────────┘${RESET}\n\n"

echo "  1) ${C_BLUE}🇺🇸 United States${RESET} (us-central1) - ${C_GREEN}Recommended${RESET}"
echo "  2) ${C_BLUE}🇸🇬 Singapore${RESET} (asia-southeast1)"
echo "  3) ${C_BLUE}🇮🇩 Indonesia${RESET} (asia-southeast2)"
echo "  4) ${C_BLUE}🇯🇵 Japan${RESET} (asia-northeast1)"
echo "  5) ${C_BLUE}🇪🇺 Belgium${RESET} (europe-west1)"
echo "  6) ${C_BLUE}🇮🇳 India${RESET} (asia-south1)"
printf "\n"

if [[ "${INTERACTIVE:-false}" == "true" ]]; then
  read -rp "${C_GREEN}Choose region [1-6, default 1]:${RESET} " _r < /dev/tty || true
else
  _r=""
fi

# If REGION was provided in the environment and we're non-interactive, prefer it
REGION="${REGION:-}"
if [[ -z "${_r:-}" && -n "${REGION}" ]]; then
  # keep REGION as provided
  :
else
  case "${_r:-1}" in
    2) REGION="asia-southeast1" ;;
    3) REGION="asia-southeast2" ;;
    4) REGION="asia-northeast1" ;;
    5) REGION="europe-west1" ;;
    6) REGION="asia-south1" ;;
    *) REGION="us-central1" ;;
  esac
fi

show_success "Selected Region: ${C_CYAN}$REGION${RESET}"

# =================== Step 3: Resources ===================
show_step "03" "Resource Configuration"

printf "\n${C_YELLOW}┌──────────────────────────────────────────────────────┐${RESET}\n"
printf "${C_YELLOW}│${RESET} ${C_CYAN}⚙️ Compute Resources${RESET}                                  ${C_YELLOW}│${RESET}\n"
printf "${C_YELLOW}└──────────────────────────────────────────────────────┘${RESET}\n\n"

if [[ "${INTERACTIVE:-false}" == "true" ]]; then
  read -rp "${C_GREEN}CPU Cores [1/2/4/6, default 2]:${RESET} " _cpu < /dev/tty || true
else
  _cpu=""
fi
CPU="${_cpu:-2}"

printf "\n${C_GRAY}Available Memory Options:${RESET}\n"
echo "  ${C_GRAY}•${RESET} 512Mi  ${C_GRAY}•${RESET} 1Gi    ${C_GRAY}•${RESET} 2Gi (Recommended)"
echo "  ${C_GRAY}•${RESET} 4Gi    ${C_GRAY}•${RESET} 8Gi    ${C_GRAY}•${RESET} 16Gi"
printf "\n"

if [[ "${INTERACTIVE:-false}" == "true" ]]; then
  read -rp "${C_GREEN}Memory [default 2Gi]:${RESET} " _mem < /dev/tty || true
else
  _mem=""
fi
MEMORY="${_mem:-2Gi}"

show_success "Resource Configuration"
show_kv "CPU Cores:" "$CPU"
show_kv "Memory:" "$MEMORY"

# =================== Step 4: Service Name ===================
show_step "04" "Service Configuration"

printf "\n${C_YELLOW}┌──────────────────────────────────────────────────────┐${RESET}\n"
printf "${C_YELLOW}│${RESET} ${C_CYAN}🪪 Service Details${RESET}                                    ${C_YELLOW}│${RESET}\n"
printf "${C_YELLOW}└──────────────────────────────────────────────────────┘${RESET}\n\n"

SERVICE="${SERVICE:-vless-ws}"
TIMEOUT="${TIMEOUT:-3600}"
PORT="${PORT:-8080}"

if [[ "${INTERACTIVE:-false}" == "true" ]]; then
  read -rp "${C_GREEN}Service Name [default: ${SERVICE}]:${RESET} " _svc < /dev/tty || true
else
  _svc=""
fi
SERVICE="${_svc:-$SERVICE}"

show_success "Service Configuration"
show_kv "Service Name:" "$SERVICE"
show_kv "Port:" "$PORT"
show_kv "Timeout:" "${TIMEOUT}s"

# =================== Step 5: Deployment Info ===================
show_step "05" "Deployment Summary"

export TZ="UTC"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
fmt_dt(){ date -d @"$1" "+%Y-%m-%d %H:%M:%S UTC"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"

printf "\n${C_YELLOW}┌──────────────────────────────────────────────────────┐${RESET}\n"
printf "${C_YELLOW}│${RESET} ${C_CYAN}🕒 Deployment Information${RESET}                             ${C_YELLOW}│${RESET}\n"
printf "${C_YELLOW}└──────────────────────────────────────────────────────┘${RESET}\n\n"

show_kv "Start Time:" "$START_LOCAL"
show_kv "Est. Completion:" "$END_LOCAL"
show_kv "Protocol:" "VLESS WebSocket"
show_info "Deployment will complete within 5 minutes"

# =================== Step 6: Enable APIs ===================
show_step "06" "GCP API Enablement"

printf "\n${C_YELLOW}┌──────────────────────────────────────────────────────┐${RESET}\n"
printf "${C_YELLOW}│${RESET} ${C_CYAN}🔧 Enabling Required APIs${RESET}                             ${C_YELLOW}│${RESET}\n"
printf "${C_YELLOW}└──────────────────────────────────────────────────────┘${RESET}\n\n"

run_with_progress "Enabling Cloud Run & Cloud Build APIs" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

show_success "All required APIs enabled"

# =================== Step 7: Deploy ===================
show_step "07" "Cloud Run Deployment"

printf "\n${C_YELLOW}┌──────────────────────────────────────────────────────┐${RESET}\n"
printf "${C_YELLOW}│${RESET} ${C_CYAN}🚀 Deploying VLESS WS Service${RESET}                         ${C_YELLOW}│${RESET}\n"
printf "${C_YELLOW}└──────────────────────────────────────────────────────┘${RESET}\n\n"

show_info "Deployment Configuration Summary:"
show_kv "Protocol:" "VLESS WebSocket"
show_kv "Region:" "$REGION"
show_kv "Service:" "$SERVICE"
show_kv "Resources:" "${CPU} vCPU / ${MEMORY}"
printf "\n"

run_with_progress "Deploying ${SERVICE} to Cloud Run" \
  gcloud run deploy "$SERVICE" \
    --image="docker.io/nkka404/vless-ws:latest" \
    --platform=managed \
    --region="$REGION" \
    --memory="$MEMORY" \
    --cpu="$CPU" \
    --concurrency=1000 \
    --timeout="$TIMEOUT" \
    --allow-unauthenticated \
    --port="$PORT" \
    --min-instances=1 \
    --quiet

# Poll for service readiness (ensure deployment completed end-to-end)
show_info "Waiting for Cloud Run service to report Ready status..."
READY_TIMEOUT=${READY_TIMEOUT:-900} # seconds (15 minutes)
READY_INTERVAL=5
elapsed=0
while true; do
  READY_STATE=$(gcloud run services describe "$SERVICE" --region="$REGION" --platform=managed --format='value(status.conditions[?(@.type=="Ready")].state)' 2>>"$LOG_FILE" || true)
  if [[ "$READY_STATE" == "True" ]]; then
    show_success "Cloud Run service is Ready"
    break
  fi
  if (( elapsed >= READY_TIMEOUT )); then
    show_error "Timed out waiting for Cloud Run service readiness (after ${READY_TIMEOUT}s). Check logs: $LOG_FILE"
    exit 1
  fi
  if [[ -t 1 ]]; then
    pct=$(( elapsed * 100 / READY_TIMEOUT ))
    printf "\r${C_PURPLE}⟳${RESET} ${C_CYAN}Waiting for service readiness...${RESET} [${C_YELLOW}%s%%%s${RESET}]" "$pct" ""
  fi
  sleep $READY_INTERVAL
  elapsed=$(( elapsed + READY_INTERVAL ))
done
printf "\n"

# =================== Step 8: Result ===================
show_step "08" "Deployment Result"

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)' 2>/dev/null || true)"
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"

printf "\n${C_YELLOW}┌──────────────────────────────────────────────────────┐${RESET}\n"
printf "${C_YELLOW}│${RESET} ${C_CYAN}✅ Deployment Successful${RESET}                               ${C_YELLOW}│${RESET}\n"
printf "${C_YELLOW}└──────────────────────────────────────────────────────┘${RESET}\n\n"

show_success "VLESS WS Service is now running!"
show_divider

printf "\n${C_GREEN}${BOLD}📡 SERVICE ENDPOINT:${RESET}\n"
printf "   ${C_CYAN}${BOLD}%s${RESET}\n\n" "${URL_CANONICAL}"

# =================== VLESS Configuration ===================
VLESS_UUID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo 'ba0e3984-ccc9-48a3-8074-b2f507f41ce8')"
URI="vless://${VLESS_UUID}@vpn.googleapis.com:443?path=%2F%40vless&security=tls&encryption=none&host=${CANONICAL_HOST}&type=ws&sni=${CANONICAL_HOST}#VLESS-WS"

printf "${C_GREEN}${BOLD}🔑 VLESS CONFIGURATION:${RESET}\n"
printf "   ${C_CYAN}%s${RESET}\n\n" "${URI}"

printf "${C_GREEN}${BOLD}📋 CONFIGURATION DETAILS:${RESET}\n"
show_kv "UUID:" "$VLESS_UUID"
show_kv "Address:" "vpn.googleapis.com"
show_kv "Port:" "443"
show_kv "Path:" "/@vless"
show_kv "Security:" "TLS"
show_kv "Encryption:" "None"
show_kv "Transport:" "WebSocket"
show_kv "SNI:" "${CANONICAL_HOST}"
show_divider

# =================== Final Output ===================
printf "\n${C_YELLOW}┌──────────────────────────────────────────────────────┐${RESET}\n"
printf "${C_YELLOW}│${RESET} ${C_CYAN}✨ DEPLOYMENT COMPLETE${RESET}                                ${C_YELLOW}│${RESET}\n"
printf "${C_YELLOW}└──────────────────────────────────────────────────────┘${RESET}\n\n"

show_success "VLESS WS service deployed successfully!"
show_info "Service URL: ${C_CYAN}${URL_CANONICAL}${RESET}"
show_kv "Log File:" "$LOG_FILE"
show_kv "Service Name:" "$SERVICE"
show_kv "Region:" "$REGION"

printf "\n${C_PURPLE}${BOLD}💡 IMPORTANT NOTES:${RESET}\n"
echo "  ${C_GRAY}•${RESET} Service configured with ${C_GREEN}warm instances${RESET} (min-instances=1)"
echo "  ${C_GRAY}•${RESET} ${C_GREEN}No cold start${RESET} delays for initial connections"
echo "  ${C_GRAY}•${RESET} Configured for ${C_GREEN}high concurrency${RESET} (1000 concurrent requests)"
echo "  ${C_GRAY}•${RESET} {{C_GREEN}Publicly accessible${RESET} via the endpoint"
echo "  ${C_GRAY}•${RESET} Auto-scales based on traffic demand"
printf "\n"

show_divider
printf "\n${C_CYAN}${BOLD}VLESS WebSocket Deployment System${RESET} ${C_GRAY}|${RESET} ${C_GREEN}v2.0${RESET}\n"
printf "${C_GRAY}──────────────────────────────────────────────────────────${RESET}\n\n"