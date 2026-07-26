# Renders the server config with secrets filled in, to stdout only.
# Recipes run as their own process, so secrets come through the mac CLI —
# engine functions are not in scope here.
src="private/vpn/config/olcrtc/server.yaml.tmpl"
content=$(<"$src")
for ph in ${(f)"$(grep -o '{{[a-zA-Z0-9_-]\{1,\}}}' "$src" | sort -u)"}; do
    name="${${ph#\{\{}%\}\}}"
    val=$(./mac secret get "$name") || { print -u2 "no value for $ph"; exit 1 }
    [[ -n "$val" ]] || { print -u2 "empty value for $ph"; exit 1 }
    content="${content//"$ph"/$val}"
done
grep -q '^mode: srv' <<< "$content" || { print -u2 "rendered config lost its mode"; exit 1 }
print -r -- "$content"
