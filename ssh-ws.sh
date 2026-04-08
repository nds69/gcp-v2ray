#!/usr/bin/env bash
set -euo pipefail

if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging & error handler =====
LOG_FILE="/tmp/fnet_ssh_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO" | tee -a "$LOG_FILE" >&2
  exit $rc
}
trap on_err ERR

# =================== FNET VPN Custom UI ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'
  C_FNET_RED=$'\e[38;5;196m'; C_FNET_BLUE=$'\e[38;5;39m'; C_FNET_GREEN=$'\e[38;5;46m'     
  C_FNET_YELLOW=$'\e[38;5;226m'; C_FNET_PURPLE=$'\e[38;5;93m'; C_FNET_GRAY=$'\e[38;5;214m'     
  C_FNET_CYAN=$'\e[38;5;51m'      
else
  RESET= BOLD= C_FNET_RED= C_FNET_BLUE= C_FNET_GREEN= C_FNET_YELLOW= C_FNET_PURPLE= C_FNET_GRAY= C_FNET_CYAN=
fi

show_fnet_banner() {
  clear
  printf "\n\n${C_FNET_RED}${BOLD}"
  printf "╔══════════════════════════════════════════════════════════════════╗\n"
  printf "║                                                                  ║\n"
  printf "║   ███████╗███╗   ██╗███████╗████████╗    ██╗   ██╗██████╗ ███╗   ██╗ ║\n"
  printf "║   ██╔════╝████╗  ██║██╔════╝╚══██╔══╝    ██║   ██║██╔══██╗████╗  ██║ ║\n"
  printf "║   █████╗  ██╔██╗ ██║█████╗     ██║       ██║   ██║██████╔╝██╔██╗ ██║ ║\n"
  printf "║   ██╔══╝  ██║╚██╗██║██╔══╝     ██║       ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║ ║\n"
  printf "║   ██║     ██║ ╚████║███████╗   ██║        ╚████╔╝ ██║     ██║ ╚████║ ║\n"
  printf "║   ╚═╝     ╚═╝  ╚═══╝╚══════╝   ╚═╝         ╚═══╝  ╚═╝     ╚═╝  ╚═══╝ ║\n"
  printf "║                                                                  ║\n"
  printf "║         ${C_FNET_YELLOW}🚀 SSH WS (ULTIMATE EDITION) => VERSION - 3.0          ${C_FNET_RED}║\n"
  printf "║         ${C_FNET_GREEN}⚡ Powered by FNET Developer                           ${C_FNET_RED}║\n"
  printf "╚══════════════════════════════════════════════════════════════════╝${RESET}\n\n"
}

show_step() { printf "\n${C_FNET_PURPLE}${BOLD}┌─── STEP $1 ──────────────────────────────────────────┐${RESET}\n${C_FNET_PURPLE}${BOLD}│${RESET} ${C_FNET_CYAN}$2${RESET}\n${C_FNET_PURPLE}${BOLD}└──────────────────────────────────────────────────────┘${RESET}\n"; }
show_success() { printf "${C_FNET_GREEN}${BOLD}✓${RESET} ${C_FNET_GREEN}%s${RESET}\n" "$1"; }
show_info() { printf "${C_FNET_BLUE}${BOLD}ℹ${RESET} ${C_FNET_BLUE}%s${RESET}\n" "$1"; }
show_warning() { printf "${C_FNET_YELLOW}${BOLD}⚠${RESET} ${C_FNET_YELLOW}%s${RESET}\n" "$1"; }
show_error() { printf "${C_FNET_RED}${BOLD}✗${RESET} ${C_FNET_RED}%s${RESET}\n" "$1"; }
show_divider() { printf "${C_FNET_GRAY}%s${RESET}\n" "──────────────────────────────────────────────────────────"; }
show_kv() { printf "   ${C_FNET_GRAY}%s${RESET}  ${C_FNET_CYAN}%s${RESET}\n" "$1" "$2"; }

run_with_progress() {
  local label="$1"; shift; local temp_file=$(mktemp)
  if [[ -t 1 ]]; then
    printf "\e[?25l"; ("$@" 2>&1 | tee "$temp_file") >>"$LOG_FILE" 2>&1 & local pid=$!; local pct=5
    while kill -0 "$pid" 2>/dev/null; do
      pct=$(( pct + $(( (RANDOM % 5) + 2 )) )); (( pct > 98 )) && pct=98
      printf "\r${C_FNET_PURPLE}⟳${RESET} ${C_FNET_CYAN}%s...${RESET} [${C_FNET_YELLOW}%s%%${RESET}]" "$label" "$pct"
      sleep 0.8
    done
    wait "$pid" 2>/dev/null || true; local rc=$?
    printf "\r\e[K"
    if (( rc==0 )); then printf "${C_FNET_GREEN}✓${RESET} ${C_FNET_GREEN}%s...${RESET} [${C_FNET_GREEN}100%%${RESET}]\n" "$label"
    else printf "${C_FNET_RED}✗${RESET} ${C_FNET_RED}%s failed!${RESET}\n" "$label"; rm -f "$temp_file"; printf "\e[?25h"; return $rc; fi
    rm -f "$temp_file"; printf "\e[?25h"
  else "$@" >>"$LOG_FILE" 2>&1; fi
}

show_fnet_banner

# =================== Step 1: Telegram Config ===================
show_step "01" "Telegram Configuration Setup"
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""
read -rp "${C_FNET_GREEN}🤖 Enter Telegram Bot Token:${RESET} " TELEGRAM_TOKEN || true
read -rp "${C_FNET_GREEN}👤 Enter Telegram Chat ID:${RESET} " TELEGRAM_CHAT_ID || true

tg_send(){
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then return 0; fi
  curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=${text}" -d "parse_mode=HTML" \
    >>"$LOG_FILE" 2>&1 || true
}

# =================== Step 2: Timezone Setup ===================
show_step "02" "Lab Timer Setup"
printf "\n${C_FNET_GRAY}💡 Qwiklabs ပေါ်က ကျန်နေတဲ့ အချိန်ကို ကြည့်ပြီး ထည့်ပေးပါ။ (ဥပမာ - 05:10)${RESET}\n"
read -rp "${C_FNET_GREEN}⏳ Remaining Time (H:M):${RESET} " REMAINING_TIME || true
export TZ="Asia/Bangkok"
START_EPOCH="$(date +%s)"
if [[ -z "$REMAINING_TIME" || ! "$REMAINING_TIME" =~ ^[0-9]+:[0-9]+$ ]]; then
  ADD_SECS=$(( 3 * 3600 ))
else
  HRS=$(echo "$REMAINING_TIME" | cut -d: -f1 | sed 's/^0*//'); MINS=$(echo "$REMAINING_TIME" | cut -d: -f2 | sed 's/^0*//')
  ADD_SECS=$(( ${HRS:-0} * 3600 + ${MINS:-0} * 60 ))
fi
END_LOCAL="$(date -d @"$(( START_EPOCH + ADD_SECS ))" "+%I:%M %p")"
show_success "Expire Time set to: $END_LOCAL"

# =================== Step 3: Enable APIs ===================
show_step "03" "GCP API Enablement"
APIS_TO_ENABLE=("run.googleapis.com" "cloudbuild.googleapis.com" "artifactregistry.googleapis.com")
for api in "${APIS_TO_ENABLE[@]}"; do
  if ! gcloud services list --enabled --filter="config.name:$api" --format="value(config.name)" | grep -q "$api"; then
    run_with_progress "Enabling $api" gcloud services enable "$api" --quiet
  fi
done
show_success "Required APIs enabled successfully."

# =================== Step 4: Build Ultimate Server ===================
show_step "04" "Building Ultimate SSH Server (UDPGW + Threading)"
BUILD_DIR=$(mktemp -d); cd "$BUILD_DIR"

# Threading-based Unbreakable Python Proxy
cat << 'EOF' > proxy.py
import socket, threading, os

def forward(source, destination):
    try:
        while True:
            data = source.recv(8192)
            if not data: break
            destination.sendall(data)
    except: pass
    finally:
        try: source.shutdown(socket.SHUT_RDWR)
        except: pass
        source.close()
        try: destination.shutdown(socket.SHUT_RDWR)
        except: pass
        destination.close()

def handle_client(client):
    try:
        req = b""
        while b"\r\n\r\n" not in req:
            chunk = client.recv(4096)
            if not chunk: break
            req += chunk

        client.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")

        ssh = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        ssh.connect(('127.0.0.1', 22))

        parts = req.split(b"\r\n\r\n", 1)
        if len(parts) > 1 and len(parts[1]) > 0:
            ssh.sendall(parts[1])

        t1 = threading.Thread(target=forward, args=(client, ssh))
        t2 = threading.Thread(target=forward, args=(ssh, client))
        t1.start()
        t2.start()
    except:
        client.close()

def main():
    port = int(os.environ.get("PORT", 8080))
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', port))
    server.listen(100)
    while True:
        client, _ = server.accept()
        threading.Thread(target=handle_client, args=(client,)).start()

if __name__ == '__main__':
    main()
EOF

# Dockerfile with BadVPN-UDPGW builder included
cat << 'EOF' > Dockerfile
FROM alpine:latest AS builder
RUN apk add --no-cache build-base cmake git
RUN git clone https://github.com/ambrop72/badvpn.git /badvpn && \
    cd /badvpn && mkdir build && cd build && \
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 && \
    make install

FROM alpine:latest
RUN apk add --no-cache openssh python3 bash
COPY --from=builder /usr/local/bin/badvpn-udpgw /usr/local/bin/badvpn-udpgw
RUN ssh-keygen -A && \
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config && \
    echo "GatewayPorts yes" >> /etc/ssh/sshd_config && \
    echo "PermitTunnel yes" >> /etc/ssh/sshd_config && \
    echo "UseDNS no" >> /etc/ssh/sshd_config && \
    adduser -D -s /bin/bash fnet && echo "fnet:fnet" | chpasswd
COPY proxy.py /app/proxy.py
EXPOSE 8080
CMD ["/bin/bash", "-c", "badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10 >/dev/null 2>&1 & /usr/sbin/sshd && python3 /app/proxy.py"]
EOF

# =================== Step 5: Deploy (Gen 2 Fix) ===================
show_step "05" "Cloud Run Deployment (Gen 2 Environment)"
SERVICE="fnet-ssh-ws-$(date +%s)"
REGION="us-central1"

# UDPGW ပါဝင်တဲ့အတွက် တည်ဆောက်ချိန် အနည်းငယ် ပိုကြာနိုင်ပါတယ်။
run_with_progress "Deploying Gen-2 Server to Cloud Run" \
  gcloud run deploy "$SERVICE" \
  --source="." \
  --region="$REGION" \
  --platform=managed \
  --allow-unauthenticated \
  --port=8080 \
  --execution-environment=gen2 \
  --timeout=3600 \
  --quiet

# =================== Step 6: Fetching Cloud Run URL ===================
show_step "06" "Fetching Cloud Run URL"
show_info "Waiting for Google to assign URL..."
SERVICE_URL=""
for i in {1..15}; do
  SERVICE_URL=$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)' 2>/dev/null || true)
  if [[ -n "$SERVICE_URL" ]]; then
    break
  fi
  sleep 3
done

if [[ -z "$SERVICE_URL" ]]; then
  show_error "URL ကို ဆွဲယူလို့ မရပါ။ Deployment Failed ဖြစ်သွားနိုင်ပါသည်။"
  exit 1
fi

HOST_URL=$(echo "$SERVICE_URL" | sed 's#^https://##; s#/$##')
show_success "URL fetched: $HOST_URL"

# =================== Step 7: Final Result & Telegram ===================
show_step "07" "Deployment Finished"

PAYLOAD="GET / HTTP/1.1[crlf]Host: ${HOST_URL}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"

# Screen Output
show_kv "Host:" "vpn.googleapis.com"
show_kv "Port:" "443"
show_kv "User/Pass:" "fnet / fnet"
show_kv "Payload:" "$PAYLOAD"

# Telegram Output
MSG=$(cat <<EOF
✅ <b>FNET SSH WS (V3.0) Deployed</b>
━━━━━━━━━━━━━━━━━━
🌍 <b>Host:</b> <code>vpn.googleapis.com</code>
🔌 <b>Port:</b> <code>443</code>
👤 <b>User:</b> <code>fnet</code>
🔑 <b>Pass:</b> <code>fnet</code>
🛡️ <b>SNI:</b> <code>vpn.googleapis.com</code>

📋 <b>PAYLOAD:</b>
<code>${PAYLOAD}</code>

⏳ <b>Expires at:</b> ${END_LOCAL}
━━━━━━━━━━━━━━━━━━
<b>UDPGW (Port 7300) Enabled for DNS/Games!</b>
EOF
)
tg_send "$MSG"
show_success "Telegram message sent! Please check your bot."
rm -rf "$BUILD_DIR"
