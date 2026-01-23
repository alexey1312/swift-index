#!/bin/sh
# SwiftIndex installer
# https://github.com/alexey1312/swift-index
#
# Usage:
#   curl -fsSL https://alexey1312.github.io/swift-index/install.sh | sh
#
# Options (via environment):
#   VERSION   - specific version (default: latest)
#   PREFIX    - install directory (default: ~/.local/bin)
#
# Flags:
#   --uninstall  - remove swiftindex and metallibs
#   --help       - show this help
#
# Examples:
#   curl -fsSL https://alexey1312.github.io/swift-index/install.sh | sh
#   curl -fsSL https://alexey1312.github.io/swift-index/install.sh | VERSION=v0.1.0 sh
#   curl -fsSL https://alexey1312.github.io/swift-index/install.sh | PREFIX=/opt/bin sh
#   curl -fsSL https://alexey1312.github.io/swift-index/install.sh | sh -s -- --uninstall

set -e

REPO="alexey1312/swift-index"
GITHUB_API="https://api.github.com/repos/${REPO}"
GITHUB_RELEASES="https://github.com/${REPO}/releases"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

info() {
    printf "${BLUE}info${NC}: %s\n" "$1"
}

success() {
    printf "${GREEN}success${NC}: %s\n" "$1"
}

warn() {
    printf "${YELLOW}warn${NC}: %s\n" "$1"
}

error() {
    printf "${RED}error${NC}: %s\n" "$1" >&2
    exit 1
}

usage() {
    cat <<EOF
SwiftIndex Installer

Usage:
  curl -fsSL https://alexey1312.github.io/swift-index/install.sh | sh

Options (environment variables):
  VERSION    Install specific version (e.g., VERSION=v0.1.0)
  PREFIX     Install directory (default: ~/.local/bin)

Flags:
  --uninstall    Remove swiftindex and associated files
  --help         Show this help message

Examples:
  # Install latest version
  curl -fsSL https://alexey1312.github.io/swift-index/install.sh | sh

  # Install specific version
  curl -fsSL https://alexey1312.github.io/swift-index/install.sh | VERSION=v0.1.0 sh

  # Install to custom location
  curl -fsSL https://alexey1312.github.io/swift-index/install.sh | PREFIX=/opt/bin sh

  # Uninstall
  curl -fsSL https://alexey1312.github.io/swift-index/install.sh | sh -s -- --uninstall
EOF
}

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        *) error "SwiftIndex only supports macOS" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        arm64|aarch64) echo "arm64" ;;
        x86_64|amd64) echo "x86_64" ;;
        *) error "Unsupported architecture: $(uname -m)" ;;
    esac
}

get_latest_version() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${GITHUB_API}/releases/latest" 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "${GITHUB_API}/releases/latest" 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
    else
        error "Neither curl nor wget found. Please install one of them."
    fi
}

download() {
    url="$1"
    output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$output"
    else
        error "Neither curl nor wget found. Please install one of them."
    fi
}

verify_checksum() {
    file="$1"
    expected="$2"

    if [ -z "$expected" ]; then
        warn "Checksum not available, skipping verification"
        return 0
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | cut -d' ' -f1)
    else
        warn "No SHA256 tool found, skipping checksum verification"
        return 0
    fi

    if [ "$actual" != "$expected" ]; then
        error "Checksum verification failed!
Expected: $expected
Actual:   $actual

The downloaded file may be corrupted or tampered with."
    fi

    info "Checksum verified"
}

do_install() {
    OS=$(detect_os)
    ARCH=$(detect_arch)

    info "Detected: ${OS} ${ARCH}"

    # Determine version
    if [ -n "$VERSION" ]; then
        # Ensure version starts with 'v'
        case "$VERSION" in
            v*) ;;
            *) VERSION="v${VERSION}" ;;
        esac
    else
        info "Fetching latest version..."
        VERSION=$(get_latest_version)
        if [ -z "$VERSION" ]; then
            error "Failed to fetch latest version. Check your internet connection or specify VERSION manually."
        fi
    fi

    info "Installing swiftindex ${VERSION}"

    # Determine install directory
    INSTALL_DIR="${PREFIX:-$HOME/.local/bin}"

    # Create install directory if needed
    if [ ! -d "$INSTALL_DIR" ]; then
        info "Creating directory: ${INSTALL_DIR}"
        mkdir -p "$INSTALL_DIR"
    fi

    # Create temp directory
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    # Download URLs
    ASSET_URL="${GITHUB_RELEASES}/download/${VERSION}/swiftindex-macos.zip"
    CHECKSUM_URL="${GITHUB_RELEASES}/download/${VERSION}/checksums.txt"

    # Download checksum file
    info "Downloading checksums..."
    CHECKSUM_FILE="${TMP_DIR}/checksums.txt"
    if ! download "$CHECKSUM_URL" "$CHECKSUM_FILE" 2>/dev/null; then
        warn "Checksums file not available (older release?)"
        CHECKSUM_FILE=""
    fi

    # Extract expected checksum
    EXPECTED_CHECKSUM=""
    if [ -n "$CHECKSUM_FILE" ] && [ -f "$CHECKSUM_FILE" ]; then
        EXPECTED_CHECKSUM=$(grep "swiftindex-macos.zip" "$CHECKSUM_FILE" | cut -d' ' -f1)
    fi

    # Download archive
    info "Downloading swiftindex-macos.zip..."
    ARCHIVE="${TMP_DIR}/swiftindex-macos.zip"
    download "$ASSET_URL" "$ARCHIVE"

    # Verify checksum
    verify_checksum "$ARCHIVE" "$EXPECTED_CHECKSUM"

    # Extract archive
    info "Extracting..."
    unzip -q "$ARCHIVE" -d "${TMP_DIR}/extract"

    # Find and install files
    # The archive contains: swiftindex, default.metallib, mlx.metallib, LICENSE, README.md
    EXTRACT_DIR="${TMP_DIR}/extract"

    # Install binary
    if [ -f "${EXTRACT_DIR}/swiftindex" ]; then
        cp "${EXTRACT_DIR}/swiftindex" "${INSTALL_DIR}/swiftindex"
        chmod +x "${INSTALL_DIR}/swiftindex"
        success "Installed: ${INSTALL_DIR}/swiftindex"
    else
        error "Binary not found in archive"
    fi

    # Install metallib files (required for MLX embeddings)
    for metallib in default.metallib mlx.metallib; do
        if [ -f "${EXTRACT_DIR}/${metallib}" ]; then
            cp "${EXTRACT_DIR}/${metallib}" "${INSTALL_DIR}/${metallib}"
            success "Installed: ${INSTALL_DIR}/${metallib}"
        fi
    done

    # Check if install directory is in PATH
    case ":$PATH:" in
        *":${INSTALL_DIR}:"*) ;;
        *)
            warn "${INSTALL_DIR} is not in your PATH"
            echo ""
            echo "Add it to your shell configuration:"
            echo ""
            echo "  # For bash (~/.bashrc or ~/.bash_profile)"
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
            echo ""
            echo "  # For zsh (~/.zshrc)"
            echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
            echo ""
            echo "  # For fish (~/.config/fish/config.fish)"
            echo "  fish_add_path ~/.local/bin"
            echo ""
            ;;
    esac

    echo ""
    success "SwiftIndex ${VERSION} installed successfully!"
    echo ""
    echo "Get started:"
    echo "  swiftindex --version"
    echo "  swiftindex init"
    echo "  swiftindex index ."
    echo ""
    echo "Documentation: https://github.com/${REPO}"
}

do_uninstall() {
    INSTALL_DIR="${PREFIX:-$HOME/.local/bin}"

    info "Uninstalling swiftindex from ${INSTALL_DIR}"

    removed=0

    for file in swiftindex default.metallib mlx.metallib; do
        filepath="${INSTALL_DIR}/${file}"
        if [ -f "$filepath" ]; then
            rm "$filepath"
            success "Removed: ${filepath}"
            removed=$((removed + 1))
        fi
    done

    if [ $removed -eq 0 ]; then
        warn "No swiftindex files found in ${INSTALL_DIR}"
        echo ""
        echo "If installed elsewhere, specify PREFIX:"
        echo "  curl ... | PREFIX=/path/to/bin sh -s -- --uninstall"
    else
        echo ""
        success "SwiftIndex uninstalled"
        echo ""
        echo "Optional: Remove configuration and cached data"
        echo "  rm -rf ~/.swiftindex"
        echo "  rm -rf ~/.config/swiftindex"
    fi
}

main() {
    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --uninstall)
                do_uninstall
                exit 0
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $arg"
                ;;
        esac
    done

    do_install
}

main "$@"
