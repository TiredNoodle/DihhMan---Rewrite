-- mods/modapi.lua
-- Central API for mods to interact with the game - Enhanced with two-way validation

local ModAPI = {
    _VERSION = "1.2.0",
    _DESCRIPTION = "Comprehensive modding API for Wave Survival Game with Two-Way Validation",
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

-- Track ALL mods (enabled and disabled) for reference
_G.MOD_ALL = _G.MOD_ALL or {}

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
function ModAPI.registerLoadedMod(modName, modInfo, enabled)
    _G.MOD_LIST[modName] = {
        name = modInfo.name,
        version = modInfo.version,
        description = modInfo.description,
        requiresSync = modInfo.requiresSync or false,
        enabled = enabled or true,
        folder = modName
    }

    -- Also store in ALL mods list
    _G.MOD_ALL[modName] = {
        name = modInfo.name,
        version = modInfo.version,
        description = modInfo.description,
        requiresSync = modInfo.requiresSync or false,
        enabled = enabled or true,
        folder = modName
    }
end

-- Register a disabled mod (for reference)
function ModAPI.registerDisabledMod(modName, modInfo)
    _G.MOD_ALL[modName] = {
        name = modInfo.name,
        version = modInfo.version,
        description = modInfo.description,
        requiresSync = modInfo.requiresSync or false,
        enabled = false,
        folder = modName
    }
end

-- Get loaded mods list (for server to send to clients)
function ModAPI.getLoadedMods()
    local modList = {}
    for name, info in pairs(_G.MOD_LIST) do
        modList[name] = {
            name = info.name,
            version = info.version,
            requiresSync = info.requiresSync,
            enabled = info.enabled
        }
    end
    return modList
end

-- Get ALL mods including disabled ones (for complete reference)
function ModAPI.getAllModsList()
    local modList = {}
    for name, info in pairs(_G.MOD_ALL) do
        modList[name] = {
            name = info.name,
            version = info.version,
            requiresSync = info.requiresSync,
            enabled = info.enabled
        }
    end
    return modList
end

-- NEW: Get mod connection state (two-way validation)
function ModAPI.getModConnectionState(localModList, remoteModList)
    local result = {
        compatible = true,
        errorMessage = "",
        warningMessage = "",
        details = {}
    }

    local errors = {}
    local warnings = {}
    local details = {}

    -- Check if remote has all our required sync mods
    for modName, localInfo in pairs(localModList) do
        if localInfo.requiresSync and localInfo.enabled ~= false then
            local remoteInfo = remoteModList[modName]

            if not remoteInfo then
                table.insert(errors, "Missing required mod: " .. modName)
                details[modName] = {status = "missing", ["local"] = "enabled", ["remote"] = "missing"}
            elseif remoteInfo.version ~= localInfo.version then
                table.insert(errors, "Version mismatch for: " .. modName .. " (local: " .. localInfo.version .. ", remote: " .. remoteInfo.version .. ")")
                details[modName] = {status = "version_mismatch", ["local"] = localInfo.version, ["remote"] = remoteInfo.version}
            elseif remoteInfo.enabled == false then
                table.insert(errors, "Required mod disabled on remote: " .. modName)
                details[modName] = {status = "disabled_on_remote", ["local"] = "enabled", ["remote"] = "disabled"}
            else
                details[modName] = {status = "ok", ["local"] = "enabled", ["remote"] = "enabled"}
            end
        end
    end

    -- Check for mods on remote that we don't have (warnings)
    for modName, remoteInfo in pairs(remoteModList) do
        if not localModList[modName] then
            if remoteInfo.requiresSync then
                table.insert(warnings, "Remote has required mod we don't have: " .. modName)
                details[modName] = {status = "missing_local", ["local"] = "missing", ["remote"] = "enabled"}
            else
                -- Non-sync mods on remote are fine, just informational
                details[modName] = {status = "extra_on_remote", ["local"] = "missing", ["remote"] = "enabled"}
            end
        elseif remoteInfo.enabled and not localModList[modName].enabled then
            if remoteInfo.requiresSync then
                table.insert(errors, "Required mod disabled locally but enabled on remote: " .. modName)
                details[modName] = {status = "disabled_local", ["local"] = "disabled", ["remote"] = "enabled"}
            else
                table.insert(warnings, "Mod disabled locally but enabled on remote: " .. modName)
                details[modName] = {status = "disabled_local_warning", ["local"] = "disabled", ["remote"] = "enabled"}
            end
        end
    end

    -- Check for mod state mismatches
    for modName, localInfo in pairs(localModList) do
        local remoteInfo = remoteModList[modName]
        if remoteInfo then
            if localInfo.enabled ~= remoteInfo.enabled then
                if localInfo.requiresSync then
                    table.insert(errors, "Mod state mismatch for: " .. modName .. " (local: " .. (localInfo.enabled and "enabled" or "disabled") .. ", remote: " .. (remoteInfo.enabled and "enabled" or "disabled") .. ")")
                else
                    table.insert(warnings, "Mod state mismatch (non-critical): " .. modName)
                end
            end
        end
    end

    -- Build result
    if #errors > 0 then
        result.compatible = false
        result.errorMessage = table.concat(errors, "\n")
    end

    if #warnings > 0 then
        result.warningMessage = table.concat(warnings, "\n")
    end

    result.details = details

    return result
end

-- Check if all clients have required mods (server-side validation)
function ModAPI.validateClientMods(clientModList, clientId)
    local connectionState = ModAPI.getModConnectionState(_G.MOD_ALL, clientModList)

    if not connectionState.compatible then
        return false, connectionState.errorMessage, connectionState.details
    end

    -- Additional server-specific checks
    for modName, modInfo in pairs(_G.MOD_LIST) do
        if modInfo.requiresSync and modInfo.enabled then
            local clientMod = clientModList[modName]
            if not clientMod then
                return false, "Client missing required mod: " .. modName
            end

            -- Check if client has mod but disabled
            if clientMod.enabled == false then
                return false, "Client has required mod disabled: " .. modName
            end

            -- Version check
            if clientMod.version ~= modInfo.version then
                return false, "Version mismatch for: " .. modName .. " (server: " .. modInfo.version .. ", client: " .. clientMod.version .. ")"
            end
        end
    end

    return true, "All mods validated", connectionState.details
end

-- Get mod compatibility report for UI display
function ModAPI.getCompatibilityReport(localModList, remoteModList)
    local report = {
        compatible = true,
        criticalIssues = {},
        warnings = {},
        informational = {}
    }

    local connectionState = ModAPI.getModConnectionState(localModList, remoteModList)

    if not connectionState.compatible then
        report.compatible = false
        for issue in connectionState.errorMessage:gmatch("[^\n]+") do
            table.insert(report.criticalIssues, issue)
        end
    end

    if connectionState.warningMessage ~= "" then
        for warning in connectionState.warningMessage:gmatch("[^\n]+") do
            table.insert(report.warnings, warning)
        end
    end

    -- Add informational details
    for modName, detail in pairs(connectionState.details) do
        if detail.status == "ok" then
            table.insert(report.informational, modName .. ": [OK] Compatible")
        elseif detail.status == "extra_on_remote" then
            table.insert(report.informational, modName .. ": Remote-only (non-critical)")
        elseif detail.status == "disabled_local_warning" then
            table.insert(report.warnings, modName .. ": Mod disabled locally but enabled on server")
        end
    end

    return report
end

-- Initialize mod API
function ModAPI.init()
    print("ModAPI initialized (Enhanced Two-Way Validation)")
    return ModAPI
end

return ModAPI
