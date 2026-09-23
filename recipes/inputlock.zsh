source "${0:A:h}/env.zsh"
set -euo pipefail
cd "$BUILD_DIR"
swift build -c release --product InputLock
bundle=.build/InputLock.app
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/InputLock" "$bundle/Contents/MacOS/InputLock"
cp Info.plist "$bundle/Contents/Info.plist"
