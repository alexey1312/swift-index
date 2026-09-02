#!/bin/sh
# SwiftIndex installer.
#
#   curl -fsSL https://raw.githubusercontent.com/alexey1312/swift-index/main/scripts/install.sh | sh
#
# Environment:
#   SWIFTINDEX_VERSION       Version to install (default: latest release)
#   SWIFTINDEX_INSTALL_DIR   Install directory (default: $HOME/.local/bin)

set -eu

REPO="alexey1312/swift-index"
INSTALL_DIR="${SWIFTINDEX_INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${SWIFTINDEX_VERSION:-latest}"
ASSET="swiftindex-macos.zip"

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# --- Platform guards -------------------------------------------------------
# SwiftIndex is Apple-Silicon-only; failing here is far clearer than a binary
# that will not launch.
[ "$(uname -s)" = "Darwin" ] || fail "SwiftIndex requires macOS (found $(uname -s))."
[ "$(uname -m)" = "arm64" ] || fail "SwiftIndex requires Apple Silicon (found $(uname -m))."

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 14 ] || fail "SwiftIndex requires macOS 14 or later."
if [ "$MACOS_MAJOR" -lt 15 ]; then
    printf 'warning: the default CPU embedding provider requires macOS 15+.\n' >&2
    printf '         On macOS 14, use MLX: swiftindex index --provider mlx\n' >&2
fi

command -v curl >/dev/null 2>&1 || fail "curl is required."
command -v unzip >/dev/null 2>&1 || fail "unzip is required."

# --- Resolve version -------------------------------------------------------
if [ "$VERSION" = "latest" ]; then
    printf 'Resolving latest release...\n'
    # Parse tag_name without depending on jq.
    VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1)"
    [ -n "$VERSION" ] || fail "Could not determine the latest release."
fi

BASE_URL="https://github.com/$REPO/releases/download/$VERSION"
printf 'Installing SwiftIndex %s to %s\n' "$VERSION" "$INSTALL_DIR"

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# --- Download and verify ---------------------------------------------------
curl -fsSL -o "$TMPDIR_WORK/$ASSET" "$BASE_URL/$ASSET" \
    || fail "Failed to download $BASE_URL/$ASSET"

# A curl|sh installer with no integrity check is exactly the thing people are
# right to object to, so the checksum is verified rather than assumed.
if curl -fsSL -o "$TMPDIR_WORK/$ASSET.sha256" "$BASE_URL/$ASSET.sha256" 2>/dev/null; then
    EXPECTED="$(cut -d' ' -f1 <"$TMPDIR_WORK/$ASSET.sha256")"
    ACTUAL="$(shasum -a 256 "$TMPDIR_WORK/$ASSET" | cut -d' ' -f1)"
    [ "$EXPECTED" = "$ACTUAL" ] || fail "Checksum mismatch (expected $EXPECTED, got $ACTUAL)."
    printf 'Checksum verified.\n'
else
    fail "No checksum published for $VERSION; refusing to install unverified binary."
fi

unzip -q -o "$TMPDIR_WORK/$ASSET" -d "$TMPDIR_WORK/extracted"
mkdir -p "$INSTALL_DIR"

# --- Install ---------------------------------------------------------------
BIN_SRC="$(find "$TMPDIR_WORK/extracted" -type f -name swiftindex -perm -u+x | head -n 1)"
[ -n "$BIN_SRC" ] || fail "Archive did not contain a swiftindex binary."
install -m 0755 "$BIN_SRC" "$INSTALL_DIR/swiftindex"

# The Metal libraries must sit beside the binary or MLX embeddings cannot load.
# Forgetting them is the single most common broken manual install.
SRC_DIR="$(dirname "$BIN_SRC")"
for lib in default.metallib mlx.metallib; do
    if [ -f "$SRC_DIR/$lib" ]; then
        install -m 0644 "$SRC_DIR/$lib" "$INSTALL_DIR/$lib"
    else
        printf 'warning: %s missing from the archive; MLX embeddings will be unavailable.\n' "$lib" >&2
    fi
done

# Downloaded archives are quarantined; without this Gatekeeper kills the binary.
xattr -d com.apple.quarantine "$INSTALL_DIR/swiftindex" 2>/dev/null || true

printf '\nInstalled swiftindex %s\n' "$VERSION"

case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
        printf '\n%s is not on your PATH. Add it with:\n\n' "$INSTALL_DIR"
        case "${SHELL:-}" in
            */zsh) printf '  echo '"'"'export PATH="%s:$PATH"'"'"' >> ~/.zshrc\n' "$INSTALL_DIR" ;;
            */bash) printf '  echo '"'"'export PATH="%s:$PATH"'"'"' >> ~/.bash_profile\n' "$INSTALL_DIR" ;;
            *) printf '  export PATH="%s:$PATH"\n' "$INSTALL_DIR" ;;
        esac
        ;;
esac

printf '\nNext steps:\n'
printf '  swiftindex index      # build the index (no configuration required)\n'
printf '  swiftindex install    # register with your AI coding agents\n'
printf '  swiftindex status     # check configuration and index health\n'
