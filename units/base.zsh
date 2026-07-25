requires=()

run xcode-clt why="Command Line Tools — nothing compiles without them" \
    check='xcode-select -p' \
    apply='xcode-select --install'

run rosetta why="x86-only apps (AmneziaVPN) need Rosetta 2" \
    check='/usr/bin/pgrep -q oahd' \
    apply='softwareupdate --install-rosetta --agree-to-license' sudo=1

run codesign-cert why="a stable signing identity keeps TCC grants across rebuilds" \
    check='security find-identity -p codesigning 2>/dev/null | grep -q mac-setup-codesign' \
    apply='zsh recipes/codesign-cert.zsh'

manual xcode \
    do="Install Xcode from the App Store, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -license accept" \
    detect='xcodebuild -version'
