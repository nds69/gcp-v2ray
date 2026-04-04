#!/usr/bin/env bash
set -euo pipefail

# ===== Ensure interactive reads even when run via curl/process substitution =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging & error handler =====
LOG_FILE="/tmp/fnet_vless_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO: ${BASH_COMMAND}" | tee -a "$LOG_FILE" >&2
  echo "—— LOG (last 80 lines) ——" >&2
  tail -n 80 "$LOG_FILE" >&2 || true
  echo "📄 Log File: $LOG_FILE" >&2
  
  if [[ "${BASH_COMMAND}" == *"gcloud run deploy"* ]]; then
    echo "🔍 Cloud Run Deployment Failed! Possible reasons:" >&2
    echo "   • Cloud Run API or Cloud Build API not enabled" >&2
    echo "   • Insufficient permissions" >&2
    echo "   • Region not supported" >&2
    echo "   • Quota exceeded" >&2
  fi
  
  exit $rc
}
trap on_err ERR

# =================== FNET VPN Custom UI ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'
  C_FNET_RED=$'\e[38;5;196m'      
  C_FNET_BLUE=$'\e[38;5;39m'      
  C_FNET_GREEN=$'\e[38;5;46m'     
  C_FNET_YELLOW=$'\e[38;5;226m'   
  C_FNET_PURPLE=$'\e[38;5;93m'    
  C_FNET_GRAY=$'\e[38;5;245m'     
  C_FNET_CYAN=$'\e[38;5;51m'      
else
  RESET= BOLD= C_FNET_RED= C_FNET_BLUE= C_FNET_GREEN= C_FNET_YELLOW= C_FNET_PURPLE= C_FNET_GRAY= C_FNET_CYAN=
fi

# =================== FNET VPN Banner ===================
show_fnet_banner() {
  clear
  printf "\n\n"
  printf "${C_FNET_CYAN}${BOLD}"
  printf "╔══════════════════════════════════════════════════════════════════╗\n"
  printf "║                                                                  ║\n"
  printf "║   ███████╗███╗   ██╗███████╗████████╗    ██╗   ██╗██████╗ ███╗   ██╗ ║\n"
  printf "║   ██╔════╝████╗  ██║██╔════╝╚══██╔══╝    ██║   ██║██╔══██╗████╗  ██║ ║\n"
  printf "║   █████╗  ██╔██╗ ██║█████╗     ██║       ██║   ██║██████╔╝██╔██╗ ██║ ║\n"
  printf "║   ██╔══╝  ██║╚██╗██║██╔══╝     ██║       ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║ ║\n"
  printf "║   ██║     ██║ ╚████║███████╗   ██║        ╚████╔╝ ██║     ██║ ╚████║ ║\n"
  printf "║   ╚═╝     ╚═╝  ╚═══╝╚══════╝   ╚═╝         ╚═══╝  ╚═╝     ╚═╝  ╚═══╝ ║\n"
  printf "║                                                                  ║\n"
  printf "║         ${C_FNET_YELLOW}🚀 FNET VPN DEPLOYMENT SYSTEM => VERSION - 2.0         ${C_FNET_CYAN}║\n"
  printf "║         ${C_FNET_GREEN}⚡ Powered by FNET Developer                           ${C_FNET_CYAN}║\n"
  printf "║                                                                  ║\n"
  printf "╚══════════════════════════════════════════════════════════════════╝${RESET}\n"
  printf "\n\n"
}

# =================== Custom UI Functions ===================
show_step() {
  local step_num="$1"
  local step_title="$2"
  printf "\n${C_FNET_PURPLE}${BOLD}┌─── STEP %s ──────────────────────────────────────────┐${RESET}\n" "$step_num"
  printf "${C_FNET_PURPLE}${BOLD}│${RESET} ${C_FNET_CYAN}%s${RESET}\n" "$step_title"
  printf "${C_FNET_PURPLE}${BOLD}└──────────────────────────────────────────────────────┘${RESET}\n"
}

show_success() { printf "${C_FNET_GREEN}${BOLD}✓${RESET} ${C_FNET_GREEN}%s${RESET}\n" "$1"; }
show_info() { printf "${C_FNET_BLUE}${BOLD}ℹ${RESET} ${C_FNET_BLUE}%s${RESET}\n" "$1"; }
show_warning() { printf "${C_FNET_YELLOW}${BOLD}⚠${RESET} ${C_FNET_YELLOW}%s${RESET}\n" "$1"; }
show_error() { printf "${C_FNET_RED}${BOLD}✗${RESET} ${C_FNET_RED}%s${RESET}\n" "$1"; }
show_divider() { printf "${C_FNET_GRAY}%s${RESET}\n" "──────────────────────────────────────────────────────────"; }
show_kv() { printf "   ${C_FNET_GRAY}%s${RESET}  ${C_FNET_CYAN}%s${RESET}\n" "$1" "$2"; }

# =================== Progress Spinner ===================
run_with_progress() {
  local label="$1"; shift
  local temp_file=$(mktemp)
  
  if [[ -t 1 ]]; then
    printf "\e[?25l"
    ("$@" 2>&1 | tee "$temp_file") >>"$LOG_FILE" 2>&1 &
    local pid=$!
    local pct=5
    
    while kill -0 "$pid" 2>/dev/null; do
      local step=$(( (RANDOM % 9) + 2 ))
      pct=$(( pct + step ))
      (( pct > 95 )) && pct=95
      printf "\r${C_FNET_PURPLE}⟳${RESET} ${C_FNET_CYAN}%s...${RESET} [${C_FNET_YELLOW}%s%%${RESET}]" "$label" "$pct"
      
      if grep -i "error\|failed\|denied" "$temp_file" 2>/dev/null | grep -v "grep" | head -1; then break; fi
      sleep "$(awk -v r=$RANDOM 'BEGIN{s=0.08+(r%7)/100; printf "%.2f", s }')"
    done
    
    wait "$pid" 2>/dev/null || true
    local rc=$?
    printf "\r\e[K"
    
    if grep -qi "error\|failed\|denied\|permission" "$temp_file"; then
      printf "${C_FNET_RED}✗${RESET} ${C_FNET_RED}%s failed${RESET}\n" "$label"
      cat "$temp_file" | grep -i "error\|failed\|denied\|permission" | head -3 | while read line; do echo "   ${C_FNET_RED}→${RESET} $line"; done
      rm -f "$temp_file"; printf "\e[?25h"; return 1
    elif (( rc==0 )); then
      printf "${C_FNET_GREEN}✓${RESET} ${C_FNET_GREEN}%s...${RESET} [${C_FNET_GREEN}100%%${RESET}]\n" "$label"
    else
      printf "${C_FNET_RED}✗${RESET} ${C_FNET_RED}%s failed (exit $rc)${RESET}\n" "$label"
      tail -5 "$temp_file" | while read line; do echo "   ${C_FNET_RED}→${RESET} $line"; done
      rm -f "$temp_file"; printf "\e[?25h"; return $rc
    fi
    rm -f "$temp_file"; printf "\e[?25h"
  else
    "$@" >>"$LOG_FILE" 2>&1
  fi
}

show_fnet_banner

# =================== Step 1: Telegram Config ===================
show_step "01" "Telegram Configuration Setup"

TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-${TELEGRAM_CHAT_ID:-}}"

printf "\n${C_FNET_YELLOW}┌──────────────────────────────────────────────────────┐${RESET}\n"
printf "${C_FNET_YELLOW}│${RESET} ${C_FNET_CYAN}🔑 Telegram Bot Configuration${RESET}                      ${C_FNET_YELLOW}│${RESET}\n"
printf "${C_FNET_YELLOW}└──────────────────────────────────────────────────────┘${RESET}\n\n"

read -rp "${C_FNET_GREEN}🤖 Enter Telegram Bot Token (optional):${RESET} " _tk || true
[[ -n "${_tk:-}" ]] && TELEGRAM_TOKEN="$_tk"
if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then
  show_warning "Telegram token is empty. Deployment will continue without notifications."
else
  show_success "Telegram token configured"
fi

read -rp "${C_FNET_GREEN}👤 Enter Owner/Channel Chat ID(s) (optional):${RESET} " _ids || true
[[ -n "${_ids:-}" ]] && TELEGRAM_CHAT_IDS="${_ids// /}"

DEFAULT_LABEL="Join FNET VPN"
DEFAULT_URL="https://t.me/fnetvpn"
BTN_LABELS=(); BTN_URLS=()

printf "\n${C_FNET_YELLOW}┌──────────────────────────────────────────────────────┐${RESET}\n"
printf "${C_FNET_YELLOW}│${RESET} ${C_FNET_CYAN}🔘 Inline Button Configuration (Optional)${RESET}            ${C_FNET_YELLOW}│${RESET}\n"
printf "${C_FNET_YELLOW}└──────────────────────────────────────────────────────┘${RESET}\n\n"

read -rp "${C_FNET_GREEN}➕ Add URL button(s)? [y/N]:${RESET} " _addbtn || true
if [[ "${_addbtn:-}" =~ ^([yY]|yes)$ ]]; then
  i=0
  while true; do
    printf "\n${C_FNET_GRAY}── Button $((i+1)) ──${RESET}\n"
    read -rp "${C_FNET_GREEN}🔖 Label [default: ${DEFAULT_LABEL}]:${RESET} " _lbl || true
    if [[ -z "${_lbl:-}" ]]; then
      BTN_LABELS+=("${DEFAULT_LABEL}")
      BTN_URLS+=("${DEFAULT_URL}")
      show_success "Added: ${DEFAULT_LABEL} → ${DEFAULT_URL}"
    else
      read -rp "${C_FNET_GREEN}🔗 URL (http/https):${RESET} " _url || true
      if [[ -n "${_url:-}" && "${_url}" =~ ^https?:// ]]; then
        BTN_LABELS+=("${_lbl}")
        BTN_URLS+=("${_url}")
        show_success "Added: ${_lbl} → ${_url}"
      else
        show_warning "Skipped (invalid or empty URL)"
      fi
    fi
    i=$(( i + 1 ))
    (( i >= 3 )) && break
    read -rp "${C_FNET_GREEN}➕ Add another button? [y/N]:${RESET} " _more || true
    [[ "${_more:-}" =~ ^([yY]|yes)$ ]] || break
  done
fi

CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS:-}" || true
json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

tg_send(){
  local text="$1" RM=""
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then return 0; fi
  if (( ${#BTN_LABELS[@]} > 0 )); then
    local L1 U1 L2 U2 L3 U3
    [[ -n "${BTN_LABELS[0]:-}" ]] && L1="$(json_escape "${BTN_LABELS[0]}")" && U1="$(json_escape "${BTN_URLS[0]}")"
    [[ -n "${BTN_LABELS[1]:-}" ]] && L2="$(json_escape "${BTN_LABELS[1]}")" && U2="$(json_escape "${BTN_URLS[1]}")"
    [[ -n "${BTN_LABELS[2]:-}" ]] && L3="$(json_escape "${BTN_LABELS[2]}")" && U3="$(json_escape "${BTN_URLS[2]}")"
    if (( ${#BTN_LABELS[@]} == 1 )); then RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}]]}"
    elif (( ${#BTN_LABELS[@]} == 2 )); then RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}],[{\"text\":\"${L2}\",\"url\":\"${U2}\"}]]}"
    else RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}],[{\"text\":\"${L2}\",\"url\":\"${U2}\"},{\"text\":\"${L3}\",\"url\":\"${U3}\"}]]}"
    fi
  fi
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" --data-urlencode "text=${text}" -d "parse_mode=HTML" \
      ${RM:+--data-urlencode "reply_markup=${RM}"} >>"$LOG_FILE" 2>&1 || true
    show_success "Telegram notification sent → ${_cid}"
  done
}

# =================== Step 2: Project ===================
show_step "02" "GCP Project Configuration"

PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  show_error "No active GCP project found."
  show_info "Please run: ${C_FNET_CYAN}gcloud config set project <YOUR_PROJECT_ID>${RESET}"
  exit 1
fi
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
show_success "Project loaded successfully"
show_kv "Project ID:" "$PROJECT"

# =================== Step 3: Protocol ===================
show_step "03" "Protocol Selection"
show_success "Protocol: ${C_FNET_CYAN}VLESS WebSocket (FNET Custom Server)${RESET}"

# =================== Step 4: Region ===================
show_step "04" "Region Selection"
echo "  1) ${C_FNET_BLUE}🇺🇸 United States${RESET} (us-central1) - ${C_FNET_GREEN}Recommended${RESET}"
echo "  2) ${C_FNET_BLUE}🇸🇬 Singapore${RESET} (asia-southeast1)"
echo "  3) ${C_FNET_BLUE}🇯🇵 Japan${RESET} (asia-northeast1)"
printf "\n"
read -rp "${C_FNET_GREEN}Choose region [1-3, default 1]:${RESET} " _r || true
case "${_r:-1}" in
  2) REGION="asia-southeast1" ;;
  3) REGION="asia-northeast1" ;;
  *) REGION="us-central1" ;;
esac
show_success "Selected Region: ${C_FNET_CYAN}$REGION${RESET}"

# =================== Step 5 & 6: Resources & Service Name ===================
show_step "05" "Service Configuration"
CPU="1"
MEMORY="512Mi"
SERVICE="${SERVICE:-fnet-vless}"
TIMEOUT="${TIMEOUT:-3600}"
PORT="${PORT:-8080}"

read -rp "${C_FNET_GREEN}Service Name [default: ${SERVICE}]:${RESET} " _svc || true
SERVICE="${_svc:-$SERVICE}"

show_kv "Service Name:" "$SERVICE"
show_kv "Resources:" "${CPU} vCPU / ${MEMORY}"

# =================== Step 7: Enable APIs ===================
show_step "06" "GCP API Enablement"
APIS_TO_ENABLE=("run.googleapis.com" "cloudbuild.googleapis.com")
for api in "${APIS_TO_ENABLE[@]}"; do
  if ! gcloud services list --enabled --filter="config.name:$api" --format="value(config.name)" | grep -q "$api"; then
    run_with_progress "Enabling $api" gcloud services enable "$api" --quiet
  fi
done
show_success "Required APIs enabled"

# =================== Step 8: Prepare Custom Files ===================
show_step "07" "Building Custom FNET VPN Server"

BUILD_DIR=$(mktemp -d)
cd "$BUILD_DIR"

VLESS_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
show_info "Generated New UUID: ${C_FNET_YELLOW}${VLESS_UUID}${RESET}"

show_info "Generating Custom config.json with /@fnetvpn Path..."
cat << EOF > config.json
{
  "log": { "loglevel": "warning", "access": "/dev/stdout", "error": "/dev/stderr" },
  "inbounds": [
    {
      "port": 8080,
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${VLESS_UUID}", "flow": "" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/@fnetvpn", "headers": { "Host": "" } },
        "security": "none"
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": {}, "tag": "direct" },
    { "protocol": "blackhole", "settings": {}, "tag": "blocked" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field", "outboundTag": "direct",
        "domain": ["geosite:google", "geosite:facebook", "geosite:youtube", "geosite:cloudflare"]
      },
      { "type": "field", "outboundTag": "direct", "ip": ["geoip:private", "8.8.8.8/32", "1.1.1.1/32"] },
      { "type": "field", "outboundTag": "blocked", "domain": ["geosite:category-ads-all"] },
      { "type": "field", "outboundTag": "direct", "network": "udp,tcp" }
    ]
  }
}
EOF

cat << 'EOF' > Dockerfile
FROM teddysun/xray:latest
COPY config.json /etc/xray/config.json
EXPOSE 8080
EOF
show_success "Custom Server Files generated in temporary build path."

# =================== Step 9: Deploy ===================
show_step "08" "Cloud Run Source Deployment"
show_info "Uploading and building FNET custom server..."

DEPLOY_CMD=(
  gcloud run deploy "$SERVICE"
  --source="."
  --platform=managed
  --region="$REGION"
  --memory="$MEMORY"
  --cpu="$CPU"
  --concurrency=1000
  --timeout="$TIMEOUT"
  --allow-unauthenticated
  --port="$PORT"
  --min-instances=1
  --quiet
)

if ! run_with_progress "Deploying ${SERVICE} to Cloud Run" "${DEPLOY_CMD[@]}"; then
  show_error "Deployment failed! Please check logs."
  exit 1
fi

# Cleanup
rm -rf "$BUILD_DIR"

# =================== Step 10: Get Service URL ===================
SERVICE_URL=$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)' 2>/dev/null || true)

printf "\n${C_FNET_YELLOW}┌──────────────────────────────────────────────────────┐${RESET}\n"
printf "${C_FNET_YELLOW}│${RESET} ${C_FNET_CYAN}✅ Deployment Successful${RESET}                               ${C_FNET_YELLOW}│${RESET}\n"
printf "${C_FNET_YELLOW}└──────────────────────────────────────────────────────┘${RESET}\n\n"

# =================== VLESS Configuration ===================
URI="vless://${VLESS_UUID}@vpn.googleapis.com:443?path=%2F%40fnetvpn&security=tls&encryption=none&host=$(basename ${SERVICE_URL#https://})&type=ws&sni=vpn.googleapis.com#FNET-VPN-VLESS-WS"

printf "${C_FNET_GREEN}${BOLD}🔑 FNET VPN VLESS CONFIGURATION:${RESET}\n"
printf "   ${C_FNET_CYAN}%s${RESET}\n\n" "${URI}"

printf "${C_FNET_GREEN}${BOLD}📋 CONFIGURATION DETAILS:${RESET}\n"
show_kv "Host:" "vpn.googleapis.com"
show_kv "UUID:" "${VLESS_UUID}"
show_kv "Path:" "/@fnetvpn"
show_kv "SNI:" "vpn.googleapis.com"
show_divider

# =================== Date Calculation ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"

# =================== Telegram Notification ===================
if [[ -n "${TELEGRAM_TOKEN:-}" && ${#CHAT_ID_ARR[@]} -gt 0 ]]; then
  MSG=$(cat <<EOF
✅ <b>FNET VPN Server Deployed</b>
━━━━━━━━━━━━━━━━━━━━━━━━━━
<blockquote>🌍 <b>Region:</b> ${REGION}
📡 <b>Protocol:</b> VLESS WS (Custom)
🔗 <b>Endpoint:</b> <a href="${SERVICE_URL}">${SERVICE_URL}</a></blockquote>
🔑 <b>VLESS Configuration:</b>
<pre><code>${URI}</code></pre>
<blockquote>🕒 <b>Deployed:</b> ${START_LOCAL}
⏳ <b>Expires:</b> ${END_LOCAL}</blockquote>
━━━━━━━━━━━━━━━━━━━━━━━━━━
<b>Powered by FNET VPN</b>
EOF
)
  tg_send "${MSG}"
  show_success "Telegram notification sent successfully"
fi

printf "\n${C_FNET_RED}${BOLD}F N E T${RESET} ${C_FNET_GRAY}|${RESET} ${C_FNET_CYAN}VLESS WebSocket Deployment System${RESET} ${C_FNET_GRAY}|${RESET} ${C_FNET_GREEN}v2.0${RESET}\n"
printf "${C_FNET_GRAY}──────────────────────────────────────────────────────────${RESET}\n\n"
