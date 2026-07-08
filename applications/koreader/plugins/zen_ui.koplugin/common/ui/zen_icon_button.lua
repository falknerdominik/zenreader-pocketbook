--[[--
Zen IconButton wrapper that supports local icon files.

Extends KOReader's IconButton to accept a `file` parameter for custom icon paths,
allowing direct loading of icons without global registration.

Usage:
    local ZenIconButton = require("common/ui/zen_icon_button")
    local btn = ZenIconButton:new{
        file = "/path/to/icon.svg",  -- Custom icon file path (takes precedence)
        icon = "fallback",            -- Fallback icon name if file is nil
        width = 32,
        height = 32,
        callback = function() ... end,
    }
]]

local IconButton = require("ui/widget/iconbutton")
local IconWidget = require("ui/widget/iconwidget")

local ZenIconButton = IconButton:extend{}

function ZenIconButton:init()
    -- Override the IconWidget creation to support `file` parameter
    self.image = IconWidget:new{
        file = self.file,                      -- Custom file path (prioritized)
        icon = self.file and nil or self.icon, -- Fallback to icon name if no file
        rotation_angle = self.icon_rotation_angle,
        width = self.width,
        height = self.height,
    }

    -- Call parent init logic (everything after image creation)
    self.show_parent = self.show_parent or self

    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")

    self.horizontal_group = HorizontalGroup:new{}
    table.insert(self.horizontal_group, HorizontalSpan:new{})
    table.insert(self.horizontal_group, self.image)
    table.insert(self.horizontal_group, HorizontalSpan:new{})

    self.button = VerticalGroup:new{}
    table.insert(self.button, VerticalSpan:new{})
    table.insert(self.button, self.horizontal_group)
    table.insert(self.button, VerticalSpan:new{})

    self[1] = self.button
    self:update()
end

return ZenIconButton
