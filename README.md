# WPS Office AppImage

Builds a portable AppImage of WPS Office (Chinese edition) using
[sharun](https://github.com/VHSgunzo/sharun) infrastructure
(`uruntime` + `dwarfs`) via
[`quick-sharun`](https://github.com/pkgforge-dev/Anylinux-AppImages).

The Chinese edition is used as the source because it ships full
`zh_CN` localization and the complete set of templates and dictionaries.

## Proprietary warning

WPS Office is proprietary software. Use at your own risk.

## Build

```sh
./make-anyimage.sh
```

On non-Arch hosts the script re-execs itself inside an Arch Linux
container (`ghcr.io/pkgforge-dev/archlinux:latest`) via `podman` for
reproducibility. On Arch hosts it runs directly. The container is reused
across runs (named `wps-office-anylinux-build`), so subsequent builds
skip the package install and `.deb` download.

The output lands at `build/dist/WPS-Office-<version>-x86_64.AppImage`.

## Use

The AppImage bundles all four WPS components in a single file and
dispatches by argument or by `argv[0]`:

```sh
./WPS-Office-*.AppImage              # WPS Writer (default)
./WPS-Office-*.AppImage et   FILE    # Spreadsheets
./WPS-Office-*.AppImage wpp  FILE    # Presentation
./WPS-Office-*.AppImage wpspdf FILE  # PDF
./WPS-Office-*.AppImage --help
```

Renaming or symlinking the AppImage to `wps`, `et`, `wpp`, or `wpspdf`
selects the matching component without an extra argument.

## What the build does

1. Resolves the latest CHN `.deb` URL from `linux.wps.cn` (signed with
   the AUR `wps-office-cn` security key, fallback to `.source.lock`).
2. Downloads and extracts the `.deb` into `build/raw/`.
3. Copies the contents into `build/AppDir/` via hard links.
4. Patches the `wps`, `et`, `wpp`, `wpspdf` wrapper scripts:
   * fallback `gInstallPath` rewritten to a path relative to the wrapper
     so WPS finds its bundled libraries inside the AppImage rather than
     at `/opt` on the host;
   * `src/fcitx5xwayland.sh` is sourced for IM support on Wayland.
5. Installs a custom `AppRun` that dispatches by `argv[0]` or `$1`.
6. Calls `quick-sharun --make-appimage` to assemble the AppImage with
   `dwarfs` compression and `uruntime`. WPS already ships its own Qt
   and runtime libraries inside `/opt/kingsoft/wps-office/` with
   `$ORIGIN`-relative `RPATH`s, so `lib4bin` deployment is intentionally
   skipped to avoid duplicating or breaking the bundled stack.

## Official website

Chinese: [linux.wps.cn](https://linux.wps.cn)
International: [www.wps.com/office/linux/](https://www.wps.com/office/linux/)

## Fonts

WPS Office for Linux used to be distributed with a set of fonts:
[wps-fonts](https://github.com/Rongronggg9/wps-fonts).

## Credits

Idea forked from [Rongronggg9/wps-office-repack](https://github.com/Rongronggg9/wps-office-repack)
and rebuilt entirely around an AppImage workflow instead of repacked
`.deb` packages.
