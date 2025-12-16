-- src/entities/Enemy.lua
-- AI-controlled enemy character with mod support

local BaseCharacter = require "src.entities.BaseCharacter"

-- Store enemy factory for modded enemies
local EnemyFactory = {}

function EnemyFactory.create(name, x, y, enemyType)
    -- Check for modded enemy first
    if _G.MOD_REGISTRY and _G.MOD_REGISTRY.enemies then
        local moddedEnemy = _G.MOD_REGISTRY.enemies[enemyType]
        if moddedEnemy and moddedEnemy.class then
            -- Create modded enemy instance
            local instance = moddedEnemy.class:new(name, x, y)
            instance.type = enemyType
            return instance
        end
    end

    -- Fall back to default enemy
    local Enemy = BaseCharacter:subclass('Enemy')

    function Enemy:initialize(name, x, y, enemyType)
        BaseCharacter.initialize(self, name, x, y)

        -- Set type-specific properties
        self.type = enemyType or "melee"
        self:applyTypeProperties()

        print(string.format("Enemy '%s' (%s) created at (%d, %d) Health: %d",
              self.name, self.type, x, y, self.health))
    end

    function Enemy:applyTypeProperties()
        if self.type == "ranged" then
            self.color = {1, 0.5, 0}  -- Orange
            self.speed = 120
            self.aggroRange = 400
            self.attackRange = 200
            self.maxHealth = 100
            self.health = 100
            self.attackCooldown = 2.5
            self.width = 35
            self.height = 35
            self.damage = 8
        elseif self.type == "boss" then
            self.color = {0.5, 0, 0.5}  -- Purple
            self.width = 80
            self.height = 80
            self.maxHealth = 300
            self.health = 300
            self.speed = 80
            self.damage = 25
            self.attackRange = 80
            self.attackCooldown = 3.0
            self.aggroRange = 500
        else -- "melee" (default)
            self.color = {0.8, 0.2, 0.2}  -- Red
            self.speed = 120
            self.maxHealth = 100
            self.health = 100
            self.width = 40
            self.height = 40
            self.damage = 10
            self.attackRange = 50
            self.attackCooldown = 2.0
            self.aggroRange = 300
        end

        -- Store original color
        self.originalColor = {self.color[1], self.color[2], self.color[3]}

        -- Initialize timers if not set
        self.attackTimer = self.attackTimer or 0
    end

    -- Add standard enemy methods
    function Enemy:findTarget(players)
        if not self.aggroRange then
            print("WARNING: Enemy " .. self.name .. " has nil aggroRange, defaulting to 300")
            self.aggroRange = 300
        end

        local closestPlayer = nil
        local closestDistance = math.huge

        for _, player in ipairs(players) do
            if player and player.isAlive and player.health > 0 then
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

    function Enemy:applyNetworkState(state)
        if not state then return end

        local oldHealth = self.health

        if state.x and state.y then
            -- Store target instead of snapping for smooth interpolation
            self.targetX = state.x - self.width/2
            self.targetY = state.y - self.height/2
            
            -- Initialize position if this is the first update (or reset)
            if not self.x then
               self.x = self.targetX
               self.y = self.targetY
            end

            -- Teleport if distance is too large (lag spike or spawn)
            local dx = self.targetX - self.x
            local dy = self.targetY - self.y
            if (dx*dx + dy*dy) > (100*100) then
                self.x = self.targetX
                self.y = self.targetY
            end
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

        if state.type and state.type ~= self.type then
            self.type = state.type
            self:applyTypeProperties()
        end

        if state.alive ~= nil then
            self.isAlive = (state.alive == 1) or state.alive == true
        elseif state.health then
            self.isAlive = state.health > 0
        end

        if state.health and state.health < oldHealth then
            self:showHealthBarTemporarily()
        end
    end

    function Enemy:update(dt, players)
        if not self.isAlive then return end
        
        -- Interpolate position if network target is present
        if self.targetX and self.targetY then
            local lerpSpeed = 10.0
            self.x = self.x + (self.targetX - self.x) * lerpSpeed * dt
            self.y = self.y + (self.targetY - self.y) * lerpSpeed * dt
        end
        
        BaseCharacter.update(self, dt)

        -- Ensure attackTimer exists
        self.attackTimer = self.attackTimer or 0
        if self.attackTimer > 0 then
            self.attackTimer = self.attackTimer - dt
        end

        -- Only run AI logic if we don't have network targets (or if we are the host/standalone)
        -- In this simple implementation, clients might just follow interpolation
        -- But if 'update' allows AI to override interpolation, we need to be careful.
        -- Assuming 'update' is run on both client and server:
        -- Server runs AI -> sets self.x/y -> sends network packet
        -- Client gets packet -> sets targetX/targetY -> lerps
        
        -- We should suppress local AI movement on clients if we are interpolating
        -- But 'players' argument implies we might be running AI.
        -- Let's check typical usage. In main.lua:
        -- Server: runs full update. Clients: run update.
        -- Modifying update() effectively changes it for both.
        -- However, BaseCharacter:update applies velocity.
        -- If we reuse 'move' for AI, it sets velocity.
        -- Conflict: Interpolation sets x/y directly. AI sets velocity.
        
        -- Fix: On clients (if we have targets), skip AI movement logic
        if self.targetX and self.targetY and _G.Network and not _G.Network.isServer then
             -- Pure interpolation, no AI chase
        else
             if players and #players > 0 then
                local target, distance = self:findTarget(players)
                if target and target.isAlive then
                    self.targetPlayer = target
                    self:chase(target, dt, distance)
                else
                    self:randomWander(dt)
                end
            else
                self:randomWander(dt)
            end
        end
    end

    function Enemy:chase(target, dt, distance)
        if not target then return end

        local dx = target.x - self.x
        local dy = target.y - self.y

        if distance > 0 then
            dx = dx / distance
            dy = dy / distance

            -- Ensure speed exists
            self.speed = self.speed or 100
            self:move(dx, dy)

            -- Ensure attackRange exists
            self.attackRange = self.attackRange or 50
            if distance < self.attackRange and (self.attackTimer or 0) <= 0 then
                self:attack(target)
                self.attackTimer = self.attackCooldown or 2.0
            end
        end
    end

    function Enemy:attack(target)
        if target and target.takeDamage then
            -- Ensure damage exists
            self.damage = self.damage or 10
            target:takeDamage(self.damage)
            print(self.name .. " attacks " .. target.name .. " for " .. self.damage .. " damage!")
        end
    end

    function Enemy:randomWander(dt)
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

    function Enemy:draw()
        if not self.isAlive then return end

        -- Draw shadow
        love.graphics.setColor(0, 0, 0, 0.3)
        love.graphics.rectangle('fill', self.x + 3, self.y + 5, self.width, self.height)

        -- Draw main body
        local healthPercent = self.health / self.maxHealth
        local r = (self.originalColor and self.originalColor[1] or 0.8) * (0.5 + 0.5 * healthPercent)
        local g = (self.originalColor and self.originalColor[2] or 0.2) * (0.3 + 0.7 * healthPercent)
        local b = (self.originalColor and self.originalColor[3] or 0.2) * (0.3 + 0.7 * healthPercent)
        love.graphics.setColor(r, g, b)
        love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)

        -- Draw eyes
        love.graphics.setColor(1, 1, 1)
        local eyeSize = math.max(4, self.width / 8)
        love.graphics.rectangle('fill', self.x + self.width/4, self.y + self.height/3, eyeSize, eyeSize)
        love.graphics.rectangle('fill', self.x + self.width*3/4 - eyeSize, self.y + self.height/3, eyeSize, eyeSize)

        -- Draw attack cooldown indicator
        if self.attackTimer and self.attackTimer > 0 and self.attackCooldown and self.attackCooldown > 0 then
            local cooldownPercent = self.attackTimer / self.attackCooldown
            love.graphics.setColor(1, 1 - cooldownPercent, 0, 0.5)
            love.graphics.rectangle('fill', self.x, self.y - 10, self.width * cooldownPercent, 3)
        end

        self:drawHealthBar()
        love.graphics.setColor(1, 1, 1)
    end

    function Enemy:getNetworkState()
        return {
            id = self.enemyId,
            x = math.floor(self.x + self.width/2),
            y = math.floor(self.y + self.height/2),
            health = self.health,
            maxHealth = self.maxHealth,
            type = self.type,
            alive = self.isAlive and 1 or 0
        }
    end



    -- Create and return the instance
    return Enemy:new(name, x, y, enemyType)
end

-- Export the factory function
return EnemyFactory.create
