#!/bin/bash
set -euo pipefail

# Chrome CDP for Remote Test Automation
# Launches Chrome with desktop GUI + CDP, accessible from Docker/Lima/LAN.
# Works on macOS and Linux.
#
# Usage:
#   ./chrome-cdp.sh [--lan|--tunnel] [-- extra-chrome-flags...]
#
#   --lan      Bind CDP to 0.0.0.0 for direct LAN/VM access (default)
#   --tunnel   Proxy CDP through a cloudflared quick tunnel
#
# Environment:
#   CDP_PORT          CDP listening port           (default: 9222)
#   CDP_BIND          Bind address                 (default: 0.0.0.0 for --lan, 127.0.0.1 for --tunnel)
#   CHROME_USER_DATA  Separate profile directory   (default: /tmp/chrome-cdp-profile)
#   CHROME_BIN        Override Chrome binary path
#   SOCAT_PORT        External-facing port for socat proxy (default: CDP_PORT + 1 = 9223)

CDP_PORT="${CDP_PORT:-9222}"
SOCAT_PORT="${SOCAT_PORT:-$((CDP_PORT + 1))}"
CHROME_USER_DATA="${CHROME_USER_DATA:-/tmp/chrome-cdp-profile}"
MODE="lan"   # default: direct LAN access
CHROME_PID=""
SOCAT_PID=""
TUNNEL_PID=""
TUNNEL_LOG=""

# ── OS detection & Chrome path ───────────────────────────────────────────────

detect_chrome() {
    if [[ -n "${CHROME_BIN:-}" && -x "$CHROME_BIN" ]]; then
        echo "Using CHROME_BIN override: $CHROME_BIN"
        return 0
    fi

    case "$(uname -s)" in
        Darwin)
            local -a candidates=(
                "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
                "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"
                "/Applications/Chromium.app/Contents/MacOS/Chromium"
                "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
                "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"
            )
            for c in "${candidates[@]}"; do
                if [[ -x "$c" ]]; then
                    CHROME_BIN="$c"
                    break
                fi
            done
            ;;
        Linux)
            for c in google-chrome google-chrome-stable chromium-browser chromium brave-browser microsoft-edge; do
                if command -v "$c" &>/dev/null; then
                    CHROME_BIN="$(command -v "$c")"
                    break
                fi
            done
            ;;
        *)
            echo "Error: unsupported OS $(uname -s)" >&2
            exit 1
            ;;
    esac

    if [[ -z "${CHROME_BIN:-}" ]]; then
        echo "Error: Chrome/Chromium not found." >&2
        echo "Set CHROME_BIN=/path/to/chrome or install Chrome." >&2
        exit 1
    fi
    echo "Chrome: $CHROME_BIN"
}

# ── Cleanup on exit ──────────────────────────────────────────────────────────

cleanup() {
    echo ""
    echo "Shutting down..."
    [[ -n "$CHROME_PID" ]]  && kill "$CHROME_PID"  2>/dev/null && echo "  stopped chrome  (pid $CHROME_PID)"
    [[ -n "$SOCAT_PID" ]]   && kill "$SOCAT_PID"   2>/dev/null && echo "  stopped socat   (pid $SOCAT_PID)"
    [[ -n "$TUNNEL_PID" ]]  && kill "$TUNNEL_PID"  2>/dev/null && echo "  stopped tunnel  (pid $TUNNEL_PID)"
    [[ -n "$TUNNEL_LOG" ]]  && rm -f "$TUNNEL_LOG"
    wait 2>/dev/null
}
trap cleanup EXIT

# ── Launch Chrome with CDP ───────────────────────────────────────────────────

launch_chrome() {
    mkdir -p "$CHROME_USER_DATA"

    # Determine bind address
    local bind_addr
    if [[ -n "${CDP_BIND:-}" ]]; then
        bind_addr="$CDP_BIND"
    elif [[ "$MODE" == "lan" ]]; then
        bind_addr="0.0.0.0"
    else
        bind_addr="127.0.0.1"
    fi

    local flags=(
        --remote-debugging-port="$CDP_PORT"
        --remote-debugging-address="$bind_addr"
        --user-data-dir="$CHROME_USER_DATA"
        --no-first-run
        --no-default-browser-check
        --disable-background-timer-throttling
        --disable-backgrounding-occluded-windows
        --disable-renderer-backgrounding
        --disable-hang-monitor

        # GPU / WebGPU — use real hardware by default
        --enable-gpu
        --enable-features=Vulkan,UseSkiaRenderer,WebGPU
        --enable-unsafe-webgpu
        --disable-gpu-sandbox

        "$@"
    )

    echo "Launching Chrome on :${CDP_PORT} ..."
    "$CHROME_BIN" "${flags[@]}" &
    CHROME_PID=$!

    # Wait for the CDP HTTP endpoint to respond
    echo -n "Waiting for CDP"
    local i
    for i in $(seq 1 30); do
        if curl -sf "http://127.0.0.1:${CDP_PORT}/json/version" >/dev/null 2>&1; then
            echo " ok"
            return 0
        fi
        # Exit early if Chrome already died
        if ! kill -0 "$CHROME_PID" 2>/dev/null; then
            echo " failed"
            echo "Error: Chrome exited prematurely" >&2
            exit 1
        fi
        echo -n "."
        sleep 1
    done
    echo " timeout"
    echo "Error: CDP not ready after 30 s" >&2
    exit 1
}

# ── Ensure socat is available ────────────────────────────────────────────────

ensure_socat() {
    command -v socat &>/dev/null && return 0

    echo "socat not found — installing..."
    case "$(uname -s)" in
        Darwin)
            if command -v brew &>/dev/null; then
                brew install socat
            else
                echo "Error: socat not found and Homebrew is not installed." >&2
                echo "  Install Homebrew (https://brew.sh) then: brew install socat" >&2
                exit 1
            fi
            ;;
        Linux)
            if command -v apt-get &>/dev/null; then
                sudo apt-get update -qq && sudo apt-get install -yqq socat
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y socat
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm socat
            elif command -v apk &>/dev/null; then
                sudo apk add --no-cache socat
            else
                echo "Error: socat not found and no known package manager available." >&2
                exit 1
            fi
            ;;
    esac

    if ! command -v socat &>/dev/null; then
        echo "Error: socat installation failed." >&2
        exit 1
    fi
    echo "socat installed."
}

# ── Start socat proxy (workaround for browsers that ignore bind address) ────

start_socat_proxy() {
    # Check if Chrome actually bound to the requested address
    local actual_bind
    actual_bind=$(lsof -iTCP:"$CDP_PORT" -sTCP:LISTEN -n -P 2>/dev/null \
        | awk 'NR>1 {print $9}' | head -1 | cut -d: -f1 || true)

    if [[ "$actual_bind" != "127.0.0.1" ]]; then
        # Chrome honoured the bind address — no proxy needed
        return 1
    fi

    echo "Chrome bound to 127.0.0.1 only — starting socat proxy on 0.0.0.0:${SOCAT_PORT} ..."
    ensure_socat

    socat TCP-LISTEN:"$SOCAT_PORT",bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:"$CDP_PORT" &
    SOCAT_PID=$!

    # Brief check that socat started
    sleep 0.3
    if ! kill -0 "$SOCAT_PID" 2>/dev/null; then
        echo "Error: socat exited immediately. Is port ${SOCAT_PORT} in use?" >&2
        exit 1
    fi
    echo "socat proxy ready (0.0.0.0:${SOCAT_PORT} → 127.0.0.1:${CDP_PORT})"
    return 0
}

# ── Start Cloudflare quick tunnel ────────────────────────────────────────────

start_tunnel() {
    if ! command -v cloudflared &>/dev/null; then
        echo "Error: cloudflared not found" >&2
        echo "  macOS:  brew install cloudflared" >&2
        echo "  Linux:  https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/" >&2
        exit 1
    fi

    TUNNEL_LOG=$(mktemp "${TMPDIR:-/tmp}/cloudflared-cdp.XXXXXX")
    echo "Starting cloudflared quick tunnel..."
    cloudflared tunnel --url "http://127.0.0.1:${CDP_PORT}" \
        --no-autoupdate 2>"$TUNNEL_LOG" &
    TUNNEL_PID=$!

    echo -n "Waiting for tunnel URL"
    local url=""
    local i
    for i in $(seq 1 30); do
        url=$(grep -oE 'https://[a-zA-Z0-9._-]+\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | head -1 || true)
        if [[ -n "$url" ]]; then
            echo " ok"
            TUNNEL_URL="$url"
            return 0
        fi
        if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
            echo " failed"
            echo "Error: cloudflared exited. Log:" >&2
            cat "$TUNNEL_LOG" >&2
            exit 1
        fi
        echo -n "."
        sleep 1
    done
    echo " timeout"
    echo "Error: no tunnel URL after 30 s. Log:" >&2
    cat "$TUNNEL_LOG" >&2
    exit 1
}

# ── Detect host LAN IP ───────────────────────────────────────────────────────

detect_lan_ip() {
    case "$(uname -s)" in
        Darwin)
            # Primary interface IP (works for Wi-Fi and Ethernet)
            ipconfig getifaddr en0 2>/dev/null \
                || ipconfig getifaddr en1 2>/dev/null \
                || echo "127.0.0.1"
            ;;
        Linux)
            hostname -I 2>/dev/null | awk '{print $1}' \
                || ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' \
                || echo "127.0.0.1"
            ;;
    esac
}

# ── Print connection info ────────────────────────────────────────────────────

print_info_lan() {
    local host_ip version_json ws_path ext_port
    host_ip=$(detect_lan_ip)
    version_json=$(curl -sf "http://127.0.0.1:${CDP_PORT}/json/version")
    ws_path=$(echo "$version_json" | sed -n 's|.*"webSocketDebuggerUrl"[[:space:]]*:[[:space:]]*"ws://[^/]*/\(.*\)".*|\1|p')

    # If socat proxy is active, external connections use SOCAT_PORT
    if [[ -n "$SOCAT_PID" ]]; then
        ext_port="$SOCAT_PORT"
    else
        ext_port="$CDP_PORT"
    fi

    cat <<EOF

════════════════════════════════════════════════
  Chrome CDP — LAN mode
════════════════════════════════════════════════

  Host IP:   ${host_ip}
  Local:     http://127.0.0.1:${CDP_PORT}
  LAN:       http://${host_ip}:${ext_port}
EOF

    if [[ -n "$SOCAT_PID" ]]; then
        cat <<EOF
  Proxy:     socat 0.0.0.0:${ext_port} → 127.0.0.1:${CDP_PORT}
             (browser ignored --remote-debugging-address)
EOF
    fi

    cat <<EOF

  Endpoints (from container/VM)
    version:   http://${host_ip}:${ext_port}/json/version
    targets:   http://${host_ip}:${ext_port}/json/list
    websocket: ws://${host_ip}:${ext_port}/${ws_path}

  Playwright (from container)
    const browser = await chromium.connectOverCDP(
      'http://${host_ip}:${ext_port}'
    );

  Puppeteer (from container)
    const browser = await puppeteer.connect({
      browserURL: 'http://${host_ip}:${ext_port}'
    });

  Docker run example
    docker run --rm \\
      -e CDP_ENDPOINT=http://${host_ip}:${ext_port} \\
      your-test-image

  Lima VM note
    The host IP ${host_ip} is reachable from Lima's
    default network. From inside the VM/container:
      curl http://${host_ip}:${ext_port}/json/version

════════════════════════════════════════════════
  Ctrl+C to stop
════════════════════════════════════════════════

EOF
}

print_info_tunnel() {
    local version_json ws_path tunnel_host
    version_json=$(curl -sf "http://127.0.0.1:${CDP_PORT}/json/version")
    ws_path=$(echo "$version_json" | sed -n 's|.*"webSocketDebuggerUrl"[[:space:]]*:[[:space:]]*"ws://[^/]*/\(.*\)".*|\1|p')
    tunnel_host="${TUNNEL_URL#https://}"

    cat <<EOF

════════════════════════════════════════════════
  Chrome CDP — Cloudflare Tunnel mode
════════════════════════════════════════════════

  Tunnel:    ${TUNNEL_URL}
  Local:     http://127.0.0.1:${CDP_PORT}

  Remote endpoints
    version:   ${TUNNEL_URL}/json/version
    targets:   ${TUNNEL_URL}/json/list
    websocket: wss://${tunnel_host}/${ws_path}

  Playwright
    const browser = await chromium.connectOverCDP('${TUNNEL_URL}');

  Puppeteer
    const browser = await puppeteer.connect({
      browserURL: '${TUNNEL_URL}'
    });

════════════════════════════════════════════════
  Ctrl+C to stop
════════════════════════════════════════════════

EOF
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    # Parse options, split on -- for extra Chrome flags
    local chrome_extra=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lan)    MODE="lan";    shift ;;
            --tunnel) MODE="tunnel"; shift ;;
            --) shift; chrome_extra=("$@"); break ;;
            *)  echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done

    detect_chrome
    launch_chrome ${chrome_extra[@]+"${chrome_extra[@]}"}

    if [[ "$MODE" == "tunnel" ]]; then
        start_tunnel
        print_info_tunnel
    else
        # If Chrome ignored the bind address, auto-start a socat proxy
        start_socat_proxy || true
        print_info_lan
    fi

    # Block until Chrome exits
    wait "$CHROME_PID" 2>/dev/null || true
}

main "$@"
