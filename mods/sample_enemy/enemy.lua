-- mods/sample_enemy/enemy.lua
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
            if player.isAlive then
                local dx = player.x - self.x
                local dy = player.y - self.y
                local dist = math.sqrt(dx*dx + dy*dy)

                if dist < closestDist and dist < self.aggroRange then
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
            end
        end
    end
end

return {
    enemy_class = SampleFastEnemy,
    enemy_data = {
        type = "sample_fast",
        display_name = "Fast Runner",
        spawn_weight = 0.3,  -- 30% chance to spawn instead of regular enemy
        min_wave = 3  -- Start appearing from wave 3
    }
}
