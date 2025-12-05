-- main.lua - Top-down multiplayer game with corrected networking
-- This is the main entry point for the game that orchestrates all systems
local Network = require "src.core.Network"
local NetworkPlayer = require "src.core.NetworkPlayer"
local World = require "src.core.World"
local BaseCharacter = require "src.entities.BaseCharacter"
local MainMenu = require "src.ui.MainMenu"
local Player = require "src.entities.Player"

-- GAME STATE MANAGEMENT
-- =====================
-- Tracks the current state of the game application
local gameState = "menu"          -- "menu", "connecting", or "playing"
local localPlayer = nil           -- The player controlled by this instance
local remotePlayers = {}          -- Table of other players connected
local myPlayerId = nil            -- Our assigned player ID from server
local mainMenu = nil              -- Main menu UI instance
local debugFont = nil             -- Font for debug information display
local showDebugInfo = true        -- Toggles debug overlay (set to TRUE for debugging)

-- DEBUG: Track frame count for periodic logging
local frameCount = 0
local lastDebugOutput = 0

-- LOVE2D LOAD FUNCTION
-- ====================
-- Initializes game systems and sets up initial state
function love.load()
    love.window.setTitle("Top-Down Network Game")
    love.window.setMode(800, 600)

    -- Initialize subsystems
    debugFont = love.graphics.newFont(12)
    World.init()

    -- Create main menu and link it to the network module
    mainMenu = MainMenu:new()
    mainMenu.network = Network

    -- Configure network event callbacks
    setupNetworkCallbacks()

    -- Start in menu state
    switchGameState("menu")

    print("Game loaded successfully. Press F1 to toggle debug info.")
end

-- NETWORK CALLBACK SETUP
-- ======================
-- Configures how the game responds to various network events
function setupNetworkCallbacks()
    -- Called when connection to server is established
    Network.setConnectCallback(function()
        print("Network: Successfully connected to server!")
        -- CRITICAL FIX: Switch to connecting state when we connect
        if gameState == "menu" then
            switchGameState("connecting")
        end
    end)

    -- Called when server sends initial game state (player positions, IDs, etc.)
    Network.setGameStateCallback(function(data)
        print("Network: Received initial game state from server")
        myPlayerId = data.yourId
        print("My player ID assigned by server:", myPlayerId)

        -- CRITICAL FIX: Always create local player from server data or spawn location
        local spawnX, spawnY
        if data.players and data.players[myPlayerId] then
            -- Use server-provided position
            local playerData = data.players[myPlayerId]
            spawnX = playerData.x
            spawnY = playerData.y
            print(string.format("Creating local player from server data: (%d, %d)", spawnX, spawnY))
        else
            -- Fallback spawn
            spawnX, spawnY = World.findSpawnLocation()
            print(string.format("Creating local player from fallback: (%d, %d)", spawnX, spawnY))
        end

        createLocalPlayer("Player_" .. myPlayerId, spawnX, spawnY)

        -- Create remote players for ALL other players in the game state
        -- This includes the host player if we're a client
        if data.players then
            for id, playerData in pairs(data.players) do
                if id ~= myPlayerId then
                    print("Creating remote player from game state:", id, "at", playerData.x, playerData.y)
                    createRemotePlayer(id, playerData)
                end
            end
        else
            print("WARNING: No players data in game state!")
        end

        -- CRITICAL FIX: Switch to playing state after receiving game state
        switchGameState("playing")
    end)

    -- Called when a new player joins the game (including host when client joins)
    Network.setPlayerJoinedCallback(function(data)
        print("Network: Player joined:", data.id, "at", data.x, data.y)
        -- Only create remote player if it's not our own ID
        if data.id ~= myPlayerId then
            createRemotePlayer(data.id, data)
        else
            print("Ignoring playerJoined for ourselves")
        end
    end)

    -- Called when server sends position updates for other players
    Network.setPlayerUpdatedCallback(function(data)
        if remotePlayers[data.id] then
            remotePlayers[data.id]:applyNetworkUpdate(data)
        else
            print("WARNING: Received update for unknown player:", data.id)
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

    -- Called when server corrects our position (collision, cheating prevention)
    Network.setPlayerCorrectedCallback(function(data)
        if localPlayer then
            print("Network: Server corrected our position")
            localPlayer.x = data.x
            localPlayer.y = data.y
        end
    end)

    -- Called when host successfully creates a game
    Network.setHostCreatedCallback(function()
        print("Network: Host game created - creating local player")
        local x, y = World.findSpawnLocation()
        createLocalPlayer("Host", x, y)
        myPlayerId = "host"

        -- IMPORTANT: Update host player data in Network module so clients get it
        if localPlayer then
            Network.setHostPlayerData(localPlayer:getNetworkState())
        end

        switchGameState("playing")
    end)

    -- Called when disconnected from server
    Network.setDisconnectCallback(function(data)
        print("Network: Disconnected from server. Data:", data)
        switchGameState("menu")
    end)
end

-- PLAYER CREATION FUNCTIONS
-- =========================

-- Creates the player controlled by this game instance
-- @param name: Display name for the player
-- @param x: Starting X position (or table with position data)
-- @param y: Starting Y position (if x is not a table)
function createLocalPlayer(name, x, y)
    local spawnX, spawnY

    -- Handle different parameter formats for backward compatibility
    if type(x) == "table" then
        -- Old format: x is a table containing position
        spawnX = x.x or x[1] or 400
        spawnY = x.y or x[2] or 300
    else
        -- New format: separate x and y parameters
        spawnX = x or 400
        spawnY = y or 300
    end

    -- Create player instance and mark as locally controlled
    localPlayer = Player:new(name, spawnX, spawnY)
    localPlayer.isLocalPlayer = true

    print(string.format("Local player '%s' created at (%d, %d)", name, spawnX, spawnY))
end

-- Creates a visual representation of a remote player
-- @param id: Unique network ID of the remote player
-- @param data: Initial state data from server
function createRemotePlayer(id, data)
    -- Check if player already exists
    if remotePlayers[id] then
        print("Remote player already exists:", id)
        return
    end

    local player = NetworkPlayer:new(id, data.x, data.y)
    player.health = data.health or 100
    remotePlayers[id] = player
    print(string.format("Remote player '%s' created at (%d, %d)", id, data.x, data.y))
end

-- GAME STATE TRANSITIONS
-- ======================

-- Manages transitions between different game states
-- @param newState: The state to transition to ("menu", "connecting", "playing")
function switchGameState(newState)
    print("Game State Transition:", gameState, "->", newState)
    gameState = newState

    if newState == "menu" then
        cleanupGame()                 -- Clear game objects
        if mainMenu then mainMenu:activate() end
    elseif newState == "connecting" then
        if mainMenu then mainMenu:deactivate() end
    elseif newState == "playing" then
        if mainMenu then mainMenu:deactivate() end
    end
end

-- Cleans up game objects when returning to menu
function cleanupGame()
    localPlayer = nil
    remotePlayers = {}
    myPlayerId = nil
    BaseCharacter.all = {}

    -- Clean up network connections
    if Network.isConnected() then
        -- Network module will handle cleanup through its callbacks
    end
end

-- LOVE2D UPDATE LOOP
-- ==================

-- Main game loop called every frame
-- @param dt: Delta time in seconds since last frame
function love.update(dt)
    Network.update(dt)  -- Process network events

    frameCount = frameCount + 1

    -- DEBUG: Log state every 60 frames (1 second at 60fps)
    if frameCount % 60 == 0 and gameState == "playing" then
        print(string.format("Frame %d: State=%s, LocalPlayer=%s, RemotePlayers=%d",
              frameCount, gameState, tostring(localPlayer ~= nil), tableCount(remotePlayers)))
    end

    if gameState == "menu" then
        if mainMenu then mainMenu:update(dt) end
    elseif gameState == "connecting" then
        -- Waiting for network connection - no updates needed
    elseif gameState == "playing" then
        -- Update local player and send state to server
        if localPlayer then
            localPlayer:update(dt)

            -- Send our current state to the server (if we're a client)
            -- Host doesn't need to send updates to itself
            if Network.isConnected() and localPlayer.isLocalPlayer and not Network.isServer then
                Network.sendPlayerState(localPlayer:getNetworkState())
            elseif Network.isServer then
                -- Host: update our data in the Network module for new clients
								local currentState = localPlayer:getNetworkState()
		            Network.setHostPlayerData(currentState)
            end
        end

        -- Update remote players (interpolation, etc.)
        for id, remotePlayer in pairs(remotePlayers) do
            if remotePlayer then  -- Check if player still exists
                remotePlayer:update(dt)
            end
        end

        -- Update all base characters (enemies, etc.)
        BaseCharacter.updateAll(dt)
    end
end

-- LOVE2D DRAW LOOP
-- ================

-- Renders the game world and UI
function love.draw()
    -- Draw the static world first
    World.draw()

    -- Draw game elements based on current state
    if gameState == "menu" then
        if mainMenu then mainMenu:draw() end
    elseif gameState == "connecting" then
        -- Draw connecting screen
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", 0, 0, 800, 600)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("Connecting to server...", 350, 300)
    elseif gameState == "playing" then
        -- DEBUG: Draw coordinate grid for troubleshooting
        drawDebugGrid()

        -- DEBUG: Draw a marker at world origin (0,0)
        love.graphics.setColor(1, 0, 0, 0.5)
        love.graphics.circle("fill", 0, 0, 10)
        love.graphics.setColor(1, 1, 1)

        -- Draw remote players first (background)
        for id, remotePlayer in pairs(remotePlayers) do
            if remotePlayer then  -- Check if player still exists
                remotePlayer:draw()

                -- DEBUG: Draw position marker for remote player
                love.graphics.setColor(0, 1, 0, 0.5)
                love.graphics.circle("line", remotePlayer.x, remotePlayer.y, 5)
                love.graphics.setColor(1, 1, 1)
            end
        end

        -- Draw local player on top
        if localPlayer then
            localPlayer:draw()
            localPlayer:drawHealthBar()

            -- DEBUG: Draw position marker for local player
            love.graphics.setColor(1, 1, 0, 0.5)
            love.graphics.circle("line", localPlayer.x, localPlayer.y, 8)
            love.graphics.setColor(1, 1, 1)
        else
            print("DEBUG: No local player to draw!")
        end

        -- Draw game UI overlay
        drawGameUI()
    end

    -- Draw debug info overlay if enabled
    if showDebugInfo then
        drawDebugInfo()
    end
end

-- Draws a debug grid to help with coordinate issues
function drawDebugGrid()
    love.graphics.setColor(0.3, 0.3, 0.3, 0.3)
    for x = 0, 800, 50 do
        love.graphics.line(x, 0, x, 600)
        love.graphics.print(tostring(x), x, 10)
    end
    for y = 0, 600, 50 do
        love.graphics.line(0, y, 800, y)
        love.graphics.print(tostring(y), 10, y)
    end
    love.graphics.setColor(1, 1, 1)
end

-- UI RENDERING FUNCTIONS
-- ======================

-- Draws the in-game UI overlay
function drawGameUI()
    love.graphics.setFont(debugFont)

    -- Semi-transparent background for UI
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 5, 5, 250, 120)

    -- UI text
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Game Status", 10, 10)
    love.graphics.print("Mode: " .. (Network.isServer and "HOST" or "CLIENT"), 10, 30)
    love.graphics.print("Connected: " .. (Network.isConnected() and "YES" or "NO"), 10, 50)
    love.graphics.print("My ID: " .. (myPlayerId or "none"), 10, 70)
    love.graphics.print("Remote Players: " .. tableCount(remotePlayers), 10, 90)

    if localPlayer then
        love.graphics.print("Local Pos: " .. math.floor(localPlayer.x) .. "," .. math.floor(localPlayer.y), 10, 110)
    end
end

-- Draws debug information overlay
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
    end

    love.graphics.print("Remote Players: " .. tableCount(remotePlayers), 555, yPos)
    yPos = yPos + 20

    -- Show remote player positions
    for id, player in pairs(remotePlayers) do
        if yPos < 180 then  -- Don't overflow the panel
            love.graphics.print(id .. ": " .. math.floor(player.x) .. "," .. math.floor(player.y), 555, yPos)
            yPos = yPos + 15
        end
    end
end

-- INPUT HANDLING
-- ==============

-- Handles keyboard input events
-- @param key: The key that was pressed
function love.keypressed(key)
    -- Global key bindings (work in any state)
    if key == "escape" then
        if gameState == "playing" then
            switchGameState("menu")
        elseif gameState == "menu" then
            love.event.quit()
        end
    elseif key == "f1" then
        showDebugInfo = not showDebugInfo
    elseif key == "f3" and localPlayer then
        -- Debug: print detailed player state
        print(string.format("Local Player - isLocalPlayer: %s, Position: %d, %d",
              tostring(localPlayer.isLocalPlayer), localPlayer.x, localPlayer.y))
    elseif key == "f5" then
        -- Debug: print network status
        Network.printDebugInfo()
    elseif key == "f6" then
        -- Debug: force create a test remote player
        if gameState == "playing" then
            local testX, testY = World.findSpawnLocation()
            createRemotePlayer("test_debug", {x = testX, y = testY, health = 100})
            print("DEBUG: Created test remote player at", testX, testY)
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
        if key == "space" and localPlayer then
            print(localPlayer.name .. " performs action!")
        elseif key == "p" then
            -- Debug: print all remote players
            print("=== Remote Players ===")
            for id, player in pairs(remotePlayers) do
                print(string.format("  %s: (%d, %d) Health: %d", id, player.x, player.y, player.health))
            end
        elseif key == "l" then
            -- Debug: print local player info
            if localPlayer then
                print("=== Local Player ===")
                print(string.format("  ID: %s, Position: (%d, %d), Health: %d",
                      myPlayerId, localPlayer.x, localPlayer.y, localPlayer.health))
            end
        elseif key == "r" then
            -- Debug: print render info
            print("=== Render Info ===")
            print("Local player exists:", localPlayer ~= nil)
            print("Remote player count:", tableCount(remotePlayers))
            print("Screen size: 800x600")
            print("Game State:", gameState)
        end
    end
end

-- UTILITY FUNCTIONS
-- =================

-- Counts the number of elements in a table
-- @param t: Table to count
-- @return: Number of key-value pairs
function tableCount(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Called when game is closing
function love.quit()
    print("Game closing...")
    return false
end
