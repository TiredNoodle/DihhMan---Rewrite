-- src/core/MessageHandler.lua
-- Handles reliable vs unreliable message types with single channel

local MessageHandler = {
    -- Reliable messages (TCP-like) - for critical game state
    RELIABLE_MESSAGES = {
        "playerId",
        "gameState",
        "gameStarted",
        "waveStarted",
        "waveCompleted",
        "gameOver",
        "gameRestart",
        "playerJoined",
        "playerLeft",
        "playerCorrected",
        "enemySpawned",
        "enemyDied",
        "disconnect"
    },

    -- Unreliable messages (UDP-like) - for frequent updates
    UNRELIABLE_MESSAGES = {
        "playerUpdate",
        "playerUpdated",
        "playerAction",
        "enemyUpdated"
    }
}

-- Check if a message type should be sent reliably
function MessageHandler:isReliable(messageType)
    for _, msg in ipairs(self.RELIABLE_MESSAGES) do
        if msg == messageType then
            return true
        end
    end
    return false
end

-- Check if a message type should be sent unreliably
function MessageHandler:isUnreliable(messageType)
    for _, msg in ipairs(self.UNRELIABLE_MESSAGES) do
        if msg == messageType then
            return true
        end
    end
    return false
end

-- Set appropriate send mode based on message type
function MessageHandler:configureSendMode(networkObj, messageType)
    if self:isReliable(messageType) then
        networkObj:setSendMode("reliable")
        networkObj:setSendChannel(0)  -- Channel 0 for reliable messages
    elseif self:isUnreliable(messageType) then
        networkObj:setSendMode("unreliable")
        networkObj:setSendChannel(0)  -- Channel 0 for unreliable messages too
    else
        -- Default to reliable
        networkObj:setSendMode("reliable")
        networkObj:setSendChannel(0)
    end
end

-- Get recommended send mode for a message type
function MessageHandler:getSendMode(messageType)
    if self:isReliable(messageType) then
        return "reliable"
    elseif self:isUnreliable(messageType) then
        return "unreliable"
    else
        return "reliable"
    end
end

-- Get recommended channel for a message type
function MessageHandler:getChannel(messageType)
    return 0  -- Always use channel 0 since we only have 1 channel
end

return MessageHandler
