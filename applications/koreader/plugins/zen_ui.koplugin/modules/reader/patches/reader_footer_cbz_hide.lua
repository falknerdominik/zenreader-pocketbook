local function apply_reader_footer_cbz_hide()
    -- Hides the bottom status bar when reading CBZ files (if the setting is on).
    -- Self-disables when feature is off; no permanent changes to footer settings.

    local ReaderFooter = require("apps/reader/modules/readerfooter")
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function is_enabled()
        local plugin = zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        local cfg = plugin and plugin.config and plugin.config.reader_footer
        return type(cfg) == "table" and cfg.hide_in_cbz == true
    end

    local function is_image_doc(ui)
        if not (ui and ui.document) then return false end
        local file = ui.document.file:lower() or ""
        return file:match("%.cbz$") ~= nil or file:match("%.pdf$") ~= nil
    end

    -- Hide footer on document load.
    local orig_onReaderReady = ReaderFooter.onReaderReady
    ReaderFooter.onReaderReady = function(self)
        orig_onReaderReady(self)
        if is_enabled() and is_image_doc(self.ui) then
            self.view.footer_visible = false
            self:refreshFooter(true, true)
        end
    end

    -- Keep footer hidden through tap-to-toggle while setting is on.
    -- (Caller always does a repaint after applyFooterMode, so no extra refresh needed.)
    local orig_applyFooterMode = ReaderFooter.applyFooterMode
    ReaderFooter.applyFooterMode = function(self, mode)
        orig_applyFooterMode(self, mode)
        if is_enabled() and is_image_doc(self.ui) then
            self.view.footer_visible = false
        end
    end
end

return apply_reader_footer_cbz_hide
