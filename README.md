# NX Dump Client

## A client for dumping over USB with [nxdumptool](https://github.com/DarkMatterCore/nxdumptool)

![GitHub Actions - Build Status](https://img.shields.io/github/actions/workflow/status/v1993/nxdumpclient/flatpak.yml)

[![AUR release package](https://img.shields.io/badge/aur-nxdumpclient-blue)](https://aur.archlinux.org/packages/nxdumpclient)
[![AUR git package](https://img.shields.io/badge/aur-nxdumpclient--git-blue)](https://aur.archlinux.org/packages/nxdumpclient-git)

[![Flathub Badge](https://dl.flathub.org/assets/badges/flathub-badge-i-en.png)](https://flathub.org/apps/org.v1993.NXDumpClient)

![screenshot](data/screenshot-1.png)

Not much to say, really - it just works! You can enable autostart in settings and leave it running in background if you so desire.

### Official nxdumptool discord server where I and other helpful people can be found: https://discord.gg/SCbbcQx

## Frequently asked questions

### What is the preferred installation method?

Short version: AUR (stable) package if you're on Arch-based distro, flatpak from Flathub otherwise. Installing flatpaks attached to releases is generally discouraged (these are provided for the sake of completeness) - please install from Flathub if possible instead.

Long version: Manual building or using unofficial packages may be viable options in non-Arch environments, but Manjaro/GNOME's Flatpak SDK (whichever is less up-to-date at the moment) is what ultimately determines what is the highest library version features from which I'll consider using. While I'm willing to support more distros natively, I won't be going out of my way to do so (a few tweaks to build system are fine, having to manually implement a feature present in newer version of a library/tool is not).

### Where are the dumps stored?

By default in your Downloads folder. You can change path (and a couple of other handy settings) in preferences.

### Why are there different NSP/NCA checksum modes and which one should I use?

A fragment of NCA's SHA256 checksum is contained within its filename, allowing to verify its contents. Among other possible file types, NSPs typically contain multiple NCAs as well as a list of filenames in their header (which is sent last during transfer). When dumping, the original name of NCA is sent with it, although it might not check out with its contents if certain dump options that modify them are enabled. However, nxdumptool later sends adjusted NCA names within NSP header.

* Compatible mode uses filenames from NSP header, so it will work correctly if NCAs are modified by nxdumptool, but can only detect errors after the transfer has finished.
* Strict mode uses original NCA filenames, so it can detect errors as soon as the NCA is transferred, but will erroneously fail if NCA was modified by nxdumptool.
* None, as its name implies, completely disables checksum computation and verification.

As a result, strict mode is recommended, but only if you do not use nxdumptool settings that mess with NCA contents -- which is almost everything save for "remove console specific data" and "generate authoringtool data". Compatible mode should be used if you, for whatever reason, want to use these options (hint: you probably don't). "None" should only be used in unorthodox cases like a badly named NCA file in a RomFS dump - files are hashed during transfer (i.e. never read back from drive) and checksum computation is very unlikely to have any meaningful impact on transfer speed.

P.S.: standalone NCAs are never tampered with, so strict mode check is used for them in both checksum modes. XCIs do not support additional verification.

### I get permissions error. Why?

Installing special udev rules is required for user access to device. You should have been prompted to do so interactively on first launch if using flatpak; system-wide installation installs rules automatically. Please report an issue if you think udev rules should have been installed by now - make sure to mention installation method in your report.

### Why does flatpak version require network access, anyways?

Because of how udev events are communicated on Linux. You can manually revoke it if you so desire, but that will break support for device hotplug - i.e. you'll have to always connect your switch before starting the program.

## Building

```bash
git clone https://github.com/v1993/nxdumpclient.git
cd nxdumpclient
meson setup --buildtype=debugoptimized -Db_lto=true -Denforce_build_order=true --prefix=/usr build
meson compile -C build
meson install -C build
```

Please note that a fairly recent distro is required - see dependencies section below.

An alternative to direct installation is to use flatpak manifest stored at `flatpak/org.v1993.NXDumpClient.yml` (please note that building with flatpak requires initializing git submodules; they are not used otherwise). Use of `flatpak-builder` is out-of-scope for this document - download pre-built package from Flathub if you just want to use the flatpak version.

### Updating

```bash
cd nxdumpclient
git pull
meson subprojects update
meson compile -C build
meson install -C build
```

Note for those using `flatpak-builder`: you'll want to update git submodules as well, but can skip updating meson subprojects.

### Dependencies

* GTK >= 4.10
* libadwaita >= 1.4
* GLib >= 2.76
* GUsb (reasonably new)
* libportal (optional for non-sandbox builds)
* blueprint-compiler >= 0.10 (build-only; automatically fetched by meson if not available)
