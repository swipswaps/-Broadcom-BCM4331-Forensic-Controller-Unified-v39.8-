#!/usr/bin/env python3
import sys
import os

# =============================================================================
# tray_applet.py (HEADLESS CONTROLLER v39.8)
# =============================================================================
# This script implements the headless logic for the BCM4331 Forensic Controller.
# It manages user preferences and provides a CLI interface for system state.

import json
import argparse

PREFS_FILE = os.path.expanduser("~/.bcm4331_prefs.json")

def load_prefs():
    if not os.path.exists(PREFS_FILE):
        default_prefs = {"auto_fix": True, "notifications": True, "log_level": "INFO"}
        with open(PREFS_FILE, "w") as f:
            json.dump(default_prefs, f, indent=4)
        return default_prefs
    with open(PREFS_FILE, "r") as f:
        return json.load(f)

def save_prefs(prefs):
    with open(PREFS_FILE, "w") as f:
        json.dump(prefs, f, indent=4)

def main():
    parser = argparse.ArgumentParser(description="BCM4331 Forensic Tray Applet (Headless)")
    parser.add_argument("--status", action="store_true", help="Show current controller status")
    parser.add_argument("--set-autofix", type=str, choices=["true", "false"], help="Enable or disable auto-fix")
    
    args = parser.parse_args()
    prefs = load_prefs()

    if args.set_autofix:
        prefs["auto_fix"] = args.set_autofix.lower() == "true"
        save_prefs(prefs)
        print(f"Auto-fix set to: {prefs['auto_fix']}")
        return

    print("🛰️ BCM4331 Forensic Tray Applet (Headless Mode)")
    print(f"Preferences loaded from {PREFS_FILE}")
    print(f"Current Config: {json.dumps(prefs, indent=2)}")

if __name__ == "__main__":
    main()
