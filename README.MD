# ZenReader for PocketBook Era Lite

**ZenReader** bundles KOReader with Zen UI, private-cloud access, and native-looking PocketBook integration for the **PocketBook Era Lite (PB710)**.

It provides an easy-to-replicate setup with:

* KOReader and the simplified Zen UI.
* Private-cloud access through WebDAV or SFTP.
* Automatic WebDAV synchronization.
* PB710 device support.
* A custom `108 × 108` launcher icon.
* Proper `KOReader` naming in the PocketBook system.
* Random lock-screen images from `/Photos`.
* Documented system changes that others can reuse.

> **Compatibility:** Tested on the PocketBook Era Lite **PB710** running firmware **U710.6.11.2124**. For Firmware **U710.6.10.** use this repository at commit `05ea7c4`.

<p align="center">
  <strong>Did ZenReader save you setup time?</strong><br>
  Support continued testing, updates, and documentation.
</p>

<p align="center">
  <a href="https://www.buymeacoffee.com/dominikfalkner">
    <img
      src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png"
      alt="Buy me a coffee"
      width="217"
      height="60"
    >
  </a>
</p>

## Installation

> [!CAUTION]
> Back up your PocketBook before applying these files. Check for existing custom applications or configuration changes to avoid overwriting them.

Connect the PocketBook to your computer and copy the repository contents to the mounted device:

```bash
cp -r <source>/* <pocketbook-mount-point>/
```

## Included changes

### KOReader

No additional changes. Koreader Version 2026-07.

### Plugins

#### RandomGalleryLock

Implemented specifically for this repository.

Randomly selects an image from `/Photos` for use as the lock screen.

```text
applications/koreader/plugins/randomphotoscreen.koplugin
```

#### Zen UI

Provides the simplified ZenReader interface.

* Location: `applications/koreader/plugins/zen_ui.koplugin`
* Source: [AnthonyGress/zen_ui.koplugin](https://github.com/AnthonyGress/zen_ui.koplugin)

#### Auto WebDAV Sync

Provides automatic synchronization with a private WebDAV cloud.

* Location: `applications/koreader/plugins/webdav-autosync.koplugin`
* Source: [Alpha3288/webdav-autosync.koplugin](https://github.com/Alpha3288/webdav-autosync.koplugin)

KOReader's built-in SFTP support can also be used to access a private cloud.

### PocketBook integration

#### Custom icon

A custom launcher icon ensures KOReader is displayed correctly in the PocketBook system menu.

The icon was adapted from [KOReader Icon for PocketBook Devices](https://github.com/tmfsd/KOReader-Icon-for-PocketBook-Devices/tree/main) and upscaled to `108 × 108` pixels for the Era Lite.

The icon was added to the system menu in:

```text
system/config/desktop/view.json
```

## FAQ
### Why do I see both `KOReader` and `@_koreader` in the application list?

The `@_koreader` entry is usually caused by a hidden or stray KOReader launcher file in the PocketBook `applications` folder.

PocketBook scans this folder automatically and may create an additional launcher entry for that file, resulting in both:

- `KOReader`
- `@_koreader`

To fix it, open the `applications` folder on the device and delete the hidden/stray `@_koreader` file. Keep the `koreader.app` file.
