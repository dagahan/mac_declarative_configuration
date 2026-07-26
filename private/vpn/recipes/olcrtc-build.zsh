set -e
cd "$BUILD_DIR"
mkdir -p build
go build -trimpath -ldflags="-s -w" -o build/olcrtc ./cmd/olcrtc
GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o build/olcrtc-linux-amd64 ./cmd/olcrtc
