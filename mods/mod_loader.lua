-- mods/mod_loader.lua
local modLoader = {}

function modLoader.loadMods()
    local modsDir = "mods"

    -- Check if mods directory exists
    local info = love.filesystem.getInfo(modsDir)
    if not info or info.type ~= "directory" then
        print("No mods directory found")
        return
    end

    -- Get all mod folders
    local items = love.filesystem.getDirectoryItems(modsDir)

    for _, modFolder in ipairs(items) do
        local modPath = modsDir .. "/" .. modFolder
        local modInfo = love.filesystem.getInfo(modPath)

        if modInfo and modInfo.type == "directory" then
            -- Look for mod.lua (Lua configuration instead of JSON)
            local configPath = modPath .. "/mod.lua"
            if love.filesystem.getInfo(configPath) then
                -- Load the mod configuration
                local configChunk = love.filesystem.load(configPath)
                local success, config = pcall(configChunk)

                if success and config then
                    print("Loading mod:", config.name or modFolder, "v" .. (config.version or "1.0"))

                    -- Load enemy definitions if present
                    local enemyPath = modPath .. "/enemy.lua"
                    if love.filesystem.getInfo(enemyPath) then
                        local enemyChunk = love.filesystem.load(enemyPath)
                        local success2, result = pcall(enemyChunk)

                        if success2 and result then
                            -- Try to register enemy with WaveManager
                            local success3, WaveManager = pcall(require, "src.core.WaveManager")
                            if success3 and WaveManager and WaveManager.registerEnemyType then
                                WaveManager.registerEnemyType(result.enemy_data.type, {
                                    class = result.enemy_class,
                                    data = result.enemy_data
                                })
                                print("  - Registered enemy:", result.enemy_data.display_name)
                            elseif result.enemy_class then
                                -- Store in global registry for later use
                                _G.MOD_ENEMIES = _G.MOD_ENEMIES or {}
                                _G.MOD_ENEMIES[result.enemy_data.type] = {
                                    class = result.enemy_class,
                                    data = result.enemy_data
                                }
                                print("  - Stored enemy for later:", result.enemy_data.display_name)
                            end
                        end
                    end
                else
                    print("  Failed to load mod config for:", modFolder)
                end
            end
        end
    end
end

return modLoader
