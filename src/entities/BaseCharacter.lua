-- BaseCharacter.lua

-- Libs
local class = require "lib.middleclass"

-- Base Character class - defines COMMON behavior for ALL characters
local BaseCharacter = class('BaseCharacter')

-- Constructor - called when you do Character:new(...)
function BaseCharacter:initialize(name, x, y)
  -- Common properties ALL characters share
  self.name = name or "Unnamed"
  self.x = x or 100
  self.y = y or 100

  -- Common state
  self.isAlive = true
  self.speed = 100
  self.health = 100
  self.maxHealth = 100

  -- Common visual properties
  self.width = 32
  self.height = 32
  self.color = {1, 1, 1} -- White (RGB 0-1 range)

  -- Common movement
  self.velocity = {x = 0, y = 0}

  -- Store all characters that are created
  BaseCharacter.all = BaseCharacter.all or {}
  table.insert(BaseCharacter.all, self)

  print(string.format("Character '%s' created at (%d, %d)", self.name, self.x, self.y))
end

-- === COMMON METHODS ALL CHARACTERS SHARE ===

-- Move character by velocity
function BaseCharacter:update(dt)
  self.x = self.x + self.velocity.x * dt
  self.y = self.y + self.velocity.y * dt
end

-- Draw the character (OVERRIDE this in subclasses)
function BaseCharacter:draw()
  love.graphics.setColor(self.color)
  love.graphics.rectangle('fill', self.x, self.y, self.width, self.height)
  love.graphics.setColor(1, 1, 1) -- RGB Color scheme
end

-- Set movement velocity
function BaseCharacter:move(dx, dy)
  self.velocity.x = dx * self.speed
  self.velocity.y = dy * self.speed
end

-- Take damage
function BaseCharacter:takeDamage(amount)
  self.health = self.health - amount
  if self.health <= 0 then
    self:die()
  end
end

-- Die (can be overriden)
function BaseCharacter:die()
  self.isAlive = false
  print(string.format("%s has died!", self.name))
end

-- Check collision with another character
function BaseCharacter:collidesWith(other)
  return self.x < other.x + other.width and
         self.x + self.width > other.x and
         self.y < other.y + other.height and
         self.y + self.height > other.y
end

-- Get center position
function BaseCharacter:getCenter()
  return self.x + self.width/2, self.y + self.height/2
end

-- Draw health bar (a common visual element)
function BaseCharacter:drawHealthBar()
  if self.health < self.maxHealth then
    local barWidth = 50
    local barHeight = 6
    local x = self.x + self.width/2 - barWidth/2
    local y = self.y - 15

    -- Background
    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle('fill', x, y, barWidth, barHeight)

    -- Health fill
    local healthPercent = self.health / self.maxHealth
    love.graphics.setColor(1 - healthPercent, healthPercent, 0)
    love.graphics.rectangle('fill', x, y, barWidth * healthPercent, barHeight)

    love.graphics.setColor(1, 1, 1)
  end
end

-- === CLASS METHODS (called on the class itself, not instances) ===

-- Get all alive characters
function BaseCharacter.getAllAlive()
  local alive = {}
  for _, char in ipairs(BaseCharacter.all or {}) do
    if char.isAlive then
      table.insert(alive, char)
    end
  end
  return alive
end

-- Update all characters
function BaseCharacter.updateAll(dt)
  for _, char in ipairs(BaseCharacter.all or {}) do
    if char.isAlive then
      char:update(dt)
    end
  end
end

-- Draw all characters
function BaseCharacter.drawAll()
  for _, char in ipairs(BaseCharacter.all or {}) do
    if char.isAlive then
      char:draw()
      char:drawHealthBar()
    end
  end
end

return BaseCharacter
