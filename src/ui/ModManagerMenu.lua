-- src/ui/ModManagerMenu.lua
-- Menu for enabling/disabling mods with enhanced multiplayer info

local BaseMenu = require "src.ui.BaseMenu"

local ModManagerMenu = BaseMenu:subclass('ModManagerMenu')

function ModManagerMenu:initialize()
    -- Call parent constructor with empty options initially
    BaseMenu.initialize(self, "MOD MANAGER", {})

    self.visible = false
    self.modList = {}
    self.modStates = {}  -- Track enabled/disabled state
    self.selectedModIndex = 1

    -- Enhanced display options
    self.showDetails = false
    self.showMultiplayerInfo = true
    self.showCompatibilityReport = false
    self.compatibilityReport = nil

    print("ModManagerMenu initialized")
end

function ModManagerMenu:show()
    self.visible = true

    -- CRITICAL: Reload preferences every time we show the menu
    self:loadModPreferences()
    self:refreshModList()

    self.selectedIndex = 1
    self.isActive = true  -- CRITICAL: Make sure menu is active for input
    print("ModManagerMenu shown with " .. #self.options .. " options")
end

function ModManagerMenu:hide()
    self.visible = false
    self:saveModPreferences()
    print("ModManagerMenu hidden")
end

function ModManagerMenu:refreshModList()
    -- Clear current options
    self.options = {}

    -- Add mod toggle options
    self.modList = self:getAvailableMods()

    for i, mod in ipairs(self.modList) do
        table.insert(self.options, {
            text = self:formatModOption(mod),
            modIndex = i,
            callback = function()
                self:toggleMod(i)
            end
        })
    end

    -- Add separator
    table.insert(self.options, {
        text = "-------------------------",
        isSeparator = true
    })

    -- Add action buttons
    table.insert(self.options, {
        text = "Show/Hide Details (D)",
        callback = function()
            self:toggleDetails()
        end
    })

    table.insert(self.options, {
        text = "Check Compatibility (C)",
        callback = function()
            self:checkCompatibility()
        end
    })

    table.insert(self.options, {
        text = "Apply Changes & Restart Game",
        callback = function()
            self:applyChanges()
        end
    })

    table.insert(self.options, {
        text = "Back to Main Menu",
        callback = function()
            if self.onReturnToMain then
                self.onReturnToMain()
            end
        end
    })

    print("Refreshed mod list:", #self.modList, "mods found")

    -- Debug: Print current mod states
    print("Current mod states:")
    for _, mod in ipairs(self.modList) do
        print(string.format("  %s: %s", mod.name, mod.enabled and "Enabled" or "Disabled"))
    end
end

function ModManagerMenu:getAvailableMods()
    local mods = {}

    -- Get mods directory
    local modsDir = "mods"
    local info = love.filesystem.getInfo(modsDir)

    if not info or info.type ~= "directory" then
        return mods
    end

    -- Scan mod directories
    local items = love.filesystem.getDirectoryItems(modsDir)
    for _, modFolder in ipairs(items) do
        local modPath = modsDir .. "/" .. modFolder
        local modInfo = love.filesystem.getInfo(modPath)

        if modInfo and modInfo.type == "directory" then
            -- Check for mod.lua
            local configPath = modPath .. "/mod.lua"
            if love.filesystem.getInfo(configPath) then
                local configChunk = love.filesystem.load(configPath)
                local success, config = pcall(configChunk)

                if success and config then
                    -- Get enabled state from saved preferences (default to true)
                    local enabled = self.modStates[modFolder]
                    if enabled == nil then
                        enabled = true  -- Default to enabled
                    end

                    table.insert(mods, {
                        folder = modFolder,
                        name = config.name or modFolder,
                        version = config.version or "1.0",
                        author = config.author or "Unknown",
                        description = config.description or "",
                        enabled = enabled,
                        requiresSync = config.requiresSync or false,
                        dependencies = config.dependencies or {},
                        main = config.main
                    })
                end
            end
        end
    end

    return mods
end

function ModManagerMenu:formatModOption(mod)
    local status = mod.enabled and "[Enabled]" or "[Disabled]"
    local syncMark = mod.requiresSync and " <S>" or ""  -- <S> for sync required
    return string.format("%s %s v%s%s", status, mod.name, mod.version, syncMark)
end

function ModManagerMenu:toggleMod(index)
    if index < 1 or index > #self.modList then return end

    local mod = self.modList[index]
    mod.enabled = not mod.enabled
    self.modStates[mod.folder] = mod.enabled

    -- Update option text
    self.options[index].text = self:formatModOption(mod)

    local status = mod.enabled and "enabled" or "disabled"
    print(string.format("Mod '%s' %s", mod.name, status))

    -- Show warning for multiplayer sync mods
    if mod.requiresSync and not mod.enabled then
        print("WARNING: Disabling a mod that requires multiplayer sync may cause connection issues!")
    end
end

function ModManagerMenu:toggleDetails()
    self.showDetails = not self.showDetails
    print("Details display:", self.showDetails and "ON" or "OFF")
end

function ModManagerMenu:checkCompatibility()
    if not _G.MOD_API then
        print("ERROR: ModAPI not available")
        return
    end

    -- Get local mod list
    local localMods = {}
    for _, mod in ipairs(self.modList) do
        localMods[mod.folder] = {
            name = mod.name,
            version = mod.version,
            requiresSync = mod.requiresSync,
            enabled = mod.enabled
        }
    end

    -- For now, simulate a server mod list (in real use, this would come from actual server)
    local serverMods = {}
    for _, mod in ipairs(self.modList) do
        -- Simulate server having all mods enabled
        serverMods[mod.folder] = {
            name = mod.name,
            version = mod.version,
            requiresSync = mod.requiresSync,
            enabled = true  -- Server always has mods enabled if installed
        }
    end

    -- Get compatibility report
    local report = _G.MOD_API.getCompatibilityReport(localMods, serverMods)

    self.compatibilityReport = report
    self.showCompatibilityReport = true

    print("\n=== MOD COMPATIBILITY REPORT ===")
    if report.compatible then
        print("[OK] All mods are compatible")
    else
        print("[ERROR] Critical issues found:")
        for _, issue in ipairs(report.criticalIssues) do
            print("  - " .. issue)
        end
    end

    if #report.warnings > 0 then
        print("\n[WARNING] Warnings:")
        for _, warning in ipairs(report.warnings) do
            print("  - " .. warning)
        end
    end
end

function ModManagerMenu:loadModPreferences()
    -- Try to load saved preferences
    local prefsFile = "mod_preferences.lua"
    if love.filesystem.getInfo(prefsFile) then
        local chunk = love.filesystem.load(prefsFile)
        local success, savedStates = pcall(chunk)
        if success and type(savedStates) == "table" then
            self.modStates = savedStates
            print("ModManagerMenu: Loaded mod preferences from file")

            -- Debug: Print what was loaded
            print("Loaded mod states:")
            for modFolder, enabled in pairs(self.modStates) do
                print(string.format("  %s: %s", modFolder, enabled and "Enabled" or "Disabled"))
            end
            return
        else
            print("ModManagerMenu: Could not load mod preferences file, using defaults")
        end
    else
        print("ModManagerMenu: No mod preferences file found, using defaults")
    end

    -- Default: all mods enabled
    self.modStates = {}
    print("ModManagerMenu: Using default mod preferences (all enabled)")
end

function ModManagerMenu:saveModPreferences()
    -- Save preferences to file
    local prefsFile = "mod_preferences.lua"
    local content = "return {\n"

    for modFolder, enabled in pairs(self.modStates) do
        content = content .. string.format('  ["%s"] = %s,\n', modFolder, tostring(enabled))
    end

    content = content .. "}"

    if love.filesystem.write(prefsFile, content) then
        print("ModManagerMenu: Saved mod preferences to file")
    else
        print("ModManagerMenu: Failed to save mod preferences")
    end
end

function ModManagerMenu:applyChanges()
    -- Save preferences first
    self:saveModPreferences()

    -- Show message about restart
    self.showRestartMessage = true
    self.restartMessageTimer = 5.0  -- Show for 5 seconds

    print("========================================")
    print("MOD CHANGES APPLIED")
    print("Please restart the game for changes to take effect!")
    print("========================================")
end

function ModManagerMenu:update(dt)
    if not self.visible then return end

    BaseMenu.update(self, dt)

    -- Update restart message timer
    if self.showRestartMessage then
        self.restartMessageTimer = self.restartMessageTimer - dt
        if self.restartMessageTimer <= 0 then
            self.showRestartMessage = false
        end
    end
end

function ModManagerMenu:draw(x, y)
    if not self.visible then return end

    x = x or 50
    y = y or 50

    -- Semi-transparent background
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle("fill", 0, 0, 800, 600)

    -- Title
    love.graphics.setColor(0, 1, 1)
    love.graphics.setFont(love.graphics.newFont(36))
    love.graphics.print("MOD MANAGER", x, y)

    -- Instructions
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(14))
    love.graphics.print("Use UP/DOWN to navigate, ENTER to toggle/select", x, y + 40)
    love.graphics.print("SPACE to toggle mod without moving selection", x, y + 60)
    love.graphics.print("D: Toggle details, C: Check compatibility", x, y + 80)

    -- Mod list
    local startY = y + 120
    local optionHeight = 30

    for i, option in ipairs(self.options) do
        local optionY = startY + (i - 1) * optionHeight

        -- Skip drawing separator as selectable
        if option.isSeparator then
            love.graphics.setColor(0.5, 0.5, 0.5)
            love.graphics.print(option.text, x, optionY)
        else
            -- Highlight selected option
            if i == self.selectedIndex then
                love.graphics.setColor(0, 1, 0)
                love.graphics.print("> " .. option.text, x, optionY)

                -- Show mod details for selected mod
                if option.modIndex then
                    local mod = self.modList[option.modIndex]
                    if self.showDetails then
                        self:drawModDetails(mod, x + 400, optionY - 20)
                    end
                end
            else
                love.graphics.setColor(0.7, 0.7, 0.7)
                love.graphics.print("  " .. option.text, x, optionY)
            end
        end
    end

    -- Show compatibility report
    if self.showCompatibilityReport and self.compatibilityReport then
        self:drawCompatibilityReport(x, y + 400)
    end

    -- Restart message
    if self.showRestartMessage then
        love.graphics.setColor(1, 1, 0)
        love.graphics.setFont(love.graphics.newFont(16))
        love.graphics.print("RESTART REQUIRED! Changes will take effect after restart.",
                           x, y + 500)
    end

    love.graphics.setColor(1, 1, 1)
end

function ModManagerMenu:drawModDetails(mod, x, y)
    if not mod then return end

    love.graphics.setColor(0.8, 0.8, 1)
    love.graphics.setFont(love.graphics.newFont(14))
    love.graphics.print("Mod Details:", x, y)

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Name: " .. mod.name, x, y + 20)
    love.graphics.print("Version: " .. mod.version, x, y + 40)
    love.graphics.print("Author: " .. mod.author, x, y + 60)
    love.graphics.print("Description: " .. mod.description, x, y + 80)

    -- Dependencies
    if mod.dependencies and #mod.dependencies > 0 then
        love.graphics.print("Dependencies: " .. table.concat(mod.dependencies, ", "), x, y + 100)
    end

    -- Multiplayer info with colored indicators
    if mod.requiresSync then
        love.graphics.setColor(1, 0.8, 0)  -- Orange/Yellow for sync required
        love.graphics.print("[SYNC REQUIRED]", x, y + 120)
        love.graphics.setColor(0.8, 0.8, 0.8)
        love.graphics.print("• All players must have this mod enabled", x, y + 140)
        love.graphics.print("• Version must match exactly", x, y + 160)
        love.graphics.print("• Must be enabled on all connected clients", x, y + 180)
    else
        love.graphics.setColor(0.5, 1, 0.5)  -- Green for client-side only
        love.graphics.print("[CLIENT-SIDE ONLY]", x, y + 120)
        love.graphics.setColor(0.8, 0.8, 0.8)
        love.graphics.print("• No multiplayer synchronization required", x, y + 140)
        love.graphics.print("• Can be enabled/disabled independently", x, y + 160)
        love.graphics.print("• Visual/audio effects only", x, y + 180)
    end

    -- Status with color coding
    if mod.enabled then
        love.graphics.setColor(0, 1, 0)
        love.graphics.print("[ENABLED]", x, y + 200)
    else
        love.graphics.setColor(1, 0, 0)
        love.graphics.print("[DISABLED]", x, y + 200)
        if mod.requiresSync then
            love.graphics.setColor(1, 0.5, 0)
            love.graphics.print("WARNING: Disabling sync mod may cause connection issues!", x, y + 220)
        end
    end
end

function ModManagerMenu:drawCompatibilityReport(x, y)
    if not self.compatibilityReport then return end

    love.graphics.setColor(0.1, 0.1, 0.2, 0.9)
    love.graphics.rectangle("fill", x - 10, y - 10, 620, 180)

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(love.graphics.newFont(16))
    love.graphics.print("COMPATIBILITY REPORT", x, y)

    y = y + 30

    if self.compatibilityReport.compatible then
        love.graphics.setColor(0, 1, 0)
        love.graphics.print("[PASS] All mods are compatible", x, y)
        y = y + 20
    else
        love.graphics.setColor(1, 0, 0)
        love.graphics.print("[FAIL] Critical issues found:", x, y)
        y = y + 20

        love.graphics.setColor(1, 0.5, 0.5)
        for i, issue in ipairs(self.compatibilityReport.criticalIssues) do
            if i <= 3 then  -- Show only first 3 issues
                love.graphics.print("  ✗ " .. issue, x, y)
                y = y + 15
            end
        end
    end

    if #self.compatibilityReport.warnings > 0 then
        love.graphics.setColor(1, 1, 0)
        love.graphics.print("[WARN] Warnings:", x, y)
        y = y + 20

        love.graphics.setColor(1, 1, 0.5)
        for i, warning in ipairs(self.compatibilityReport.warnings) do
            if i <= 2 then  -- Show only first 2 warnings
                love.graphics.print("  ! " .. warning, x, y)
                y = y + 15
            end
        end
    end

    -- Show informational messages if available
    if #self.compatibilityReport.informational > 0 then
        love.graphics.setColor(0.7, 0.7, 1)
        love.graphics.print("[INFO] Informational:", x, y)
        y = y + 20

        love.graphics.setColor(0.8, 0.8, 1)
        for i, info in ipairs(self.compatibilityReport.informational) do
            if i <= 3 then  -- Show only first 3
                love.graphics.print("  • " .. info, x, y)
                y = y + 15
            end
        end
    end

    love.graphics.setColor(0.7, 0.7, 1)
    love.graphics.print("(Press C to close)", x, y + 10)
end

function ModManagerMenu:keypressed(key)
    if not self.visible then return end

    -- Handle space for toggling without moving selection
    if key == "space" and self.options[self.selectedIndex].modIndex then
        self:toggleMod(self.options[self.selectedIndex].modIndex)
        return
    end

    -- Handle up/down navigation
    if key == "up" then
        self:selectPrevious()
    elseif key == "down" then
        self:selectNext()
    elseif key == "return" then
        self:selectCurrent()
    elseif key == "escape" then
        self:hide()
        if self.onReturnToMain then
            self.onReturnToMain()
        end
    elseif key == "d" then
        self:toggleDetails()
    elseif key == "c" then
        if self.showCompatibilityReport then
            self.showCompatibilityReport = false
        else
            self:checkCompatibility()
        end
    end
end

return ModManagerMenu
