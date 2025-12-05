-- Enemy.lua (subclass of BaseCharacter)
local BaseCharacter = require "src.entities.BaseCharacter"

local Enemy = BaseCharacter:subclass('Enemy')

function Enemy:initialize(name, x, y, enemyType)
  BaseCharacter.initialize(self, name, x, y)

  self.type = enemyType or "melee"
  self.damage = 10
  self.attackRange = 50
  self.aggroRange = 200

  -- Type-specific properties
  if enemyType == "ranged" then
    self.color = {1, 0.5, 0} -- Orange
    self.speed = 80
  elseif enemyType == "boss" then
    self.color = {0.5, 0, 0.5} -- Purple
    self.width = 80
    self.height = 80
    self.health = 300
    self.maxHealth = 300
  else
    self.color = {0.8, 0.2, 0.2} -- Red
    self.speed = 60
  end
end

-- AI behavior
function Enemy:update(dt, target)
  BaseCharacter.update(self, dt)

  if target and self:distanceTo(target) < self.aggroRange then
    self:chase(target, dt)
  end
end

-- Enemy-specific method
function Enemy:chase(target, dt)
  local dx = target.x - self.x
  local dy = target.y - self.y
  local distance = math.sqrt(dx*dx + dy*dy)

  if distance > 0 then
    dx = dx / distance
    dy = dy / distance
    self.x = self.x + dx * self.speed * dt
    self.y = self.y + dy * self.speed * dt
  end
end

function Enemy:distanceTo(other)
  local dx = other.x - self.x
  local dy = other.y - self.y
  return math.sqrt(dx*dx + dy*dy)
end

return Enemy
