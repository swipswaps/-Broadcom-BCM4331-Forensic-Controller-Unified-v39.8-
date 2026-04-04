#!/usr/bin/env bash
# PATH: prepare-bundle.sh
# =============================================================================
# prepare-bundle.sh (FIRMWARE FETCHER v39.9)
# =============================================================================
# WHAT: downloads and extracts b43 firmware for BCM4331, installs to
#       /usr/lib/firmware/b43, and rebuilds the initramfs so firmware is
#       available at boot time.
#
# WHY: v39.8 prepare-bundle.sh only tarred the project directory -- it never
#      fetched firmware. The b43 firmware at /usr/lib/firmware/b43 dated
#      Mar 27 was from a prior session's manual run. After kernel update to
#      6.19.9 the initramfs did not include it, causing boot-time error -2.
#      Confirmed fix: dracut --force after firmware present = WIFI-HW: enabled.
#
# MENTAL MODEL BEFORE: firmware on disk but not in initramfs -- b43 fails
#   at boot with ENOENT, works only after manual modprobe post-boot
# MENTAL MODEL AFTER: firmware in initramfs -- b43 loads at boot cleanly
#
# FAILURE MODE: if online and b43-firmware package unavailable, falls back
#   to b43-fwcutter + Broadcom driver download. If both fail, prints exact
#   manual steps. Never exits silently without reporting status.
#
# VERIFIES WITH: ls /usr/lib/firmware/b43 shows ht0initvals29.fw,
#   ucode29_mimo.fw, ht0bsinitvals29.fw; lsinitrd | grep b43 shows firmware;
#   after reboot nmcli radio shows WIFI-HW: enabled

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE_DIR="/usr/lib/firmware/b43"
REQUIRED_FW=("ucode29_mimo.fw" "ht0initvals29.fw" "ht0bsinitvals29.fw")

echo "[BUNDLE] BCM4331 firmware preparation starting"

# Check for firmware committed in repo first (fastest, no network required)
REPO_FW="$(cd "$(dirname "$0")" && pwd)/firmware/b43"
if [[ -d "$REPO_FW" ]] && ls "$REPO_FW"/*.fw >/dev/null 2>&1; then
    echo "[BUNDLE] Installing firmware from repo (no network required)."
    sudo mkdir -p "$FIRMWARE_DIR"
    sudo cp "$REPO_FW"/*.fw "$FIRMWARE_DIR"/
    sudo chmod 644 "$FIRMWARE_DIR"/*.fw
    echo "[BUNDLE] Firmware installed from repo."
fi

# ── Check if firmware already present and complete ──────────────────────────
firmware_complete() {
    for fw in "${REQUIRED_FW[@]}"; do
        [[ ! -f "$FIRMWARE_DIR/$fw" ]] && return 1
    done
    return 0
}

if firmware_complete; then
    echo "[BUNDLE] Firmware already present at $FIRMWARE_DIR:"
    ls -lh "$FIRMWARE_DIR"
else
    echo "[BUNDLE] Firmware missing or incomplete -- fetching."

    # ── Method 1: distro package (fastest, preferred) ────────────────────────
    # WHY: b43-firmware package on RPMFusion contains pre-extracted firmware.
    #      Preferred over fwcutter because it handles path and version correctly.
    if command -v dnf >/dev/null 2>&1; then
        echo "[BUNDLE] Attempting dnf install b43-firmware (requires RPMFusion)."
        if sudo dnf install -y b43-firmware 2>/dev/null; then
            echo "[BUNDLE] b43-firmware installed via dnf."
        else
            echo "[BUNDLE] dnf install failed (RPMFusion may not be enabled) -- trying fwcutter."

            # ── Method 2: b43-fwcutter + Broadcom driver ─────────────────────
            # WHY: b43-fwcutter extracts firmware from Broadcom's proprietary
            #      Windows driver. This is the canonical offline method used in
            #      earlier repo versions (bcm4331-fedora-offline-fix prepare-bundle.sh).
            #      Source: https://wireless.docs.kernel.org/en/latest/en/users/drivers/b43/
            if ! command -v b43-fwcutter >/dev/null 2>&1; then
                echo "[BUNDLE] Installing b43-fwcutter."
                sudo dnf install -y b43-fwcutter || {
                    echo "[BUNDLE] FATAL: cannot install b43-fwcutter. Install manually:"
                    echo "  sudo dnf install b43-fwcutter"
                    exit 1
                }
            fi

            TMPDIR=$(mktemp -d)
            trap "rm -rf $TMPDIR" EXIT

            # Broadcom driver version confirmed to contain BCM4331 rev 29 firmware
            DRIVER_URL="https://www.lwfinger.com/b43-firmware/broadcom-wl-5.100.138.tar.bz2"
            DRIVER_FILE="$TMPDIR/broadcom-wl.tar.bz2"

            echo "[BUNDLE] Downloading Broadcom driver from $DRIVER_URL"
            if curl -sSL --retry 3 -o "$DRIVER_FILE" "$DRIVER_URL"; then
                tar -xjf "$DRIVER_FILE" -C "$TMPDIR"
                DRIVER_BIN=$(find "$TMPDIR" -name "*.wl_apsta.o" | head -1 || \
                             find "$TMPDIR" -name "*.o" | head -1)
                if [[ -n "$DRIVER_BIN" ]]; then
                    sudo mkdir -p "$FIRMWARE_DIR"
                    sudo b43-fwcutter -w /usr/lib/firmware "$DRIVER_BIN"
                    echo "[BUNDLE] Firmware extracted via b43-fwcutter."
                else
                    echo "[BUNDLE] FATAL: could not find driver binary in downloaded archive."
                    echo "[BUNDLE] Download manually from: $DRIVER_URL"
                    echo "[BUNDLE] Then run: sudo b43-fwcutter -w /usr/lib/firmware <driver.o>"
                    exit 1
                fi
            else
                echo "[BUNDLE] FATAL: download failed. Check network connectivity."
                echo "[BUNDLE] Manual alternative:"
                echo "  sudo dnf install -y b43-firmware"
                echo "  OR enable RPMFusion: https://rpmfusion.org/Configuration"
                exit 1
            fi
        fi
    fi
fi

# ── Verify firmware is now complete ─────────────────────────────────────────
echo "[BUNDLE] Verifying firmware files:"
ls -lh "$FIRMWARE_DIR"
if ! firmware_complete; then
    echo "[BUNDLE] FATAL: required firmware files still missing after install."
    echo "[BUNDLE] Expected in $FIRMWARE_DIR: ${REQUIRED_FW[*]}"
    exit 1
fi
echo "[BUNDLE] All required firmware files confirmed present."

# ── Rebuild initramfs ────────────────────────────────────────────────────────
# WHY: dracut must run after firmware is on disk so the initramfs includes it.
#      Without this step, b43 fails at boot with error -2 even when files exist.
#      Confirmed: dracut --force fixed boot-time failure (session 2026-04-04).
echo "[BUNDLE] Rebuilding initramfs to include b43 firmware."
sudo dracut --force
echo "[BUNDLE] Initramfs rebuilt."

# ── Confirm firmware in initramfs ───────────────────────────────────────────
echo "[BUNDLE] Confirming firmware in initramfs:"
sudo lsinitrd | grep b43 || echo "[BUNDLE] WARN: b43 not found in lsinitrd output"

echo "[BUNDLE] Preparation complete. Reboot or run fix-wifi.sh to activate."