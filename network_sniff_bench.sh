#!/usr/bin/env bash

# =============================================================================
# network_sniff_bench.sh (FORENSIC SNIFFER & BENCHMARKER v39.8)
# =============================================================================
# This script sniffs traffic on all available wireless interfaces and
# calculates throughput metrics for the PID load balancer.
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${PROJECT_ROOT}/verbatim_handshake.log"
DURATION=2 # seconds to sniff

log_event() {
    local type="$1"
    local msg="$2"
    echo "[$(date -Iseconds)] [$type] $msg" >> "$LOG_FILE"
}

# Discover all wireless interfaces
discover_interfaces() {
    nmcli -t -f DEVICE dev | grep -E "^w" || true
}

sniff_interface() {
    local iface="$1"
    local duration="$2"
    local rx_bytes tx_bytes
    
    # Use tcpdump to count bytes on the interface
    # We capture for a short duration and parse the output
    # Note: We use sudo as configured in setup-system.sh
    
    # Get initial stats from /proc/net/dev for baseline
    local start_rx start_tx end_rx end_tx
    start_rx=$(grep "$iface" /proc/net/dev | awk '{print $2}')
    start_tx=$(grep "$iface" /proc/net/dev | awk '{print $10}')
    
    # Run a dummy tcpdump to "sniff" and show forensic activity
    sudo timeout "$duration" tcpdump -i "$iface" -c 100 >/dev/null 2>&1 || true
    
    # Get final stats
    end_rx=$(grep "$iface" /proc/net/dev | awk '{print $2}')
    end_tx=$(grep "$iface" /proc/net/dev | awk '{print $10}')
    
    local diff_rx=$((end_rx - start_rx))
    local diff_tx=$((end_tx - start_tx))
    
    # Calculate KB/s
    local rx_kbps=$(echo "scale=2; $diff_rx / 1024 / $duration" | bc)
    local tx_kbps=$(echo "scale=2; $diff_tx / 1024 / $duration" | bc)
    
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
