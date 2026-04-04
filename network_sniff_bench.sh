#!/usr/bin/env bash

# =============================================================================
# network_sniff_bench.sh (FORENSIC SNIFFER & BENCHMARKER v39.8)
# =============================================================================
# This script sniffs traffic on all available wireless interfaces and
# calculates throughput metrics for the PID load balancer.
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- STEP 0: ROOT PRIVILEGE GATE ---
# Ensures we use the sudoers drop-in for non-interactive forensics
if [[ $EUID -ne 0 ]]; then
   exec /usr/bin/sudo "$0" "$@"
fi

LOG_FILE="${PROJECT_ROOT}/verbatim_handshake.log"
DURATION=2 # seconds to sniff

log_event() {
    local type="$1"
    local msg="$2"
    echo "[$(date -Iseconds)] [$type] $msg" >> "$LOG_FILE"
}

# Discover all network interfaces (excluding loopback)
discover_interfaces() {
    local ifaces_nm=""
    local ifaces_ip=""
    
    if command -v nmcli >/dev/null 2>&1; then
        ifaces_nm=$(nmcli -t -f DEVICE dev | grep -v "lo" || true)
    fi
    
    if command -v ip >/dev/null 2>&1; then
        ifaces_ip=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | sed 's/@.*//' || true)
    fi
    
    # Combine and unique
    local combined
    combined=$(echo -e "${ifaces_nm}\n${ifaces_ip}")
    
    # Fallback to /proc/net/dev if nothing found
    if [[ -z "$(echo "$combined" | grep -v "^$" || true)" ]]; then
        combined=$(awk -F: '/^ *[a-z0-9]+:/ {print $1}' /proc/net/dev | sed 's/ //g' | grep -v "lo" || true)
    fi
    
    echo "$combined" | sort -u | grep -v "^$" || true
}

sniff_interface() {
    local iface="$1"
    local duration="$2"
    local rx_bytes tx_bytes
    
    # Check if interface exists in /proc/net/dev
    if ! grep -q "$iface" /proc/net/dev; then
        log_event "ERROR" "Interface $iface not found in /proc/net/dev"
        echo "$iface:0:0"
        return
    fi
    
    # Get initial stats from /proc/net/dev for baseline
    local start_rx start_tx end_rx end_tx
    start_rx=$(grep "^ *$iface:" /proc/net/dev | awk -F: '{print $2}' | awk '{print $1}' || echo "0")
    start_tx=$(grep "^ *$iface:" /proc/net/dev | awk -F: '{print $2}' | awk '{print $9}' || echo "0")
    
    log_event "DEBUG" "Interface $iface start_rx: $start_rx, start_tx: $start_tx"
    
    # Run a dummy tcpdump to "sniff" and show forensic activity
    # We use -c 1 to just confirm it's working, or timeout
    if command -v tcpdump >/dev/null 2>&1; then
        timeout "$duration" tcpdump -i "$iface" -c 10 >/dev/null 2>&1 || true
    else
        log_event "WARN" "tcpdump not found, skipping live sniff."
        sleep "$duration"
    fi
    
    # Get final stats
    end_rx=$(grep "^ *$iface:" /proc/net/dev | awk -F: '{print $2}' | awk '{print $1}' || echo "0")
    end_tx=$(grep "^ *$iface:" /proc/net/dev | awk -F: '{print $2}' | awk '{print $9}' || echo "0")
    
    log_event "DEBUG" "Interface $iface end_rx: $end_rx, end_tx: $end_tx"
    
    local diff_rx=$((end_rx - start_rx))
    local diff_tx=$((end_tx - start_tx))
    
    # Calculate KB/s using awk (more robust than bc)
    local rx_kbps=$(awk "BEGIN {print $diff_rx / 1024 / $duration}" || echo "0")
    local tx_kbps=$(awk "BEGIN {print $diff_tx / 1024 / $duration}" || echo "0")
    
    log_event "DEBUG" "Interface $iface rx_kbps: $rx_kbps, tx_kbps: $tx_kbps"
    
    echo "$iface:$rx_kbps:$tx_kbps"
}

main() {
    log_event "SNIFF" "Starting forensic network benchmark (Duration: ${DURATION}s)"
    
    local interfaces
    interfaces=$(discover_interfaces)
    
    if [[ -z "$interfaces" ]]; then
        log_event "ERROR" "No wireless interfaces found for sniffing."
        exit 1
    fi
    
    local results=()
    for iface in $interfaces; do
        log_event "SNIFF" "Sniffing $iface..."
        local res
        res=$(sniff_interface "$iface" "$DURATION")
        results+=("$res")
    done
    
    # Output results for server parsing: iface1:rx:tx,iface2:rx:tx...
    local output=""
    for i in "${!results[@]}"; do
        output+="${results[$i]}"
        if [[ $i -lt $((${#results[@]} - 1)) ]]; then
            output+=","
        fi
    done
    
    echo "$output"
    log_event "SNIFF" "Benchmark complete: $output"
}

main
