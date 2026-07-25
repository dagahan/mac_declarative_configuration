requires=()

# Everything that is not in the Brewfile: dmg/pkg/zip downloads, pinned in
# apps.lock. One line is enough — the rest is inferred on first contact.

app hiddify github=hiddify/hiddify-app asset=Hiddify-MacOS.dmg
