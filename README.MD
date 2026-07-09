# PocketBook Era Lite (PB710)

Contains all modifications for this device. 

- *Easy install* by using `cp -r ...` onto the device. 
- *Document* all changes done to the system and how.
- *Provide* a starting point for others

## Changes

### KOReader

- Manually added support for the PB710 device (see: https://github.com/koreader/koreader/pull/15415)
  - Adapted: `applications/koreader/frontend/device/pocketbook/device.lua`
- Added icon
  - Adopted from: https://github.com/tmfsd/KOReader-Icon-for-PocketBook-Devices/tree/main
  - Upscaled icons for ERA lite (108x108)
  - Added icons to system menu (see: `system/config/desktop/view.json`)
- Renamed @koreader to KOReader
  - see: `system/language/en.txt`

#### Plugins

- Implemented RandomGalleryLock
  - Randomly selects from `/Photos` for lock screen
  - see: `applications/koreader/plugins/randomphotoscreen.koplugin`
- Added Zen UI
  - see: `applications/koreader/plugins/zen_ui.koplugin`
  - source: `https://github.com/AnthonyGress/zen_ui.koplugin`
- Added Auto Webdav Sync
  - see: `applications/koreader/plugins/webdav-autosync.koplugin`
  - source: `https://github.com/Alpha3288/webdav-autosync.koplugin`
