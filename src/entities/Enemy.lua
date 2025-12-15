-- src/entities/Enemy.lua
-- AI-controlled enemy character with proper health bar fade
local BaseCharacter = require "src.entities.BaseCharacter"

local Enemy = BaseCharacter:subclass('Enemy')

function Enemy:initialize(name, x, y, enemyType)
    -- Call parent constructor first
    BaseCharacter.initialize(self, name, x, y)

    -- Enemy-specific AI properties
    self.type = enemyType or "melee"
    self.damage = 10
    self.attackRange = 50
    self.aggroRange = 300
    self.attackCooldown = 2.0  -- Increased to prevent spam
    self.attackTimer = 0
    self.targetPlayer = nil
    self.enemyId = nil  -- Will be set from network data

    -- Type-specific property overrides
    if enemyType == "ranged" then
        self.color = {1, 0.5, 0}  -- Orange
        self.speed = 120
        self.aggroRange = 400
        self.attackRange = 200
        self.maxHealth = 100
        self.health = 100
        self.attackCooldown = 2.5
        self.width = 35
        self.height = 35
    elseif enemyType == "boss" then
        self.color = {0.5, 0, 0.5}  -- Purple
        self.width = 80
        self.height = 80
        self.maxHealth = 300
        self.health = 300
        self.speed = 80
        self.damage = 25
        self.attackRange = 80
        self.attackCooldown = 3.0
    elseif enemyType == "sample_fast" then
        self.color = {0, 1, 0.5}  -- Teal
        self.speed = 180
        self.width = 35
        self.height = 35
        self.maxHealth = 75
        self.health = 75
        self.damage = 15
        self.attackRange = 40
        self.attackCooldown = 1.5
        self.aggroRange = 350
    else -- "melee" (default)
        self.color = {0.8, 0.2, 0.2}  -- Red
        self.speed = 120
        self.maxHealth = 100
        self.health = 100
        self.width = 40
        self.height = 40
    end

    -- Store original color
    self.originalColor = {self.color[1], self.color[2], self.color[3]}

    print(string.format("Enemy '%s' (%s) created at (%d, %d) Health: %d",
          self.name, self.type, x, y, self.health))
end

-- Find closest player to target
function Enemy:findTarget(players)
    local closestPlayer = nil
    local closestDistance = math.huge

    for _, player in ipairs(players) do
        if player.isAlive and player.health > 0 then
            local dx = player.x - self.x
            local dy = player.y - self.y
            local distance = math.sqrt(dx*dx + dy*dy)

            if distance < closestDistance and distance < self.aggroRange then
                closestDistance = distance
                closestPlayer = player
            end
        end
    end

    return closestPlayer, closestDistance
end

-- Main update loop - CRITICAL: Calls BaseCharacter.update for health bar fade
function Enemy:update(dt, players)
    -- Only update if alive
    if not self.isAlive then return end

    -- 1. Update base movement, collision, and health bar fade
    BaseCharacter.update(self, dt)

    -- 2. Update internal cooldown timer
    if self.attackTimer > 0 then
        self.attackTimer = self.attackTimer - dt
    end

    -- 3. Find and chase target (only if game is active and we have players)
    if players and #players > 0 then
        local target, distance = self:findTarget(players)

        if target and target.isAlive then
            self.targetPlayer = target
            self:chase(target, dt, distance)
        else
            -- Idle behavior: wander randomly
            self:randomWander(dt)
        end
    else
        self:randomWander(dt)
    end
end

-- Random wandering when no target
function Enemy:randomWander(dt)
    -- Occasionally change direction
    if love.math.random() < 0.01 then
        self.wanderDirection = {
            x = love.math.random(-1, 1),
            y = love.math.random(-1, 1)
        }
    end

    if self.wanderDirection then
        self:move(self.wanderDirection.x, self.wanderDirection.y)
    end
end

-- Chase logic
function Enemy:chase(target, dt, distance)
    local dx = target.x - self.x
    local dy = target.y - self.y

    if distance > 0 then
        -- Normalize direction vector
        dx = dx / distance
        dy = dy / distance

        -- Use the parent's move method
        self:move(dx, dy)

        -- Check if we're in range to attack
        if distance < self.attackRange and self.attackTimer <= 0 then
            self:attack(target)
            self.attackTimer = self.attackCooldown
        end
    end
end

-- Attack function
function Enemy:attack(target)
    if target.takeDamage then
        target:takeDamage(self.damage)
        print(self.name .. " attacks " .. target.name .. " for " .. self.damage .. " damage!")

        -- Create attack effect/visual
        self:createAttackEffect(target)
    end
end

-- Create visual attack effect
function Enemy:createAttackEffect(target)
    local effect = {
        type = "attack",
        attackerId = self.enemyId,
        targetId = target.name,
        damage = self.damage,
        x = target.x,
        y = target.y
    }

    return effect
end

-- Draw enemy with special effects
function Enemy:draw()
    if not self.isAlive then
        return  -- Don't draw dead enemies
    end

    -- Draw shadow
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle('fill', self.x + 3, self.y + 5, self.width, self.height)

    -- Draw main body with health-based color tint
    local healthPercent = self.health / self.maxHealth
    local r = self.originalColor[1] * (0.5 + 0.5 * healthPercent)
    local g = self.originalColor[2] * (0.3 + 0.7 * healthPercent)
    local b = self.originalColor[3] * (0.3 + 0.7 * healthPercent)
    love.graphics.setColor(r, g, b)
    love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)

    -- Draw enemy eyes
    love.graphics.setColor(1, 1, 1)
    local eyeSize = math.max(4, self.width / 8)
    love.graphics.rectangle('fill', self.x + self.width/4, self.y + self.height/3, eyeSize, eyeSize)
    love.graphics.rectangle('fill', self.x + self.width*3/4 - eyeSize, self.y + self.height/3, eyeSize, eyeSize)

    -- Draw attack cooldown indicator
    if self.attackTimer > 0 then
        local cooldownPercent = self.attackTimer / self.attackCooldown
        love.graphics.setColor(1, 1 - cooldownPercent, 0, 0.5)
        love.graphics.rectangle('fill', self.x, self.y - 10, self.width * cooldownPercent, 3)
    end

    -- Draw health bar using base class method (which fades correctly)
    self:drawHealthBar()

    love.graphics.setColor(1, 1, 1)
end

-- NETWORKING: Creates state snapshot for the enemy
function Enemy:getNetworkState()
    return {
        id = self.enemyId,
        x = math.floor(self.x + self.width/2),   -- Center X
        y = math.floor(self.y + self.height/2),  -- Center Y
        health = self.health,
        maxHealth = self.maxHealth,
        type = self.type,
        alive = self.isAlive and 1 or 0
    }
end

-- NETWORKING: Applies network state to the enemy - FIXED VERSION
function Enemy:applyNetworkState(state)
    if not state then return end

    local oldHealth = self.health

    -- Convert from center to top-left
    if state.x and state.y then
        self.x = state.x - self.width/2
        self.y = state.y - self.height/2
    end

    if state.health then
        self.health = state.health
    end

    if state.maxHealth then
        self.maxHealth = state.maxHealth
    end

    if state.id then
        self.enemyId = state.id
    end

    if state.type then
        self.type = state.type
    end

    -- CRITICAL FIX: Handle alive state properly
    if state.alive ~= nil then
        self.isAlive = (state.alive == 1) or state.alive == true
    elseif state.health then
        self.isAlive = state.health > 0
    end

    -- Show health bar when health changes (network sync)
    if state.health and state.health < oldHealth then
        self:showHealthBarTemporarily()
    end

    -- Debug log
    if state.health and oldHealth ~= state.health then
        print(string.format("Enemy %s: Health updated %d -> %d, Alive: %s",
              self.enemyId or "unknown", oldHealth, state.health, tostring(self.isAlive)))
    end
end

-- Take damage with death notification
function Enemy:takeDamage(amount)
    local oldHealth = self.health
    BaseCharacter.takeDamage(self, amount)

    if self.health <= 0 then
        self.isAlive = false
        print(self.name .. " has been defeated!")
    end
end

return Enemy
