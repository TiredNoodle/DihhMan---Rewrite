-- src/entities/Player.lua
-- Represents the player-controlled character with actions
local BaseCharacter = require "src.entities.BaseCharacter"
local Network = require "src.core.Network"

local Player = BaseCharacter:subclass('Player')

function Player:initialize(name, x, y)
    -- FIRST, call the parent class's constructor
    BaseCharacter.initialize(self, name, x, y)

    -- Player-specific properties
    self.score = 0
    self.inventory = {}
    self.isLocalPlayer = false -- CRITICAL: Determines if this instance accepts input.

    -- Action system
    self.actions = {
        attack = {cooldown = 0.5, timer = 0, damage = 20, range = 60},
        special = {cooldown = 2.0, timer = 0, damage = 40, range = 100},
        dash = {cooldown = 1.0, timer = 0, distance = 100}
    }

    -- Visual properties
    self.speed = 150
    self.color = {0.2, 0.6, 1} -- Player Blue
    self.width = 40
    self.height = 60

    -- Action state
    self.currentAction = nil
    self.actionTarget = nil
    self.actionStartTime = 0
    self.actionDuration = 0.2
end

-- UPDATED: Update with action cooldowns
function Player:update(dt)
    -- Update action cooldowns
    for actionName, action in pairs(self.actions) do
        if action.timer > 0 then
            action.timer = action.timer - dt
        end
    end

    -- Update current action
    if self.currentAction then
        local elapsed = love.timer.getTime() - self.actionStartTime
        if elapsed >= self.actionDuration then
            self:completeAction()
        end
    end

    if self.isLocalPlayer then
        self:handleInput(dt) -- Process keyboard input
        self:handleActions() -- Process action input
    end

    -- Call the parent update to apply velocity and resolve collisions
    BaseCharacter.update(self, dt)
end

-- Handle keyboard input for movement
function Player:handleInput(dt)
    local dx, dy = 0, 0

    if love.keyboard.isDown('w', 'up') then dy = -1 end
    if love.keyboard.isDown('s', 'down') then dy = 1 end
    if love.keyboard.isDown('a', 'left') then dx = -1 end
    if love.keyboard.isDown('d', 'right') then dx = 1 end

    -- Normalize diagonal movement
    if dx ~= 0 and dy ~= 0 then
        dx = dx * 0.7071 -- 1 / sqrt(2)
        dy = dy * 0.7071
    end

    -- Set the velocity
    self:move(dx, dy)

    -- Stop if no keys are pressed
    if dx == 0 and dy == 0 then
        self.velocity.x = 0
        self.velocity.y = 0
    end
end

-- Handle action input
function Player:handleActions()
    -- Attack action (Space)
    if love.keyboard.isDown('space') and self:canPerformAction('attack') then
        self:performAction('attack')
    end

    -- Special action (Shift)
    if love.keyboard.isDown('lshift', 'rshift') and self:canPerformAction('special') then
        self:performAction('special')
    end

    -- Dash action (F key)
    if love.keyboard.isDown('f') and self:canPerformAction('dash') then
        self:performAction('dash')
    end
end

-- Check if action can be performed
function Player:canPerformAction(actionName)
    local action = self.actions[actionName]
    return action and action.timer <= 0 and not self.currentAction
end

-- Perform an action
function Player:performAction(actionName)
    local action = self.actions[actionName]
    if not action then return end

    -- Start the action
    self.currentAction = actionName
    self.actionStartTime = love.timer.getTime()
    action.timer = action.cooldown

    -- Find target for attack actions
    if actionName == 'attack' or actionName == 'special' then
        self:findActionTarget()
    end

    -- Handle dash action
    if actionName == 'dash' then
        self:performDash()
    end

    -- Create action effect
    local actionData = self:createActionEffect()

    -- Network: Send action to server if we're a client
    if self.isLocalPlayer and not Network.isServer then
        Network.sendPlayerAction(actionData)
    end

    print(self.name .. " performs " .. actionName .. " action!")
end

-- Complete current action
function Player:completeAction()
    if not self.currentAction then return end

    -- Apply damage if attack action
    if self.currentAction == 'attack' or self.currentAction == 'special' then
        if self.actionTarget then
            self:applyActionDamage()
        end
    end

    -- Clear action state
    self.currentAction = nil
    self.actionTarget = nil
end

-- Find target for attack actions
function Player:findActionTarget()
    -- Get all potential targets (enemies, other players)
    local allTargets = {}

    -- Add enemies
    for _, enemy in ipairs(BaseCharacter.getAllAlive() or {}) do
        if enemy.class and enemy.class.name == 'Enemy' then
            table.insert(allTargets, enemy)
        end
    end

    -- Find closest target in range
    local action = self.actions[self.currentAction]
    local closestTarget = nil
    local closestDistance = math.huge

    for _, target in ipairs(allTargets) do
        local distance = self:distanceTo(target)
        if distance <= action.range and distance < closestDistance then
            closestDistance = distance
            closestTarget = target
        end
    end

    self.actionTarget = closestTarget
end

-- Apply damage to action target
function Player:applyActionDamage()
    if not self.actionTarget then return end

    local action = self.actions[self.currentAction]
    self.actionTarget:takeDamage(action.damage)

    print(string.format("%s hits %s for %d damage!",
          self.name, self.actionTarget.name, action.damage))
end

-- Perform dash movement
function Player:performDash()
    local action = self.actions.dash

    -- Dash in current movement direction or last direction
    local dashX, dashY = 0, 0
    if math.abs(self.velocity.x) > 0 or math.abs(self.velocity.y) > 0 then
        -- Normalize velocity for dash direction
        local length = math.sqrt(self.velocity.x^2 + self.velocity.y^2)
        dashX = (self.velocity.x / length) * action.distance
        dashY = (self.velocity.y / length) * action.distance
    else
        -- Default dash forward (based on last direction or facing)
        dashY = -action.distance  -- Dash upward by default
    end

    -- Apply dash (temporarily disable collision for dash)
    local oldCollision = self.collisionEnabled
    self.collisionEnabled = false
    self.x = self.x + dashX
    self.y = self.y + dashY
    self.collisionEnabled = oldCollision
end

-- Create action effect data for networking
function Player:createActionEffect()
    local action = self.actions[self.currentAction]

    local effect = {
        playerId = self.name,
        action = self.currentAction,
        x = self.x + self.width/2,
        y = self.y + self.height/2,
        direction = {x = self.velocity.x, y = self.velocity.y},
        timestamp = love.timer.getTime()
    }

    -- Add target info if available
    if self.actionTarget then
        effect.targetId = self.actionTarget.name
        effect.targetX = self.actionTarget.x
        effect.targetY = self.actionTarget.y
    end

    return effect
end

-- Override draw to show action effects
function Player:draw()
    -- Draw a shadow for depth
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle('fill', self.x + 3, self.y + 5, self.width, self.height)

    -- Draw the main body
    love.graphics.setColor(self.color)
    love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)

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

    -- Draw eyes - color indicates if this is the local player
    if self.isLocalPlayer then
        love.graphics.setColor(1, 1, 0) -- Yellow for local
    else
        love.graphics.setColor(1, 0, 0) -- Red for remote/networked players
    end
    love.graphics.rectangle('fill', self.x + 10, self.y + 15, 6, 6)
    love.graphics.rectangle('fill', self.x + 24, self.y + 15, 6, 6)

    love.graphics.setColor(1, 1, 1)
end

-- NETWORKING: Creates a compact state snapshot to send over the network
function Player:getNetworkState()
    return {
        x = math.floor(self.x + self.width/2),   -- Send CENTER X
        y = math.floor(self.y + self.height/2),  -- Send CENTER Y
        health = self.health,
        alive = self.isAlive and 1 or 0,
        actions = {  -- Include action states
            attack = self.actions.attack.timer,
            special = self.actions.special.timer,
            dash = self.actions.dash.timer
        }
    }
end

-- NETWORKING: Applies a state snapshot received from the network
function Player:applyNetworkState(state)
    -- Convert from center to top-left corner
    self.x = state.x - self.width/2
    self.y = state.y - self.height/2
    self.health = state.health
    self.isAlive = (state.alive == 1)

    -- Update action cooldowns if provided
    if state.actions then
        for actionName, timer in pairs(state.actions) do
            if self.actions[actionName] then
                self.actions[actionName].timer = timer or 0
            end
        end
    end
end

-- Apply action effect from network
function Player:applyActionEffect(effectData)
    -- Visual effect for remote player actions
    if effectData.action == 'attack' or effectData.action == 'special' then
        self:showActionEffect(effectData)
    elseif effectData.action == 'dash' then
        self:showDashEffect(effectData)
    end
end

-- Show visual effect for action
function Player:showActionEffect(effectData)
    -- This would trigger particles/animations
    -- For now, just log it
    print(string.format("%s performs %s at (%d, %d)",
          effectData.playerId, effectData.action, effectData.x, effectData.y))
end

-- Show dash effect
function Player:showDashEffect(effectData)
    -- Visual trail effect for dash
    print(string.format("%s dashes!", effectData.playerId))
end

return Player
