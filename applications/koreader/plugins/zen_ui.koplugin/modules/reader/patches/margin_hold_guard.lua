local function apply_margin_hold_guard()
    --[[
        Swallows onHold gestures inside page margin areas to prevent
        accidental word selection (CRE/EPUB only; PDF left untouched).
        Left/right margins always guarded; top/bottom only in page (not scroll) mode.
    --]]

    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local Device = require("device")
    local Screen = Device.screen

    local _onHold_orig = ReaderHighlight.onHold

    ReaderHighlight.onHold = function(self, arg, ges)
        -- PDF / DjVu / CBZ – do not interfere.
        if self.ui.paging then
            return _onHold_orig(self, arg, ges)
        end

        local ok, margins = pcall(function()
            return self.ui.document:getPageMargins()
        end)

        if ok and type(margins) == "table" then
            local x  = ges.pos.x
            local y  = ges.pos.y
            local sw = Screen:getWidth()
            local sh = Screen:getHeight()

            -- Horizontal margins (left / right) – reliable in every view mode.
            local left  = margins["left"]  or 0
            local right = margins["right"] or 0
            if x < left or x > sw - right then
                return false
            end

            -- Vertical margins (top / bottom) – only in page mode.
            if self.view and self.view.view_mode == "page" then
                local top    = margins["top"]    or 0
                local bottom = margins["bottom"] or 0
                if y < top or y > sh - bottom then
                    return false
                end
            end
        end

        return _onHold_orig(self, arg, ges)
    end
end

return apply_margin_hold_guard
