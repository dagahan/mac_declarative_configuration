source "${0:A:h}/env.zsh"
set -euo pipefail
cd "$BUILD_DIR"
./generate.sh --codesign-identity -
swift build -c release --arch arm64 --product aerospace
xcodebuild -project xcode/AeroSpace.xcodeproj -scheme AeroSpace \
    -configuration Release -derivedDataPath .xcbuild build
