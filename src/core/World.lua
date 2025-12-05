-- World.lua
local World = {}
World.walls = {}
World.groundTiles = {}
World.gridSize = 32  -- Size of each tile in pixels
World.width = 800    -- Screen width
World.height = 600   -- Screen height

-- Initialize the world with walls and ground
function World.init()
    -- Clear existing walls
    World.walls = {}

    -- Define wall types
    local wallTypes = {
        normal = {color = {0.5, 0.3, 0.1}, thickness = 1.0},    -- Brown
        boundary = {color = {0.2, 0.2, 0.4}, thickness = 1.0},  -- Dark blue
        obstacle = {color = {0.6, 0.2, 0.2}, thickness = 1.0}   -- Red
    }

    -- 1. Create boundary walls (screen edges)
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

    -- 2. Create interior walls (rooms, corridors)
    -- Room 1 (top-left)
    table.insert(World.walls, {x = 100, y = 100, width = 200, height = 10})
    table.insert(World.walls, {x = 100, y = 100, width = 10, height = 150})
    table.insert(World.walls, {x = 290, y = 100, width = 10, height = 150})
    table.insert(World.walls, {x = 100, y = 240, width = 200, height = 10})

    -- Room 2 (top-right) with entrance
    table.insert(World.walls, {x = 400, y = 100, width = 200, height = 10})
    table.insert(World.walls, {x = 400, y = 100, width = 10, height = 150})
    -- Note: No right wall for entrance
    table.insert(World.walls, {x = 400, y = 240, width = 200, height = 10})

    -- Central pillar/obstacle
    table.insert(World.walls, {
        x = 350, y = 250, width = 100, height = 100,
        type = "obstacle", properties = wallTypes.obstacle
    })

    -- Bottom area walls
    table.insert(World.walls, {x = 50, y = 400, width = 300, height = 10})
    table.insert(World.walls, {x = 450, y = 400, width = 300, height = 10})
    table.insert(World.walls, {x = 50, y = 400, width = 10, height = 100})
    table.insert(World.walls, {x = 740, y = 400, width = 10, height = 100})

    -- 3. Generate ground tiles (visual only, no collision)
    World.generateGroundTiles()

    print("World initialized with " .. #World.walls .. " walls")
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
                color = isDark and {0.3, 0.3, 0.3} or {0.35, 0.35, 0.35}
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
    love.graphics.setColor(0.2, 0.2, 0.2, 0.3)
    for x = 0, World.width, World.gridSize do
        love.graphics.line(x, 0, x, World.height)
    end
    for y = 0, World.height, World.gridSize do
        love.graphics.line(0, y, World.width, y)
    end

    -- Draw walls
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

-- Check collision between two rectangles (AABB collision)
function World.checkCollision(rect1, rect2)
    return rect1.x < rect2.x + rect2.width and
           rect1.x + rect1.width > rect2.x and
           rect1.y < rect2.y + rect2.height and
           rect1.y + rect1.height > rect2.y
end

-- Check if a rectangle collides with any wall
-- Returns: true/false, wall that was collided with, and collision side
function World.checkWallCollision(rect)
    for _, wall in ipairs(World.walls) do
        if World.checkCollision(rect, wall) then
            -- Determine collision side for better resolution
            local side = World.getCollisionSide(rect, wall)
            return true, wall, side
        end
    end
    return false, nil, nil
end

-- Determine which side of the wall was hit
function World.getCollisionSide(rect, wall)
    -- Calculate overlaps on each axis
    local overlapLeft = (rect.x + rect.width) - wall.x
    local overlapRight = (wall.x + wall.width) - rect.x
    local overlapTop = (rect.y + rect.height) - wall.y
    local overlapBottom = (wall.y + wall.height) - rect.y

    -- Find smallest overlap
    local minOverlap = math.min(overlapLeft, overlapRight, overlapTop, overlapBottom)

    if minOverlap == overlapLeft then return "left" end
    if minOverlap == overlapRight then return "right" end
    if minOverlap == overlapTop then return "top" end
    if minOverlap == overlapBottom then return "bottom" end

    return "unknown"
end

-- Resolve collision by pushing rectangle out of wall
function World.resolveCollision(rect, wall, side)
    if side == "left" then
        rect.x = wall.x - rect.width
    elseif side == "right" then
        rect.x = wall.x + wall.width
    elseif side == "top" then
        rect.y = wall.y - rect.height
    elseif side == "bottom" then
        rect.y = wall.y + wall.height
    end
end

-- Raycasting: Check if a line hits a wall
function World.raycast(x1, y1, x2, y2)
    -- Simple implementation: check line intersection with each wall
    for _, wall in ipairs(World.walls) do
        local hit, hitX, hitY = World.lineRectIntersect(x1, y1, x2, y2, wall)
        if hit then
            return true, hitX, hitY, wall
        end
    end
    return false, nil, nil, nil
end

-- Line-rectangle intersection
function World.lineRectIntersect(x1, y1, x2, y2, rect)
    -- Check if either endpoint is inside the rectangle
    if (x1 >= rect.x and x1 <= rect.x + rect.width and
        y1 >= rect.y and y1 <= rect.y + rect.height) then
        return true, x1, y1
    end
    if (x2 >= rect.x and x2 <= rect.x + rect.width and
        y2 >= rect.y and y2 <= rect.y + rect.height) then
        return true, x2, y2
    end

    -- Check line intersection with each edge
    local edges = {
        {x1 = rect.x, y1 = rect.y, x2 = rect.x + rect.width, y2 = rect.y}, -- top
        {x1 = rect.x, y1 = rect.y + rect.height, x2 = rect.x + rect.width, y2 = rect.y + rect.height}, -- bottom
        {x1 = rect.x, y1 = rect.y, x2 = rect.x, y2 = rect.y + rect.height}, -- left
        {x1 = rect.x + rect.width, y1 = rect.y, x2 = rect.x + rect.width, y2 = rect.y + rect.height} -- right
    }

    for _, edge in ipairs(edges) do
        local hit, x, y = World.lineLineIntersect(x1, y1, x2, y2,
                                                  edge.x1, edge.y1, edge.x2, edge.y2)
        if hit then
            return true, x, y
        end
    end

    return false, nil, nil
end

-- Line-line intersection
function World.lineLineIntersect(x1, y1, x2, y2, x3, y3, x4, y4)
    local denom = (y4 - y3) * (x2 - x1) - (x4 - x3) * (y2 - y1)
    if denom == 0 then return false end

    local ua = ((x4 - x3) * (y1 - y3) - (y4 - y3) * (x1 - x3)) / denom
    local ub = ((x2 - x1) * (y1 - y3) - (y2 - y1) * (x1 - x3)) / denom

    if ua >= 0 and ua <= 1 and ub >= 0 and ub <= 1 then
        return true, x1 + ua * (x2 - x1), y1 + ua * (y2 - y1)
    end
    return false
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
    local attempts = 0
    local maxAttempts = 100

    while attempts < maxAttempts do
        local x = love.math.random(50, World.width - 50)
        local y = love.math.random(50, World.height - 50)

        -- Check if this point is clear of walls
        if not World.isPointInWall(x, y) then
            -- Also check area around the point
            local areaClear = true
            for dx = -20, 20, 10 do
                for dy = -20, 20, 10 do
                    if World.isPointInWall(x + dx, y + dy) then
                        areaClear = false
                        break
                    end
                end
                if not areaClear then break end
            end

            if areaClear then
                return x, y
            end
        end

        attempts = attempts + 1
    end

    -- Fallback to center
    return World.width / 2, World.height / 2
end

-- Draw collision debug info (call this after all drawing)
function World.drawDebugInfo()
    love.graphics.setColor(0, 1, 0)
    love.graphics.print("Walls: " .. #World.walls, World.width - 100, 10)

    -- Show grid coordinates at mouse position
    local mx, my = love.mouse.getPosition()
    local gridX = math.floor(mx / World.gridSize)
    local gridY = math.floor(my / World.gridSize)
    love.graphics.print("Grid: " .. gridX .. ", " .. gridY, World.width - 100, 30)

    love.graphics.setColor(1, 1, 1)
end

return World
