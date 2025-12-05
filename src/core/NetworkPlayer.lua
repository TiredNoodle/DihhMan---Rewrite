-- src/core/NetworkPlayer.lua
-- Represents a remote player in the game world
-- Handles interpolation and display of other players' characters

local class = require "lib.middleclass"

local NetworkPlayer = class('NetworkPlayer')

-- Constructor: Creates a new remote player representation
-- @param playerId: Unique network ID of the player
-- @param x: Initial X position (CENTER position from network)
-- @param y: Initial Y position (CENTER position from network)
function NetworkPlayer:initialize(playerId, x, y)
    self.id = playerId            -- Network identifier
    self.width = 40               -- Display dimensions (match Player.lua)
    self.height = 60              -- Display dimensions (match Player.lua)

    -- Store CENTER position for interpolation (what we receive from network)
    self.centerX = x              -- Center X position
    self.centerY = y              -- Center Y position
    self.targetCenterX = x        -- Target center position for interpolation
    self.targetCenterY = y

    -- Calculate top-left corner for drawing
    self.x = x - self.width/2     -- Top-left X for drawing
    self.y = y - self.height/2    -- Top-left Y for drawing

    self.health = 100             -- Current health
    self.maxHealth = 100          -- Maximum health
    self.isLocal = false          -- Always false for NetworkPlayer
    self.isAlive = true           -- Player state
    self.lastUpdateTime = 0       -- Timestamp of last update
    self.name = "Player_" .. playerId  -- Display name

    print(string.format("NetworkPlayer created: ID=%s at center (%d, %d)", playerId, x, y))
end

-- Update loop: Smoothly interpolates position toward target
-- @param dt: Delta time in seconds
function NetworkPlayer:update(dt)
    -- Only interpolate if we have a target different from current position
    if self.targetCenterX ~= self.centerX or self.targetCenterY ~= self.centerY then
        -- Linear interpolation for smooth movement
        -- Higher speed = faster interpolation, lower = smoother
        local interpolationSpeed = 8

        -- Calculate distance to target
        local dx = self.targetCenterX - self.centerX
        local dy = self.targetCenterY - self.centerY
        local distance = math.sqrt(dx * dx + dy * dy)

        -- If we're very close, snap to target
        if distance < 1 then
            self.centerX = self.targetCenterX
            self.centerY = self.targetCenterY
        else
            -- Interpolate with speed proportional to distance
            self.centerX = self.centerX + dx * interpolationSpeed * dt
            self.centerY = self.centerY + dy * interpolationSpeed * dt
        end

        -- Update top-left corner for drawing
        self.x = self.centerX - self.width/2
        self.y = self.centerY - self.height/2
    end
end

-- Draws the remote player character
function NetworkPlayer:draw()
    if not self.isAlive then return end  -- Don't draw dead players

    -- Draw shadow for depth
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle('fill', self.x + 3, self.y + 5, self.width, self.height)

    -- Remote players are drawn in red to distinguish from local player
    love.graphics.setColor(0.8, 0.2, 0.2)  -- Red

    -- Draw player body (top-left corner)
    love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)

    -- Draw simple face/eyes (distinguish from local player)
    love.graphics.setColor(1, 1, 1)  -- White eyes for remote players
    local eyeSize = 6
    local eyeOffsetX = 10
    local eyeOffsetY = 15

    -- Left eye
    love.graphics.rectangle("fill",
        self.x + eyeOffsetX,
        self.y + eyeOffsetY,
        eyeSize,
        eyeSize
    )

    -- Right eye
    love.graphics.rectangle("fill",
        self.x + self.width - eyeOffsetX - eyeSize,
        self.y + eyeOffsetY,
        eyeSize,
        eyeSize
    )

    -- Draw name tag above player
    love.graphics.setColor(1, 1, 1)
    local font = love.graphics.newFont(10)
    love.graphics.setFont(font)
    local nameWidth = font:getWidth(self.name)
    love.graphics.print(self.name,
        self.x + self.width/2 - nameWidth/2,
        self.y - 15
    )

    -- Health bar (only shown if damaged)
    self:drawHealthBar()

    love.graphics.setColor(1, 1, 1)  -- Reset to white
end

-- Draws health bar above the player
function NetworkPlayer:drawHealthBar()
    if self.health < self.maxHealth then
        local barWidth = 50
        local barHeight = 6
        local healthPercent = self.health / self.maxHealth

        -- Position above player (centered)
        local barX = self.x + self.width/2 - barWidth/2
        local barY = self.y - 10

        -- Background
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("fill", barX, barY, barWidth, barHeight)

        -- Health fill (green to red based on health)
        local r = 1 - healthPercent  -- Red increases as health decreases
        local g = healthPercent      -- Green decreases as health decreases
        love.graphics.setColor(r, g, 0)
        love.graphics.rectangle("fill", barX, barY, barWidth * healthPercent, barHeight)

        -- Border
        love.graphics.setColor(0, 0, 0)
        love.graphics.rectangle("line", barX, barY, barWidth, barHeight)
    end
end

-- Applies network update to this player
-- @param data: Network data containing new CENTER position and state
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

-- Returns bounding box for collision detection (top-left corner)
-- @return: Table with x, y, width, height
function NetworkPlayer:getBoundingBox()
    return {
        x = self.x,        -- Top-left X
        y = self.y,        -- Top-left Y
        width = self.width,
        height = self.height
    }
end

-- Returns the center position of the player
-- @return: centerX, centerY
function NetworkPlayer:getCenter()
    return self.centerX, self.centerY
end

-- Checks collision with another object
-- @param other: Object with getBoundingBox method or bounding box table
-- @return: Boolean indicating collision
function NetworkPlayer:collidesWith(other)
    local box1 = self:getBoundingBox()
    local box2 = other.getBoundingBox and other:getBoundingBox() or other

    -- Axis-Aligned Bounding Box (AABB) collision detection
    return box1.x < box2.x + box2.width and
           box1.x + box1.width > box2.x and
           box1.y < box2.y + box2.height and
           box1.y + box1.height > box2.y
end

-- Applies damage to the remote player
-- @param amount: Damage amount to subtract from health
function NetworkPlayer:takeDamage(amount)
    self.health = math.max(0, self.health - amount)
    print(string.format("NetworkPlayer %s took %d damage (Health: %d)",
          self.id, amount, self.health))

    if self.health <= 0 then
        self.isAlive = false
        print(string.format("NetworkPlayer %s has died!", self.id))
    end
end

-- Calculates distance to another object (center to center)
-- @param other: Object with getCenter method or x,y properties
-- @return: Euclidean distance between centers
function NetworkPlayer:distanceTo(other)
    local otherCenterX, otherCenterY
    if other.getCenter then
        otherCenterX, otherCenterY = other:getCenter()
    else
        otherCenterX, otherCenterY = other.x, other.y
    end

    local dx = otherCenterX - self.centerX
    local dy = otherCenterY - self.centerY
    return math.sqrt(dx * dx + dy * dy)
end

-- Returns network state for this player (for debugging)
-- @return: Table with current player state (center position)
function NetworkPlayer:getState()
    return {
        id = self.id,
        x = math.floor(self.centerX),
        y = math.floor(self.centerY),
        health = self.health,
        alive = self.isAlive
    }
end

-- String representation for debugging
-- @return: Formatted string describing the player
function NetworkPlayer:__tostring()
    return string.format("NetworkPlayer[%s] at center (%.1f, %.1f) Health: %d/%d Alive: %s",
        self.id, self.centerX, self.centerY, self.health, self.maxHealth, tostring(self.isAlive))
end

return NetworkPlayer
