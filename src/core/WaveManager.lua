-- src/core/WaveManager.lua
-- Manages wave-based enemy spawning with stages and host confirmation

local class = require "lib.middleclass"

local registeredEnemyTypes = {
    melee = {
        class = nil,  -- Will be set when loading Enemy.lua
        data = { display_name = "Melee Enemy", spawn_weight = 1.0 }
    },
    ranged = {
        class = nil,
        data = { display_name = "Ranged Enemy", spawn_weight = 0.5 }
    },
    boss = {
        class = nil,
        data = { display_name = "Boss", spawn_weight = 0.1, min_wave = 5 }
    }
}

local WaveManager = class('WaveManager')

function WaveManager:initialize()
    self.currentStage = 1
    self.currentWave = 0
    self.isWaveActive = false
    self.waveCountdown = 0
    self.totalEnemies = 0
    self.enemiesAlive = 0
    self.enemiesSpawned = 0
    self.awaitingConfirmation = false
    self.gameActive = false
    self.lastEnemySpawnTime = 0
    self.enemySpawnInterval = 0.8  -- Spawn enemies every 0.8 seconds during wave

    -- Wave configurations for each stage (Stage I, Stage II, etc.)
    -- Each stage has 10 waves
    self.wavesPerStage = 10
    self.waveConfigs = {}

    -- Generate wave configs for multiple stages
    self:generateWaveConfigs()

    print("WaveManager initialized")

    -- Load modded enemies if they exist
    if _G.MOD_ENEMIES then
        for typeName, def in pairs(_G.MOD_ENEMIES) do
            self:registerEnemyType(typeName, def)
        end
    end

end

function WaveManager:registerEnemyType(typeName, enemyDef)
    registeredEnemyTypes[typeName] = enemyDef
    print("WaveManager: Registered enemy type:", typeName)
end

function WaveManager:generateWaveConfigs()
    -- Generate configurations for 10 stages
    for stage = 1, 10 do
        self.waveConfigs[stage] = {}
        for wave = 1, self.wavesPerStage do
            -- Base enemies increase with wave number
            local baseEnemies = 5 + (wave * 2) + ((stage - 1) * 5)

            -- Every 3rd wave requires host confirmation
            local requiresConfirmation = (wave % 3 == 0)

            -- Boss wave every 5th wave
            local hasBoss = (wave % 5 == 0)

            self.waveConfigs[stage][wave] = {
                enemies = baseEnemies,
                requiresConfirmation = requiresConfirmation,
                hasBoss = hasBoss,
                enemyTypes = self:getEnemyTypesForWave(stage, wave)
            }
        end
    end
end

function WaveManager:getEnemyTypesForWave(stage, wave)
    local types = {}

    -- Base enemy types
    if stage == 1 then
        if wave <= 3 then
            types = {"melee"}
        elseif wave <= 6 then
            types = {"melee", "ranged"}
        else
            types = {"melee", "ranged"}
        end
    elseif stage == 2 then
        types = {"melee", "ranged"}
        if wave >= 5 then
            table.insert(types, "boss")
        end
    else
        types = {"melee", "ranged", "boss"}
    end

    -- Add modded enemies that meet wave requirements
    for enemyType, def in pairs(registeredEnemyTypes) do
        if not (enemyType == "melee" or enemyType == "ranged" or enemyType == "boss") then
            local minWave = def.data.min_wave or 1
            if wave >= minWave then
                table.insert(types, enemyType)
            end
        end
    end

    return types
end

function WaveManager:startGame()
    self.currentStage = 1
    self.currentWave = 0
    self.isWaveActive = false
    self.gameActive = true
    self.totalEnemies = 0
    self.enemiesAlive = 0
    self.enemiesSpawned = 0
    self.awaitingConfirmation = false

    -- Start with 5-second countdown
    self.waveCountdown = 5

    return {
        stage = self.currentStage,
        wave = self.currentWave,
        countdown = self.waveCountdown,
        message = "Game starting in 5 seconds...",
        gameActive = true
    }
end

function WaveManager:update(dt)
    if not self.gameActive then return nil end

    -- Handle countdown
    if self.waveCountdown > 0 then
        self.waveCountdown = self.waveCountdown - dt
        if self.waveCountdown <= 0 then
            local waveData = self:startNextWave()
            return {
                type = "wave_started",
                data = waveData
            }
        end
        return {
            type = "countdown",
            data = {
                countdown = math.ceil(self.waveCountdown)
            }
        }
    end

    -- Handle wave completion check
    if self.isWaveActive and self.enemiesAlive <= 0 and self.enemiesSpawned >= self.totalEnemies then
        local waveData = self:completeWave()
        return {
            type = "wave_completed",
            data = waveData
        }
    end

    return nil
end

function WaveManager:startNextWave()
    self.currentWave = self.currentWave + 1

    -- Check if we need to advance to next stage
    if self.currentWave > self.wavesPerStage then
        self.currentStage = self.currentStage + 1
        self.currentWave = 1
    end

    local config = self.waveConfigs[self.currentStage][self.currentWave]
    self.totalEnemies = config.enemies
    self.enemiesAlive = 0  -- Will increase as enemies spawn
    self.enemiesSpawned = 0
    self.isWaveActive = true
    self.awaitingConfirmation = config.requiresConfirmation
    self.lastEnemySpawnTime = 0

    if self.awaitingConfirmation then
        self.isWaveActive = false
        return {
            stage = self.currentStage,
            wave = self.currentWave,
            enemies = self.totalEnemies,
            requiresConfirmation = true,
            hasBoss = config.hasBoss,
            message = "Wave " .. self.currentWave .. " (Stage " .. self.currentStage .. ") requires host confirmation"
        }
    end

    return {
        stage = self.currentStage,
        wave = self.currentWave,
        enemies = self.totalEnemies,
        requiresConfirmation = false,
        hasBoss = config.hasBoss,
        enemyTypes = config.enemyTypes,
        message = "Wave " .. self.currentWave .. " (Stage " .. self.currentStage .. ") started!"
    }
end

function WaveManager:confirmWave()
    if self.awaitingConfirmation then
        self.awaitingConfirmation = false
        self.isWaveActive = true
        return true
    end
    return false
end

function WaveManager:completeWave()
    self.isWaveActive = false

    -- CRITICAL FIX: Only auto-start countdown for waves that don't require confirmation
    local nextWave = self.currentWave + 1
    local nextStage = self.currentStage

    if nextWave > self.wavesPerStage then
        nextStage = nextStage + 1
        nextWave = 1
    end

    local nextConfig = self.waveConfigs[nextStage] and self.waveConfigs[nextStage][nextWave]

    if nextConfig and not nextConfig.requiresConfirmation then
        -- Auto-start next wave after 5 seconds
        self.waveCountdown = 5
    else
        -- Wave requires confirmation - don't auto-start
        self.waveCountdown = 0
    end

    -- Check if all stages and waves completed
    if self.currentStage >= 10 and self.currentWave >= self.wavesPerStage then
        self.gameActive = false
        return {
            stage = self.currentStage,
            wave = self.currentWave,
            completed = true,
            gameCompleted = true,
            message = "CONGRATULATIONS! You completed all stages!",
            requiresConfirmation = false
        }
    end

    return {
        stage = self.currentStage,
        wave = self.currentWave,
        completed = true,
        gameCompleted = false,
        message = "Wave " .. self.currentWave .. " (Stage " .. self.currentStage .. ") completed!" ..
                 (nextConfig and nextConfig.requiresConfirmation and
                  " Host must confirm next wave." or " Next wave in 5 seconds..."),
        requiresConfirmation = nextConfig and nextConfig.requiresConfirmation or false
    }
end

function WaveManager:shouldSpawnEnemy(currentTime)
    if not self.isWaveActive then return false end
    if self.enemiesSpawned >= self.totalEnemies then return false end

    return currentTime - self.lastEnemySpawnTime >= self.enemySpawnInterval
end

function WaveManager:spawnEnemy(currentTime)
    self.enemiesSpawned = self.enemiesSpawned + 1
    self.enemiesAlive = self.enemiesAlive + 1
    self.lastEnemySpawnTime = currentTime

    local config = self.waveConfigs[self.currentStage][self.currentWave]
    local enemyTypes = config.enemyTypes

    -- Weighted random selection
    local totalWeight = 0
    local weightedList = {}

    for _, enemyType in ipairs(enemyTypes) do
        local def = registeredEnemyTypes[enemyType]
        if def then
            local weight = def.data.spawn_weight or 1.0
            totalWeight = totalWeight + weight
            table.insert(weightedList, {type = enemyType, weight = weight, cumWeight = 0})
        end
    end

    -- Build cumulative weights
    local cumWeight = 0
    for i, entry in ipairs(weightedList) do
        cumWeight = cumWeight + entry.weight
        entry.cumWeight = cumWeight
    end

    -- Select random enemy
    local rand = love.math.random() * totalWeight
    local selectedType = "melee"  -- Default

    for _, entry in ipairs(weightedList) do
        if rand <= entry.cumWeight then
            selectedType = entry.type
            break
        end
    end

    return selectedType
end

function WaveManager:enemyDied()
    self.enemiesAlive = math.max(0, self.enemiesAlive - 1)
end

function WaveManager:canAcceptNewPlayers()
    return not self.isWaveActive and self.waveCountdown <= 0 and self.gameActive
end

function WaveManager:getStatus()
    return {
        stage = self.currentStage,
        wave = self.currentWave,
        isWaveActive = self.isWaveActive,
        waveCountdown = math.max(0, self.waveCountdown),
        enemiesAlive = self.enemiesAlive,
        totalEnemies = self.totalEnemies,
        enemiesSpawned = self.enemiesSpawned,
        awaitingConfirmation = self.awaitingConfirmation,
        gameActive = self.gameActive
    }
end

function WaveManager:reset()
    self.currentStage = 1
    self.currentWave = 0
    self.isWaveActive = false
    self.gameActive = false
    self.waveCountdown = 0
    self.totalEnemies = 0
    self.enemiesAlive = 0
    self.enemiesSpawned = 0
    self.awaitingConfirmation = false
end

return WaveManager
