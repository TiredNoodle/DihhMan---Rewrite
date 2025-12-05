-- src/ui/BaseMenu.lua
-- Generic, reusable menu base class using middleclass.
local class = require "lib.middleclass"

local BaseMenu = class('BaseMenu')

-- Constructor: Initialize the menu with a title and list of options.
-- @param title (string) The menu title.
-- @param options (table) Array of option tables: {text="Option Text", callback=function}
function BaseMenu:initialize(title, options)
    self.title = title or "Menu"
    self.options = options or {}
    self.selectedIndex = 1 -- Start with the first option selected.
    self.isActive = false  -- Menu is not visible/active by default.
    print(string.format("Menu '%s' created with %d options", self.title, #self.options))
end

-- Activates the menu, making it visible and interactive.
function BaseMenu:activate()
    self.isActive = true
    self.selectedIndex = 1 -- Reset selection when activated.
    print("Menu activated:", self.title)
end

-- Deactivates the menu.
function BaseMenu:deactivate()
    self.isActive = false
    print("Menu deactivated:", self.title)
end

-- Moves the selection up.
function BaseMenu:selectPrevious()
    if not self.isActive then return end
    self.selectedIndex = self.selectedIndex - 1
    if self.selectedIndex < 1 then
        self.selectedIndex = #self.options -- Wrap to bottom.
    end
end

-- Moves the selection down.
function BaseMenu:selectNext()
    if not self.isActive then return end
    self.selectedIndex = self.selectedIndex + 1
    if self.selectedIndex > #self.options then
        self.selectedIndex = 1 -- Wrap to top.
    end
end

-- Triggers the callback of the currently selected option.
function BaseMenu:selectCurrent()
    if not self.isActive then return end
    local option = self.options[self.selectedIndex]
    if option and option.callback then
        print("Menu selected:", option.text)
        option.callback() -- Execute the option's action.
    end
end

-- Draws the menu. Should be called in love.draw().
-- This is a generic implementation; subclasses should override for custom visuals.
-- @param x (number) X position to draw the menu.
-- @param y (number) Y position to draw the menu.
function BaseMenu:draw(x, y)
    if not self.isActive then return end
    x = x or 100
    y = y or 100
    love.graphics.setColor(1, 1, 1) -- White.
    -- Draw the title.
    love.graphics.print(self.title, x, y)
    -- Draw each option, highlighting the selected one.
    for i, option in ipairs(self.options) do
        local optionY = y + 40 + (i * 30) -- Positioning.
        if i == self.selectedIndex then
            love.graphics.setColor(0, 1, 0) -- Green for selected.
            love.graphics.print("> " .. option.text, x, optionY)
        else
            love.graphics.setColor(0.7, 0.7, 0.7) -- Grey for unselected.
            love.graphics.print("  " .. option.text, x, optionY)
        end
    end
    love.graphics.setColor(1, 1, 1)
end

-- Updates the menu. Should be called in love.update(dt).
-- Add any animations or timed logic here if needed.
function BaseMenu:update(dt)
    if not self.isActive then return end
    -- Placeholder for any per-frame updates (e.g., animations).
end

return BaseMenu
