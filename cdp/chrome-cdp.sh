#!/bin/bash
set -euo pipefail

# Chrome CDP + Cloudflare Tunnel for Remote Test Automation
# Launches Chrome with desktop GUI, enables CDP, proxies via cloudflared.
# Works on macOS and Linux.
#
# Usage:
#   ./chrome-cdp.sh [-- extra-chrome-flags...]
#
# Environment:
#   CDP_PORT          CDP listening port           (default: 9222)
#   CHROME_USER_DATA  Separate profile directory   (default: /tmp/chrome-cdp-profile)
#   CHROME_BIN        Override Chrome binary path

CDP_PORT="${CDP_PORT:-9222}"
CHROME_USER_DATA="${CHROME_USER_DATA:-/tmp/chrome-cdp-profile}"
CHROME_PID=""
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
    [[ -n "$TUNNEL_PID" ]]  && kill "$TUNNEL_PID"  2>/dev/null && echo "  stopped tunnel  (pid $TUNNEL_PID)"
    [[ -n "$TUNNEL_LOG" ]]  && rm -f "$TUNNEL_LOG"
    wait 2>/dev/null
}
trap cleanup EXIT

# ── Launch Chrome with CDP ───────────────────────────────────────────────────

launch_chrome() {
    mkdir -p "$CHROME_USER_DATA"

    local flags=(
        --remote-debugging-port="$CDP_PORT"
        --remote-debugging-address=127.0.0.1
        --user-data-dir="$CHROME_USER_DATA"
        --no-first-run
        --no-default-browser-check
        --disable-background-timer-throttling
        --disable-backgrounding-occluded-windows
        --disable-renderer-backgrounding
        --disable-hang-monitor
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

# ── Print connection info ────────────────────────────────────────────────────

print_info() {
    local version_json ws_path tunnel_host
    version_json=$(curl -sf "http://127.0.0.1:${CDP_PORT}/json/version")
    # Extract the path portion of the browser websocket debugger URL
    ws_path=$(echo "$version_json" | sed -n 's|.*"webSocketDebuggerUrl"[[:space:]]*:[[:space:]]*"ws://[^/]*/\(.*\)".*|\1|p')
    tunnel_host="${TUNNEL_URL#https://}"

    cat <<EOF

════════════════════════════════════════════════
  Chrome CDP via Cloudflare Tunnel
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
    # Split on -- so users can pass extra Chrome flags
    local chrome_extra=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --) shift; chrome_extra=("$@"); break ;;
            *)  echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done

    detect_chrome
    launch_chrome ${chrome_extra[@]+"${chrome_extra[@]}"}
    start_tunnel
    print_info

    # Block until Chrome exits
    wait "$CHROME_PID" 2>/dev/null || true
}

main "$@"
