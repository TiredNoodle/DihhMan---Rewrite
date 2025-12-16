-- main.lua - Top-down multiplayer wave survival game
local Network = require "src.core.Network"
local NetworkPlayer = require "src.core.NetworkPlayer"
local PositionSync = require "src.core.PositionSync"
local World = require "src.core.World"
local BaseCharacter = require "src.entities.BaseCharacter"
local MainMenu = require "src.ui.MainMenu"
local Player = require "src.entities.Player"
local HostControl = require "src.ui.HostControl"

-- GAME STATE MANAGEMENT
-- =====================
local gameState = "menu"          -- "menu", "connecting", "playing"
local localPlayer = nil           -- The player controlled by this instance
local remotePlayers = {}          -- Table of other players connected
local myPlayerId = nil            -- Our assigned player ID from server
local enemies = {}                -- Table of active enemies
local mainMenu = nil              -- Main menu UI instance
local hostControl = nil           -- Host control UI
local debugFont = nil             -- Font for debug information display
local showDebugInfo = true        -- Toggles debug overlay

-- Track enemy creation timestamps to prevent duplicate creation
local enemyCreationTimestamps = {}

-- Game state
local allPlayersDead = false
local gameActive = false

-- Position update optimization
local lastSentState = nil
local positionThreshold = 2.0  -- Minimum movement required to send update

-- DEBUG: Track frame count for periodic logging
local frameCount = 0
local lastDebugOutput = 0

-- Debug: Debug logging to trace where nil is coming from
function validatePlayerState(state, playerName)
    if not state then
        print("ERROR: State is nil for player:", playerName)
        return false
    end

    if type(state) ~= "table" then
        print("ERROR: State is not a table for player:", playerName, type(state))
        return false
    end

    print(string.format("DEBUG %s: x=%s, y=%s, health=%s, type_x=%s, type_y=%s, type_health=%s",
        playerName,
        tostring(state.x), tostring(state.y), tostring(state.health),
        type(state.x), type(state.y), type(state.health)))

    return true
end

-- LOVE2D LOAD FUNCTION
function love.load()
    love.window.setTitle("Top-Down Wave Survival Game")
    love.window.setMode(800, 600)

    -- Initialize subsystems
    debugFont = love.graphics.newFont(12)
    World.init()
    hostControl = HostControl:new()

    -- Create main menu
    mainMenu = MainMenu:new()
    mainMenu.network = Network
    mainMenu.onStateChange = function(state)
        switchGameState(state)
    end

    -- Configure network event callbacks
    setupNetworkCallbacks()

    -- Start in menu state
    switchGameState("menu")

    -- Load mods
    local success, modLoader = pcall(require, "mods.mod_loader")
    if success then
        modLoader.loadMods()
    else
        print("Note: Mod system not available")
    end

    print("Game loaded successfully. Press F1 to toggle debug info.")
end

-- NETWORK CALLBACK SETUP
function setupNetworkCallbacks()
    -- Called when connection to server is established
    Network.setConnectCallback(function()
        print("Network: Successfully connected to server!")
        -- When connected, we enter the game
        if gameState == "connecting" then
            switchGameState("playing")
        end
    end)

    -- Called when server sends our player ID
    Network.setPlayerIdCallback(function(data)
        myPlayerId = data.id
        print("Network: Received player ID from server: " .. myPlayerId)
        lastSentState = nil  -- Reset for new player
    end)

    -- Called when server sends initial game state
    Network.setGameStateCallback(function(data)
        print("Network: Received initial game state from server")
        myPlayerId = data.yourId
        gameActive = data.gameActive or false

        -- Clear existing players first to prevent duplicates
        localPlayer = nil
        remotePlayers = {}
        enemies = {}
        lastSentState = nil

        -- Create players from server data
        if data.players then
            for id, playerData in pairs(data.players) do
                if id == myPlayerId then
                    -- This is us, create local player
                    createLocalPlayer("Player_" .. myPlayerId, playerData.x, playerData.y,
                                    playerData.health, playerData.alive)
                else
                    -- This is another player, create remote player
                    createRemotePlayer(id, playerData)
                end
            end
        else
            -- No player data yet, create local player at spawn
            local spawnX, spawnY = World.findSpawnLocation()
            createLocalPlayer("Player_" .. myPlayerId, spawnX, spawnY, 100, true)
        end

        -- Create enemies
        if data.enemies then
            for enemyId, enemyData in pairs(data.enemies) do
                createEnemy(enemyId, enemyData)
            end
        end

        switchGameState("playing")
    end)

    -- Called when game starts (with countdown)
    Network.setGameStartedCallback(function(data)
        print("Network: Game started with countdown")
        gameActive = true
        hostControl:updateStatus(data)
        hostControl:showMessage(data.message, 3)
    end)

    -- Called when wave starts
    Network.setWaveStartedCallback(function(data)
        print("Network: Wave " .. data.wave .. " started!")
        gameActive = true
        hostControl:updateStatus(data)
        hostControl:showMessage(data.message, 3)
    end)

    -- Called when wave completes
    Network.setWaveCompletedCallback(function(data)
        print("Network: Wave " .. data.wave .. " completed!")
        hostControl:updateStatus(data)
        hostControl:showMessage(data.message, 3)

        if data.gameCompleted then
            print("Network: All stages completed!")
            gameActive = false
        end
    end)

    -- Called when game is over (all players dead)
    Network.setGameOverCallback(function(data)
        print("Network: Game Over!")
        allPlayersDead = true
        gameActive = false
        hostControl:setAllPlayersDead(true)
        hostControl:showMessage(data.message, 0)  -- Show until restart
    end)

    -- Called when game restarts
    Network.setGameRestartCallback(function(data)
        print("Network: Game restarted!")
        allPlayersDead = false
        gameActive = true
        hostControl:setAllPlayersDead(false)
        hostControl:showMessage(data.message, 3)

        -- Reset local player health
        if localPlayer then
            localPlayer.health = 100
            localPlayer.isAlive = true
        end
        lastSentState = nil
    end)

    -- Called when a new player joins the game
    Network.setPlayerJoinedCallback(function(data)
        print("Network: Player joined:", data.id, "at", data.x, data.y)
        if data.id ~= myPlayerId then
            createRemotePlayer(data.id, data)
        end
    end)

    -- Called when server sends position updates for other players
    Network.setPlayerUpdatedCallback(function(data)
        if remotePlayers[data.id] then
            remotePlayers[data.id]:applyNetworkUpdate(data)
        else
            -- If we don't have this player yet, create them
            if data.id ~= myPlayerId then
                createRemotePlayer(data.id, data)
            end
        end
    end)

    -- Called when a player leaves the game
    Network.setPlayerLeftCallback(function(data)
        print("Network: Player left:", data.id)
        if remotePlayers[data.id] then
            remotePlayers[data.id] = nil
            print("Remote player removed:", data.id)
        end
    end)

    -- Called when server corrects our position
    Network.setPlayerCorrectedCallback(function(data)
        if localPlayer then
            print("Network: Server corrected our position")
            localPlayer.x = data.x
            localPlayer.y = data.y
            lastSentState = nil  -- Force resend
        end
    end)

    -- Enemy related callbacks
    Network.setEnemySpawnedCallback(function(data)
        print("Enemy spawned:", data.id, "type:", data.type)
        createEnemy(data.id, data)
    end)

    Network.setEnemyUpdatedCallback(function(data)
        if enemies[data.id] then
            enemies[data.id]:applyNetworkState(data)
        else
            print("WARNING: Received update for unknown enemy:", data.id)
            createEnemy(data.id, data)
        end
    end)

    Network.setEnemyDiedCallback(function(data)
        print("Enemy died:", data.id)
        if enemies[data.id] then
            enemies[data.id] = nil
        end
        enemyCreationTimestamps[data.id] = nil
    end)

    -- Called when a player performs an action
    Network.setPlayerActionCallback(function(data)
        local playerId = data.playerId

        -- Handle Host player actions
        if playerId == "host" or playerId == "Host" then
            if Network.isServer then
                -- If we're the server and this is our host player
                if localPlayer and localPlayer.name == "Host" then
                    localPlayer:applyActionEffect(data)
                end
            else
                -- If we're a client and this is the host's action
                if remotePlayers["Host"] then
                    remotePlayers["Host"]:applyActionEffect(data)
                end
            end
        elseif remotePlayers[playerId] then
            -- Remote player action
            remotePlayers[playerId]:applyActionEffect(data)
        elseif playerId == myPlayerId and localPlayer then
            -- Our own action (should be handled locally already)
            localPlayer:applyActionEffect(data)
        else
            print("WARNING: Received action for unknown player:", data.playerId)
        end
    end)

    Network.setHostCreatedCallback(function()
        print("Network: Host game created")
        myPlayerId = "Host"

        -- Create local player for host
        local x, y = World.findSpawnLocation()
        createLocalPlayer("Host", x, y, 100, true)

        -- Update host player data in Network
        if localPlayer then
            Network.setHostPlayerData(localPlayer:getNetworkState())
        end

        switchGameState("playing")
        hostControl:show()
    end)

    -- Called when disconnected from server
    Network.setDisconnectCallback(function(data)
        print("Network: Disconnected from server")

        -- Clean up and return to menu
        cleanupGame()
        switchGameState("menu")
    end)
end

-- PLAYER CREATION FUNCTIONS
function createLocalPlayer(name, x, y, health, isAlive)
    local spawnX, spawnY

    if type(x) == "table" then
        spawnX = x.x or x[1] or 400
        spawnY = x.y or x[2] or 300
    else
        spawnX = x or 400
        spawnY = y or 300
    end

    localPlayer = Player:new(name, spawnX, spawnY)
    localPlayer.isLocalPlayer = true

    if name == "Host" then
        localPlayer.name = "Host"
    end

    -- Set health and alive state
    if health then
        localPlayer.health = health
        localPlayer.maxHealth = 100
    end

    if isAlive ~= nil then
        localPlayer.isAlive = isAlive
    end

    -- Initialize last sent state
    lastSentState = {
        x = localPlayer.x + localPlayer.width/2,
        y = localPlayer.y + localPlayer.height/2,
        health = localPlayer.health
    }

    print(string.format("Local player '%s' created at (%d, %d) Health: %d Alive: %s",
          name, spawnX, spawnY, localPlayer.health, tostring(localPlayer.isAlive)))
end

function createRemotePlayer(id, data)
    -- Don't create remote player for ourselves
    if id == myPlayerId then return end

    local normalizedId = id
    if id == "host" then
        normalizedId = "Host"
    end

    if remotePlayers[normalizedId] then
        print("Remote player already exists:", normalizedId)
        return
    end

    local player = NetworkPlayer:new(normalizedId, data.x, data.y)
    player.health = data.health or 100
    player.maxHealth = 100
    player.isAlive = data.alive or (data.health or 100) > 0
    remotePlayers[normalizedId] = player

    print(string.format("Remote player '%s' created at (%d, %d) Health: %d Alive: %s",
          normalizedId, data.x, data.y, player.health, tostring(player.isAlive)))
end

function createEnemy(enemyId, data)
    -- Prevent rapid duplicate creation
    local now = love.timer.getTime()
    if enemyCreationTimestamps[enemyId] and (now - enemyCreationTimestamps[enemyId] < 0.1) then
        print("DEBUG: Ignoring rapid duplicate enemy creation:", enemyId)
        return
    end

    if enemies[enemyId] then
        print("Enemy already exists, updating:", enemyId)
        enemies[enemyId]:applyNetworkState(data)
        enemyCreationTimestamps[enemyId] = now
        return
    end

    local Enemy = require "src.entities.Enemy"

    -- CRITICAL FIX: Create enemy with correct parameters
    -- data.x and data.y are center coordinates from network
    local enemy = Enemy:new("Enemy_" .. enemyId, data.x, data.y, data.type)

    -- Set properties from network data
    enemy.health = data.health or 100
    enemy.maxHealth = enemy.health
    enemy.enemyId = enemyId
    enemy.isAlive = (data.alive == 1) or (data.alive == true) or (data.health > 0)  -- Use network alive flag

    -- Store enemy
    enemies[enemyId] = enemy
    enemyCreationTimestamps[enemyId] = now

    print(string.format("Enemy %s created at (%d, %d) Type: %s Health: %d Alive: %s",
          enemyId, data.x, data.y, data.type or "unknown", enemy.health, tostring(enemy.isAlive)))
end

-- GAME STATE TRANSITIONS
function switchGameState(newState)
    print("Game State Transition:", gameState, "->", newState)
    gameState = newState

    if newState == "menu" then
        cleanupGame()
        if mainMenu then mainMenu:activate() end
        hostControl:hide()
        PositionSync.setActive(false)

    elseif newState == "connecting" then
        if mainMenu then mainMenu:deactivate() end
        hostControl:hide()
        PositionSync.setActive(false)

    elseif newState == "playing" then
        if mainMenu then mainMenu:deactivate() end

        -- Activate position sync when playing
        PositionSync.setActive(true)

        -- Show host control if we're the host
        if Network.isServer then
            hostControl:show()
        end
    end
end

function cleanupGame()
    print("Cleaning up game state...")

    if Network.isConnected() then
        Network.disconnect()
    end

    localPlayer = nil
    remotePlayers = {}
    myPlayerId = nil
    enemies = {}
    BaseCharacter.all = {}
    enemyCreationTimestamps = {}
    allPlayersDead = false
    gameActive = false
    lastSentState = nil

    print("Game state cleaned up")
end

-- LOVE2D UPDATE LOOP
function love.update(dt)
    Network.update(dt)

    frameCount = frameCount + 1

    -- Debug output every 60 frames
    if frameCount % 60 == 0 and gameState == "playing" then
        print(string.format("Frame %d: LocalPlayer=%s, RemotePlayers=%d, Enemies=%d, GameActive=%s",
              frameCount, tostring(localPlayer ~= nil), tableCount(remotePlayers), tableCount(enemies), tostring(gameActive)))

        -- Debug: Print player positions
        if localPlayer then
            local centerX, centerY = localPlayer:getCenter()
            print(string.format("  Local Player: center(%d, %d) top-left(%d, %d) Health: %d",
                  math.floor(centerX), math.floor(centerY),
                  math.floor(localPlayer.x), math.floor(localPlayer.y),
                  localPlayer.health))
        end

        for id, remotePlayer in pairs(remotePlayers) do
            if remotePlayer then
                local centerX, centerY = remotePlayer:getCenter()
                print(string.format("  Remote %s: center(%d, %d) target(%d, %d) Health: %d",
                      id, math.floor(centerX), math.floor(centerY),
                      math.floor(remotePlayer.targetCenterX or 0), math.floor(remotePlayer.targetCenterY or 0),
                      remotePlayer.health))
            end
        end
    end

    if gameState == "menu" then
        if mainMenu then mainMenu:update(dt) end
    elseif gameState == "connecting" then
        -- Nothing to update while connecting
    elseif gameState == "playing" then
        -- Update host control
        hostControl:update(dt)

        -- Add a position sync system to ensure players see each other move
        PositionSync.update(dt)

        -- Update local player and send state to server (OPTIMIZED: Only send on change)
        if localPlayer and localPlayer.isAlive then
            localPlayer:update(dt)

            if Network.isConnected() and localPlayer.isLocalPlayer then
                -- Get current state
                local currentState = localPlayer:getNetworkState()

                -- Check if we should send an update
                local shouldSend = false

                if not lastSentState then
                    shouldSend = true  -- First time sending
                else
                    -- Check position change
                    local dx = math.abs(currentState.x - lastSentState.x)
                    local dy = math.abs(currentState.y - lastSentState.y)
                    local dHealth = math.abs(currentState.health - lastSentState.health)

                    -- Send if position changed significantly OR health changed
                    if dx > positionThreshold or dy > positionThreshold or dHealth > 0 then
                        shouldSend = true
                    end
                end

                if shouldSend then
                    -- Validate state before sending
                    if currentState and type(currentState) == "table" and
                       currentState.x and currentState.y and currentState.health then
                        -- Ensure values are valid numbers
                        if tonumber(currentState.x) and tonumber(currentState.y) and tonumber(currentState.health) then
                            if not Network.isServer then
                                -- Client: Send state to server
                                Network.sendPlayerState(currentState)
                            else
                                -- Host: Update internal state
                                Network.setHostPlayerData(currentState)
                            end

                            -- Update last sent state
                            lastSentState = {
                                x = currentState.x,
                                y = currentState.y,
                                health = currentState.health
                            }
                        else
                            print("DEBUG: Invalid number values in player state:", currentState.x, currentState.y, currentState.health)
                        end
                    else
                        print("DEBUG: Invalid player state structure:", currentState)
                    end
                end
            end
        end

        -- Update remote players
        for id, remotePlayer in pairs(remotePlayers) do
            if remotePlayer then
                remotePlayer:update(dt)
            end
        end

        -- Update enemies (clients interpolate, server runs AI)
        for id, enemy in pairs(enemies) do
            if enemy then
                local allPlayers = {}
                if localPlayer and localPlayer.isAlive then table.insert(allPlayers, localPlayer) end
                for _, remotePlayer in pairs(remotePlayers) do
                    if remotePlayer and remotePlayer.isAlive then table.insert(allPlayers, remotePlayer) end
                end
                enemy:update(dt, allPlayers)
            end
        end

        -- Update all base characters
        require("src.entities.BaseCharacter").updateAll(dt)
    end
end

-- Add a new debug visualization function
function drawNetworkDebug()
    if not showDebugInfo then return end

    love.graphics.setFont(debugFont)

    -- Draw network player position markers
    for id, remotePlayer in pairs(remotePlayers) do
        if remotePlayer then
            -- Draw center position (red)
            local centerX, centerY = remotePlayer:getCenter()
            love.graphics.setColor(1, 0, 0, 0.5)
            love.graphics.circle("fill", centerX, centerY, 5)

            -- Draw target position (green)
            love.graphics.setColor(0, 1, 0, 0.5)
            love.graphics.circle("line", remotePlayer.targetCenterX, remotePlayer.targetCenterY, 8)

            -- Draw connection line between current and target
            love.graphics.setColor(1, 1, 0, 0.3)
            love.graphics.line(centerX, centerY, remotePlayer.targetCenterX, remotePlayer.targetCenterY)

            -- Draw ID text
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(id, centerX + 10, centerY - 10)
        end
    end

    -- Draw local player center marker
    if localPlayer then
        local centerX, centerY = localPlayer:getCenter()
        love.graphics.setColor(0, 1, 1, 0.5)  -- Cyan for local player
        love.graphics.circle("fill", centerX, centerY, 6)
        love.graphics.setColor(0, 1, 1, 0.3)
        love.graphics.circle("line", centerX, centerY, 10)
    end

    love.graphics.setColor(1, 1, 1)
end

-- LOVE2D DRAW LOOP
function love.draw()
    -- Draw the static world first
    World.draw()

    if gameState == "menu" then
        if mainMenu then mainMenu:draw() end
    elseif gameState == "connecting" then
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", 0, 0, 800, 600)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Connecting to server...", 350, 300)
    elseif gameState == "playing" then
        -- Draw enemies first (background)
        for id, enemy in pairs(enemies) do
            if enemy and enemy.isAlive then  -- CRITICAL: Check both existence and alive status
                enemy:draw()
            end
        end

        -- Draw remote players (only if alive)
        for id, remotePlayer in pairs(remotePlayers) do
            if remotePlayer and remotePlayer.isAlive then
                remotePlayer:draw()
            end
        end

        -- Draw local player (if alive)
        if localPlayer and localPlayer.isAlive then
            localPlayer:draw()
            localPlayer:drawHealthBar()
        end

        -- Draw host control panel
        hostControl:draw()

        -- Draw game UI overlay
        drawGameUI()

        -- Draw network debug visualization
        drawNetworkDebug()
    end

    -- Draw debug info overlay if enabled
    if showDebugInfo then
        drawDebugInfo()
    end
end

-- UI RENDERING FUNCTIONS
function drawGameUI()
    love.graphics.setFont(debugFont)

    -- Semi-transparent background for UI
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 5, 5, 250, 120)

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Game Status", 10, 10)
    love.graphics.print("Mode: " .. (Network.isServer and "HOST" or "CLIENT"), 10, 30)
    love.graphics.print("Connected: " .. (Network.isConnected() and "YES" or "NO"), 10, 50)
    love.graphics.print("My ID: " .. (myPlayerId or "none"), 10, 70)
    love.graphics.print("Players: " .. tableCount(remotePlayers), 10, 90)
    love.graphics.print("Enemies: " .. tableCount(enemies), 10, 110)
end

function drawDebugInfo()
    love.graphics.setFont(debugFont)

    -- Debug panel background
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 550, 5, 245, 200)

    -- Debug header
    love.graphics.setColor(0, 1, 0)
    love.graphics.print("DEBUG INFO", 555, 10)

    -- Debug information
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 555, 30)
    love.graphics.print("State: " .. gameState, 555, 50)
    love.graphics.print("Frame: " .. frameCount, 555, 70)

    -- Player info
    local yPos = 90
    if localPlayer then
        love.graphics.print("Local: " .. localPlayer.name, 555, yPos)
        yPos = yPos + 20
        love.graphics.print("  Pos: " .. math.floor(localPlayer.x) .. "," .. math.floor(localPlayer.y), 555, yPos)
        yPos = yPos + 20
        love.graphics.print("  Health: " .. localPlayer.health .. "/" .. localPlayer.maxHealth, 555, yPos)
        yPos = yPos + 20
    else
        love.graphics.print("Local: No player", 555, yPos)
        yPos = yPos + 40
    end

    love.graphics.print("Remote Players: " .. tableCount(remotePlayers), 555, yPos)
    yPos = yPos + 20
    love.graphics.print("Enemies: " .. tableCount(enemies), 555, yPos)
    yPos = yPos + 20
    love.graphics.print("Game Active: " .. tostring(gameActive), 555, yPos)

    -- Position update info
    yPos = yPos + 20
    if localPlayer and lastSentState then
        local centerX, centerY = localPlayer:getCenter()
        local dx = math.abs(centerX - lastSentState.x)
        local dy = math.abs(centerY - lastSentState.y)
        love.graphics.print("Pos Delta: " .. string.format("%.1f, %.1f", dx, dy), 555, yPos)
    end
end

-- INPUT HANDLING
function love.keypressed(key)
    -- Global key bindings
    if key == "escape" then
        if gameState == "playing" then
            switchGameState("menu")
        elseif gameState == "menu" then
            love.event.quit()
        end
    elseif key == "f1" then
        showDebugInfo = not showDebugInfo
    elseif key == "f5" then
        Network.printDebugInfo()
    elseif key == "f7" then
        print("=== DEBUG: PLAYER STATES ===")
        print("Local Player:", localPlayer and string.format("Health: %d, Alive: %s",
              localPlayer.health, tostring(localPlayer.isAlive)) or "NONE")

        print("Remote Players:")
        for id, player in pairs(remotePlayers) do
            if player then
                print(string.format("  %s: Health: %d, Alive: %s, X: %d, Y: %d",
                      id, player.health, tostring(player.isAlive), player.x, player.y))
            end
        end

        print("Enemies:")
        for id, enemy in pairs(enemies) do
            if enemy then
                print(string.format("  %s: Health: %d, Alive: %s, Type: %s",
                      id, enemy.health, tostring(enemy.isAlive), enemy.type or "unknown"))
            end
        end
    end

    -- State-specific key handling
    if gameState == "menu" and mainMenu then
        if key == "up" then
            mainMenu:selectPrevious()
        elseif key == "down" then
            mainMenu:selectNext()
        elseif key == "return" then
            mainMenu:selectCurrent()
        end
    elseif gameState == "playing" then
        -- Host controls
        if Network.isServer then
            if key == "g" and not gameActive then
                -- Start game
                Network.onStartGame({}, {getIndex = function() return "host" end})
            elseif key == "space" and hostControl.awaitingConfirmation then
                -- Confirm wave
                print("Host: Attempting to confirm wave...")
                Network.onWaveConfirm({}, {getIndex = function() return "host" end})
            elseif key == "r" then
                -- Restart game
                Network.onRestartGame({}, {getIndex = function() return "host" end})
            end
        end

        -- Debug keys
        if key == "p" then
            print("=== Remote Players ===")
            for id, player in pairs(remotePlayers) do
                print(string.format("  %s: (%d, %d) Health: %d", id, player.x, player.y, player.health))
            end
        elseif key == "e" then
            print("=== Enemies ===")
            for id, enemy in pairs(enemies) do
                print(string.format("  %s: (%d, %d) Health: %d", id, enemy.x, enemy.y, enemy.health))
            end
        end
    end
end

-- UTILITY FUNCTIONS
function tableCount(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

function love.quit()
    print("Game closing...")
    return false
end
