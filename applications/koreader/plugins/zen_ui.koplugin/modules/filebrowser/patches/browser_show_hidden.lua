local function apply_browser_show_hidden()
    -- When "show hidden outside home" is enabled, automatically enforce:
    --   • at or below home dir  → show_hidden = false, show_unsupported = false
    --   • outside home dir      → show_hidden = true, show_unsupported = true
    --
    -- Hook point: FileChooser:getList(), which is where lfs.dir is called and
    -- dot-files are filtered via the class-level field FileChooser.show_hidden.
    -- genItemTable only receives pre-filtered lists, so hooking it is too late.

    local FileChooser = require("ui/widget/filechooser")
    local paths       = require("common/paths")

    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then
        return
    end

    local function is_enabled()
        return zen_plugin.config.developer
            and zen_plugin.config.developer.show_hidden_outside_home == true
    end

    local function is_at_or_below_home(path)
        local home = paths.getHomeDir()
        if not home or not path then return true end
        local norm = paths.normPath(path:gsub("/$", ""))
        return norm == home or norm:sub(1, #home + 1) == home .. "/"
    end

    local orig_getList = FileChooser.getList

    function FileChooser:getList(path, collate)
        if is_enabled() and self.name == "filemanager" then
            local want_hidden = not is_at_or_below_home(path or self.path)
            -- FileChooser.show_hidden is a class-level field read directly by
            -- the getList loop — must set on the class, not the instance.
            if FileChooser.show_hidden ~= want_hidden then
                FileChooser.show_hidden = want_hidden
                G_reader_settings:saveSetting("show_hidden", want_hidden)
            end
            if FileChooser.show_unsupported ~= want_hidden then
                FileChooser.show_unsupported = want_hidden
                G_reader_settings:saveSetting("show_unsupported", want_hidden)
            end
        end
        return orig_getList(self, path, collate)
    end
end

return apply_browser_show_hidden
