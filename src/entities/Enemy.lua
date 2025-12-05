-- src/entities/Enemy.lua
-- AI-controlled enemy character. Inherits from BaseCharacter.
local BaseCharacter = require "src.entities.BaseCharacter"

local Enemy = BaseCharacter:subclass('Enemy')

function Enemy:initialize(name, x, y, enemyType)
    -- Call parent constructor first
    BaseCharacter.initialize(self, name, x, y)

    -- Enemy-specific AI properties
    self.type = enemyType or "melee"
    self.damage = 10
    self.attackRange = 50
    self.aggroRange = 200
    self.attackCooldown = 1.5
    self.attackTimer = 0

    -- Type-specific property overrides
    if enemyType == "ranged" then
        self.color = {1, 0.5, 0}  -- Orange
        self.speed = 80
        self.aggroRange = 300 -- Ranged enemies spot you from farther away
    elseif enemyType == "boss" then
        self.color = {0.5, 0, 0.5}  -- Purple
        self.width = 80
        self.height = 80
        self.health = 300
        self.maxHealth = 300
        self.speed = 60
        self.damage = 25
    else -- "melee" (default)
        self.color = {0.8, 0.2, 0.2}  -- Red
        self.speed = 100
    end
end

-- UPDATED: AI behavior. Now uses BaseCharacter:move() for collision-aware movement.
function Enemy:update(dt, target)
    -- 1. Update base movement and collision
    BaseCharacter.update(self, dt)

    -- 2. Update internal cooldown timer
    if self.attackTimer > 0 then
        self.attackTimer = self.attackTimer - dt
    end

    -- 3. Execute AI if there's a valid target
    if target and target.isAlive and self:distanceTo(target) < self.aggroRange then
        self:chase(target, dt)
    else
        -- Idle behavior: stop moving if no target
        self.velocity.x = 0
        self.velocity.y = 0
    end
end

-- UPDATED: Chase logic now uses the inherited `:move()` method for proper physics.
function Enemy:chase(target, dt)
    local dx = target.x - self.x
    local dy = target.y - self.y
    local distance = math.sqrt(dx*dx + dy*dy)

    if distance > 0 then
        -- Normalize direction vector
        dx = dx / distance
        dy = dy / distance

        -- Use the parent's move method to set velocity.
        -- The BaseCharacter:update() will handle the movement with collision.
        self:move(dx, dy)

        -- Check if we're in range to attack
        if distance < self.attackRange and self.attackTimer <= 0 then
            self:attack(target)
            self.attackTimer = self.attackCooldown
        end
    end
end

-- Simple attack function.
function Enemy:attack(target)
    if target.takeDamage then
        target:takeDamage(self.damage)
        print(self.name .. " attacks " .. target.name .. " for " .. self.damage .. " damage!")
    end
end

-- Helper to calculate distance to another object.
function Enemy:distanceTo(other)
    local dx = other.x - self.x
    local dy = other.y - self.y
    return math.sqrt(dx*dx + dy*dy)
end

-- NETWORKING: Creates state snapshot for the enemy (similar to Player).
function Enemy:getNetworkState()
    return {
        x = math.floor(self.x),
        y = math.floor(self.y),
        health = self.health,
        type = self.type,
        alive = self.isAlive and 1 or 0
    }
end

-- NETWORKING: Applies network state to the enemy.
function Enemy:applyNetworkState(state)
    self.x = state.x
    self.y = state.y
    self.health = state.health
    -- Note: 'type' generally shouldn't change after creation
    self.isAlive = (state.alive == 1)
end

return Enemy
