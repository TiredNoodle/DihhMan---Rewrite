-- src/entities/Player.lua
-- Represents the player-controlled character with actions
local BaseCharacter = require "src.entities.BaseCharacter"
local Network = require "src.core.Network"

local Player = BaseCharacter:subclass('Player')

function Player:initialize(name, x, y)
    -- Call parent constructor first
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

    -- Effect timers
    self.attackEffectTimer = nil
    self.specialEffectTimer = nil
    self.dashEffectTimer = nil
end

function Player:update(dt)
    -- Update action cooldowns
    for actionName, action in pairs(self.actions) do
        if action.timer > 0 then
            action.timer = action.timer - dt
        end
    end

    -- Update action effects
    self:updateActionEffects(dt)

    if self.isLocalPlayer then
        self:handleInput(dt) -- Process keyboard input
        self:handleActions() -- Process action input
    end

    -- Call the parent update to apply velocity and resolve collisions
    BaseCharacter.update(self, dt)
end

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

    -- Store movement direction for actions
    self.lastMoveDirection = {x = dx, y = dy}

    -- Set the velocity
    self:move(dx, dy)

    -- Stop if no keys are pressed
    if dx == 0 and dy == 0 then
        self.velocity.x = 0
        self.velocity.y = 0
    end
end

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

function Player:canPerformAction(actionName)
    local action = self.actions[actionName]
    return action and action.timer <= 0 and not self.currentAction
end

function Player:performAction(actionName)
    local action = self.actions[actionName]
    if not action or not self:canPerformAction(actionName) then return end

    -- Start the action locally
    self.currentAction = actionName
    self.actionStartTime = love.timer.getTime()
    action.timer = action.cooldown

    -- Calculate attack direction based on last movement or default
    local attackDirection = {x = 0, y = 0}
    if self.lastMoveDirection then
        attackDirection = self.lastMoveDirection
    elseif self.velocity.x ~= 0 or self.velocity.y ~= 0 then
        -- Normalize velocity for direction
        local length = math.sqrt(self.velocity.x^2 + self.velocity.y^2)
        attackDirection = {x = self.velocity.x/length, y = self.velocity.y/length}
    else
        attackDirection = {x = 0, y = -1} -- Default: attack forward (up)
    end

    -- Create action data to send to server
    -- The server will handle finding targets and applying damage
    local actionData = {
        playerId = self.name,
        action = actionName,
        x = self.x + self.width/2,  -- Center position
        y = self.y + self.height/2, -- Center position
        direction = attackDirection, -- Direction of attack
        timestamp = love.timer.getTime()
    }

    -- Network: Send action to server if we're a client
    if self.isLocalPlayer and Network and not Network.isServer then
        Network.sendPlayerAction(actionData)
    end

    -- If we're the host, send to our own server for processing
    if self.isLocalPlayer and Network and Network.isServer then
        -- Host triggers its own effect locally
        self:triggerActionEffect(actionName, nil, nil, nil)

        -- Also process the action through server logic (this will handle damage)
        -- We need to simulate receiving the action as if from a client
        Network.onPlayerAction(actionData, {getIndex = function() return "host" end})
    elseif self.isLocalPlayer and Network and not Network.isServer then
        -- Client triggers local effect (visual only)
        self:triggerActionEffect(actionName, nil, nil, nil)
    end

    return actionData
end

-- Simplified: Just triggers visual effects, damage is handled by server
function Player:completeAction()
    if not self.currentAction then return end

    -- Clear action state
    self.currentAction = nil
    self.actionTarget = nil
end

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

-- Action effect system - visual only
function Player:triggerActionEffect(actionName, targetId, targetX, targetY)
    -- Set up the action state for visual feedback
    self.currentAction = actionName
    self.actionStartTime = love.timer.getTime()

    -- Create visual effects based on action type
    if actionName == "attack" then
        self:showAttackEffect()
    elseif actionName == "special" then
        self:showSpecialEffect()
    elseif actionName == "dash" then
        self:showDashEffect()
    end

    print(self.name .. " performs " .. actionName .. " action!")
end

-- Visual effect methods
function Player:showAttackEffect()
    -- Create attack animation/particles
    self.attackEffectTimer = 0.3  -- 300ms effect
end

function Player:showSpecialEffect()
    -- Create special attack animation
    self.specialEffectTimer = 0.5  -- 500ms effect
end

function Player:showDashEffect()
    -- Create dash trail effect
    self.dashEffectTimer = 0.4  -- 400ms effect
end

function Player:updateActionEffects(dt)
    -- Update effect timers
    if self.attackEffectTimer then
        self.attackEffectTimer = self.attackEffectTimer - dt
        if self.attackEffectTimer <= 0 then
            self.attackEffectTimer = nil
        end
    end

    if self.specialEffectTimer then
        self.specialEffectTimer = self.specialEffectTimer - dt
        if self.specialEffectTimer <= 0 then
            self.specialEffectTimer = nil
        end
    end

    if self.dashEffectTimer then
        self.dashEffectTimer = self.dashEffectTimer - dt
        if self.dashEffectTimer <= 0 then
            self.dashEffectTimer = nil
        end
    end

    -- Update current action timer
    if self.currentAction then
        local elapsed = love.timer.getTime() - self.actionStartTime
        if elapsed >= self.actionDuration then
            self:completeAction()
        end
    end
end

-- Apply action effect from network (visual only)
function Player:applyActionEffect(effectData)
    -- Trigger the visual effect for this player
    if effectData.action and effectData.playerId == self.name then
        self:triggerActionEffect(effectData.action, effectData.targetId, effectData.targetX, effectData.targetY)
    end
end

function Player:draw()
    -- Draw a shadow for depth
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle('fill', self.x + 3, self.y + 5, self.width, self.height)

    -- Draw the main body
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

return Player
