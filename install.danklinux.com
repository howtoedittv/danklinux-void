#!/usr/bin/env bash

set -e

# =========================
# Colors for output
# =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# =========================
# Sanity checks
# =========================

# Must not be root
if [ "$(id -u)" = "0" ]; then
    printf "%bError: This script must not be run as root%b\n" "$RED" "$NC"
    exit 1
fi

# Linux only
if [ "$(uname -s)" != "Linux" ]; then
    printf "%bError: This installer only supports Linux systems%b\n" "$RED" "$NC"
    exit 1
fi

# Void Linux only
if [ ! -f /etc/os-release ]; then
    printf "%bError: Could not detect operating system%b\n" "$RED" "$NC"
    exit 1
fi

. /etc/os-release

if [ "$ID" != "void" ]; then
    printf "%bError: This installer only supports Void Linux (glibc)%b\n" "$RED" "$NC"
    printf "Detected OS: %s\n" "${NAME:-unknown}"
    exit 1
fi

# Fail explicitly on Void musl
if ldd --version 2>&1 | grep -qi musl; then
    printf "%bError: Void Linux musl is not supported%b\n" "$RED" "$NC"
    printf "Please use Void Linux (glibc)\n"
    exit 1
fi

# =========================
# Detect architecture
# =========================
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64)
        ARCH="arm64"
        ;;
    *)
        printf "%bError: Unsupported architecture: %s%b\n" "$RED" "$ARCH" "$NC"
        printf "Supported: x86_64 (amd64), aarch64 (arm64)\n"
        exit 1
        ;;
esac

# =========================
# Fetch latest release
# =========================
LATEST_VERSION=$(
    wget -qO- https://api.github.com/repos/AvengeMedia/DankMaterialShell/releases/latest \
    | grep '"tag_name"' \
    | head -n1 \
    | cut -d '"' -f4
)

if [ -z "$LATEST_VERSION" ]; then
    printf "%bError: Could not fetch latest version%b\n" "$RED" "$NC"
    exit 1
fi

printf "%bInstalling Dankinstall %s for Void Linux (glibc, %s)...%b\n" \
    "$GREEN" "$LATEST_VERSION" "$ARCH" "$NC"

# =========================
# Download & install
# =========================
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

printf "%bDownloading installer...%b\n" "$GREEN" "$NC"

wget -O installer.gz \
    "https://github.com/AvengeMedia/DankMaterialShell/releases/download/$LATEST_VERSION/dankinstall-$ARCH.gz"

wget -O expected.sha256 \
    "https://github.com/AvengeMedia/DankMaterialShell/releases/download/$LATEST_VERSION/dankinstall-$ARCH.gz.sha256"

# =========================
# Verify checksum
# =========================
EXPECTED_CHECKSUM=$(awk '{print $1}' expected.sha256)

printf "%bVerifying checksum...%b\n" "$GREEN" "$NC"
ACTUAL_CHECKSUM=$(sha256sum installer.gz | awk '{print $1}')

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    printf "%bError: Checksum verification failed%b\n" "$RED" "$NC"
    printf "Expected: %s\n" "$EXPECTED_CHECKSUM"
    printf "Got:      %s\n" "$ACTUAL_CHECKSUM"
    printf "The downloaded file may be corrupted or tampered with\n"
    cd - >/dev/null
    rm -rf "$TEMP_DIR"
    exit 1
fi

# =========================
# Decompress & run
# =========================
printf "%bDecompressing installer...%b\n" "$GREEN" "$NC"
gunzip installer.gz
chmod +x installer

printf "%bRunning installer...%b\n" "$GREEN" "$NC"
./installer

# =========================
# Cleanup
# =========================
cd - >/dev/null
rm -rf "$TEMP_DIR"
