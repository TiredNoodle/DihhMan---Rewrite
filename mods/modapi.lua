-- mods/modapi.lua
-- Central API for mods to interact with the game

local ModAPI = {
    _VERSION = "1.1.0",
    _DESCRIPTION = "Comprehensive modding API for Wave Survival Game",
    _MULTIPLAYER_SYNC = true
}

-- Global registry for all modded content (synchronized between server and clients)
_G.MOD_REGISTRY = _G.MOD_REGISTRY or {
    enemies = {},
    worlds = {},
    ui = {},
    items = {},
    players = {},
    weapons = {},
    abilities = {},
    events = {},
    hooks = {}  -- For event hooks
}

-- For multiplayer: Track which mods are loaded on server
_G.MOD_LIST = _G.MOD_LIST or {}

-- Register different types of content
function ModAPI.registerEnemy(typeName, enemyClass, enemyData)
    _G.MOD_REGISTRY.enemies[typeName] = {
        class = enemyClass,
        data = enemyData
    }
    print("ModAPI: Registered enemy type:", typeName)
    return true
end

function ModAPI.registerWorld(worldName, worldGenerator, properties)
    _G.MOD_REGISTRY.worlds[worldName] = {
        generator = worldGenerator,
        properties = properties
    }
    print("ModAPI: Registered world type:", worldName)
    return true
end

function ModAPI.registerItem(itemId, itemClass, itemData)
    _G.MOD_REGISTRY.items[itemId] = {
        class = itemClass,
        data = itemData
    }
    print("ModAPI: Registered item:", itemId)
    return true
end

function ModAPI.registerUIElement(name, uiClass, properties)
    _G.MOD_REGISTRY.ui[name] = {
        class = uiClass,
        properties = properties
    }
    print("ModAPI: Registered UI element:", name)
    return true
end

function ModAPI.registerPlayerClass(className, playerClass, properties)
    _G.MOD_REGISTRY.players[className] = {
        class = playerClass,
        properties = properties
    }
    print("ModAPI: Registered player class:", className)
    return true
end

function ModAPI.registerAbility(abilityName, abilityClass, abilityData)
    _G.MOD_REGISTRY.abilities[abilityName] = {
        class = abilityClass,
        data = abilityData
    }
    print("ModAPI: Registered ability:", abilityName)
    return true
end

-- Event hook system (client-side only, unless specified)
function ModAPI.addHook(eventName, callback, priority, isServerSide)
    priority = priority or 5  -- Default priority (1-10, lower runs first)
    _G.MOD_REGISTRY.hooks[eventName] = _G.MOD_REGISTRY.hooks[eventName] or {}
    table.insert(_G.MOD_REGISTRY.hooks[eventName], {
        callback = callback,
        priority = priority,
        isServerSide = isServerSide or false
    })
    -- Sort by priority
    table.sort(_G.MOD_REGISTRY.hooks[eventName], function(a, b)
        return a.priority < b.priority
    end)
    print("ModAPI: Added hook for event:", eventName, isServerSide and "(server-side)" or "(client-side)")
    return true
end

-- Trigger hooks with context awareness
function ModAPI.triggerHook(eventName, isServer, ...)
    local hooks = _G.MOD_REGISTRY.hooks[eventName]
    if not hooks then return false end

    for _, hook in ipairs(hooks) do
        -- Only run server-side hooks on server, client-side hooks on clients
        if (isServer and hook.isServerSide) or (not isServer and not hook.isServerSide) then
            local success, result = pcall(hook.callback, ...)
            if not success then
                print("ModAPI: Hook error for", eventName, ":", result)
            end
        end
    end
    return true
end

-- Utility function to check if mod content exists
function ModAPI.getModContent(category, name)
    if _G.MOD_REGISTRY[category] then
        return _G.MOD_REGISTRY[category][name]
    end
    return nil
end

-- Get all mods of a certain category
function ModAPI.getAllMods(category)
    return _G.MOD_REGISTRY[category] or {}
end

-- Register a loaded mod
function ModAPI.registerLoadedMod(modName, modInfo)
    _G.MOD_LIST[modName] = {
        name = modInfo.name,
        version = modInfo.version,
        description = modInfo.description,
        requiresSync = modInfo.requiresSync or false
    }
end

-- Get loaded mods list (for server to send to clients)
function ModAPI.getLoadedMods()
    local modList = {}
    for name, info in pairs(_G.MOD_LIST) do
        modList[name] = {
            name = info.name,
            version = info.version,
            requiresSync = info.requiresSync
        }
    end
    return modList
end

-- Check if all clients have required mods
function ModAPI.validateClientMods(clientModList)
    for modName, modInfo in pairs(_G.MOD_LIST) do
        if modInfo.requiresSync then
            if not clientModList[modName] then
                return false, "Missing required mod: " .. modName
            elseif clientModList[modName].version ~= modInfo.version then
                return false, "Mod version mismatch for: " .. modName
            end
        end
    end
    return true, "All mods validated"
end

-- Initialize mod API
function ModAPI.init()
    print("ModAPI initialized (Multiplayer Support Enabled)")
    return ModAPI
end

return ModAPI
