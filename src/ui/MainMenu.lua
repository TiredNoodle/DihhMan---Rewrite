-- src/ui/MainMenu.lua
-- Main menu screen with host/join functionality
-- Inherits from BaseMenu for common menu functionality

local BaseMenu = require "src.ui.BaseMenu"

local MainMenu = BaseMenu:subclass('MainMenu')

-- Constructor: Sets up menu options and callbacks
function MainMenu:initialize()
    local menuOptions = {
        {
            text = "Host Game",
            callback = function()
                print("Main Menu: Host Game selected")
                self:onHostSelected()
            end
        },
        {
            text = "Join Game",
            callback = function()
                print("Main Menu: Join Game selected")
                self:onJoinSelected()
            end
        },
        {
            text = "Exit",
            callback = function()
                print("Main Menu: Exit selected")
                self:onExitSelected()
            end
        }
    }

    -- Initialize base menu with our options
    BaseMenu.initialize(self, "Main Menu", menuOptions)

    -- Network module reference (set by main.lua)
    self.network = nil
end

-- Called when "Host Game" is selected
function MainMenu:onHostSelected()
    if self.network then
        self:deactivate()
        -- IMPORTANT: Directly call Network.init, not self.network.init
        -- The network module is already loaded by main.lua
        local Network = require "src.core.Network"
        Network.init("localhost", 22122, true)
        print("Main Menu: Starting as SERVER (Host)...")
        -- Local player will be created via Network.setHostCreatedCallback
    else
        print("ERROR: Network module not connected to menu")
    end
end

-- Called when "Join Game" is selected
function MainMenu:onJoinSelected()
    if self.network then
        self:deactivate()
        -- IMPORTANT: Directly call Network.init
        local Network = require "src.core.Network"
        Network.init("localhost", 22122, false)
        print("Main Menu: Starting as CLIENT...")
        -- Client will wait for server connection
    else
        print("ERROR: Network module not connected to menu")
    end
end

-- Called when "Exit" is selected
function MainMenu:onExitSelected()
    love.event.quit()
end

-- Custom draw method with improved visuals
function MainMenu:draw()
    if not self.isActive then return end

    -- Semi-transparent background overlay
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 100, 50, 600, 500)

    -- Menu title with centered alignment
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(24))
    local titleWidth = love.graphics.getFont():getWidth(self.title)
    love.graphics.print(self.title, (800 - titleWidth) / 2, 80)

    -- Draw menu options with selection indicator
    for i, option in ipairs(self.options) do
        local y = 150 + (i * 40)

        -- Highlight selected option
        if i == self.selectedIndex then
            love.graphics.setColor(0, 1, 0)  -- Green for selected
            love.graphics.print("> " .. option.text, 200, y)
        else
            love.graphics.setColor(0.7, 0.7, 0.7)  -- Gray for unselected
            love.graphics.print("  " .. option.text, 200, y)
        end
    end

    -- Instructions footer
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(14))
    love.graphics.print("Use UP/DOWN arrows to navigate, ENTER to select", 200, 450)
    love.graphics.print("Press ESC to return/quit", 200, 470)
end

return MainMenu
