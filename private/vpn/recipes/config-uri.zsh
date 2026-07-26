# Prints the current tunnel as an olcrtc:// URI — what olcbox and the Android
# client import. Re-run after rotating the room and re-import on each device.
room=$(./mac secret get olcrtc-room) || exit 1
key=$(./mac secret get olcrtc-key)   || exit 1
tmpl=private/vpn/config/olcrtc/client.yaml.tmpl
auth=$(sed -n 's/^  provider: //p' "$tmpl" | head -1)
transport=$(sed -n 's/^  transport: //p' "$tmpl" | head -1)
roomurl=$(sed -n 's/^  id: "\(.*\)"/\1/p' "$tmpl" | head -1)
roomurl="${roomurl//\{\{olcrtc-room\}\}/$room}"
print -r -- "olcrtc://${auth}?${transport}@${roomurl}#${key}\$mac_setup"
