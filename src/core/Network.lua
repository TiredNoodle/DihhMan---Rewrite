-- src/core/Network.lua
-- Main networking module for wave survival game

local sock = require "lib.sock"
local bitser = require "lib.bitser"
local World = require "src.core.World"
local MessageHandler = require "src.core.MessageHandler"

-- NETWORK MODULE DEFINITION
-- =========================
local Network = {
    isServer = false,           -- True if this instance is hosting
    connectedPlayers = {},      -- Server-only: tracks connected clients
    hostPlayerData = nil,       -- Server-only: host's player data
    lastHostUpdateTime = 0,     -- Server-only: time of last host update broadcast
    hostUpdateInterval = 0.033, -- Server-only: send host updates ~30 times/sec

    -- Wave system
    waveManager = nil,          -- WaveManager instance
    gameActive = false,         -- Whether the game is currently active
    allPlayersDead = false,     -- Whether all players are dead (game over)
    canAcceptPlayers = true,    -- Whether new players can join (false during waves)

    -- Enemy system
    enemies = {},              -- Server-only: track all enemies
    lastEnemySpawnTime = 0,    -- Server-only: track enemy spawning
    enemySpawnInterval = 0.8,  -- Seconds between enemy spawns during wave

    -- Game state persistence
    persistentPlayerStates = {}, -- Keep player states even after disconnect

    -- Position update optimization
    lastSentPositions = {},    -- Track last sent position per player
    positionThreshold = 2.0,   -- Minimum movement required to send update
}

-- Private variables for network connections
local server, client

-- Helper function to count table entries
local function tableCount(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Helper function to get serializable game state
local function getGameState()
    local playersData = {}

    -- Include host player
    if Network.hostPlayerData then
        playersData["Host"] = {
            id = "Host",
            x = Network.hostPlayerData.x,
            y = Network.hostPlayerData.y,
            health = Network.hostPlayerData.health,
            alive = Network.hostPlayerData.health > 0
        }
    end

    -- Include connected clients
    for id, player in pairs(Network.connectedPlayers) do
        playersData[id] = {
            id = id,
            x = player.x,
            y = player.y,
            health = player.health,
            alive = player.health > 0
        }
    end

    -- Get enemy data
    local enemiesData = {}
    for enemyId, enemy in pairs(Network.enemies) do
        enemiesData[enemyId] = {
            id = enemyId,
            x = enemy.x,
            y = enemy.y,
            type = enemy.type,
            health = enemy.health
        }
    end

    return {
        players = playersData,
        enemies = enemiesData,
        gameActive = Network.gameActive,
        waveStatus = Network.waveManager and Network.waveManager:getStatus() or nil
    }
end

-- Broadcast game state to all clients
local function broadcastGameState()
    if not Network.isServer or not server then return end

    local gameState = getGameState()

    for id, player in pairs(Network.connectedPlayers) do
        if player and player.client then
            MessageHandler:configureSendMode(player.client, "gameState")
            player.client:send("gameState", {
                players = gameState.players,
                enemies = gameState.enemies,
                yourId = id,
                gameActive = Network.gameActive,
                waveStatus = gameState.waveStatus
            })
        end
    end

    -- Notify host about game state
    if Network.onGameStateCallback then
        Network.onGameStateCallback({
            players = gameState.players,
            enemies = gameState.enemies,
            yourId = "Host",
            gameActive = Network.gameActive,
            waveStatus = gameState.waveStatus
        })
    end
end

-- Broadcast host position updates to all connected clients
local function broadcastHostUpdate()
    if not Network.isServer or not server or not Network.hostPlayerData then
        return
    end

    -- Send host update to all connected clients
    for id, player in pairs(Network.connectedPlayers) do
        if player and player.client then
            MessageHandler:configureSendMode(player.client, "playerUpdated")
            player.client:send("playerUpdated", {
                id = "Host",
                x = Network.hostPlayerData.x,
                y = Network.hostPlayerData.y,
                health = Network.hostPlayerData.health
            })
        end
    end
end

-- Check if all players are dead
local function checkAllPlayersDead()
    if not Network.gameActive then return false end

    local aliveCount = 0

    -- Check host
    if Network.hostPlayerData and Network.hostPlayerData.health > 0 then
        aliveCount = aliveCount + 1
    end

    -- Check connected players
    for id, player in pairs(Network.connectedPlayers) do
        if player.health > 0 then
            aliveCount = aliveCount + 1
        end
    end

    return aliveCount == 0
end

-- Broadcast game over to all clients
local function broadcastGameOver()
    if not Network.isServer or not server then return end

    local waveStatus = Network.waveManager and Network.waveManager:getStatus() or {}

    for id, player in pairs(Network.connectedPlayers) do
        if player and player.client then
            MessageHandler:configureSendMode(player.client, "gameOver")
            player.client:send("gameOver", {
                message = "All players dead! Host can restart.",
                stage = waveStatus.stage or 0,
                wave = waveStatus.wave or 0
            })
        end
    end

    -- Notify host
    if Network.onGameOverCallback then
        Network.onGameOverCallback({
            message = "All players dead! Host can restart.",
            stage = waveStatus.stage or 0,
            wave = waveStatus.wave or 0
        })
    end

    Network.allPlayersDead = true
    Network.canAcceptPlayers = true  -- Allow new players after game over
end

-- Clean up all enemies on server
function Network.cleanupEnemies()
    Network.enemies = {}
    Network.lastEnemySpawnTime = 0
    print("Network: Enemies cleared")
end

-- Enemy damage stats
local enemyDamageStats = {
    melee = {damage = 10, attackRange = 60, attackCooldown = 1.5},
    ranged = {damage = 8, attackRange = 100, attackCooldown = 2.0},
    boss = {damage = 25, attackRange = 80, attackCooldown = 2.5},
    sample_fast = {damage = 15, attackRange = 50, attackCooldown = 1.0}
}

-- Enemy attack timers
local enemyAttackTimers = {}

-- Apply enemy damage to players - UPDATED WITH FIXED LOGIC
local function applyEnemyDamage(enemyId, enemy, targetPlayer, targetType, targetId)
    local stats = enemyDamageStats[enemy.type] or enemyDamageStats.melee

    -- Check if enemy can attack
    local attackKey = enemyId .. "_" .. (targetId or "host")
    enemyAttackTimers[attackKey] = enemyAttackTimers[attackKey] or 0

    if enemyAttackTimers[attackKey] > 0 then
        return false  -- Still on cooldown
    end

    -- Apply damage
    local damageApplied = false

    if targetType == "host" then
        if Network.hostPlayerData then
            Network.hostPlayerData.health = math.max(0, Network.hostPlayerData.health - stats.damage)
            print(string.format("Server: Enemy %s dealt %d damage to Host (health: %d)",
                  enemyId, stats.damage, Network.hostPlayerData.health))

            -- Update host data
            Network.setHostPlayerData(Network.hostPlayerData)
            broadcastHostUpdate()

            -- Check if host died
            if Network.hostPlayerData.health <= 0 then
                print("Server: Host has been killed!")
                -- Notify host death to all clients
                for id, player in pairs(Network.connectedPlayers) do
                    if player and player.client then
                        MessageHandler:configureSendMode(player.client, "playerUpdated")
                        player.client:send("playerUpdated", {
                            id = "Host",
                            x = Network.hostPlayerData.x,
                            y = Network.hostPlayerData.y,
                            health = 0,
                            alive = false
                        })
                    end
                end
            end

            damageApplied = true
        end
    else
        -- Apply damage to connected player
        local player = Network.connectedPlayers[targetId]
        if player then
            local oldHealth = player.health
            player.health = math.max(0, player.health - stats.damage)
            print(string.format("Server: Enemy %s dealt %d damage to Player %s (health: %d -> %d)",
                  enemyId, stats.damage, targetId, oldHealth, player.health))

            -- Update persistent state
            if Network.persistentPlayerStates[targetId] then
                Network.persistentPlayerStates[targetId].health = player.health
                Network.persistentPlayerStates[targetId].alive = player.health > 0
            end

            -- Broadcast player update to ALL clients (including host via callback)
            for id, p in pairs(Network.connectedPlayers) do
                if p and p.client then
                    MessageHandler:configureSendMode(p.client, "playerUpdated")
                    p.client:send("playerUpdated", {
                        id = targetId,
                        x = player.x,
                        y = player.y,
                        health = player.health,
                        alive = player.health > 0
                    })
                end
            end

            -- Notify host
            if Network.onPlayerUpdatedCallback then
                Network.onPlayerUpdatedCallback({
                    id = targetId,
                    x = player.x,
                    y = player.y,
                    health = player.health,
                    alive = player.health > 0
                })
            end

            -- Check if player died
            if player.health <= 0 then
                print("Server: Player " .. targetId .. " has been killed!")
            end

            damageApplied = true
        end
    end

    -- Set attack cooldown only if damage was applied
    if damageApplied then
        enemyAttackTimers[attackKey] = stats.attackCooldown
    end

    return damageApplied
end

-- Update enemy attack timers
local function updateEnemyAttackTimers(dt)
    for key, timer in pairs(enemyAttackTimers) do
        if timer > 0 then
            enemyAttackTimers[key] = timer - dt
            if enemyAttackTimers[key] <= 0 then
                enemyAttackTimers[key] = 0
            end
        end
    end
end

-- Check if position has changed significantly
local function positionChanged(playerId, newX, newY)
    local lastPos = Network.lastSentPositions[playerId]
    if not lastPos then
        return true  -- First time sending
    end

    local dx = math.abs(newX - lastPos.x)
    local dy = math.abs(newY - lastPos.y)

    return dx > Network.positionThreshold or dy > Network.positionThreshold
end

-- Update last sent position
local function updateLastSentPosition(playerId, x, y)
    Network.lastSentPositions[playerId] = {x = x, y = y}
end

-- INITIALIZATION
function Network.init(host, port, serverMode)
    Network.isServer = serverMode
    Network.gameActive = false
    Network.allPlayersDead = false
    Network.canAcceptPlayers = true

    -- Clear any existing connections
    Network.connectedPlayers = {}
    Network.persistentPlayerStates = {}
    Network.enemies = {}
    enemyAttackTimers = {}
    Network.lastSentPositions = {}

    if Network.isServer then
        -- Initialize WaveManager for server
        Network.waveManager = require("src.core.WaveManager"):new()

        -- SERVER INITIALIZATION
        print(string.format("Initializing server on %s:%d", host, port))
        server = sock.newServer(host, port)
        server:setSerialization(bitser.dumps, bitser.loads)

        -- Server event handlers
        server:on("connect", function(data, clientObj)
            Network.onClientConnected(clientObj, data)
        end)

        server:on("startGame", function(data, clientObj)
            Network.onStartGame(data, clientObj)
        end)

        server:on("waveConfirm", function(data, clientObj)
            Network.onWaveConfirm(data, clientObj)
        end)

        server:on("restartGame", function(data, clientObj)
            Network.onRestartGame(data, clientObj)
        end)

        server:on("playerUpdate", function(data, clientObj)
            Network.onPlayerUpdate(data, clientObj)
        end)

        server:on("playerAction", function(data, clientObj)
            Network.onPlayerAction(data, clientObj)
        end)

        server:on("disconnect", function(data, clientObj)
            Network.onClientDisconnected(clientObj, data)
        end)

        print("Server started. Waiting for connections...")

        -- Add host to game
        Network.persistentPlayerStates["Host"] = {
            id = "Host",
            x = 400,
            y = 300,
            health = 100,
            alive = true
        }

        -- Notify that host is ready
        if Network.onHostCreatedCallback then
            Network.onHostCreatedCallback()
        end
    else
        -- CLIENT INITIALIZATION
        print(string.format("Initializing client connecting to %s:%d", host, port))
        client = sock.newClient(host, port)
        client:setSerialization(bitser.dumps, bitser.loads)

        -- Client event handlers
        client:on("connect", function(data)
            Network.onConnected(data)
        end)

        client:on("playerId", function(data)
            if Network.onPlayerIdCallback then
                Network.onPlayerIdCallback(data)
            end
        end)

        client:on("gameState", function(data)
            Network.onGameStateReceived(data)
        end)

        client:on("gameStarted", function(data)
            if Network.onGameStartedCallback then
                Network.onGameStartedCallback(data)
            end
        end)

        client:on("waveStarted", function(data)
            if Network.onWaveStartedCallback then
                Network.onWaveStartedCallback(data)
            end
        end)

        client:on("waveCompleted", function(data)
            if Network.onWaveCompletedCallback then
                Network.onWaveCompletedCallback(data)
            end
        end)

        client:on("gameOver", function(data)
            if Network.onGameOverCallback then
                Network.onGameOverCallback(data)
            end
        end)

        client:on("gameRestart", function(data)
            if Network.onGameRestartCallback then
                Network.onGameRestartCallback(data)
            end
        end)

        client:on("playerJoined", function(data)
            if Network.onPlayerJoinedCallback then
                Network.onPlayerJoinedCallback(data)
            end
        end)

        client:on("playerUpdated", function(data)
            if Network.onPlayerUpdatedCallback then
                Network.onPlayerUpdatedCallback(data)
            end
        end)

        client:on("playerLeft", function(data)
            if Network.onPlayerLeftCallback then
                Network.onPlayerLeftCallback(data)
            end
        end)

        client:on("playerCorrected", function(data)
            if Network.onPlayerCorrectedCallback then
                Network.onPlayerCorrectedCallback(data)
            end
        end)

        client:on("enemySpawned", function(data)
            if Network.onEnemySpawnedCallback then
                Network.onEnemySpawnedCallback(data)
            end
        end)

        client:on("enemyUpdated", function(data)
            if Network.onEnemyUpdatedCallback then
                Network.onEnemyUpdatedCallback(data)
            end
        end)

        client:on("enemyDied", function(data)
            if Network.onEnemyDiedCallback then
                Network.onEnemyDiedCallback(data)
            end
        end)

        client:on("playerAction", function(data)
            if Network.onPlayerActionCallback then
                Network.onPlayerActionCallback(data)
            end
        end)

        client:on("disconnect", function(data)
            if Network.onDisconnectCallback then
                Network.onDisconnectCallback(data)
            end
        end)

        -- Attempt connection
        client:connect()
        print("Client attempting connection...")
    end
end

-- FRAME UPDATE
function Network.update(dt)
    if Network.isServer and server then
        server:update()

        -- Update enemy attack timers
        updateEnemyAttackTimers(dt)

        -- Position broadcast timer
        Network.positionBroadcastTimer = (Network.positionBroadcastTimer or 0) - dt
        if Network.positionBroadcastTimer <= 0 then
            Network.broadcastPlayerPositions()
            Network.positionBroadcastTimer = 0.033  -- ~30 times/sec
        end

        -- Update wave manager if game is active
        if Network.waveManager and Network.gameActive then
            local waveEvent = Network.waveManager:update(dt)

            if waveEvent then
                if waveEvent.type == "wave_started" then
                    -- Broadcast wave start
                    local waveData = waveEvent.data

                    for id, player in pairs(Network.connectedPlayers) do
                        if player and player.client then
                            MessageHandler:configureSendMode(player.client, "waveStarted")
                            player.client:send("waveStarted", waveData)
                        end
                    end

                    -- Notify host
                    if Network.onWaveStartedCallback then
                        Network.onWaveStartedCallback(waveData)
                    end

                elseif waveEvent.type == "wave_completed" then
                    -- Broadcast wave completion
                    local waveData = waveEvent.data

                    for id, player in pairs(Network.connectedPlayers) do
                        if player and player.client then
                            MessageHandler:configureSendMode(player.client, "waveCompleted")
                            player.client:send("waveCompleted", waveData)
                        end
                    end

                    -- Notify host
                    if Network.onWaveCompletedCallback then
                        Network.onWaveCompletedCallback(waveData)
                    end

                    -- Update player acceptance based on wave state
                    Network.canAcceptPlayers = Network.waveManager:canAcceptNewPlayers()
                elseif waveEvent.type == "countdown" then
                    -- Update countdown display (host only)
                    if Network.onGameStartedCallback then
                        Network.onGameStartedCallback({
                            countdown = waveEvent.data.countdown,
                            message = "Starting in " .. waveEvent.data.countdown .. " seconds..."
                        })
                    end
                end
            end

            -- Spawn enemies during active waves
            if Network.waveManager.isWaveActive then
                Network.updateEnemies(dt)
            end
        end

        -- Periodically broadcast host updates to all clients
        local currentTime = love.timer.getTime()
        if Network.hostPlayerData and currentTime - Network.lastHostUpdateTime > Network.hostUpdateInterval then
            -- Only broadcast if position changed significantly
            if positionChanged("Host", Network.hostPlayerData.x, Network.hostPlayerData.y) then
                broadcastHostUpdate()
                updateLastSentPosition("Host", Network.hostPlayerData.x, Network.hostPlayerData.y)
                Network.lastHostUpdateTime = currentTime
            end
        end

        -- Check if all players are dead and broadcast game over
        if Network.gameActive and checkAllPlayersDead() and not Network.allPlayersDead then
            broadcastGameOver()
        end
    elseif client then
        client:update()
    end
end

-- SERVER EVENT HANDLERS

-- Called when a new client connects to the server
function Network.onClientConnected(clientObj, data)
    local clientId = tostring(clientObj:getIndex())

    -- Check if we can accept new players
    if not Network.canAcceptPlayers then
        print("Server: Rejecting new player - wave in progress")
        clientObj:disconnect()
        return
    end

    print("Server: Client connected with ID:", clientId)

    -- Find a valid spawn location
    local spawnX, spawnY = World.findSpawnLocation()

    -- Store player data with client object
    Network.connectedPlayers[clientId] = {
        client = clientObj,  -- Store the client object
        id = clientId,
        x = spawnX,
        y = spawnY,
        health = 100,
        lastSentX = spawnX,
        lastSentY = spawnY
    }

    -- Send the client its player ID
    clientObj:send("playerId", {id = clientId})

    -- Add to persistent states
    Network.persistentPlayerStates[clientId] = {
        id = clientId,
        x = spawnX,
        y = spawnY,
        health = 100,
        alive = true
    }

    -- Broadcast updated game state to ALL clients
    broadcastGameState()

    -- Notify other players about new player
    for id, player in pairs(Network.connectedPlayers) do
        if id ~= clientId and player and player.client then
            MessageHandler:configureSendMode(player.client, "playerJoined")
            player.client:send("playerJoined", {
                id = clientId,
                x = spawnX,
                y = spawnY,
                health = 100
            })
        end
    end

    -- Notify host
    if Network.onPlayerJoinedCallback then
        Network.onPlayerJoinedCallback({
            id = clientId,
            x = spawnX,
            y = spawnY,
            health = 100
        })
    end

    print("Server: Player", clientId, "joined the game")
end

-- Called when host wants to start game
function Network.onStartGame(data, clientObj)
    -- Only host can start game
    local clientId = tostring(clientObj:getIndex())
    if clientId ~= "host" and clientId ~= "Host" then
        print("Server: Non-host tried to start game:", clientId)
        return
    end

    if Network.gameActive then
        print("Server: Game already active")
        return
    end

    -- Start the wave-based game
    Network.gameActive = true
    Network.allPlayersDead = false
    Network.canAcceptPlayers = false  -- Don't accept new players during game

    local waveData = Network.waveManager:startGame()

    -- Broadcast game start with countdown
    for id, player in pairs(Network.connectedPlayers) do
        if player and player.client then
            MessageHandler:configureSendMode(player.client, "gameStarted")
            player.client:send("gameStarted", {
                stage = waveData.stage,
                wave = waveData.wave,
                countdown = waveData.countdown,
                message = waveData.message,
                gameActive = true
            })
        end
    end

    -- Notify host
    if Network.onGameStartedCallback then
        Network.onGameStartedCallback({
            stage = waveData.stage,
            wave = waveData.wave,
            countdown = waveData.countdown,
            message = waveData.message,
            gameActive = true
        })
    end

    print("Server: Wave-based game started with 5-second countdown")
end

-- Called when host confirms a wave
function Network.onWaveConfirm(data, clientObj)
    local clientId = tostring(clientObj:getIndex())
    if clientId ~= "host" and clientId ~= "Host" then
        print("Server: Non-host tried to confirm wave:", clientId)
        return
    end

    if not Network.waveManager or not Network.gameActive then
        print("Server: Cannot confirm wave - game not active")
        return
    end

    -- FIX: Check if we're actually awaiting confirmation
    local waveStatus = Network.waveManager:getStatus()
    if not waveStatus.awaitingConfirmation then
        print("Server: Cannot confirm wave - not awaiting confirmation")
        return
    end

    if Network.waveManager:confirmWave() then
        local waveData = Network.waveManager:getStatus()

        -- Broadcast wave start
        for id, player in pairs(Network.connectedPlayers) do
            if player and player.client then
                MessageHandler:configureSendMode(player.client, "waveStarted")
                player.client:send("waveStarted", {
                    stage = waveData.stage,
                    wave = waveData.wave,
                    enemies = waveData.totalEnemies,
                    message = "Wave " .. waveData.wave .. " (Stage " .. waveData.stage .. ") started by host!"
                })
            end
        end

        -- Notify host
        if Network.onWaveStartedCallback then
            Network.onWaveStartedCallback({
                stage = waveData.stage,
                wave = waveData.wave,
                enemies = waveData.totalEnemies,
                message = "Wave " .. waveData.wave .. " (Stage " .. waveData.stage .. ") started!"
            })
        end

        Network.canAcceptPlayers = false  -- Don't accept new players during wave
        print("Server: Wave", waveData.wave, "confirmed and started")
    end
end

-- Called when host wants to restart game
function Network.onRestartGame(data, clientObj)
    local clientId = tostring(clientObj:getIndex())
    if clientId ~= "host" and clientId ~= "Host" then
        print("Server: Non-host tried to restart game:", clientId)
        return
    end

    if not Network.allPlayersDead then
        print("Server: Cannot restart - players still alive")
        return
    end

    -- Reset game state
    Network.gameActive = false
    Network.allPlayersDead = false
    Network.canAcceptPlayers = true
    Network.enemies = {}
    Network.lastEnemySpawnTime = 0
    enemyAttackTimers = {}
    Network.lastSentPositions = {}

    -- Reset wave manager
    if Network.waveManager then
        Network.waveManager:reset()
    end

    -- Reset all players
    for id, player in pairs(Network.connectedPlayers) do
        player.health = 100
        player.lastSentX = player.x
        player.lastSentY = player.y
    end

    -- Reset persistent states
    for id, state in pairs(Network.persistentPlayerStates) do
        state.health = 100
        state.alive = true
    end

    if Network.hostPlayerData then
        Network.hostPlayerData.health = 100
    end

    -- Broadcast restart
    for id, player in pairs(Network.connectedPlayers) do
        if player and player.client then
            MessageHandler:configureSendMode(player.client, "gameRestart")
            player.client:send("gameRestart", {
                message = "Game restarted by host! Players can join."
            })
        end
    end

    -- Broadcast updated game state
    broadcastGameState()

    print("Server: Game restarted by host")
end

-- Called when a client disconnects from server
function Network.onClientDisconnected(clientObj, data)
    local clientId = tostring(clientObj:getIndex())
    print("Server: Client disconnected:", clientId)

    -- Mark as dead in persistent state
    if Network.persistentPlayerStates[clientId] then
        Network.persistentPlayerStates[clientId].alive = false
    end

    -- Broadcast player left
    for id, player in pairs(Network.connectedPlayers) do
        if id ~= clientId and player and player.client then
            MessageHandler:configureSendMode(player.client, "playerLeft")
            player.client:send("playerLeft", {
                id = clientId,
                reason = "disconnected",
                alive = false
            })
        end
    end

    -- Notify host
    if Network.onPlayerLeftCallback then
        Network.onPlayerLeftCallback({
            id = clientId,
            reason = "disconnected",
            alive = false
        })
    end

    -- Remove from connected players
    Network.connectedPlayers[clientId] = nil
    Network.lastSentPositions[clientId] = nil

    -- Broadcast updated state
    broadcastGameState()
end

-- Processes position updates from clients - FIXED VERSION
function Network.onPlayerUpdate(data, clientObj)
    -- Validate data structure
    if type(data) ~= "table" then
        print("Server: Received invalid player update - not a table:", type(data))
        return
    end

    local clientId = tostring(clientObj:getIndex())
    if not Network.connectedPlayers[clientId] then
        print("Server: Received update from unknown client:", clientId)
        return
    end

    local playerData = Network.connectedPlayers[clientId]
    local oldX, oldY = playerData.x, playerData.y
    local oldHealth = playerData.health

    -- Check for required fields
    if data.x == nil or data.y == nil or data.health == nil then
        print("Server: Received player update with missing fields:",
              "x=" .. tostring(data.x),
              "y=" .. tostring(data.y),
              "health=" .. tostring(data.health))
        return
    end

    -- Accept the update
    playerData.x = data.x
    playerData.y = data.y
    playerData.health = data.health

    -- Update persistent state
    if Network.persistentPlayerStates[clientId] then
        Network.persistentPlayerStates[clientId].x = data.x
        Network.persistentPlayerStates[clientId].y = data.y
        Network.persistentPlayerStates[clientId].health = data.health
        Network.persistentPlayerStates[clientId].alive = data.health > 0
    end

    -- Only broadcast update if position changed significantly
    if positionChanged(clientId, data.x, data.y) or data.health ~= oldHealth then
        -- Broadcast update to all other clients (including host via callback)
        for id, player in pairs(Network.connectedPlayers) do
            if id ~= clientId and player and player.client then
                MessageHandler:configureSendMode(player.client, "playerUpdated")
                player.client:send("playerUpdated", {
                    id = clientId,
                    x = playerData.x,
                    y = playerData.y,
                    health = playerData.health,
                    alive = playerData.health > 0
                })
            end
        end

        -- Also update host via callback
        if Network.onPlayerUpdatedCallback then
            Network.onPlayerUpdatedCallback({
                id = clientId,
                x = playerData.x,
                y = playerData.y,
                health = playerData.health,
                alive = playerData.health > 0
            })
        end

        -- Update last sent position
        updateLastSentPosition(clientId, data.x, data.y)
        playerData.lastSentX = data.x
        playerData.lastSentY = data.y

        print(string.format("Server: Updated player %s to position (%d, %d)",
              clientId, playerData.x, playerData.y))
    end
end

-- PLAYER ACTION HANDLING - FIXED FOR DASH
function Network.onPlayerAction(data, clientObj)
    if not data or not data.action then return end

    local clientId = tostring(clientObj:getIndex())
    local senderPlayerId = clientId
    if data.playerId == "Host" or data.playerId == "host" then
        senderPlayerId = "Host"
    end

    -- Handle dash movement with full parameters
    if data.action == "dash" and (data.targetX and data.targetY) then
        print(string.format("Server: Player %s dashing to (%.1f, %.1f)",
              senderPlayerId, data.targetX, data.targetY))

        -- Update player position immediately for server authoritative movement
        if senderPlayerId == "Host" and Network.hostPlayerData then
            Network.hostPlayerData.x = data.targetX
            Network.hostPlayerData.y = data.targetY
            -- Force position update for dash
            updateLastSentPosition("Host", data.targetX, data.targetY)
        elseif Network.connectedPlayers[senderPlayerId] then
            Network.connectedPlayers[senderPlayerId].x = data.targetX
            Network.connectedPlayers[senderPlayerId].y = data.targetY
            updateLastSentPosition(senderPlayerId, data.targetX, data.targetY)
        end
    end

    -- SERVER-SIDE DAMAGE PROCESSING
    if (data.action == "attack" or data.action == "special") and data.x and data.y then
        local damageAmount = (data.action == "special") and 40 or 20
        local attackRange = (data.action == "special") and 100 or 60

        -- Find the closest enemy to the attack position
        local closestEnemy = nil
        local closestDistance = attackRange

        for enemyId, enemy in pairs(Network.enemies) do
            local dx = enemy.x - data.x
            local dy = enemy.y - data.y
            local distance = math.sqrt(dx*dx + dy*dy)

            if distance < closestDistance then
                closestDistance = distance
                closestEnemy = {id = enemyId, data = enemy}
            end
        end

        -- If an enemy is in range, apply damage
        if closestEnemy then
            closestEnemy.data.health = closestEnemy.data.health - damageAmount
            print(string.format("Server: Player %s dealt %d damage to enemy %s (health: %d)",
                  senderPlayerId, damageAmount, closestEnemy.id, closestEnemy.data.health))

            -- Check if enemy died
            if closestEnemy.data.health <= 0 then
                -- Notify wave manager
                if Network.waveManager then
                    Network.waveManager:enemyDied()
                end

                -- Broadcast enemy death
                for id, player in pairs(Network.connectedPlayers) do
                    if player and player.client then
                        MessageHandler:configureSendMode(player.client, "enemyDied")
                        player.client:send("enemyDied", {id = closestEnemy.id})
                    end
                end

                -- Notify host via callback
                if Network.onEnemyDiedCallback then
                    Network.onEnemyDiedCallback({id = closestEnemy.id})
                end

                -- Remove from server tracking
                Network.enemies[closestEnemy.id] = nil
                print("Server: Enemy", closestEnemy.id, "has been defeated")
            else
                -- Broadcast enemy health update
                for id, player in pairs(Network.connectedPlayers) do
                    if player and player.client then
                        MessageHandler:configureSendMode(player.client, "enemyUpdated")
                        player.client:send("enemyUpdated", {
                            id = closestEnemy.id,
                            x = closestEnemy.data.x,
                            y = closestEnemy.data.y,
                            health = closestEnemy.data.health
                        })
                    end
                end

                -- Notify host via callback
                if Network.onEnemyUpdatedCallback then
                    Network.onEnemyUpdatedCallback({
                        id = closestEnemy.id,
                        x = closestEnemy.data.x,
                        y = closestEnemy.data.y,
                        health = closestEnemy.data.health
                    })
                end
            end
        end
    end

    -- Broadcast action to all other clients with ALL parameters
    for id, player in pairs(Network.connectedPlayers) do
        if id ~= clientId and player and player.client then
            MessageHandler:configureSendMode(player.client, "playerAction")
            player.client:send("playerAction", {
                playerId = senderPlayerId,
                action = data.action,
                x = data.x,
                y = data.y,
                direction = data.direction,
                directionX = data.directionX,
                directionY = data.directionY,
                distance = data.distance,
                duration = data.duration,
                targetId = data.targetId,
                targetX = data.targetX,
                targetY = data.targetY,
                timestamp = data.timestamp
            })
        end
    end

    -- Also notify the host about this action (if it came from a client)
    if Network.onPlayerActionCallback then
        Network.onPlayerActionCallback({
            playerId = senderPlayerId,
            action = data.action,
            x = data.x,
            y = data.y,
            direction = data.direction,
            directionX = data.directionX,
            directionY = data.directionY,
            distance = data.distance,
            duration = data.duration,
            targetId = data.targetId,
            targetX = data.targetX,
            targetY = data.targetY,
            timestamp = data.timestamp
        })
    end
end

function Network.sendPlayerAction(actionData)
    if client and client:isConnected() then
        MessageHandler:configureSendMode(client, "playerAction")
        client:send("playerAction", actionData)
    end
end

function Network.broadcastPlayerPositions()
    if not Network.isServer or not server then return end

    -- Send all player positions to all clients
    for clientId, playerData in pairs(Network.connectedPlayers) do
        -- Only send if position changed significantly
        if positionChanged(clientId, playerData.x, playerData.y) then
            for otherId, otherPlayer in pairs(Network.connectedPlayers) do
                if clientId ~= otherId and otherPlayer and otherPlayer.client then
                    MessageHandler:configureSendMode(otherPlayer.client, "playerUpdated")
                    otherPlayer.client:send("playerUpdated", {
                        id = clientId,
                        x = playerData.x,
                        y = playerData.y,
                        health = playerData.health,
                        alive = playerData.health > 0
                    })
                end
            end

            -- Update last sent position
            updateLastSentPosition(clientId, playerData.x, playerData.y)
            playerData.lastSentX = playerData.x
            playerData.lastSentY = playerData.y
        end
    end

    -- Also send host player to all clients (if position changed)
    if Network.hostPlayerData and positionChanged("Host", Network.hostPlayerData.x, Network.hostPlayerData.y) then
        for _, player in pairs(Network.connectedPlayers) do
            if player and player.client then
                MessageHandler:configureSendMode(player.client, "playerUpdated")
                player.client:send("playerUpdated", {
                    id = "Host",
                    x = Network.hostPlayerData.x,
                    y = Network.hostPlayerData.y,
                    health = Network.hostPlayerData.health,
                    alive = Network.hostPlayerData.health > 0
                })
            end
        end
        updateLastSentPosition("Host", Network.hostPlayerData.x, Network.hostPlayerData.y)
    end
end

-- ENEMY MANAGEMENT FUNCTIONS
function Network.spawnEnemy()
    if not Network.isServer or not server or not Network.waveManager then return nil end

    if not Network.waveManager.isWaveActive then
        return nil  -- Don't spawn enemies outside of waves
    end

    local currentTime = love.timer.getTime()
    if not Network.waveManager:shouldSpawnEnemy(currentTime) then
        return nil
    end

    -- Get enemy type from wave manager
    local enemyType = Network.waveManager:spawnEnemy(currentTime)

    -- Spawn enemy at random location
    local spawnX, spawnY = World.findSpawnLocation()

    local enemyId = tostring(love.math.random(10000, 99999))

    -- Set enemy health based on type
    local enemyHealth
    if enemyType == "boss" then
        enemyHealth = 300
    elseif enemyType == "ranged" then
        enemyHealth = 80
    elseif enemyType == "sample_fast" then
        enemyHealth = 75
    else
        enemyHealth = 100  -- melee
    end

    local enemyData = {
        id = enemyId,
        x = spawnX,
        y = spawnY,
        type = enemyType,
        health = enemyHealth,
        alive = 1  -- CRITICAL: Add alive flag
    }

    -- Store enemy
    Network.enemies[enemyId] = enemyData

    -- Broadcast to all clients
    for _, player in pairs(Network.connectedPlayers) do
        if player and player.client then
            MessageHandler:configureSendMode(player.client, "enemySpawned")
            player.client:send("enemySpawned", enemyData)
        end
    end

    -- Notify host
    if Network.onEnemySpawnedCallback then
        Network.onEnemySpawnedCallback(enemyData)
    end

    print("Server: Spawned enemy", enemyId, "type:", enemyType, "health:", enemyHealth)
    return enemyId
end

function Network.updateEnemies(dt)
    if not Network.isServer or not Network.waveManager or not Network.waveManager.isWaveActive then return end

    -- Spawn enemies for current wave
    Network.spawnEnemy()

    -- Enemy movement stats
    local enemySpeedStats = {
        melee = 120,
        ranged = 100,
        boss = 80,
        sample_fast = 150
    }

    -- Update existing enemies (simple AI)
    for enemyId, enemy in pairs(Network.enemies) do
        -- Find nearest player to chase
        local nearestPlayer = nil
        local nearestDistance = math.huge
        local targetType = nil
        local targetId = nil

        -- Check host player (if alive)
        if Network.hostPlayerData and Network.hostPlayerData.health > 0 then
            local dx = enemy.x - Network.hostPlayerData.x
            local dy = enemy.y - Network.hostPlayerData.y
            local distance = math.sqrt(dx*dx + dy*dy)
            if distance < nearestDistance then
                nearestDistance = distance
                nearestPlayer = Network.hostPlayerData
                targetType = "host"
            end
        end

        -- Check connected clients (if alive)
        for clientId, player in pairs(Network.connectedPlayers) do
            if player.health > 0 then
                local dx = enemy.x - player.x
                local dy = enemy.y - player.y
                local distance = math.sqrt(dx*dx + dy*dy)
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestPlayer = player
                    targetType = "client"
                    targetId = clientId
                end
            end
        end

        -- Move enemy toward nearest player
        if nearestPlayer and nearestDistance > 50 then
            local dx = nearestPlayer.x - enemy.x
            local dy = nearestPlayer.y - enemy.y
            local dist = math.sqrt(dx*dx + dy*dy)

            if dist > 0 then
                local speed = enemySpeedStats[enemy.type] or enemySpeedStats.melee
                enemy.x = enemy.x + (dx/dist) * speed * dt
                enemy.y = enemy.y + (dy/dist) * speed * dt

                -- Check if enemy can attack
                local stats = enemyDamageStats[enemy.type] or enemyDamageStats.melee
                if nearestDistance < stats.attackRange then
                    -- Apply damage to player
                    applyEnemyDamage(enemyId, enemy, nearestPlayer, targetType, targetId)
                end

                -- Broadcast update to all clients
                for _, player in pairs(Network.connectedPlayers) do
                    if player and player.client then
                        MessageHandler:configureSendMode(player.client, "enemyUpdated")
                        player.client:send("enemyUpdated", {
                            id = enemyId,
                            x = math.floor(enemy.x),
                            y = math.floor(enemy.y),
                            health = enemy.health,
                            type = enemy.type,
                            alive = enemy.health > 0 and 1 or 0
                        })
                    end
                end

                -- Notify host
                if Network.onEnemyUpdatedCallback then
                    Network.onEnemyUpdatedCallback({
                        id = enemyId,
                        x = math.floor(enemy.x),
                        y = math.floor(enemy.y),
                        health = enemy.health,
                        type = enemy.type,
                        alive = enemy.health > 0 and 1 or 0
                    })
                end
            end
        end
    end
end

-- CLIENT EVENT HANDLERS
function Network.onConnected(data)
    print("Client: Successfully connected to server!")
    if Network.onConnectCallback then
        Network.onConnectCallback()
    end
end

function Network.onGameStateReceived(data)
    print("Client: Received game state from server")
    if Network.onGameStateCallback then
        Network.onGameStateCallback(data)
    end
end

-- HOST PLAYER MANAGEMENT
function Network.setHostPlayerData(playerData)
    Network.hostPlayerData = playerData

    -- Update persistent state for host
    Network.persistentPlayerStates["Host"] = {
        id = "Host",
        x = playerData.x,
        y = playerData.y,
        health = playerData.health,
        alive = playerData.health > 0
    }
end

-- LOBBY FUNCTIONS REMOVED - Using direct join instead

function Network:sendStartGame()
    if client and client:isConnected() then
        MessageHandler:configureSendMode(client, "startGame")
        client:send("startGame", {})
        print("Client: Sent start game request")
    end
end

function Network:sendWaveConfirm()
    if client and client:isConnected() then
        MessageHandler:configureSendMode(client, "waveConfirm")
        client:send("waveConfirm", {})
        print("Client: Sent wave confirm request")
    end
end

function Network:sendRestartGame()
    if client and client:isConnected() then
        MessageHandler:configureSendMode(client, "restartGame")
        client:send("restartGame", {})
        print("Client: Sent restart game request")
    end
end

function Network.sendPlayerState(stateData)
    if client and client:isConnected() then
        -- Enhanced validation
        if type(stateData) ~= "table" then
            print("DEBUG: Player state is not a table:", type(stateData))
            return
        end

        local xValid = stateData.x and tonumber(stateData.x)
        local yValid = stateData.y and tonumber(stateData.y)
        local healthValid = stateData.health and tonumber(stateData.health)

        if not (xValid and yValid and healthValid) then
            print("DEBUG: Invalid player state fields - x:", stateData.x, "y:", stateData.y, "health:", stateData.health)
            return
        end

        MessageHandler:configureSendMode(client, "playerUpdate")
        client:send("playerUpdate", stateData)
    end
end

-- CALLBACK REGISTRATION FUNCTIONS
function Network.setConnectCallback(callback)
    Network.onConnectCallback = callback
end

function Network.setGameStateCallback(callback)
    Network.onGameStateCallback = callback
end

function Network.setGameStartedCallback(callback)
    Network.onGameStartedCallback = callback
end

function Network.setWaveStartedCallback(callback)
    Network.onWaveStartedCallback = callback
end

function Network.setWaveCompletedCallback(callback)
    Network.onWaveCompletedCallback = callback
end

function Network.setGameOverCallback(callback)
    Network.onGameOverCallback = callback
end

function Network.setGameRestartCallback(callback)
    Network.onGameRestartCallback = callback
end

function Network.setPlayerJoinedCallback(callback)
    Network.onPlayerJoinedCallback = callback
end

function Network.setPlayerIdCallback(callback)
    Network.onPlayerIdCallback = callback
end

function Network.setPlayerUpdatedCallback(callback)
    Network.onPlayerUpdatedCallback = callback
end

function Network.setPlayerLeftCallback(callback)
    Network.onPlayerLeftCallback = callback
end

function Network.setPlayerCorrectedCallback(callback)
    Network.onPlayerCorrectedCallback = callback
end

function Network.setEnemySpawnedCallback(callback)
    Network.onEnemySpawnedCallback = callback
end

function Network.setEnemyUpdatedCallback(callback)
    Network.onEnemyUpdatedCallback = callback
end

function Network.setEnemyDiedCallback(callback)
    Network.onEnemyDiedCallback = callback
end

function Network.setPlayerActionCallback(callback)
    Network.onPlayerActionCallback = callback
end

function Network.setHostCreatedCallback(callback)
    Network.onHostCreatedCallback = callback
end

function Network.setDisconnectCallback(callback)
    Network.onDisconnectCallback = callback
end

-- UTILITY FUNCTIONS
function Network.isConnected()
    if Network.isServer then
        return server ~= nil
    else
        return client and client:isConnected()
    end
end

function Network.printDebugInfo()
    print("=== Network Debug Information ===")
    print("Mode:", Network.isServer and "SERVER" or "CLIENT")
    print("Connected:", Network.isConnected())
    print("Game Active:", Network.gameActive)
    print("All Players Dead:", Network.allPlayersDead)
    print("Can Accept Players:", Network.canAcceptPlayers)
    print("Connected Clients:", tableCount(Network.connectedPlayers))

    if Network.isServer then
        print("Connected clients:", tableCount(Network.connectedPlayers))
        for id, player in pairs(Network.connectedPlayers) do
            print(string.format("  Client %s at (%d, %d) Health: %d", id, player.x, player.y, player.health))
        end
        if Network.hostPlayerData then
            print(string.format("  Host at (%d, %d) Health: %d",
                  Network.hostPlayerData.x, Network.hostPlayerData.y, Network.hostPlayerData.health))
        end

        -- Show enemy count
        local enemyCount = 0
        for _ in pairs(Network.enemies) do enemyCount = enemyCount + 1 end
        print("Active enemies:", enemyCount)

        -- Show wave status
        if Network.waveManager then
            local status = Network.waveManager:getStatus()
            print(string.format("Wave Status: Stage %d, Wave %d, Enemies: %d/%d",
                  status.stage, status.wave, status.enemiesAlive, status.totalEnemies))
        end
    end
end

function Network.disconnect()
    print("Network: Disconnecting...")

    if Network.isServer then
        -- Server: destroy the server
        if server then
            server:destroy()
            server = nil
            print("Server shut down")
        end
        Network.connectedPlayers = {}
        Network.hostPlayerData = nil
        Network.cleanupEnemies()
        if Network.waveManager then
            Network.waveManager:reset()
        end
        Network.persistentPlayerStates = {}
        Network.gameActive = false
        Network.allPlayersDead = false
        Network.canAcceptPlayers = true
        Network.lastSentPositions = {}
    else
        -- Client: disconnect from server
        if client and client:isConnected() then
            client:disconnect()
            client = nil
            print("Client disconnected from server")
        end
    end
end

return Network
