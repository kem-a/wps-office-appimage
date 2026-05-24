<!-- Core project info -->
[![Download](https://img.shields.io/badge/Download-latest-blue)](https://github.com/kem-a/wps-office-appimage/releases/latest)
[![Release](https://img.shields.io/github/v/release/kem-a/wps-office-appimage?semver)](https://github.com/kem-a/wps-office-appimage/releases/latest)
[![License](https://img.shields.io/github/license/kem-a/wps-office-appimage)](https://github.com/kem-a/wps-office-appimage/blob/main/LICENSE)
[![AnyLinux](https://img.shields.io/badge/AnyLinux-compatible-green?logo=linux&logoColor=white)](https://pkgforge-dev.github.io/Anylinux-AppImages/)
[![Stars](https://img.shields.io/github/stars/kem-a/wps-office-appimage?style=social)](https://github.com/kem-a/wps-office-appimage/stargazers)

# Unofficial WPS Office AppImage

Builds a portable AppImage of WPS Office **(Chinese edition)** using
[sharun](https://github.com/VHSgunzo/sharun) infrastructure
(`uruntime` + `dwarfs`) via
[`quick-sharun`](https://github.com/pkgforge-dev/Anylinux-AppImages).

The Chinese edition is used as the source because it ships full
`zh_CN` localization and the complete set of templates and dictionaries.

<img src="https://res-academy.cache.wpscdn.com/images/seo_posts/20230706/65692f1ceb3fdcbad777be45273b0baa.png" />

## /!\ Proprietary warning /!\

**WPS Office is proprietary software. Use at your own risk.**

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

## Debug

```sh
WPS_DEBUG=1 ./WPS-Office-*.AppImage et
```

## Official website

Chinese: [linux.wps.cn](https://linux.wps.cn)
International: [www.wps.com/office/linux/](https://www.wps.com/office/linux/)
