-- src/entities/Player.lua
-- Represents the player-controlled character. Inherits from BaseCharacter.
local BaseCharacter = require "src.entities.BaseCharacter"

local Player = BaseCharacter:subclass('Player') -- This sets up inheritance

function Player:initialize(name, x, y)
    -- FIRST, call the parent class's constructor
    BaseCharacter.initialize(self, name, x, y)

    -- Player-specific properties
    self.score = 0
    self.inventory = {}
    self.isLocalPlayer = false -- CRITICAL: Determines if this instance accepts input.

    -- Override defaults from BaseCharacter
    self.speed = 150
    self.color = {0.2, 0.6, 1} -- Player Blue
    self.width = 40
    self.height = 60
end

-- UPDATED: Handles input for the local player and calls the parent's collision update.
function Player:update(dt)
    if self.isLocalPlayer then
        self:handleInput(dt) -- Process keyboard input
    end
    -- Call the parent update to apply velocity and resolve world collisions
    BaseCharacter.update(self, dt)
end

-- NEW: Converts keyboard state into movement velocity.
function Player:handleInput(dt)
    local dx, dy = 0, 0

    if love.keyboard.isDown('w', 'up') then dy = -1 end
    if love.keyboard.isDown('s', 'down') then dy = 1 end
    if love.keyboard.isDown('a', 'left') then dx = -1 end
    if love.keyboard.isDown('d', 'right') then dx = 1 end

    -- Normalize diagonal movement so speed is consistent
    if dx ~= 0 and dy ~= 0 then
        dx = dx * 0.7071 -- 1 / sqrt(2)
        dy = dy * 0.7071
    end

    -- Set the velocity. The parent's update() will apply it.
    self:move(dx, dy)

    -- Stop if no keys are pressed (optional, could also use acceleration)
    if dx == 0 and dy == 0 then
        self.velocity.x = 0
        self.velocity.y = 0
    end
end

-- Overrides the parent's draw to add player-specific details.
function Player:draw()
    -- Draw a shadow for depth
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle('fill', self.x + 3, self.y + 5, self.width, self.height)

    -- Draw the main body
    love.graphics.setColor(self.color)
    love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)

    -- Draw eyes - color indicates if this is the local player
    if self.isLocalPlayer then
        love.graphics.setColor(1, 1, 0) -- Yellow for local
    else
        love.graphics.setColor(1, 0, 0) -- Red for remote/networked players
    end
    love.graphics.rectangle('fill', self.x + 10, self.y + 15, 6, 6)
    love.graphics.rectangle('fill', self.x + 24, self.y + 15, 6, 6)

    love.graphics.setColor(1, 1, 1)
    -- Health bar is drawn by BaseCharacter.drawAll()
end

-- NETWORKING: Creates a compact state snapshot to send over the network.
-- Returns CENTER position (x + width/2, y + height/2) for consistency
function Player:getNetworkState()
    return {
        x = math.floor(self.x + self.width/2),   -- Send CENTER X
        y = math.floor(self.y + self.height/2),  -- Send CENTER Y
        health = self.health,
        alive = self.isAlive and 1 or 0
    }
end

-- NETWORKING: Applies a state snapshot received from the network.
-- Converts center position back to top-left corner for rendering
function Player:applyNetworkState(state)
    -- Convert from center to top-left corner
    self.x = state.x - self.width/2
    self.y = state.y - self.height/2
    self.health = state.health
    self.isAlive = (state.alive == 1)
end

-- Example of adding an item (can be expanded).
function Player:collectItem(item)
    table.insert(self.inventory, item)
    self.score = self.score + (item.points or 0)
end

return Player
