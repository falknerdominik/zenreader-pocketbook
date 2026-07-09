-- randomphotoscreen.koplugin
-- KOReader plugin for PocketBook devices.
--
-- Picks a random image from the device Photos/Pictures folders, renders it in
-- memory, scales it to the current screen size, and writes it directly as BMP to
-- known PocketBook lock/sleep/power-off image paths. It does not use temporary
-- files.
--
-- Fast path:
--   The first update scans the configured photo folders and builds an in-memory
--   cache. Later updates pick a random array index from that cache instead of
--   rescanning the filesystem. This keeps suspend/resume updates much faster
--   while KOReader stays open.

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Device = require("device")

if not Device.isPocketBook() then
    return { disabled = true }
end

local Screen = Device.screen
local RenderImage = require("ui/renderimage")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")

local RandomPhotoScreen = WidgetContainer:extend{
    name = "randomphotoscreen",
    is_doc_only = false,
}

-- Edit these paths if your device stores photos somewhere else.
-- /mnt/ext1 is the usual internal-storage mount point on PocketBook.
local IMAGE_DIRS = {
    "/mnt/ext1/Photos",
    "/mnt/ext1/photos",
    "/mnt/ext1/Photo",
    "/mnt/ext1/photo",
    "/mnt/ext1/Pictures",
    "/mnt/ext1/pictures",
}

-- Files this plugin tries to update.
-- Different PocketBook firmware versions use different files/settings:
--   * system/resources/Line/taskmgr_lock_background.bmp: task manager / lock background
--   * system/logo/bookcover: firmware 6.10 style "Book Cover" logo path
--   * system/logo/offlogo/cover.bmp: "Power-off Logo" / Random logo workaround path
local OUTPUT_FILES = {
    "/mnt/ext1/system/resources/Line/taskmgr_lock_background.bmp",
    "/mnt/ext1/system/logo/bookcover",
    "/mnt/ext1/system/logo/offlogo/cover.bmp",
}

local VALID_EXT = {
    jpg = true,
    jpeg = true,
    png = true,
    bmp = true,
    gif = true,
    webp = true,
}

-- Performance/configuration knobs.
-- CACHE_IMAGE_LIST means: scan once, then pick a random index from the cached
-- table for the rest of this KOReader session. This is the main speedup.
local CACHE_IMAGE_LIST = true

-- Rescan once every 24 hours while KOReader remains open so newly added or
-- removed photos are picked up without rescanning on every suspend/resume.
-- Set to 0 to disable periodic rescans.
local CACHE_RESCAN_INTERVAL_SECS = 24 * 60 * 60

-- Avoid pathological recursion on weird folder links/mounts.
local MAX_RECURSION_DEPTH = 8

-- If a random image cannot be decoded/scaled, remove it from the in-memory cache
-- and try another one, up to this many attempts.
local MAX_RENDER_ATTEMPTS = 10

local image_cache = nil
local image_cache_built_at = 0

local function path_exists(path)
    return lfs.attributes(path) ~= nil
end

local function is_dir(path)
    local attr = lfs.attributes(path)
    return attr and attr.mode == "directory"
end

local function dirname(path)
    return path:match("^(.*)/[^/]+$") or "."
end

local function mkdir_p(path)
    if not path or path == "" or path == "/" then
        return true
    end

    local current = ""
    for part in path:gmatch("[^/]+") do
        current = current .. "/" .. part
        if not path_exists(current) then
            local ok, err = lfs.mkdir(current)
            if not ok and not is_dir(current) then
                logger.warn("randomphotoscreen: cannot create directory ", current, ": ", err)
                return false
            end
        end
    end

    return true
end

local function lower_ext(filename)
    local ext = filename:match("%.([^%.]+)$")
    return ext and ext:lower() or nil
end

local function is_supported_image(filename)
    local ext = lower_ext(filename)
    return ext and VALID_EXT[ext] == true
end

local function collect_images_recursive(dir, images, depth)
    depth = depth or 0

    if depth > MAX_RECURSION_DEPTH then
        return
    end

    if not is_dir(dir) then
        return
    end

    local ok, iterator, state, first = pcall(lfs.dir, dir)
    if not ok or not iterator then
        logger.warn("randomphotoscreen: cannot list directory ", dir)
        return
    end

    for entry in iterator, state, first do
        if entry ~= "." and entry ~= ".." then
            local path = dir .. "/" .. entry
            local attr = lfs.attributes(path)
            if attr and attr.mode == "directory" then
                collect_images_recursive(path, images, depth + 1)
            elseif attr and attr.mode == "file" and is_supported_image(entry) then
                images[#images + 1] = path
            end
        end
    end
end

local function scan_images()
    local images = {}

    for _, dir in ipairs(IMAGE_DIRS) do
        collect_images_recursive(dir, images, 0)
    end

    return images
end

local function should_rebuild_cache()
    if not CACHE_IMAGE_LIST then
        return true
    end

    if not image_cache or #image_cache == 0 then
        return true
    end

    if CACHE_RESCAN_INTERVAL_SECS and CACHE_RESCAN_INTERVAL_SECS > 0 then
        local now = os.time()
        if now - image_cache_built_at >= CACHE_RESCAN_INTERVAL_SECS then
            return true
        end
    end

    return false
end

local function get_images()
    if should_rebuild_cache() then
        image_cache = scan_images()
        image_cache_built_at = os.time()
        logger.info("randomphotoscreen: image cache contains ", tostring(#image_cache), " image(s)")
    end

    return image_cache or {}
end

local function remove_cached_image(index)
    if image_cache and index and image_cache[index] then
        table.remove(image_cache, index)
    end
end

local function screen_dimensions()
    local width = Screen:getWidth()
    local height = Screen:getHeight()
    local rotation = Screen:getRotationMode()

    -- Match the reference PocketBook cover plugin behavior.
    if rotation == 1 or rotation == 3 then
        width, height = height, width
    end

    return width, height
end

local function random_seed()
    -- os.time alone repeats if several hooks fire in the same second. Add a
    -- process-clock component to reduce repeated picks without storing state.
    local seed = os.time() + math.floor(os.clock() * 1000000)
    math.randomseed(seed)
    -- Discard the first few values; this helps older Lua PRNGs after seeding.
    math.random(); math.random(); math.random()
end

local function pick_random_image(images)
    if #images == 0 then
        return nil, nil
    end

    local index = math.random(#images)
    return images[index], index
end

local function free_blitbuffer(blitbuffer)
    if blitbuffer and blitbuffer.free then
        pcall(function()
            blitbuffer:free()
        end)
    end
end

local function render_scaled_bmp_source(image_path, width, height)
    local ok, image = pcall(function()
        return RenderImage:renderImageFile(image_path, false, width, height)
    end)

    if not ok or not image then
        logger.warn("randomphotoscreen: failed to render image ", image_path)
        return nil
    end

    local scaled_ok, scaled = pcall(function()
        return RenderImage:scaleBlitBuffer(image, width, height)
    end)

    if not scaled_ok or not scaled then
        logger.warn("randomphotoscreen: failed to scale image ", image_path)
        return nil
    end

    return scaled
end

local function write_outputs(blitbuffer)
    local wrote_any = false

    for _, output in ipairs(OUTPUT_FILES) do
        local dir = dirname(output)
        if mkdir_p(dir) then
            local ok, result_or_err = pcall(function()
                return blitbuffer:writeToFile(output, "bmp", 100, false)
            end)

            -- BlitBuffer:writeToFile reports failure by returning false on some
            -- paths/errors, not only by throwing. Treat false as a real failure.
            if ok and result_or_err ~= false then
                wrote_any = true
                logger.info("randomphotoscreen: wrote ", output)
            else
                logger.warn("randomphotoscreen: failed to write ", output, ": ", tostring(result_or_err))
            end
        end
    end

    return wrote_any
end

function RandomPhotoScreen:update(reason)
    local images = get_images()
    if #images == 0 then
        logger.warn("randomphotoscreen: no images found in configured Photos/Pictures directories")
        return false
    end

    random_seed()

    local width, height = screen_dimensions()
    local attempts = math.min(#images, MAX_RENDER_ATTEMPTS)

    for _ = 1, attempts do
        local image_path, index = pick_random_image(images)
        if not image_path then
            break
        end

        local scaled = render_scaled_bmp_source(image_path, width, height)
        if scaled then
            local wrote_any = write_outputs(scaled)
            free_blitbuffer(scaled)
            if wrote_any then
                logger.info("randomphotoscreen: selected ", image_path, " for ", tostring(reason or "update"))
                return true
            end

            -- If rendering worked but no output path could be written, another
            -- random image will not fix permissions/path issues.
            break
        else
            -- Bad/corrupt/unsupported image: remove it from the in-memory cache
            -- so later updates do not keep retrying it.
            remove_cached_image(index)
            images = get_images()
        end
    end

    logger.warn("randomphotoscreen: failed to render/write a random image after ", attempts, " attempt(s)")
    return false
end

function RandomPhotoScreen:onReaderReady()
    self:update("reader ready")
end

function RandomPhotoScreen:onCloseDocument()
    self:update("close document")
end

function RandomPhotoScreen:onEndOfBook()
    self:update("end of book")
end

function RandomPhotoScreen:onSuspend()
    self:update("suspend")
end

function RandomPhotoScreen:onResume()
    self:update("resume")
end

return RandomPhotoScreen
