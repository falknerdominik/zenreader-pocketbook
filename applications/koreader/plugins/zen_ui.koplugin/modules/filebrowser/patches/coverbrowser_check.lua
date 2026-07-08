-- coverbrowser_check.lua
-- Show a one-time alert per session if KOReader's CoverBrowser plugin is not enabled.

local function apply_coverbrowser_check()
    local UIManager = require("ui/uimanager")

    -- Schedule check so FileManager is fully rendered before the dialog appears.
    UIManager:scheduleIn(1.0, function()
        -- CoverBrowser presence: covermenu is exclusive to the CoverBrowser plugin.
        local ok_cm = pcall(require, "covermenu")
        if ok_cm then return end

        local _ = require("gettext")
        local ButtonDialog = require("ui/widget/buttondialog")

        local dialog
        local buttons = {}

        -- Offer to enable if coverbrowser is installed but disabled.
        -- plugins_disabled is a map keyed by plugin name (not an array),
        -- and disabled plugin dirs are never added to package.path, so
        -- we rely solely on the settings map for detection.
        local disabled_list = {}
        if G_reader_settings then
            local dl = G_reader_settings:readSetting("plugins_disabled")
            if type(dl) == "table" then disabled_list = dl end
        end
        local plugin_available = disabled_list["coverbrowser"] ~= nil

        if plugin_available then
            table.insert(buttons, {{
                text = _("Enable"),
                callback = function()
                    UIManager:close(dialog)
                    if G_reader_settings then
                        disabled_list["coverbrowser"] = nil
                        G_reader_settings:saveSetting("plugins_disabled", disabled_list)
                        G_reader_settings:flush()
                    end
                    require("modules/settings/zen_settings_apply").prompt_restart()
                end,
            }})
        end

        table.insert(buttons, {{
            text = _("OK"),
            callback = function() UIManager:close(dialog) end,
        }})

        dialog = ButtonDialog:new{
            title       = _("CoverBrowser plugin is not enabled, some features will not work correctly."),
            title_align = "center",
            buttons     = buttons,
        }
        UIManager:show(dialog)
    end)
end

return apply_coverbrowser_check
