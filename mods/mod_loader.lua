-- mods/mod_loader.lua
local modLoader = {}

-- Track mod loading order for dependencies
local modLoadOrder = {}

function modLoader.loadMods()
    local modsDir = "mods"

    -- Check if mods directory exists
    local info = love.filesystem.getInfo(modsDir)
    if not info or info.type ~= "directory" then
        print("No mods directory found")
        return {}
    end

    -- Load mod API first
    local ModAPI = require("mods.modapi")
    ModAPI.init()

    -- Get all mod folders
    local items = love.filesystem.getDirectoryItems(modsDir)
    local loadedMods = {}
    local modQueue = {}

    -- First pass: collect mod info and check dependencies
    for _, modFolder in ipairs(items) do
        local modPath = modsDir .. "/" .. modFolder
        local modInfo = love.filesystem.getInfo(modPath)

        if modInfo and modInfo.type == "directory" then
            -- Look for mod.lua
            local configPath = modPath .. "/mod.lua"
            if love.filesystem.getInfo(configPath) then
                -- Load the mod configuration
                local configChunk = love.filesystem.load(configPath)
                local success, config = pcall(configChunk)

                if success and config then
                    -- Store mod in queue
                    modQueue[modFolder] = {
                        path = modPath,
                        config = config,
                        dependencies = config.dependencies or {},
                        loaded = false
                    }
                end
            end
        end
    end

    -- Second pass: load mods respecting dependencies
    local attempts = 0
    local maxAttempts = 10  -- Prevent infinite loops

    while true do
        local loadedThisRound = false

        for modName, modData in pairs(modQueue) do
            if not modData.loaded then
                local canLoad = true

                -- Check dependencies
                for _, dep in ipairs(modData.dependencies) do
                    if not modQueue[dep] or not modQueue[dep].loaded then
                        canLoad = false
                        break
                    end
                end

                if canLoad then
                    print("\n=== Loading Mod: " .. (modData.config.name or modName) .. " ===")
                    print("  Version: " .. (modData.config.version or "1.0"))
                    print("  Author: " .. (modData.config.author or "Unknown"))
                    print("  Description: " .. (modData.config.description or ""))

                    if #modData.dependencies > 0 then
                        print("  Dependencies: " .. table.concat(modData.dependencies, ", "))
                    end

                    -- Load main mod file if specified
                    local mainSuccess = true
                    if modData.config.main then
                        local mainPath = modData.path .. "/" .. modData.config.main
                        if love.filesystem.getInfo(mainPath) then
                            local mainChunk = love.filesystem.load(mainPath)
                            local success, result = pcall(mainChunk, ModAPI, modData.path)
                            if success then
                                print("  Main file loaded successfully")
                            else
                                print("  ERROR loading main file:", result)
                                mainSuccess = false
                            end
                        else
                            print("  WARNING: Main file not found:", modData.config.main)
                        end
                    end

                    -- Auto-load common component files
                    if mainSuccess then
                        modLoader.loadComponents(ModAPI, modData.path, modData.config)
                    end

                    -- Mark as loaded
                    modData.loaded = true
                    loadedMods[modName] = modData.config
                    table.insert(modLoadOrder, modName)

                    -- Register with ModAPI
                    ModAPI.registerLoadedMod(modName, {
                        name = modData.config.name or modName,
                        version = modData.config.version or "1.0",
                        description = modData.config.description or "",
                        requiresSync = modData.config.requiresSync or false
                    })

                    loadedThisRound = true
                end
            end
        end

        attempts = attempts + 1
        if not loadedThisRound or attempts >= maxAttempts then
            break
        end
    end

    -- Check for unloaded mods due to missing dependencies
    for modName, modData in pairs(modQueue) do
        if not modData.loaded then
            print("  WARNING: Could not load mod '" .. modName .. "' - missing dependencies")
        end
    end

    print("\n=== Mod Loading Complete ===")
    print("Total mods loaded:", #modLoadOrder)

    -- Print loaded content summary
    for category, content in pairs(_G.MOD_REGISTRY) do
        local count = 0
        for _ in pairs(content) do count = count + 1 end
        if count > 0 then
            print(string.format("  %s: %d registered", category, count))
        end
    end

    -- Print load order
    print("Load order:", table.concat(modLoadOrder, ", "))

    return loadedMods
end

-- Auto-load common component files
function modLoader.loadComponents(ModAPI, modPath, config)
    local componentFiles = {
        "enemies.lua",
        "enemy.lua",
        "world.lua",
        "items.lua",
        "ui.lua",
        "players.lua",
        "abilities.lua",
        "hooks.lua"
    }

    for _, file in ipairs(componentFiles) do
        local filePath = modPath .. "/" .. file
        if love.filesystem.getInfo(filePath) then
            print("  Loading component:", file)
            local chunk = love.filesystem.load(filePath)
            local success, result = pcall(chunk, ModAPI, modPath)
            if not success then
                print("    ERROR:", result)
            end
        end
    end
end

-- Get mod asset path
function modLoader.getAssetPath(modName, assetPath)
    return "mods/" .. modName .. "/" .. assetPath
end

-- Check if mod asset exists
function modLoader.assetExists(modName, assetPath)
    return love.filesystem.getInfo(modLoader.getAssetPath(modName, assetPath)) ~= nil
end

-- Get mod load order (for debugging)
function modLoader.getLoadOrder()
    return modLoadOrder
end

return modLoader
