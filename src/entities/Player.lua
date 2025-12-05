-- Player.lua (subclass of BaseCharacter)
local BaseCharacter = require "src.entities.BaseCharacter"

local Player = BaseCharacter:subclass('Player') -- Inherits ALL Character methods

-- Override Constructor to add player-specific properties
function Player:initialize(name, x, y)
  -- Call parent constructor FIRST
  BaseCharacter.initialize(self, name, x, y)

  -- Player-specific properties
  self.jumpForce = 300
  self.isGrounded = false
  self.hasDoubleJump = true
  self.score = 0
  self.inventory = {}

  -- Override some defaults
  self.speed = 150
  self.color = {0.2, 0.6, 1} -- Player Blue
  self.width = 40
  self.height = 60
end

-- Override update to add gravity/jumping
function Player:update(dt)
  -- Call parent update (handles movement)
  BaseCharacter.update(self, dt)

  -- Add gravity
  if not self.isGrounded then
    self.velocity.y = self.velocity.y + 500 * dt -- Gravity
  end
end

-- Override draw to make player look different
function Player:draw()
  -- Draw body (rectangle from parent class)
  BaseCharacter.draw(self)

  -- Add player-specific details (like a face or weapon)
  love.graphics.setColor(1, 1, 0) -- Yellow eyes
  love.graphics.rectangle('fill', self.x + 8, self.y + 10, 5, 5)
  love.graphics.rectangle('fill', self.x + 18, self.y + 10, 5, 5)
  love.graphics.setColor(1, 1, 1)
end

-- Add player-specific methods
function Player:jump()
  if self.isGrounded then
    self.velocity.y = -self.jumpForce
    self.isGrounded = false
  elseif self.hasDoubleJump then
    self.velocity.y = -self.jumpForce * 0.8
    self.hasDoubleJump = false
  end
end

function Player:collectItem(item)
  table.insert(self.inventory, item)
  self.score = self.score + item.points
end

return Player
