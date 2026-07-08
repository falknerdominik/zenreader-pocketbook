local function apply_disable_top_menu_swipe_zones()
    local ReaderMenu = require("apps/reader/modules/readermenu")

    ReaderMenu._getTabIndexFromLocation = function(self, ges)
        return self.last_tab_index
    end

    local FileManagerMenu = require("apps/filemanager/filemanagermenu")

    FileManagerMenu._getTabIndexFromLocation = function(self, ges)
        return self.last_tab_index
    end
end

return apply_disable_top_menu_swipe_zones
