-- src/entities/Enemy.lua
-- AI-controlled enemy character with network synchronization
local BaseCharacter = require "src.entities.BaseCharacter"

local Enemy = BaseCharacter:subclass('Enemy')

function Enemy:initialize(name, x, y, enemyType)
    -- Call parent constructor first
    BaseCharacter.initialize(self, name, x, y)

    -- Enemy-specific AI properties
    self.type = enemyType or "melee"
    self.damage = 10
    self.attackRange = 50
    self.aggroRange = 300  -- Increased for open arena
    self.attackCooldown = 1.5
    self.attackTimer = 0
    self.targetPlayer = nil
    self.enemyId = tostring(love.math.random(10000, 99999)) -- Unique ID for networking

    -- Type-specific property overrides
    if enemyType == "ranged" then
        self.color = {1, 0.5, 0}  -- Orange
        self.speed = 120
        self.aggroRange = 400
        self.attackRange = 200  -- Ranged enemies attack from farther
    elseif enemyType == "boss" then
        self.color = {0.5, 0, 0.5}  -- Purple
        self.width = 80
        self.height = 80
        self.health = 300
        self.maxHealth = 300
        self.speed = 80
        self.damage = 25
        self.attackRange = 80
    else -- "melee" (default)
        self.color = {0.8, 0.2, 0.2}  -- Red
        self.speed = 120
    end

    -- Store original color for health display
    self.originalColor = {self.color[1], self.color[2], self.color[3]}

    print(string.format("Enemy '%s' (%s) created at (%d, %d)",
          self.name, self.type, x, y))
end

-- Find closest player to target
function Enemy:findTarget(players)
    local closestPlayer = nil
    local closestDistance = math.huge

    for _, player in ipairs(players) do
        if player.isAlive then
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

-- UPDATED: Main update loop. Applies velocity and resolves world collisions.
function Enemy:update(dt, players)
    -- 1. Update base movement and collision
    BaseCharacter.update(self, dt)

    -- 2. Update internal cooldown timer
    if self.attackTimer > 0 then
        self.attackTimer = self.attackTimer - dt
    end

    -- 3. Find and chase target
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

-- Attack function with network event
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
    -- This can be expanded with particles or animations
    local effect = {
        type = "attack",
        attackerId = self.enemyId,
        targetId = target.name,
        damage = self.damage,
        x = target.x,
        y = target.y
    }

    -- In a networked game, this effect would be broadcast to all clients
    return effect
end

-- Draw enemy with special effects
function Enemy:draw()
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

    -- Draw health bar (always visible for enemies)
    self:drawHealthBar()

    love.graphics.setColor(1, 1, 1)
end

-- Override health bar to always show for enemies
function Enemy:drawHealthBar()
    local barWidth = 50
    local barHeight = 6
    local x = self.x + self.width/2 - barWidth/2
    local y = self.y - 15

    -- Background
    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle('fill', x, y, barWidth, barHeight)

    -- Health bar
    local healthPercent = self.health / self.maxHealth
    if healthPercent > 0.6 then
        love.graphics.setColor(0, 1, 0)  -- Green
    elseif healthPercent > 0.3 then
        love.graphics.setColor(1, 1, 0)  -- Yellow
    else
        love.graphics.setColor(1, 0, 0)  -- Red
    end
    love.graphics.rectangle('fill', x, y, barWidth * healthPercent, barHeight)

    -- Outline
    love.graphics.setColor(0, 0, 0)
    love.graphics.rectangle('line', x, y, barWidth, barHeight)

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

-- NETWORKING: Applies network state to the enemy
function Enemy:applyNetworkState(state)
    if state.x and state.y then
        -- Convert center to top-left
        self.x = state.x - self.width/2
        self.y = state.y - self.height/2
    end
    if state.health then
        self.health = state.health
    end
    if state.maxHealth then
        self.maxHealth = state.maxHealth
    end
    self.isAlive = (state.alive == 1) or state.alive == true

    -- Flash white when damaged
    if state.health and state.health < self.health then
        self.damageFlashTimer = 0.2
    end
end

-- Take damage with death notification
function Enemy:takeDamage(amount)
    BaseCharacter.takeDamage(self, amount)

    if not self.isAlive then
        -- Enemy died - could trigger death effect/score here
        print(self.name .. " has been defeated!")
    end
end

return Enemy
