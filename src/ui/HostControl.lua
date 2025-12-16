-- src/ui/HostControl.lua
-- Host interface for controlling wave progression and game state

local class = require "lib.middleclass"

local HostControl = class('HostControl')

function HostControl:initialize()
    self.visible = false
    self.countdown = 0
    self.message = ""
    self.messageTimer = 0
    self.stage = 1
    self.wave = 0
    self.enemiesAlive = 0
    self.totalEnemies = 0
    self.awaitingConfirmation = false
    self.gameActive = false
    self.allPlayersDead = false

    -- Colors
    self.backgroundColor = {0, 0, 0, 0.7}
    self.textColor = {1, 1, 1, 1}
    self.countdownColor = {1, 1, 0, 1}
    self.warningColor = {1, 0.5, 0, 1}
    self.successColor = {0, 1, 0, 1}
    self.errorColor = {1, 0, 0, 1}

    print("HostControl initialized")
end

function HostControl:draw()
    if not self.visible then return end

    -- Draw background panel
    love.graphics.setColor(self.backgroundColor)
    love.graphics.rectangle("fill", 10, 10, 320, 200)

    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 10, 10, 320, 200)

    -- Draw title
    love.graphics.setColor(0, 1, 1)
    love.graphics.print("HOST CONTROL PANEL", 20, 20)

    -- Draw game status
    love.graphics.setColor(self.textColor)
    love.graphics.print("Stage: " .. self.stage, 20, 45)
    love.graphics.print("Wave: " .. self.wave, 150, 45)
    love.graphics.print("Enemies: " .. self.enemiesAlive .. "/" .. self.totalEnemies, 20, 65)

    -- Draw countdown
    if self.countdown > 0 then
        love.graphics.setColor(self.countdownColor)
        local countdownText = "Next wave in: " .. math.ceil(self.countdown)
        love.graphics.print(countdownText, 20, 85)
    end

    -- Draw current message - UPDATED with wrapping
    if self.message ~= "" then
        local messageColor = self.textColor

        if self.message:find("started") then
            messageColor = self.successColor
        elseif self.message:find("requires") or self.message:find("confirmation") then
            messageColor = self.warningColor
        elseif self.message:find("dead") or self.message:find("over") then
            messageColor = self.errorColor
        end

        love.graphics.setColor(messageColor)
        -- Wrap long messages
        local maxWidth = 300
        local lines = {}
        local words = self.message:gmatch("%S+")
        local currentLine = ""

        for word in words do
            local testLine = currentLine .. (currentLine == "" and "" or " ") .. word
            if love.graphics.getFont():getWidth(testLine) < maxWidth then
                currentLine = testLine
            else
                table.insert(lines, currentLine)
                currentLine = word
            end
        end
        if currentLine ~= "" then
            table.insert(lines, currentLine)
        end

        for i, line in ipairs(lines) do
            love.graphics.print(line, 20, 105 + (i-1) * 15)
        end
    end

    -- Draw control instructions - UPDATED
    love.graphics.setColor(self.textColor)

    if not self.gameActive then
        love.graphics.print("Press G to start game", 20, 140)
    else
        if self.allPlayersDead then
            love.graphics.setColor(self.errorColor)
            love.graphics.print("ALL PLAYERS DEAD!", 20, 140)
        end

        -- ALWAYS show restart option for host
        love.graphics.setColor(self.textColor)
        love.graphics.print("Press R to restart match", 20, 155)

        if self.awaitingConfirmation then
            love.graphics.setColor(self.warningColor)
            love.graphics.print("Press SPACE or G to confirm wave " .. (self.wave + 1), 20, 170)
            love.graphics.print("(Next wave requires host confirmation)", 20, 185)
        elseif self.countdown > 0 then
            love.graphics.setColor(self.successColor)
            love.graphics.print("Wave " .. (self.wave + 1) .. " starts in " .. math.ceil(self.countdown) .. " seconds", 20, 170)
        end
    end

    -- Draw player status reminder
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.print("Players can join between waves", 20, 185)
end

function HostControl:updateStatus(status)
    self.stage = status.stage or 1
    self.wave = status.wave or 0
    self.enemiesAlive = status.enemiesAlive or 0
    self.totalEnemies = status.totalEnemies or 0
    self.countdown = status.waveCountdown or 0
    self.awaitingConfirmation = status.awaitingConfirmation or false
    self.gameActive = status.gameActive or false
end

function HostControl:showMessage(msg, duration)
    self.message = msg
    if duration then
        self.messageTimer = duration
    end
end

function HostControl:setAllPlayersDead(dead)
    self.allPlayersDead = dead
end

function HostControl:update(dt)
    if self.messageTimer > 0 then
        self.messageTimer = self.messageTimer - dt
        if self.messageTimer <= 0 then
            self.messageTimer = 0
            self.message = ""
        end
    end

    -- Update countdown display
    if self.countdown > 0 then
        self.countdown = self.countdown - dt
    end
end

function HostControl:show()
    self.visible = true
end

function HostControl:hide()
    self.visible = false
end

return HostControl
