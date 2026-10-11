source "${0:A:h}/env.zsh"
set -euo pipefail
cd "$BUILD_DIR"
xcodebuild -workspace Easydict.xcworkspace -scheme Easydict -configuration Release \
    -derivedDataPath DerivedData \
    ASSETCATALOG_COMPILER_APPICON_NAME=Easydict-26 EXCLUDED_SOURCE_FILE_NAMES=Easydict-27.icon \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
