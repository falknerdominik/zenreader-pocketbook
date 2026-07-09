# Random Photo Screen for KOReader / PocketBook

This PocketBook-only KOReader plugin picks a random image from the PocketBook Photos/Pictures folder, renders it in memory, scales it to the current screen size, and writes it directly as BMP to known PocketBook lock/sleep/power-off image paths.

It does **not** use temporary files.

## Faster image picking

The plugin now builds an in-memory image cache on the first update in a KOReader session. After that, it picks a random array index from the cached list instead of rescanning the filesystem every time.

That means:

- first update: scans your configured photo folders
- later suspend/resume/update events: random index lookup + decode one image + write outputs
- no temp files and no persistent cache file

If you add new photos while KOReader remains open, they will be picked up after the next 24-hour cache rescan, or immediately after restarting KOReader.

## Review notes

This build checks the return value from `BlitBuffer:writeToFile`, not just Lua exceptions. It also frees the rendered/scaled image buffer after writing to avoid accumulating full-screen image buffers during long KOReader sessions.

## What it writes

The plugin attempts to update all of these paths:

- `/mnt/ext1/system/resources/Line/taskmgr_lock_background.bmp`
- `/mnt/ext1/system/logo/bookcover`
- `/mnt/ext1/system/logo/offlogo/cover.bmp`

Different PocketBook firmware versions use different paths/settings, so writing all three gives the best chance of covering lock, sleep, and power-off logo behavior.

## Where it looks for images

By default it recursively scans:

- `/mnt/ext1/Photos`
- `/mnt/ext1/photos`
- `/mnt/ext1/Photo`
- `/mnt/ext1/photo`
- `/mnt/ext1/Pictures`
- `/mnt/ext1/pictures`

Supported extensions: `jpg`, `jpeg`, `png`, `bmp`, `gif`, `webp`.

## Install

1. Unzip this package.
2. Copy the folder `randomphotoscreen.koplugin` to:

   `applications/koreader/plugins/`

   You should end up with:

   `applications/koreader/plugins/randomphotoscreen.koplugin/main.lua`

3. Restart KOReader.
4. Open a book in KOReader.
5. Suspend/lock the device from KOReader.

The plugin updates on:

- reader ready
- close document
- end of book
- suspend
- resume

## PocketBook settings to try

Depending on firmware, try one of these PocketBook settings after installing:

- `Settings -> Personalize -> Logos -> Power-off Logo -> Book Cover`
- `Settings -> Personalize -> Logos -> Power-off Logo -> Random`

## Tuning

At the top of `main.lua`:

- `CACHE_IMAGE_LIST = true` keeps the image list in memory after the first scan.
- `CACHE_RESCAN_INTERVAL_SECS = 24 * 60 * 60` rebuilds the image list about once every 24 hours while KOReader is open.
- Set `CACHE_RESCAN_INTERVAL_SECS = 0` to disable periodic rescans, or `3600` to rescan about once per hour.
- `MAX_RENDER_ATTEMPTS = 10` controls how many random images are tried if some files cannot be decoded.

## Notes

- This is KOReader-specific. It rotates images while KOReader is running or involved in sleep/resume.
- It does not create a system-wide PocketBook daemon.
- Some PocketBook firmware may cache the image until a later suspend/resume or power cycle.
- To change image folders or output paths, edit the `IMAGE_DIRS` or `OUTPUT_FILES` arrays near the top of `main.lua`.
