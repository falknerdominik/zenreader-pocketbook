local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckMark = require("ui/widget/checkmark")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local RadioMark = require("ui/widget/radiomark")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")

local Screen = Device.screen

local M = {}

local DEFAULT_WIDTH = Screen:scaleBySize(30)

function M.decorate(item, glyph, width)
    item = item or {}
    item.icon_glyph = glyph
    item.icon_width = width or item.icon_width or DEFAULT_WIDTH
    return item
end

function M.text(glyph, text, item)
    item = item or {}
    item.text = text
    return M.decorate(item, glyph)
end

function M.textFunc(glyph, text_func, item)
    item = item or {}
    item.text_func = text_func
    return M.decorate(item, glyph)
end

function M.getWidth(item)
    return item and item.icon_width or DEFAULT_WIDTH
end

function M.makeState(glyph, width, height, face)
    width = width or DEFAULT_WIDTH
    height = height or width
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        TextWidget:new{
            text = glyph,
            face = face or Font:getFace("smallinfofont"),
        },
    }
end

local function rebuild_touch_menu_item(row)
    local item = row and row.item
    if not (item and item.icon_glyph and row.dimen) then return end

    local item_enabled = item.enabled
    if item.enabled_func then
        item_enabled = item.enabled_func()
    end
    local item_checkable = false
    local item_checked = item.checked
    if item.checked_func then
        item_checkable = true
        item_checked = item.checked_func()
    end
    local checkmark_widget
    if item.radio then
        checkmark_widget = RadioMark:new{
            checkable = item_checkable,
            checked = item_checked,
            enabled = item_enabled,
        }
    else
        checkmark_widget = CheckMark:new{
            checkable = item_checkable,
            checked = item_checked,
            enabled = item_enabled,
        }
    end

    local checked_widget = CheckMark:new{ checked = true }
    local check_w = checked_widget:getSize().w
    local icon_w = M.getWidth(item)
    local text_max_width = row.dimen.w - 2 * Size.padding.default - check_w - icon_w
    local text = require("ui/widget/menu").getMenuText(item)
    local face = row.face
    local forced_baseline, forced_height
    if item.font_func then
        face = item.font_func(row.face.orig_size)
        if face then
            local w = TextWidget:new{ text = "", face = row.face }
            forced_baseline = w:getBaseline()
            forced_height = w:getSize().h
            w:free()
        else
            face = row.face
        end
    end
    local text_widget = TextWidget:new{
        text = text,
        max_width = text_max_width,
        fgcolor = item_enabled ~= false and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
        face = face,
        forced_baseline = forced_baseline,
        forced_height = forced_height,
    }
    row.text_truncated = text_widget:isTruncated()
    row.item_frame = FrameContainer:new{
        width = row.dimen.w,
        bordersize = 0,
        color = Blitbuffer.COLOR_BLACK,
        HorizontalGroup:new{
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{ w = check_w },
                checkmark_widget,
            },
            M.makeState(item.icon_glyph, icon_w, row.dimen.h, face),
            text_widget,
        },
    }

    row._underline_container = UnderlineContainer:new{
        vertical_align = "center",
        dimen = row.dimen:copy(),
        line_width = row.item_frame:getSize().w,
        row.item_frame,
    }
    row[1] = row._underline_container
end

local function prepare_menu_items(menu)
    local items = menu and menu.item_table
    if type(items) ~= "table" then return end
    local width
    for _i, item in ipairs(items) do
        if type(item) == "table" and item.icon_glyph then
            width = math.max(width or 0, M.getWidth(item))
        end
    end
    if width then
        if menu._zen_icon_item_base_state_w == nil then
            menu._zen_icon_item_base_state_w = menu.state_w or false
        end
        menu.state_w = math.max(menu._zen_icon_item_base_state_w or 0, width)
        local height = menu.item_dimen and menu.item_dimen.h or width
        local face = Font:getFace(menu.font or "smallinfofont", menu.font_size)
        for _i, item in ipairs(items) do
            if type(item) == "table" and item.icon_glyph then
                item.state = M.makeState(item.icon_glyph, width, height, face)
            end
        end
    elseif menu._zen_icon_item_base_state_w ~= nil then
        menu.state_w = menu._zen_icon_item_base_state_w or nil
        menu._zen_icon_item_base_state_w = nil
    end
end

function M.installMenuPatch()
    local Menu = require("ui/widget/menu")
    if not Menu._zen_icon_item_patched then
        Menu._zen_icon_item_patched = true
        local orig_updateItems = Menu.updateItems
        Menu.updateItems = function(self, ...)
            prepare_menu_items(self)
            return orig_updateItems(self, ...)
        end
    end

    local ok_touch, TouchMenu = pcall(require, "ui/widget/touchmenu")
    if not ok_touch or TouchMenu._zen_icon_item_patched then return end
    local TouchMenuItem
    for i = 1, 64 do
        local name, value = debug.getupvalue(TouchMenu.updateItems, i)
        if name == nil then break end
        if name == "TouchMenuItem" then
            TouchMenuItem = value
            break
        end
    end
    if not (TouchMenuItem and type(TouchMenuItem.init) == "function") then return end
    TouchMenu._zen_icon_item_patched = true
    local orig_touch_init = TouchMenuItem.init
    TouchMenuItem.init = function(self, ...)
        local result = orig_touch_init(self, ...)
        rebuild_touch_menu_item(self)
        return result
    end
end

return M
