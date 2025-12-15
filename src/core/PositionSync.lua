-- src/core/PositionSync.lua
-- Handles position synchronization between players

local Network = require "src.core.Network"
local MessageHandler = require "src.core.MessageHandler"

local PositionSync = {}

-- Store last known positions
PositionSync.lastPositions = {}
PositionSync.updateInterval = 0.033  -- 30 updates per second
PositionSync.updateTimer = 0
PositionSync.isActive = true

function PositionSync.setActive(active)
    PositionSync.isActive = active
    print("PositionSync: " .. (active and "activated" or "deactivated"))
end

function PositionSync.update(dt)
    if not PositionSync.isActive then return end
    if not Network.isServer then return end

    PositionSync.updateTimer = PositionSync.updateTimer - dt
    if PositionSync.updateTimer <= 0 then
        PositionSync.broadcastAllPositions()
        PositionSync.updateTimer = PositionSync.updateInterval
    end
end

function PositionSync.broadcastAllPositions()
    if not Network.isServer then return end

    -- Broadcast host position to all clients
    if Network.hostPlayerData then
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
    end

    -- Broadcast client positions to each other and host
    for clientId, playerData in pairs(Network.connectedPlayers) do
        -- To other clients
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

        -- To host (via callback)
        if Network.onPlayerUpdatedCallback then
            Network.onPlayerUpdatedCallback({
                id = clientId,
                x = playerData.x,
                y = playerData.y,
                health = playerData.health,
                alive = playerData.health > 0
            })
        end
    end
end

return PositionSync
