-- mods/sample_enemy/enemy.lua
-- Multiplayer-compatible fast enemy

local BaseCharacter = require "src.entities.BaseCharacter"

local SampleFastEnemy = BaseCharacter:subclass('SampleFastEnemy')

function SampleFastEnemy:initialize(name, x, y)
    BaseCharacter.initialize(self, name, x, y)

    -- Custom properties for fast enemy
    self.type = "sample_fast"
    self.color = {0, 1, 0.5}  -- Teal color
    self.speed = 180  -- Faster than regular enemies
    self.width = 35
    self.height = 35
    self.maxHealth = 75
    self.health = 75
    self.damage = 15
    self.attackRange = 40
    self.attackCooldown = 1.5
    self.attackTimer = 0
    self.aggroRange = 350

    print("SampleFastEnemy created:", self.name)
end

function SampleFastEnemy:update(dt, players)
    BaseCharacter.update(self, dt)

    -- Simple AI: find nearest player and chase
    if players and #players > 0 then
        local target = nil
        local closestDist = math.huge

        for _, player in ipairs(players) do
            if player and player.isAlive then
                local dx = player.x - self.x
                local dy = player.y - self.y
                local dist = math.sqrt(dx*dx + dy*dy)

                if dist < closestDist and dist < (self.aggroRange or 350) then
                    closestDist = dist
                    target = player
                end
            end
        end

        if target then
            -- Move toward target
            local dx = target.x - self.x
            local dy = target.y - self.y
            local dist = math.sqrt(dx*dx + dy*dy)

            if dist > 0 then
                dx = dx / dist
                dy = dy / dist
                self:move(dx, dy)

                -- Check for attack with defensive checks
                local attackRange = self.attackRange or 40
                local attackTimer = self.attackTimer or 0
                if dist < attackRange and attackTimer <= 0 then
                    if target.takeDamage then
                        target:takeDamage(self.damage or 15)
                        self.attackTimer = self.attackCooldown or 1.5
                    end
                end
            end
        end
    end

    -- Update attack timer with defensive check
    if self.attackTimer and self.attackTimer > 0 then
        self.attackTimer = self.attackTimer - dt
    end
end

function SampleFastEnemy:draw()
    if not self.isAlive then return end

    -- Draw shadow
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle('fill', self.x + 3, self.y + 5, self.width, self.height)

    -- Draw main body with pulsing effect
    local pulse = (math.sin(love.timer.getTime() * 5) + 1) * 0.1
    local color = self.color or {0, 1, 0.5}
    love.graphics.setColor(
        color[1] + pulse,
        color[2] + pulse,
        color[3] + pulse
    )
    love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)

    -- Draw eyes
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle('fill', self.x + 8, self.y + 12, 5, 5)
    love.graphics.rectangle('fill', self.x + 22, self.y + 12, 5, 5)

    -- Draw speed lines when moving fast
    if math.abs(self.velocity.x) > 50 or math.abs(self.velocity.y) > 50 then
        love.graphics.setColor(1, 1, 1, 0.3)
        love.graphics.rectangle('fill', self.x - 5, self.y, 5, self.height)
        love.graphics.rectangle('fill', self.x + self.width, self.y, 5, self.height)
    end

    self:drawHealthBar()
    love.graphics.setColor(1, 1, 1)
end

return {
    enemy_class = SampleFastEnemy,
    enemy_data = {
        type = "sample_fast",
        display_name = "Fast Runner",
        spawn_weight = 0.3,
        min_wave = 3,
        requiresSync = true  -- Important for multiplayer
    }
}
