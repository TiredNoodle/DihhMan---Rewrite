-- Main Entry point for DihhMan --

local BaseCharacter = require "src.entities.BaseCharacter"
local Player = require "src.entities.Player"
local Enemy = require "src.entities.Enemy"

function love.load()
	-- Create Player using Player subclass
	player = Player:new("Player", 100, 100)

	-- Create Enemies using Enemy subclass
	goblin = Enemy:new("Goblin", 300, 100, "melee")
	archer = Enemy:new("Archer", 400, 200, "ranged")
	boss = Enemy:new("Troll", 500, 500, "boss")

	-- Create generic NPC using base class
	merchant = BaseCharacter:new("Merchant", 200, 300)
	merchant.speed = 0
	merchant.color = {0.2, 0.8, 0.2}
end

function love.update(dt)
	-- Update all characters
	BaseCharacter.updateAll(dt)

	-- Update enemies with AI (targeting player)
	goblin:update(dt, player)
	archer:update(dt, player)
	boss:update(dt, player)

	-- Player controls
	local dx, dy = 0, 0
	if love.keyboard.isDown("w") then dy = -1 end
	if love.keyboard.isDown("s") then dy = 1 end
	if love.keyboard.isDown("a") then dx = -1 end
	if love.keyboard.isDown("d") then dx = 1 end
	player:move(dx, dy)
end

function love.draw()
	BaseCharacter.drawAll()

	-- Draw UI
	love.graphics.print("Player Score: " .. player.score, 10, 10)
	love.graphics.print("Alive Characters: " .. #BaseCharacter.getAllAlive(), 10, 30)
end

function love.keypressed(key)
	if key == 'space' then
		player:jump()
	end

	if key == 'e' then
		-- Attack nearby enemies
		for _, enemy in ipairs(BaseCharacter.getAllAlive()) do
			if enemy:collidesWith(player) and enemy.name ~= "Player" then
				enemy:takeDamage(20)
			end
		end
	end
end
