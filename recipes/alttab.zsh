source "${0:A:h}/env.zsh"
set -euo pipefail
cd "$BUILD_DIR"
xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -derivedDataPath DerivedData \
    CURRENT_PROJECT_VERSION="11.4.3-${BUILD_REF:0:8}" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
