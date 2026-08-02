requires=()

run xcode-clt why="Command Line Tools — nothing compiles without them" \
    check='xcode-select -p' \
    apply='xcode-select --install' \
    irreversible="the CLT are an OS component; removing them would break every build on the machine"

run rosetta why="x86-only apps (AmneziaVPN) need Rosetta 2" \
    check='/usr/bin/pgrep -q oahd' \
    apply='softwareupdate --install-rosetta --agree-to-license' sudo=1 \
    irreversible="Rosetta is installed by the OS updater and has no supported removal"

run codesign-cert why="a stable signing identity keeps TCC grants across rebuilds" \
    check='security find-identity -p codesigning 2>/dev/null | grep -q mac-setup-codesign' \
    apply='zsh recipes/codesign-cert.zsh' \
    irreversible="deleting the identity would revoke every TCC grant tied to the apps it signed"
