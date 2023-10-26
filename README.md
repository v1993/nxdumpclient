# NX Dump Client

## A client for dumping over USB with [nxdumptool](https://github.com/DarkMatterCore/nxdumptool)

![screenshot](data/screenshot-1.png)

Not much to say, really - it just works!

### Official nxdumptool discord server where I and other helpful people can be found: https://discord.gg/SCbbcQx

## Building

```bash
git clone https://github.com/v1993/nxdumpclient.git
cd nxdumpclient
meson setup --buildtype=release -Db_lto=true -Denforce_build_order=true --prefix=/usr build
meson compile -C build
meson install -C build
```

Please note that a fairly fresh distro is required.

An alternative to direct installation is to use flatpak manifest stored at `flatpak/org.v1993.NXDumpClient.yml` (please note that building with flatpak requires initializing submodules; they are not used otherwise).

I'll look into publishing on flathub (and likely AUR) once I get version 1.0 out, which should trivialize installation.

### Dependencies

* GTK >= 4.10
* libadwaita >= 1.4
* GLib >= 2.76
* GUsb (reasonably new)
* libportal (optional)

Or, once again, use `flatpak-builder`, which will take care of installing everything required as part of the build.

## Frequently asked questions

### Where are the dumps stored?

By default in your Downloads folder. You can change path (and a couple of other handy settings) in preferences.

### NSP/NCA dumps always abort with checksum error

Additional verification is implemented compared to official `nxdt_host.py` program for those file types. An unfortunate side effect of this is that dumping with most non-default options will lead to checksum failure (since it modifies file contents but not initial checksum).

You can either dump with default settings (which you probably should be doing anyways) or disable additional verification in preferences.

### I get permissions error. Why?

Installing a udev rule is required for user access to device. You should have been prompted to do so interactively on first launch if using flatpak and system-wide installation does this automatically. Please report an issue if you think udev rules should have been installed by now and make sure to mention installation method in your report.
