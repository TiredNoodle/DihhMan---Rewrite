-- src/core/NetworkPlayer.lua
-- Represents a remote player in the game world
-- Handles interpolation and display of other players' characters

local Player = require "src.entities.Player"
local BaseCharacter = require "src.entities.BaseCharacter"

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

    -- Clear velocity to prevent unwanted movement
    self.velocity = {x = 0, y = 0}

    -- Add interpolation properties
    self.interpolationSpeed = 8.0

    -- Dash properties for network players
    self.isDashing = false
    self.dashProgress = 0
    self.dashDuration = 0.15
    self.dashStartX = nil
    self.dashStartY = nil
    self.dashTargetX = nil
    self.dashTargetY = nil
    self.dashDirectionX = nil
    self.dashDirectionY = nil

    print(string.format("NetworkPlayer created: ID=%s at center (%d, %d)", playerId, x, y))
end

function NetworkPlayer:update(dt)
    -- Call parent update for health bar and base movement
    Player.update(self, dt)

    -- Handle dashing for network players
    if self.isDashing then
        self.dashProgress = self.dashProgress + dt

        if self.dashProgress >= self.dashDuration then
            -- Complete dash
            self.isDashing = false
            if self.dashTargetX and self.dashTargetY then
                self.centerX = self.dashTargetX
                self.centerY = self.dashTargetY
                self.x = self.centerX - self.width/2
                self.y = self.centerY - self.height/2
                self.targetCenterX = self.centerX
                self.targetCenterY = self.centerY
            end
            self.dashProgress = self.dashDuration
        else
            -- Smooth interpolation during dash with easing
            local t = self.dashProgress / self.dashDuration
            t = self:easeOutCubic(t)  -- Smooth acceleration

            if self.dashStartX and self.dashStartY and self.dashTargetX and self.dashTargetY then
                self.centerX = self.dashStartX + (self.dashTargetX - self.dashStartX) * t
                self.centerY = self.dashStartY + (self.dashTargetY - self.dashStartY) * t
                self.x = self.centerX - self.width/2
                self.y = self.centerY - self.height/2
                self.targetCenterX = self.centerX
                self.targetCenterY = self.centerY
            end
        end
    else
        -- Normal position interpolation when not dashing
        if self.targetCenterX ~= self.centerX or self.targetCenterY ~= self.centerY then
            -- Calculate distance to target
            local dx = self.targetCenterX - self.centerX
            local dy = self.targetCenterY - self.centerY
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance < 2 then
                -- Close enough, snap to target
                self.centerX = self.targetCenterX
                self.centerY = self.targetCenterY
            else
                -- Smooth interpolation with easing
                local moveDist = self.interpolationSpeed * distance * dt
                if moveDist > distance then
                    self.centerX = self.targetCenterX
                    self.centerY = self.targetCenterY
                else
                    self.centerX = self.centerX + (dx / distance) * moveDist
                    self.centerY = self.centerY + (dy / distance) * moveDist
                end
            end

            -- Update top-left corner for drawing (to match center position)
            self.x = self.centerX - self.width/2
            self.y = self.centerY - self.height/2
        end
    end
end

function NetworkPlayer:applyNetworkUpdate(data)
    if not data then return end

    -- If we're currently dashing, don't update position from normal updates
    if self.isDashing then
        -- Only update health during dash
        if data.health and data.health ~= self.health then
            local oldHealth = self.health
            self.health = data.health
            if data.health < oldHealth then
                self:showHealthBarTemporarily()
            end
            self.isAlive = self.health > 0
        end
        return
    end

    -- Store new target CENTER position for interpolation
    if data.x and data.y then
        -- Always update target position (these are CENTER coordinates from network)
        self.targetCenterX = data.x
        self.targetCenterY = data.y

        -- If we're far from target (> 100 pixels), jump to position immediately
        local dx = math.abs(data.x - self.centerX)
        local dy = math.abs(data.y - self.centerY)
        if dx > 100 or dy > 100 then
            self.centerX = data.x
            self.centerY = data.y
            self.x = self.centerX - self.width/2
            self.y = self.centerY - self.height/2
        end
    end

    -- Update health and show health bar if health decreased
    if data.health and data.health ~= self.health then
        local oldHealth = self.health
        self.health = data.health

        if data.health < oldHealth then
            self:showHealthBarTemporarily()
        end

        -- Update alive status based on health
        self.isAlive = self.health > 0
    end

    -- Update alive status if explicitly provided
    if data.alive ~= nil then
        self.isAlive = (data.alive == 1) or data.alive == true
    end

    self.lastUpdateTime = love.timer.getTime()
end

-- Apply action effect from network
function NetworkPlayer:applyActionEffect(effectData)
    -- CRITICAL FIX: Check if this action is for us
    local isForMe = false

    -- Handle different ID formats
    if effectData.playerId == self.id then
        isForMe = true
    elseif effectData.playerId == "host" and self.id == "Host" then
        isForMe = true
    elseif effectData.playerId == "Host" and self.id == "Host" then
        isForMe = true
    end

    if isForMe then
        -- Trigger the visual effect
        self:triggerActionEffect(effectData.action, effectData.targetId, effectData.targetX, effectData.targetY)

        -- Handle dash with proper interpolation
        if effectData.action == "dash" then
            -- Store dash parameters for smooth interpolation
            if effectData.directionX and effectData.directionY and effectData.distance then
                -- Calculate dash from parameters
                self.dashStartX = self.centerX
                self.dashStartY = self.centerY
                self.dashTargetX = self.centerX + effectData.directionX * effectData.distance
                self.dashTargetY = self.centerY + effectData.directionY * effectData.distance
                self.isDashing = true
                self.dashProgress = 0
                self.dashDirectionX = effectData.directionX
                self.dashDirectionY = effectData.directionY

                -- Update duration if provided
                if effectData.duration then
                    self.dashDuration = effectData.duration
                end

                print(string.format("NetworkPlayer %s: Starting dash from (%.1f, %.1f) to (%.1f, %.1f)",
                      self.id, self.dashStartX, self.dashStartY, self.dashTargetX, self.dashTargetY))
            elseif effectData.targetX and effectData.targetY then
                -- Use provided target position
                self.dashStartX = self.centerX
                self.dashStartY = self.centerY
                self.dashTargetX = effectData.targetX
                self.dashTargetY = effectData.targetY
                self.isDashing = true
                self.dashProgress = 0

                -- Update duration if provided
                if effectData.duration then
                    self.dashDuration = effectData.duration
                end
            end
        end

        print("NetworkPlayer " .. self.id .. " triggered action effect for " .. effectData.action)
    else
        print("NetworkPlayer " .. self.id .. " received action for " ..
              effectData.playerId .. " but my id is " .. self.id)
    end
end

function NetworkPlayer:draw()
    -- Only draw if alive
    if not self.isAlive then return end

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

    -- Draw health bar (fades out after damage)
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
    -- Ensure valid state data
    local state = {
        id = self.id or "unknown",
        x = math.floor(self.centerX or 0),
        y = math.floor(self.centerY or 0),
        health = self.health or 100,
        alive = self.isAlive or false
    }

    -- Validate
    if not (state.x and state.y and state.health) then
        print("NetworkPlayer: Invalid state for player", self.id)
    end

    return state
end

function NetworkPlayer:__tostring()
    return string.format("NetworkPlayer[%s] at center (%.1f, %.1f) Health: %d/%d Alive: %s",
        self.id, self.centerX, self.centerY, self.health, self.maxHealth, tostring(self.isAlive))
end

return NetworkPlayer
