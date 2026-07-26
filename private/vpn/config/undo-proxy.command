#!/bin/zsh
# Turns the tunnel off. Needs no network, no repo and no mac_setup — if
# everything else is broken, double-clicking this is still enough.
echo "Stopping the tunnel…"
sudo launchctl bootout system/com.mac-setup.sing-box 2>/dev/null
launchctl bootout gui/$UID/com.mac-setup.olcrtc 2>/dev/null
sudo pkill -x sing-box 2>/dev/null
pkill -x olcrtc 2>/dev/null
sudo route -n delete -net 1.0.0.0/8 2>/dev/null
echo "Done. Networking is back to normal."
echo "Press return to close."
read
