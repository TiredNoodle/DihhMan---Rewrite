-- src/core/Network.lua
-- Main networking module that handles client-server communication
-- Uses sock.lua for underlying network transport and bitser for serialization

local sock = require "lib.sock"
local bitser = require "lib.bitser"
local World = require "src.core.World"

-- NETWORK MODULE DEFINITION
-- =========================
-- Contains all networking logic and state
local Network = {
    isServer = false,           -- True if this instance is hosting
    connectedPlayers = {},      -- Server-only: tracks connected clients
    hostPlayerData = nil,       -- Server-only: host's player data
    lastHostUpdateTime = 0,     -- Server-only: time of last host update broadcast
    hostUpdateInterval = 0.033  -- Server-only: send host updates ~30 times/sec
}

-- Private variables for network connections
local server, client

-- Helper function to get serializable player data (without client objects)
-- @return: Table containing only serializable player data
local function getSerializablePlayers()
    local playersData = {}

    -- Include host player if exists
    if Network.isServer and Network.hostPlayerData then
        playersData["host"] = {
            id = "host",
            x = Network.hostPlayerData.x,
            y = Network.hostPlayerData.y,
            health = Network.hostPlayerData.health
        }
    end

    -- Include connected clients
    for id, player in pairs(Network.connectedPlayers) do
        playersData[id] = {
            id = player.id,
            x = player.x,
            y = player.y,
            health = player.health
        }
    end
    return playersData
end

-- Broadcast host position updates to all connected clients
local function broadcastHostUpdate()
    if not Network.isServer or not server or not Network.hostPlayerData then
        return
    end

    -- Send host update to all connected clients
    for id, player in pairs(Network.connectedPlayers) do
        player.client:send("playerUpdated", {
            id = "host",
            x = Network.hostPlayerData.x,
            y = Network.hostPlayerData.y,
            health = Network.hostPlayerData.health
        })
    end
end

-- INITIALIZATION
-- ==============
-- Initializes network as either server (host) or client
-- @param host: IP address or hostname to connect to (client) or bind to (server)
-- @param port: Port number for connection
-- @param serverMode: Boolean indicating if this instance should host
function Network.init(host, port, serverMode)
    Network.isServer = serverMode

    if Network.isServer then
        -- SERVER INITIALIZATION
        print(string.format("Initializing server on %s:%d", host, port))
        server = sock.newServer(host, port)
        server:setSerialization(bitser.dumps, bitser.loads)

        -- Server event handlers
        -- sock.lua passes: (data, clientObject) to callbacks
        server:on("connect", function(data, clientObj)
            Network.onClientConnected(clientObj, data)
        end)

        server:on("playerUpdate", function(data, clientObj)
            Network.onPlayerUpdate(data, clientObj)
        end)

        server:on("disconnect", function(data, clientObj)
            Network.onClientDisconnected(clientObj, data)
        end)

        print("Server started successfully. Waiting for connections...")

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

        client:on("gameState", function(data)
            Network.onGameStateReceived(data)
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
-- ============
-- Must be called every frame to process network events
-- @param dt: Delta time (unused by sock but kept for consistency)
function Network.update(dt)
    if Network.isServer and server then
        server:update()

        -- Periodically broadcast host updates to all clients
        local currentTime = love.timer.getTime()
        if Network.hostPlayerData and currentTime - Network.lastHostUpdateTime > Network.hostUpdateInterval then
            broadcastHostUpdate()
            Network.lastHostUpdateTime = currentTime
        end
    elseif client then
        client:update()
    end
end

-- SERVER EVENT HANDLERS
-- =====================

-- Called when a new client connects to the server
-- @param clientObj: The client object created by sock.lua
-- @param data: Connection data (usually 0)
function Network.onClientConnected(clientObj, data)
    -- Get client ID from the client object
    local clientId = tostring(clientObj:getIndex())
    print("Server: Client connected with ID:", clientId, "Data:", data)

    -- Find a valid spawn location for new player
    local spawnX, spawnY = World.findSpawnLocation()

    -- Store player data (WITHOUT serializing client object in the data we send)
    Network.connectedPlayers[clientId] = {
        client = clientObj,     -- Reference to sock client object (local use only)
        id = clientId,          -- Unique identifier
        x = spawnX,             -- Initial position
        y = spawnY,
        health = 100            -- Initial health
    }

    -- Get serializable player data (without client objects)
    local playersData = getSerializablePlayers()

    -- Send complete game state to the new client (only serializable data!)
    clientObj:send("gameState", {
        players = playersData,
        yourId = clientId
    })

    -- Notify all other clients (including host via callback) about the new player
    -- First, send to other connected clients
    for id, player in pairs(Network.connectedPlayers) do
        if id ~= clientId then
            player.client:send("playerJoined", {
                id = clientId,
                x = spawnX,
                y = spawnY,
                health = 100
            })
        end
    end

    -- IMPORTANT: Also notify the host instance about the new player
    -- The host needs to create a NetworkPlayer for the client
    if Network.onPlayerJoinedCallback then
        Network.onPlayerJoinedCallback({
            id = clientId,
            x = spawnX,
            y = spawnY,
            health = 100
        })
    end
end

-- Called when a client disconnects from server
-- @param clientObj: The client that disconnected
-- @param data: Disconnection data (usually 0)
function Network.onClientDisconnected(clientObj, data)
    local clientId = tostring(clientObj:getIndex())
    print("Server: Client disconnected:", clientId, "Data:", data)

    -- Notify other clients (including host) about the departure
    for id, player in pairs(Network.connectedPlayers) do
        if id ~= clientId then
            player.client:send("playerLeft", {id = clientId})
        end
    end

    -- Also notify host via callback
    if Network.onPlayerLeftCallback then
        Network.onPlayerLeftCallback({id = clientId})
    end

    -- Remove from tracking
    Network.connectedPlayers[clientId] = nil
end

-- Processes position updates from clients
-- @param data: Player state data from client
-- @param clientObj: The client that sent the update
function Network.onPlayerUpdate(data, clientObj)
    if not data or not data.x or not data.y then
        print("Server: Received invalid player update")
        return
    end

    local clientId = tostring(clientObj:getIndex())
    if not Network.connectedPlayers[clientId] then
        print("Server: Received update from unknown client:", clientId)
        return
    end

    local playerData = Network.connectedPlayers[clientId]
    local oldX, oldY = playerData.x, playerData.y

    -- SERVER-SIDE COLLISION VALIDATION
    -- IMPORTANT: Player dimensions must match Player.lua (40x60)

    local PLAYER_WIDTH = 40
    local PLAYER_HEIGHT = 60

    local playerBox = {
        x = data.x - PLAYER_WIDTH/2,    -- Convert center X to top-left X
        y = data.y - PLAYER_HEIGHT/2,   -- Convert center Y to top-left Y
        width = PLAYER_WIDTH,
        height = PLAYER_HEIGHT
    }

    -- Check if new position collides with walls
    local hasCollision = false
    for _, wall in ipairs(World.walls or {}) do
        if playerBox.x < wall.x + wall.width and
           playerBox.x + playerBox.width > wall.x and
           playerBox.y < wall.y + wall.height and
           playerBox.y + playerBox.height > wall.y then
            hasCollision = true
            break
        end
    end

    if not hasCollision then
        -- Accept the update
        playerData.x = data.x
        playerData.y = data.y
        playerData.health = data.health or playerData.health
    else
        -- Reject the update and send correction to client
        clientObj:send("playerCorrected", {x = oldX, y = oldY})
        -- Keep original position
        data.x, data.y = oldX, oldY
        print(string.format("Server: Rejected invalid movement from client %s", clientId))
    end

    -- Broadcast update to all other clients (including host via callback) if position changed
    if oldX ~= data.x or oldY ~= data.y then
        for id, player in pairs(Network.connectedPlayers) do
            if id ~= clientId then
                player.client:send("playerUpdated", {
                    id = clientId,
                    x = data.x,
                    y = data.y,
                    health = playerData.health
                })
            end
        end

        -- Also update host via callback
        if Network.onPlayerUpdatedCallback then
            Network.onPlayerUpdatedCallback({
                id = clientId,
                x = data.x,
                y = data.y,
                health = playerData.health
            })
        end
    end
end

-- CLIENT EVENT HANDLERS
-- =====================

-- Called when client successfully connects to server
-- @param data: Connection data (usually 0)
function Network.onConnected(data)
    print("Client: Successfully connected to server! Data:", data)
    if Network.onConnectCallback then
        Network.onConnectCallback()
    end
end

-- Called when client receives initial game state from server
-- @param data: Complete game state including all player positions
function Network.onGameStateReceived(data)
    print("Client: Received initial game state from server")
    if Network.onGameStateCallback then
        Network.onGameStateCallback(data)
    end
end

-- HOST PLAYER MANAGEMENT
-- ======================

-- Sets the host's player data for inclusion in game state
-- @param playerData: Host player's state data
function Network.setHostPlayerData(playerData)
    Network.hostPlayerData = playerData
end

-- CALLBACK REGISTRATION FUNCTIONS
-- ===============================
-- These allow main.lua to specify how to handle network events

function Network.setConnectCallback(callback)
    Network.onConnectCallback = callback
end

function Network.setGameStateCallback(callback)
    Network.onGameStateCallback = callback
end

function Network.setPlayerJoinedCallback(callback)
    Network.onPlayerJoinedCallback = callback
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

function Network.setHostCreatedCallback(callback)
    Network.onHostCreatedCallback = callback
end

function Network.setDisconnectCallback(callback)
    Network.onDisconnectCallback = callback
end

-- CLIENT NETWORKING FUNCTIONS
-- ===========================

-- Sends current player state to server
-- @param stateData: Player position and state to send
function Network.sendPlayerState(stateData)
    if client and client:isConnected() then
        client:send("playerUpdate", stateData)
    end
end

-- UTILITY FUNCTIONS
-- =================

-- Checks if network connection is active
-- @return: Boolean indicating connection status
function Network.isConnected()
    if Network.isServer then
        return server ~= nil
    else
        return client and client:isConnected()
    end
end

-- Prints debug information about network status
function Network.printDebugInfo()
    print("=== Network Debug Information ===")
    print("Mode:", Network.isServer and "SERVER" or "CLIENT")
    print("Connected:", Network.isConnected())

    if Network.isServer then
        print("Connected clients:", #server:getClients())
        for id, player in pairs(Network.connectedPlayers) do
            print(string.format("  Client %s at (%d, %d)", id, player.x, player.y))
        end
        if Network.hostPlayerData then
            print(string.format("  Host at (%d, %d)",
                  Network.hostPlayerData.x, Network.hostPlayerData.y))
        end
    end
end

return Network
