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

> **Compatibility:** Tested on the PocketBook Era Lite **PB710** running firmware **6.10.x**.

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

KOReader is the centerpiece of ZenReader.

Support for the PB710 was manually added by adapting:

```text
applications/koreader/frontend/device/pocketbook/device.lua
```

This work is based on [KOReader pull request #15415](https://github.com/koreader/koreader/pull/15415).

The functional additions to KOReader are limited to the following three plugins.

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

#### Application name

The default `@koreader` label was renamed to `KOReader` in:

```text
system/language/en.txt
```

