-- World.lua - Empty arena for multiplayer combat
local World = {}
World.walls = {}
World.groundTiles = {}
World.gridSize = 32  -- Size of each tile in pixels
World.width = 800    -- Screen width
World.height = 600   -- Screen height
World.spawnPoints = {} -- Designated spawn points for players

-- Initialize the world as an empty arena
function World.init()
    -- Clear existing walls
    World.walls = {}

    -- Define arena boundary (optional - you can remove for completely open)
    local wallTypes = {
        boundary = {color = {0.2, 0.2, 0.4}, thickness = 1.0}  -- Dark blue
    }

    -- Optional: Create boundary walls (screen edges) - COMMENT OUT FOR OPEN ARENA
    --[[
    table.insert(World.walls, {
        x = 0, y = 0, width = World.width, height = 10,
        type = "boundary", properties = wallTypes.boundary
    })
    table.insert(World.walls, {
        x = 0, y = World.height - 10, width = World.width, height = 10,
        type = "boundary", properties = wallTypes.boundary
    })
    table.insert(World.walls, {
        x = 0, y = 0, width = 10, height = World.height,
        type = "boundary", properties = wallTypes.boundary
    })
    table.insert(World.walls, {
        x = World.width - 10, y = 0, width = 10, height = World.height,
        type = "boundary", properties = wallTypes.boundary
    })
    --]]

    -- Create designated spawn points around the arena
    World.spawnPoints = {
        {x = 100, y = 100},        -- Top-left
        {x = World.width - 100, y = 100},  -- Top-right
        {x = 100, y = World.height - 100}, -- Bottom-left
        {x = World.width - 100, y = World.height - 100}, -- Bottom-right
        {x = World.width / 2, y = 100},    -- Top-center
        {x = World.width / 2, y = World.height - 100}, -- Bottom-center
        {x = 100, y = World.height / 2},   -- Middle-left
        {x = World.width - 100, y = World.height / 2}  -- Middle-right
    }

    -- Generate ground tiles (visual only)
    World.generateGroundTiles()

    print("Empty arena initialized with " .. #World.walls .. " walls")
end

-- Generate a checkerboard ground pattern
function World.generateGroundTiles()
    World.groundTiles = {}
    local tileSize = World.gridSize

    for x = 0, World.width, tileSize do
        for y = 0, World.height, tileSize do
            local isDark = ((math.floor(x / tileSize) + math.floor(y / tileSize)) % 2) == 0
            table.insert(World.groundTiles, {
                x = x, y = y,
                color = isDark and {0.2, 0.2, 0.2} or {0.25, 0.25, 0.25} -- Darker for arena
            })
        end
    end
end

-- Draw the world (call this in love.draw, before drawing entities)
function World.draw()
    -- Draw ground tiles first
    for _, tile in ipairs(World.groundTiles) do
        love.graphics.setColor(tile.color)
        love.graphics.rectangle("fill", tile.x, tile.y, World.gridSize, World.gridSize)
    end

    -- Draw grid lines (optional, for debugging)
    love.graphics.setColor(0.1, 0.1, 0.1, 0.3)
    for x = 0, World.width, World.gridSize do
        love.graphics.line(x, 0, x, World.height)
    end
    for y = 0, World.height, World.gridSize do
        love.graphics.line(0, y, World.width, y)
    end

    -- Draw walls (if any)
    for _, wall in ipairs(World.walls) do
        if wall.properties and wall.properties.color then
            love.graphics.setColor(wall.properties.color)
        else
            love.graphics.setColor(0.5, 0.3, 0.1) -- Default wall color
        end

        love.graphics.rectangle("fill", wall.x, wall.y, wall.width, wall.height)

        -- Draw wall outline
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("line", wall.x, wall.y, wall.width, wall.height)
    end

    love.graphics.setColor(1, 1, 1)
end

-- Get a random spawn point
function World.getRandomSpawnPoint()
    if #World.spawnPoints > 0 then
        local spawn = World.spawnPoints[love.math.random(1, #World.spawnPoints)]
        return spawn.x, spawn.y
    end
    return World.width / 2, World.height / 2
end

-- Check collision between two rectangles (AABB collision)
function World.checkCollision(rect1, rect2)
    return rect1.x < rect2.x + rect2.width and
           rect1.x + rect1.width > rect2.x and
           rect1.y < rect2.y + rect2.height and
           rect1.y + rect1.height > rect2.y
end

-- Check if a rectangle collides with any wall
function World.checkWallCollision(rect)
    for _, wall in ipairs(World.walls) do
        if World.checkCollision(rect, wall) then
            return true, wall
        end
    end
    return false, nil
end

-- Check if point is inside any wall (for spawn point validation)
function World.isPointInWall(x, y)
    for _, wall in ipairs(World.walls) do
        if x >= wall.x and x <= wall.x + wall.width and
           y >= wall.y and y <= wall.y + wall.height then
            return true
        end
    end
    return false
end

-- Find a valid spawn location (not in walls)
function World.findSpawnLocation()
    -- Use designated spawn points
    return World.getRandomSpawnPoint()
end

return World
