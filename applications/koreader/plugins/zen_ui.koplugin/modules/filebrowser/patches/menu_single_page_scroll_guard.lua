local function apply_menu_single_page_scroll_guard()
    -- Prevents a screen flash when the user swipes (or presses a page-turn key)
    -- on a Menu that has only one page.
    --
    -- Stock behaviour: onNextPage/onPrevPage always resolve to page 1 when
    -- page_num == 1, then call onGotoPage(1) → updateItems() → full repaint,
    -- which produces a visible flash even though nothing changed.
    --
    -- The fix: return immediately (consuming the event) when there is nothing to
    -- scroll.  This covers all entry points:
    --   • touch swipe east/west  (FileManager:onSwipeFM → onNextPage/onPrevPage)
    --   • Menu:onSwipe           (history, collections, other non-FM menus)
    --   • hardware page-turn keys (key_events.NextPage / PrevPage → same methods)
    --   • chevron buttons        (their callbacks call the same methods, though
    --                             they are disabled by updatePageInfo when nb==1)
    local Menu = require("ui/widget/menu")
    if Menu._zen_single_page_guard_patched then return end
    Menu._zen_single_page_guard_patched = true

    local orig_next = Menu.onNextPage
    local orig_prev = Menu.onPrevPage

    Menu.onNextPage = function(self)
        if (self.page_num or 1) <= 1 then return true end
        return orig_next(self)
    end

    Menu.onPrevPage = function(self)
        if (self.page_num or 1) <= 1 then return true end
        return orig_prev(self)
    end

    -- Guard FileChooser item taps for 1s after quickstart closes.
    local ok_fc, FileChooser = pcall(require, "ui/widget/filechooser")
    if ok_fc and not FileChooser._zen_tap_cooldown_patched then
        FileChooser._zen_tap_cooldown_patched = true
        local orig_select = FileChooser.onMenuSelect
        FileChooser.onMenuSelect = function(fc_self, item)
            if _G.__ZEN_QUICKSTART_JUST_CLOSED then return true end
            return orig_select and orig_select(fc_self, item)
        end
    end
end

return apply_menu_single_page_scroll_guard
