--[[
    browser_cover_rounded_corners.lua
    Paints white corner masks on mosaic covers for a rounded appearance.
    Toggled at runtime via config (no restart needed).
]]

local function apply_browser_cover_rounded_corners()
    local Blitbuffer = require("ffi/blitbuffer")
    local Screen     = require("device").screen

    -- Capture plugin reference at apply-time.
    local _plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    -- Restore corner pixels from a pre-paint background snapshot so the rounded
    -- cut-outs reveal whatever was behind the cover (page or library bg image)
    -- instead of an opaque white square. snap origin is absolute (ox, oy).
    local function paintCornerMasks(bb, tx, ty, tw, th, r, snap, ox, oy)
        for j = 0, r - 1 do
            local inner = math.sqrt(r * r - (r - j) * (r - j))
            local cut   = math.ceil(r - inner)
            if cut > 0 then
                -- top edge
                bb:blitFrom(snap, tx,            ty + j,          tx - ox,            ty + j - oy,          cut, 1)
                bb:blitFrom(snap, tx + tw - cut, ty + j,          tx + tw - cut - ox, ty + j - oy,          cut, 1)
                -- bottom edge
                bb:blitFrom(snap, tx,            ty + th - 1 - j, tx - ox,            ty + th - 1 - j - oy, cut, 1)
                bb:blitFrom(snap, tx + tw - cut, ty + th - 1 - j, tx + tw - cut - ox, ty + th - 1 - j - oy, cut, 1)
            end
        end
    end

    -- Redraw border arcs over the masked corners.
    local function paintCornerBorderArcs(bb, tx, ty, tw, th, r, bsz, color)
        local r_outer = r
        local r_inner = r - bsz
        for j = 0, r - 1 do
            for c = 0, r - 1 do
                local dx   = r - c - 0.5
                local dy   = r - j - 0.5
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist >= r_inner and dist <= r_outer then
                    bb:paintRect(tx + c,           ty + j,           1, 1, color)
                    bb:paintRect(tx + tw - 1 - c,  ty + j,           1, 1, color)
                    bb:paintRect(tx + c,           ty + th - 1 - j,  1, 1, color)
                    bb:paintRect(tx + tw - 1 - c,  ty + th - 1 - j,  1, 1, color)
                end
            end
        end
    end


    local function patchMosaicMenu()
        local MosaicMenu = require("mosaicmenu")
        if not MosaicMenu then return end

        local function get_upvalue(fn, name)
            if type(fn) ~= "function" then return nil end
            for i = 1, 128 do
                local upname, value = debug.getupvalue(fn, i)
                if not upname then break end
                if upname == name then return value end
            end
        end

        local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        if not MosaicMenuItem then return end

        -- Guard against double-patching (e.g. on FileManager re-layout).
        if MosaicMenuItem._zen_rounded_corners_patched then return end
        MosaicMenuItem._zen_rounded_corners_patched = true

        local orig_paintTo = MosaicMenuItem.paintTo
        if not orig_paintTo then return end

        local corner_radius = Screen:scaleBySize(8)

        -- Locate the cover FrameContainer for both book and folder items.
        --
        -- Book / standard folder (coverbrowser):
        --   self[1]       = _underline_container (outer FrameContainer)
        --   self[1][1]    = OverlapGroup (cover + shortcut icon)
        --   self[1][1][1] = cover FrameContainer  ← target
        --
        -- Folder cover (browser_folder_cover.lua):
        --   self[1]                = _underline_container
        --   self[1][1]             = OverlapGroup (widget from _setFolderCover)
        --   self[1][1][1]          = CenterContainer (image layer)   ← Layer 1
        --   self[1][1][1][1]       = inner OverlapGroup (dimen = dimen)
        --   self[1][1][1][1][1]    = image_widget FrameContainer  ← target
        --   self[1][1][2]          = TopContainer (tab lines layer)  ← Layer 2
        --
        -- Discriminator: FrameContainers always carry a `bordersize` field;
        -- other containers do not.
        local function find_cover_frame(item)
            local t = item[1] and item[1][1] and item[1][1][1]
            if not t then return nil end
            -- Standard path: FrameContainer (book cover or stock folder icon)
            if t.bordersize ~= nil then
                return t
            end
            -- browser_folder_cover path: Layer 1 is now a VerticalGroup.
            -- VerticalGroup[1] = VerticalSpan, VerticalGroup[2] = CenterContainer
            -- → [1] = inner OverlapGroup{dimen} → [1] = image_widget FrameContainer
            local inner = t[2] and t[2][1] and t[2][1][1]
            if inner and inner.bordersize ~= nil then
                return inner
            end
            return nil
        end

        function MosaicMenuItem:paintTo(bb, x, y)
            -- 0. Check live config first so we only snapshot when the feature is on.
            local plug = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
            local enabled = plug
                and type(plug.config) == "table"
                and type(plug.config.features) == "table"
                and plug.config.features.browser_cover_rounded_corners == true

            -- 1. Snapshot the background behind this item *before* painting the
            --    cover, so the corner cut-outs can reveal it (page or library bg
            --    image) instead of an opaque white square.
            local snap
            if enabled then
                local sz = self:getSize()
                local w, h = sz and sz.w, sz and sz.h
                if w and h and w > 0 and h > 0 then
                    snap = Blitbuffer.new(w, h, bb:getType())
                    snap:blitFrom(bb, 0, 0, x, y, w, h)
                end
            end

            -- 2. Full base painting (cover image + any previously applied overlays
            --    such as the badge patch).
            orig_paintTo(self, bb, x, y)

            if not enabled then
                if snap then snap:free() end
                return
            end

            -- 3. Locate the cover FrameContainer (book or folder).
            local target = find_cover_frame(self)
            if not (target and target.dimen
                and target.dimen.x and target.dimen.y
                and target.dimen.w and target.dimen.h
                and target.dimen.w > 0 and target.dimen.h > 0)
            then
                if snap then snap:free() end
                return
            end

            -- 4. Paint the four rounded corner masks, then redraw the border arc
            --    so the border looks unbroken around the rounded corners.
            local tx, ty = target.dimen.x, target.dimen.y
            local tw, th = target.dimen.w, target.dimen.h
            local bsz    = math.max(1, target.bordersize or 0)

            if snap then
                paintCornerMasks(bb, tx, ty, tw, th, corner_radius, snap, x, y)
                snap:free()
            end
            paintCornerBorderArcs(bb, tx, ty, tw, th, corner_radius, bsz, Blitbuffer.COLOR_BLACK)
        end
    end

    -- ── Hook FileManager:setupLayout (same pattern as browser_cover_badges) ───
    local FileManager      = require("apps/filemanager/filemanager")
    local orig_setupLayout = FileManager.setupLayout
    local patched          = false

    FileManager.setupLayout = function(self)
        orig_setupLayout(self)
        if not patched and self.coverbrowser then
            patchMosaicMenu()
            patched = true
        end
    end
end

return apply_browser_cover_rounded_corners
