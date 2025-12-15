-- src/entities/BaseCharacter.lua
-- Base class for all characters in the game.
local class = require "lib.middleclass"
local World = require "src.core.World" -- Required for world interaction

local BaseCharacter = class('BaseCharacter')

-- Constructor: called when creating a new instance (e.g., BaseCharacter:new())
function BaseCharacter:initialize(name, x, y)
    self.name = name or "Unnamed"
    -- Position is set via a helper to ensure it's a valid, collision-free spawn point.
    self:setPosition(x or 100, y or 100)

    -- Common state for all characters
    self.isAlive = true
    self.speed = 100
    self.health = 100
    self.maxHealth = 100

    -- Common visual properties
    self.width = 32
    self.height = 32
    self.color = {1, 1, 1} -- Default white

    -- Common movement: velocity is now managed by the base update for physics.
    self.velocity = {x = 0, y = 0}
    -- NEW: Flag to enable/disable collision (useful for debugging or special abilities)
    self.collisionEnabled = true

    -- Track all created characters (useful for global updates/drawing)
    BaseCharacter.all = BaseCharacter.all or {}
    table.insert(BaseCharacter.all, self)

    -- NEW: Health bar fade timer
    self.healthBarAlpha = 0
    self.healthBarVisibleTime = 0  -- How long to show health bar after damage
    self.showHealthBar = false
    self.lastHealth = self.health  -- Track health changes

    print(string.format("Character '%s' created at (%d, %d)", self.name, self.x, self.y))
end

-- NEW: Safe position setter. Finds a valid spawn if the requested point is inside a wall.
function BaseCharacter:setPosition(x, y)
    if World and World.isPointInWall(x, y) then
        self.x, self.y = World.findSpawnLocation()
        print(string.format("%s spawned in wall, moved to (%d, %d)", self.name, self.x, self.y))
    else
        self.x = x
        self.y = y
    end
end

-- NEW: Returns a table representing the character's collision box.
-- Used by World.checkWallCollision and other character collision.
function BaseCharacter:getBoundingBox()
    return {x = self.x, y = self.y, width = self.width, height = self.height}
end

-- UPDATED: Main update loop. Applies velocity and resolves world collisions.
function BaseCharacter:update(dt)
    if not self.isAlive then return end

    -- Store the old position in case we need to revert due to collision
    local oldX, oldY = self.x, self.y

    -- Calculate new position based on velocity
    local newX = self.x + self.velocity.x * dt
    local newY = self.y + self.velocity.y * dt

    if self.collisionEnabled then
        -- SEPARATE-AXIS COLLISION RESOLUTION:
        -- 1. Try movement on the X-axis
        self.x = newX
        local collidesX = World.checkWallCollision(self:getBoundingBox())
        if collidesX then
            self.x = oldX -- Revert X movement if it caused a collision
            self.velocity.x = 0 -- Stop horizontal velocity
        end

        -- 2. Try movement on the Y-axis (from the potentially updated X position)
        self.y = newY
        local collidesY = World.checkWallCollision(self:getBoundingBox())
        if collidesY then
            self.y = oldY -- Revert Y movement
            self.velocity.y = 0 -- Stop vertical velocity
        end
    else
        -- If collision is disabled, move freely (for debugging or special states)
        self.x = newX
        self.y = newY
    end

    -- NEW: Update health bar visibility and fade
    if self.showHealthBar then
        self.healthBarVisibleTime = self.healthBarVisibleTime - dt
        if self.healthBarVisibleTime <= 0 then
            self.healthBarVisibleTime = 0
            self.showHealthBar = false
        end

        -- Fade out in the last 0.5 seconds (of 3 seconds total)
        if self.healthBarVisibleTime <= 0.5 then
            self.healthBarAlpha = self.healthBarVisibleTime / 0.5
        else
            self.healthBarAlpha = 1
        end
    else
        self.healthBarAlpha = 0
    end

    -- Check for health changes
    if self.health ~= self.lastHealth then
        self:onHealthChanged(self.lastHealth, self.health)
        self.lastHealth = self.health
    end
end

-- NEW: Called when health changes
function BaseCharacter:onHealthChanged(oldHealth, newHealth)
    if newHealth < oldHealth then  -- Only show on damage, not healing
        self:showHealthBarTemporarily()
    end
end

-- NEW: Show health bar for a limited time - UPDATED TO 3 SECONDS
function BaseCharacter:showHealthBarTemporarily()
    self.showHealthBar = true
    self.healthBarVisibleTime = 3.0  -- Show for 3 seconds after damage
    self.healthBarAlpha = 1
end

-- Basic drawing method. Subclasses should override this for custom visuals.
function BaseCharacter:draw()
    love.graphics.setColor(self.color)
    love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)
    love.graphics.setColor(1, 1, 1)
end

-- Set movement velocity. Called by Player input or Enemy AI.
function BaseCharacter:move(dx, dy)
    self.velocity.x = dx * self.speed
    self.velocity.y = dy * self.speed
end

-- Take damage. Override in subclasses for special death effects.
function BaseCharacter:takeDamage(amount)
    local oldHealth = self.health
    self.health = self.health - amount

    -- Show health bar when taking damage
    if self.health < oldHealth then
        self:showHealthBarTemporarily()
    end

    if self.health <= 0 then
        self:die()
    end
end

function BaseCharacter:die()
    self.isAlive = false
    print(string.format("%s has died!", self.name))
end

-- Check collision with another character using Axis-Aligned Bounding Box (AABB)
function BaseCharacter:collidesWith(other)
    local a = self:getBoundingBox()
    local b = other:getBoundingBox()
    return a.x < b.x + b.width and
           a.x + a.width > b.x and
           a.y < b.y + b.height and
           a.y + a.height > b.y
end

function BaseCharacter:getCenter()
    return self.x + self.width/2, self.y + self.height/2
end

-- Draws a health bar above the character (fades out after damage)
function BaseCharacter:drawHealthBar()
    if self.healthBarAlpha > 0 and self.health < self.maxHealth then
        local barWidth = 50
        local barHeight = 6
        local x = self.x + self.width/2 - barWidth/2
        local y = self.y - 15

        -- Background with alpha
        love.graphics.setColor(0.2, 0.2, 0.2, self.healthBarAlpha)
        love.graphics.rectangle('fill', x, y, barWidth, barHeight)

        local healthPercent = self.health / self.maxHealth
        -- Color changes based on health percentage
        local r = 1 - healthPercent
        local g = healthPercent
        local b = 0

        love.graphics.setColor(r, g, b, self.healthBarAlpha)
        love.graphics.rectangle('fill', x, y, barWidth * healthPercent, barHeight)

        love.graphics.setColor(1, 1, 1, 1)
    end
end

-- === CLASS METHODS (Operate on all characters) ===
function BaseCharacter.getAllAlive()
    local alive = {}
    for _, char in ipairs(BaseCharacter.all or {}) do
        if char.isAlive then table.insert(alive, char) end
    end
    return alive
end

function BaseCharacter.updateAll(dt)
    for _, char in ipairs(BaseCharacter.all or {}) do
        if char.isAlive then char:update(dt) end
    end
end

function BaseCharacter.drawAll()
    for _, char in ipairs(BaseCharacter.all or {}) do
        if char.isAlive then
            char:draw()
            char:drawHealthBar()
        end
    end
end

return BaseCharacter
