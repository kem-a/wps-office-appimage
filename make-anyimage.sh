#!/bin/sh
#
# Build a portable AppImage of WPS Office (Chinese edition) using sharun
# infrastructure (uruntime + dwarfs) via quick-sharun.
#
# WPS ships its own Qt and runtime libraries inside /opt/kingsoft/wps-office/
# with $ORIGIN-relative RPATHs, so we deliberately skip lib4bin/quick-sharun
# binary deployment (which would duplicate or break the bundled stack) and
# only use quick-sharun's --make-appimage stage to assemble the AppImage.
#
# Single AppImage with arg-based dispatch:
#   ./WPS-Office-*.AppImage              # launches Writer (wps)
#   ./WPS-Office-*.AppImage et   FILE    # Spreadsheets
#   ./WPS-Office-*.AppImage wpp  FILE    # Presentation
#   ./WPS-Office-*.AppImage wpspdf FILE  # PDF
#
# Or rename/symlink the AppImage to wps/et/wpp/wpspdf to dispatch by argv0.
#
# Run on Fedora/Debian/etc.: re-execs inside an Arch Linux podman container
# for reproducible builds. Run inside Arch directly: skips bootstrap.

set -eu

CONTAINER_IMAGE="ghcr.io/pkgforge-dev/archlinux:latest"
CONTAINER_NAME="wps-office-anylinux-build"

# ── Container bootstrap ─────────────────────────────────────────────
_inside_arch() {
    [ -f /etc/arch-release ] 2>/dev/null
}

if ! _inside_arch; then
    if ! command -v podman >/dev/null 2>&1; then
        echo "Error: podman is required to build outside of Arch Linux." >&2
        echo "Install it with your package manager, e.g.:" >&2
        echo "  sudo dnf install podman   # Fedora" >&2
        echo "  sudo apt install podman   # Debian/Ubuntu" >&2
        exit 1
    fi

    if ! podman image exists "$CONTAINER_IMAGE" 2>/dev/null; then
        printf "Arch container image not found locally.\n"
        printf "Pull %s? [Y/n] " "$CONTAINER_IMAGE"
        read -r answer </dev/tty || answer=""
        case "$answer" in
            [nN]*) echo "Aborted."; exit 1 ;;
        esac
        podman pull "$CONTAINER_IMAGE"
    fi

    if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
        echo "=== Reusing existing Arch container ($CONTAINER_NAME) ==="
        exec podman start -ai "$CONTAINER_NAME"
    else
        echo "=== Creating Arch container ($CONTAINER_NAME) ==="
        exec podman run \
            -v "$PWD":/src:Z \
            -w /src \
            --name "$CONTAINER_NAME" \
            "$CONTAINER_IMAGE" \
            sh make-anyimage.sh
    fi
fi

# ── From here we are inside Arch Linux ──────────────────────────────

ARCH=$(uname -m)
QUICK_SHARUN_URL="https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/refs/heads/main/useful-tools/quick-sharun.sh"

echo "=== Installing build dependencies ==="
pacman -Syu --noconfirm \
    coreutils \
    sed \
    grep \
    gawk \
    curl \
    wget \
    dpkg \
    zsync \
    file

# ── Paths ───────────────────────────────────────────────────────────
BASE_DIR="$PWD/build"
DOWNLOAD_DIR="$BASE_DIR/raw"
EXTRACT_DIR="$BASE_DIR/raw"
APPDIR="$BASE_DIR/AppDir"
OUTPATH="$BASE_DIR/dist"
mkdir -p "$DOWNLOAD_DIR" "$OUTPATH"

# ── Resolve latest CHN .deb URL ─────────────────────────────────────
load_source() {
    previous_lock=$(cat .source.lock 2>/dev/null || echo)
    LOCK_CHN_URL=$(echo "$previous_lock" | grep -m1 '^CHN:' | sed 's/^CHN: //')

    echo "Fetching latest version from linux.wps.cn..."
    download_page=$(curl -sL 'https://linux.wps.cn' || true)
    NEW_CHN_URL=$(echo "$download_page" \
        | grep -Po "(?<=['\"])http.+?_amd64.deb(?=['\"])" \
        | sort -u)

    if [ "$(echo "$NEW_CHN_URL" | wc -l)" -eq 1 ] && [ -n "$NEW_CHN_URL" ]; then
        CHN_DEB_URL="$NEW_CHN_URL"
    elif [ -n "$LOCK_CHN_URL" ]; then
        echo "Remote fetch failed, using lock file URL."
        CHN_DEB_URL="$LOCK_CHN_URL"
    else
        echo "ERROR: unable to determine CHN deb URL." >&2
        exit 1
    fi

    LATEST_VERSION=$(echo "$CHN_DEB_URL" | grep -Po '(?<=_)(\d+\.)+\d+(?=[_.])')
    if [ -z "$LATEST_VERSION" ]; then
        echo "ERROR: cannot parse version from $CHN_DEB_URL" >&2
        exit 1
    fi

    new_lock=$(printf '%s\nCHN: %s\n' "$LATEST_VERSION" "$CHN_DEB_URL")
    if [ "$new_lock" != "$previous_lock" ]; then
        printf '%s' "$new_lock" > .source.lock
    fi

    CHN_DEB_FILENAME=$(basename "$CHN_DEB_URL")
    CHN_DEB_TRIPLE=$(echo "$CHN_DEB_FILENAME" | sed 's/\.deb$//')
    CHN_DEB_FILE="$DOWNLOAD_DIR/$CHN_DEB_FILENAME"
    EXTRACT_PATH="$EXTRACT_DIR/$CHN_DEB_TRIPLE"

    # Sign the download URL (per AUR wps-office-cn PKGBUILD).
    uri=$(echo "$CHN_DEB_URL" | sed 's#https://wps-linux-personal.wpscdn.cn##')
    secrityKey='7f8faaaa468174dc1c9cd62e5f218a5b'
    timestamp10=$(date '+%s')
    md5hash=$(printf '%s%s%s' "$secrityKey" "$uri" "$timestamp10" | md5sum | cut -d' ' -f1)
    SIGNED_CHN_URL="$CHN_DEB_URL?t=$timestamp10&k=$md5hash"

    echo "Version:  $LATEST_VERSION"
    echo "URL:      $CHN_DEB_URL"
}

download() {
    if [ -f "$2" ]; then
        echo "Already downloaded: $2"
        return 0
    fi
    if command -v aria2c >/dev/null 2>&1; then
        aria2c -c -j8 -x8 -s8 -d "$(dirname "$2")" -o "$(basename "$2")" "$1"
    else
        wget -c --tries=10 --show-progress -O "$2" "$1"
    fi
}

extract() {
    if [ -d "$2" ]; then
        echo "Already extracted: $2"
        return 0
    fi
    mkdir -p "$2"
    dpkg-deb -R "$1" "$2/"
}

load_source
download "$SIGNED_CHN_URL" "$CHN_DEB_FILE"
extract "$CHN_DEB_FILE" "$EXTRACT_PATH"

# ── Build AppDir from extracted deb ─────────────────────────────────
echo "=== Building AppDir ==="
rm -rf "$APPDIR"
mkdir -p "$APPDIR"
cp -al "$EXTRACT_PATH/usr" "$APPDIR/usr"
cp -al "$EXTRACT_PATH/opt" "$APPDIR/opt"

# WPS ships libstdc++.so.6.0.32 (GCC 13 / CXXABI_1.3.14) and libgcc_s.so.1.
# On modern hosts (Fedora 43+ etc.) the system mesa/libva drivers need
# CXXABI_1.3.15 (GCC 14+); when those drivers dlopen into a process that has
# already loaded WPS's older bundled copy, they fail and crash the GUI. The
# libstdc++ ABI is backward-compatible, so the host's newer copy works for
# WPS too — let the dynamic linker resolve them from the host.
echo "=== Stripping bundled libstdc++/libgcc_s ==="
rm -f "$APPDIR/opt/kingsoft/wps-office/office6"/libstdc++.so* \
      "$APPDIR/opt/kingsoft/wps-office/office6"/libgcc_s.so*

# ── Patch wrapper scripts ───────────────────────────────────────────
# 1. Make gInstallPath relative to the wrapper (so WPS finds its bundled
#    libs inside the mounted AppImage rather than at /opt on the host).
# 2. Source fcitx5xwayland.sh shim for IM support on Wayland.
echo "=== Patching wrapper scripts ==="

cp src/fcitx5xwayland.sh \
   "$APPDIR/opt/kingsoft/wps-office/office6/fcitx5xwayland.sh"

for cmd in wps et wpp wpspdf; do
    wrapper="$APPDIR/usr/bin/$cmd"
    [ -f "$wrapper" ] || continue

    # Preserve the upstream shebang (#!/bin/bash — the wrappers use bash arrays
    # and `function` syntax). Inject the relocation prelude after it. Strip the
    # `> /dev/null 2>&1` redirects so that `WPS_DEBUG=1` shows the binary's real
    # output; otherwise the prelude redirects everything to /dev/null itself.
    {
        head -n 1 "$wrapper"
        cat <<'PRELUDE'
currdir=$(dirname "$(readlink -f "$0")")
. "$currdir/../../opt/kingsoft/wps-office/office6/fcitx5xwayland.sh"
[ -n "${WPS_DEBUG:-}" ] || exec >/dev/null 2>&1
PRELUDE
        sed \
            -e '1d' \
            -e 's#gInstallPath=/opt/kingsoft/wps-office#gInstallPath="$currdir/../../opt/kingsoft/wps-office"#' \
            -e 's#> /dev/null 2>&1##g' \
            "$wrapper"
    } > "$wrapper.new"
    mv "$wrapper.new" "$wrapper"
    chmod +x "$wrapper"
done

# Rewrite hardcoded `Exec=/usr/bin/<cmd>` paths in the bundled .desktop files
# to bare command names. Absolute host paths break "Open with…" because the
# host has no /usr/bin/wps; bare names let appimaged / xdg-desktop-menu
# substitute the AppImage path (or a same-directory argv[0] symlink) on
# integration. Done here so the umbrella copy at AppDir root inherits the fix.
echo "=== Patching desktop entries ==="
for desktop in "$APPDIR/usr/share/applications"/wps-office-*.desktop; do
    [ -f "$desktop" ] || continue
    sed -i \
        -e 's#^Exec=/usr/bin/wps #Exec=wps #' \
        -e 's#^Exec=/usr/bin/et #Exec=et #' \
        -e 's#^Exec=/usr/bin/wpp #Exec=wpp #' \
        -e 's#^Exec=/usr/bin/wpspdf #Exec=wpspdf #' \
        "$desktop"
done

# ── Custom AppRun: dispatch to wps/et/wpp/wpspdf ────────────────────
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
APPDIR=$(cd "${0%/*}" && echo "$PWD")
ARG0="${ARGV0:-$0}"
unset ARGV0

_is_wps_cmd() {
    case "$1" in et|wpp|wps|wpspdf) return 0 ;; esac
    return 1
}

# Pick component by file extension so `./AppImage file.xlsx` routes to et,
# `./AppImage file.pptx` to wpp, etc. — instead of always defaulting to wps
# (which silently rejects non-Writer formats).
_pick_by_ext() {
    ext=${1##*.}
    case "$ext" in
        xls|xlsx|xlsm|xlsb|xlt|xltx|xltm|csv|et|ett|uos|uof) echo et ;;
        ppt|pptx|pptm|pps|ppsx|pot|potx|potm|dps|dpt|uop)    echo wpp ;;
        pdf)                                                  echo wpspdf ;;
        *)                                                    echo wps ;;
    esac
}

if _is_wps_cmd "${ARG0##*/}"; then
    BIN=${ARG0##*/}
elif _is_wps_cmd "$1"; then
    BIN=$1
    shift
else
    case "$1" in
        -h|--help|help)
            echo "Usage: $0 [wps|et|wpp|wpspdf] [FILE...]"
            echo "  wps     WPS Writer (default)"
            echo "  et      Spreadsheets"
            echo "  wpp     Presentation"
            echo "  wpspdf  PDF"
            exit 0
            ;;
        -v|--version)
            cat "$APPDIR/.appimage-version" 2>/dev/null || echo unknown
            exit 0
            ;;
    esac
    BIN=$(_pick_by_ext "${1:-}")
fi

exec "$APPDIR/usr/bin/$BIN" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

echo "$LATEST_VERSION" > "$APPDIR/.appimage-version"

# ── Pick a top-level desktop entry + icon ──────────────────────────
# wps-office-prometheus.desktop is the umbrella entry covering all four
# components, so it makes the natural top-level entry for the AppImage.
# Per-component entries (wps/et/wpp/pdf) stay under usr/share/applications.
DESKTOP_SRC="$APPDIR/usr/share/applications/wps-office-prometheus.desktop"
if [ ! -f "$DESKTOP_SRC" ]; then
    echo "ERROR: $DESKTOP_SRC not found in extracted deb." >&2
    exit 1
fi

ICON_FILE="$APPDIR/usr/share/icons/hicolor/scalable/apps/wps-office2023-kprometheus.svg"
if [ ! -f "$ICON_FILE" ]; then
    echo "ERROR: $ICON_FILE not found in extracted deb." >&2
    exit 1
fi

# Promote the umbrella desktop entry to AppDir root and drop the copy under
# usr/share/applications so it isn't shipped twice. quick-sharun's _get_desktop
# short-circuits when a top-level .desktop already exists, so this also pins
# our chosen entry against any auto-detection.
cp "$DESKTOP_SRC" "$APPDIR/$(basename "$DESKTOP_SRC")"
rm -f "$DESKTOP_SRC"

# ── Fetch quick-sharun and assemble the AppImage ───────────────────
if command -v quick-sharun >/dev/null 2>&1; then
    QS=quick-sharun
else
    wget --retry-connrefused --tries=30 "$QUICK_SHARUN_URL" -O /tmp/quick-sharun
    chmod +x /tmp/quick-sharun
    QS=/tmp/quick-sharun
fi

export ARCH
export VERSION="$LATEST_VERSION"
export APPDIR
export OUTPATH
export OUTNAME="WPS-Office-${LATEST_VERSION}-${ARCH}.AppImage"
export DESKTOP="$DESKTOP_SRC"
export ICON="$ICON_FILE"
export UPINFO="${UPINFO:-gh-releases-zsync|kem-a|wps-office-appimage|latest|*${ARCH}.AppImage.zsync}"

echo "=== Assembling AppImage with quick-sharun --make-appimage ==="
"$QS" --make-appimage

rm -f "$OUTPATH"/appinfo

echo
echo "=== AppImage built ==="
echo "Output: $OUTPATH/$OUTNAME"
