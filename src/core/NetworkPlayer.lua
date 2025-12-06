-- src/core/NetworkPlayer.lua
-- Represents a remote player in the game world
-- Handles interpolation and display of other players' characters

local Player = require "src.entities.Player"

local NetworkPlayer = Player:subclass('NetworkPlayer')

function NetworkPlayer:initialize(playerId, x, y)
    -- Call parent constructor with name based on playerId
    Player.initialize(self, "Player_" .. playerId, x, y)

    self.id = playerId            -- Network identifier
    self.isLocal = false          -- Always false for NetworkPlayer
    self.isLocalPlayer = false    -- Ensure this is false for NetworkPlayer

    -- Override color to distinguish from local player
    self.color = {0.8, 0.2, 0.2}  -- Red for remote players

    -- Store CENTER position for interpolation (what we receive from network)
    self.centerX = x              -- Center X position
    self.centerY = y              -- Center Y position
    self.targetCenterX = x        -- Target center position for interpolation
    self.targetCenterY = y

    -- Calculate top-left corner for drawing (already done by parent)
    -- self.x and self.y are set by parent

    self.lastUpdateTime = 0       -- Timestamp of last update

    print(string.format("NetworkPlayer created: ID=%s at center (%d, %d)", playerId, x, y))
end

function NetworkPlayer:update(dt)
    -- Update action cooldowns (inherited from Player)
    for actionName, action in pairs(self.actions) do
        if action.timer > 0 then
            action.timer = action.timer - dt
        end
    end

    -- Update action effects
    self:updateActionEffects(dt)

    -- Skip input handling (NetworkPlayers don't accept local input)
    -- Don't call Player.handleInput or Player.handleActions

    -- Interpolate position if we have target positions
    if self.targetCenterX ~= self.centerX or self.targetCenterY ~= self.centerY then
        -- Linear interpolation for smooth movement
        local interpolationSpeed = 8
        local dx = self.targetCenterX - self.centerX
        local dy = self.targetCenterY - self.centerY
        local distance = math.sqrt(dx * dx + dy * dy)

        if distance < 1 then
            self.centerX = self.targetCenterX
            self.centerY = self.targetCenterY
        else
            self.centerX = self.centerX + dx * interpolationSpeed * dt
            self.centerY = self.centerY + dy * interpolationSpeed * dt
        end

        -- Update top-left corner for drawing (to match center position)
        self.x = self.centerX - self.width/2
        self.y = self.centerY - self.height/2
    end
end

function NetworkPlayer:applyNetworkUpdate(data)
    if not data then return end

    -- Store new target CENTER position for interpolation
    self.targetCenterX = data.x or self.targetCenterX
    self.targetCenterY = data.y or self.targetCenterY

    -- Update health
    if data.health then
        self.health = data.health
    end

    -- Update alive status
    if data.alive ~= nil then
        self.isAlive = (data.alive == 1) or data.alive == true
    end

    self.lastUpdateTime = love.timer.getTime()

    -- Debug output for significant position changes
    local dx = math.abs(self.targetCenterX - self.centerX)
    local dy = math.abs(self.targetCenterY - self.centerY)
    if dx > 10 or dy > 10 then
        print(string.format("NetworkPlayer %s: Moving to center (%d, %d)",
              self.id, self.targetCenterX, self.targetCenterY))
    end
end

-- Apply action effect from network
function NetworkPlayer:applyActionEffect(effectData)
    -- Check if this action is for this player by comparing the playerId in the effectData with self.id
    if effectData.playerId == self.id then
        -- Trigger the visual effect
        self:triggerActionEffect(effectData.action, effectData.targetId, effectData.targetX, effectData.targetY)
        print("NetworkPlayer " .. self.id .. " triggered action effect for " .. effectData.action)
    else
        print("NetworkPlayer " .. self.id .. " received action for " .. effectData.playerId .. " but my id is " .. self.id)
    end
end

function NetworkPlayer:draw()
    -- Draw a shadow for depth
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle('fill', self.x + 3, self.y + 5, self.width, self.height)

    -- Draw the main body with NetworkPlayer color (red)
    love.graphics.setColor(self.color)
    love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)

    -- Draw action effect overlays
    if self.attackEffectTimer then
        love.graphics.setColor(1, 0, 0, 0.5)  -- Red flash for attack
        love.graphics.rectangle('fill', self.x - 5, self.y - 5, self.width + 10, self.height + 10)
    end

    if self.specialEffectTimer then
        love.graphics.setColor(1, 1, 0, 0.5)  -- Yellow flash for special
        love.graphics.rectangle('fill', self.x - 10, self.y - 10, self.width + 20, self.height + 20)
    end

    if self.dashEffectTimer then
        love.graphics.setColor(0, 1, 1, 0.3)  -- Cyan trail for dash
        -- Draw multiple rectangles behind for trail effect
        for i = 1, 3 do
            love.graphics.rectangle('fill', self.x - i*5, self.y - i*3, self.width, self.height)
        end
    end

    -- Draw action indicator
    if self.currentAction then
        local progress = (love.timer.getTime() - self.actionStartTime) / self.actionDuration
        love.graphics.setColor(1, 1, 0, 0.5 * (1 - progress))
        love.graphics.rectangle('line', self.x - 5, self.y - 5,
                               self.width + 10, self.height + 10)
    end

    -- Draw cooldown indicators
    local indicatorY = self.y - 20
    for actionName, action in pairs(self.actions) do
        if action.timer > 0 then
            local cooldownPercent = action.timer / action.cooldown
            local color = {1, 1 - cooldownPercent, 0}

            love.graphics.setColor(color[1], color[2], color[3], 0.7)
            love.graphics.rectangle('fill', self.x, indicatorY,
                                   self.width * cooldownPercent, 3)
            indicatorY = indicatorY - 5
        end
    end

    -- Draw eyes - always red for NetworkPlayer
    love.graphics.setColor(1, 0, 0) -- Red for remote players
    love.graphics.rectangle('fill', self.x + 10, self.y + 15, 6, 6)
    love.graphics.rectangle('fill', self.x + 24, self.y + 15, 6, 6)

    -- Draw health bar
    self:drawHealthBar()

    -- Draw name tag above player
    love.graphics.setColor(1, 1, 1)
    local font = love.graphics.newFont(10)
    love.graphics.setFont(font)
    local nameWidth = font:getWidth(self.name)
    love.graphics.print(self.name,
        self.x + self.width/2 - nameWidth/2,
        self.y - 15
    )

    love.graphics.setColor(1, 1, 1)
end

function NetworkPlayer:getCenter()
    return self.centerX, self.centerY
end

function NetworkPlayer:getState()
    return {
        id = self.id,
        x = math.floor(self.centerX),
        y = math.floor(self.centerY),
        health = self.health,
        alive = self.isAlive
    }
end

function NetworkPlayer:__tostring()
    return string.format("NetworkPlayer[%s] at center (%.1f, %.1f) Health: %d/%d Alive: %s",
        self.id, self.centerX, self.centerY, self.health, self.maxHealth, tostring(self.isAlive))
end

return NetworkPlayer
