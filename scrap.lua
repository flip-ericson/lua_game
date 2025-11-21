---"collision.lua" begins here ---
local Settings = require('settings')

local Collision = {}

--- COORDINATE CONVERSION ---
-- Convert pixel coordinates to axial hex coordinates (q, r); this matches your hexToPixel conversion
function Collision.pixelToAxial(x, y)
    local size = Settings.hexSize
    local q = (2/3 * x) / size
    local r = (-1/3 * x + math.sqrt(3)/3 * y) / size
    -- Round to nearest hex using cube coordinates
    return Collision.axialRound(q, r)
end

-- Round fractional axial coordinates to nearest hex
function Collision.axialRound(q, r)
    -- Convert axial to cube coordinates
    local x = q
    local z = r
    local y = -x - z
    -- Round each coordinate
    local rx = math.floor(x + 0.5)
    local ry = math.floor(y + 0.5)
    local rz = math.floor(z + 0.5)
    -- Calculate rounding errors
    local x_diff = math.abs(rx - x)
    local y_diff = math.abs(ry - y)
    local z_diff = math.abs(rz - z)
    -- Reset the component with largest error
    if x_diff > y_diff and x_diff > z_diff then
        rx = -ry - rz
    elseif y_diff > z_diff then
        ry = -rx - rz
    else
        rz = -rx - ry
    end
    -- Convert back to axial
    return rx, rz
end

-- Convert axial hex coordinates to pixel coordinates (center of hex); this matches your "main.lua" hexToPixel function
function Collision.axialToPixel(q, r)
    local size = Settings.hexSize
    local x = size * (3/2 * q)
    local y = size * (math.sqrt(3)/2 * q + math.sqrt(3) * r)
    return x, y
end

--- HEX NEIGHBORS ---
-- Axial direction vectors for the 6 neighbors (flat-top)
local AXIAL_DIRECTIONS = {
    {1, 0},   -- SE
    {1, -1},  -- NE  
    {0, -1},  -- N
    {-1, 0},  -- NW
    {-1, 1},  -- SW
    {0, 1}    -- S
}
-- Get all 6 neighboring hex coordinates
function Collision.getHexNeighbors(q, r)
    local neighbors = {}
    for i = 1, 6 do
        local dir = AXIAL_DIRECTIONS[i]
        neighbors[i] = {q = q + dir[1], r = r + dir[2]}
    end
    return neighbors
end

--- POINT-IN-HEX TEST ---
-- Test if a point (px, py) is inside a hexagon centered at (hexX, hexY)
function Collision.pointInHex(px, py, hexX, hexY, hexRadius)
    -- Translate point to hex-local coordinates
    local dx = px - hexX
    local dy = py - hexY
    -- Flat-top hexagon has 6 edges; test against 3 pairs of parallel edges
    local radius = hexRadius or Settings.hexSize
    local s = radius * math.sqrt(3) / 2  -- horizontal distance to edge
    -- Test 1: Top and bottom edges (horizontal)
    if math.abs(dy) > radius * 0.75 then
        return false
    end
    -- Test 2: Upper edges (angled)
    local upperBound = radius - math.abs(dx) / s * radius * 0.5
    if math.abs(dy) > upperBound then
        return false
    end
    return true
end

--- CIRCLE FULLY INSIDE HEX TEST ---
-- Test if a circle is COMPLETELY inside a hexagon (for water detection)
function Collision.circleFullyInsideHex(circleX, circleY, circleRadius, hexX, hexY)
    local numSamples = 8  -- Check 8 points around the circle (every 45 degrees)
    for i = 0, numSamples - 1 do
        local angle = (i / numSamples) * 2 * math.pi
        local edgeX = circleX + circleRadius * math.cos(angle)
        local edgeY = circleY + circleRadius * math.sin(angle)
        -- If ANY point on the circle edge is outside the hex, circle is not fully inside
        if not Collision.pointInHex(edgeX, edgeY, hexX, hexY) then
            return false
        end
    end
    -- All sampled points are inside - circle is fully contained
    return true
end

--- COLLISION CHECKING ---
-- Check if player collides with any solid tiles; Returns: colliding (boolean), collision data table, water tiles
function Collision.checkCollision(player, World)
    -- Get player center position
    local centerX = player.x + player.size / 2
    local centerY = player.y + player.size / 2
    --Get player feet position
    local feetX = player.x + player.size / 2
    local feetY = player.y + player.size * 0.75
    -- Convert player position to hex coordinates
    local playerQ, playerR = Collision.pixelToAxial(centerX, centerY)
    -- Get current hex + 6 neighbors (broad phase)
    local hexesToCheck = {{q = playerQ, r = playerR}}
    local neighbors = Collision.getHexNeighbors(playerQ, playerR)
    for i = 1, 6 do
        hexesToCheck[#hexesToCheck + 1] = neighbors[i]
    end
    -- Check each hex for collision (narrow phase)
    local collisions = {}
    local waterTiles = {}
    local waterDetectionRadius = (player.size / 2) * 0.35 -- adjust this multiplier to tune the swimming
    local onGround = false

    for _, hex in ipairs(hexesToCheck) do
        local hexCenterX, hexCenterY = Collision.axialToPixel(hex.q, hex.r)
        -- Check for solid tiles on current layer
        local tile = World.getTile(hex.q, hex.r, player.zLayer)
        local tileBelow = World.getTile(hex.q, hex.r, (player.zLayer - 1))
        if tile and tile.type.solid then
            -- Check if player circle overlaps this hex (full radius for solids)
            if Collision.circleHexCollision(centerX, centerY, player.size / 2, hexCenterX, hexCenterY) then
                table.insert(collisions, {
                    q = hex.q,
                    r = hex.r,
                    hexCenterX = hexCenterX,
                    hexCenterY = hexCenterY,
                    tile = tile
                })
            end
        end
        -- Check if there's ANY solid ground below the player's feet
        if tileBelow and not tileBelow.type.isWater then
            -- Check if feet are over this tile
            if Collision.pointInHex(feetX, feetY, hexCenterX, hexCenterY) then
                onGround = true
            end
        end
        -- Check for water tiles on layer below
        if tileBelow and tileBelow.type.isWater then
            -- Water detection uses a SMALLER radius
            -- Check if the smaller detection circle is COMPLETELY inside the water hex
            if Collision.circleFullyInsideHex(feetX, feetY, waterDetectionRadius, hexCenterX, hexCenterY) then
                table.insert(waterTiles, {
                    q = hex.q,
                    r = hex.r,
                    tile = tileBelow
                })
            end
        end
        -- Check for ledge tile
        if not player.isJumping then
            if not tileBelow then
                onGround = false
                local hexCenterX, hexCenterY = Collision.axialToPixel(hex.q, hex.r)
                -- Check if player circle overlaps this hex (full radius for solids)
                if Collision.circleHexCollision(centerX, centerY, player.size / 2, hexCenterX, hexCenterY) then
                    table.insert(collisions, {
                        q = hex.q,
                        r = hex.r,
                        hexCenterX = hexCenterX,
                        hexCenterY = hexCenterY,
                        tile = tile
                    })
                end
                -- see if he fell in the hole like an idiot
                if Collision.circleFullyInsideHex(feetX, feetY, (player.size / 2), hexCenterX, hexCenterY) then
                    print(player.zLayer)
                    player.zLayer = player.zLayer - 1
                end
            end
        end
    end
    -- Return BOTH collision types
    return #collisions > 0, collisions, waterTiles, onGround
end

-- CIRCLE-HEX COLLISION
-- Test if a circle overlaps with a hexagon
function Collision.circleHexCollision(circleX, circleY, circleRadius, hexX, hexY)
    -- First check: is circle center inside hex?
    if Collision.pointInHex(circleX, circleY, hexX, hexY) then
        return true
    end
    -- Second check: is circle close enough to touch hex edges?
    -- Get the 6 vertices of the hex
    local vertices = Collision.getHexVertices(hexX, hexY)
    -- Check distance to each edge
    for i = 1, 6 do
        local v1 = vertices[i]
        local v2 = vertices[(i % 6) + 1]  -- Next vertex (wraps around)
        -- Find closest point on edge to circle center
        local closestX, closestY = Collision.closestPointOnSegment(
            circleX, circleY, v1.x, v1.y, v2.x, v2.y
        )
        -- Check if closest point is within circle radius
        local dx = closestX - circleX
        local dy = closestY - circleY
        local distSquared = dx * dx + dy * dy
        if distSquared <= circleRadius * circleRadius then
            return true
        end
    end
    return false
end

-- Get the 6 vertices of a flat-top hexagon
function Collision.getHexVertices(hexX, hexY)
    local vertices = {}
    local radius = Settings.hexSize
    -- Flat-top hexagon vertices (starting from rightmost, going counter-clockwise)
    local angles = {0, 60, 120, 180, 240, 300}
    for i = 1, 6 do
        local angleRad = math.rad(angles[i])
        vertices[i] = {
            x = hexX + radius * math.cos(angleRad),
            y = hexY + radius * math.sin(angleRad)
        }
    end
    return vertices
end

-- Find closest point on line segment to a given point
function Collision.closestPointOnSegment(px, py, ax, ay, bx, by)
    local dx = bx - ax
    local dy = by - ay
    local lengthSquared = dx * dx + dy * dy
    if lengthSquared == 0 then
        return ax, ay  -- Segment is a point
    end
    -- Project point onto line, clamped to segment
    local t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSquared))
    return ax + t * dx, ay + t * dy
end

--- COLLISION RESOLUTION ---
-- Resolve collision by pushing player away from hex edges
function Collision.resolveCollision(player, collisions)
    if #collisions == 0 then return end
    local playerCenterX = player.x + player.size / 2
    local playerCenterY = player.y + player.size / 2
    local playerRadius = player.size / 2
    -- Accumulate push vectors from all colliding hexes
    local totalPushX = 0
    local totalPushY = 0
    for _, collision in ipairs(collisions) do
        local hexX = collision.hexCenterX
        local hexY = collision.hexCenterY
        -- Get the 6 edges of this hex
        local vertices = Collision.getHexVertices(hexX, hexY)
        -- Find the closest edge to the player
        local minPushDist = math.huge
        local bestPushX = 0
        local bestPushY = 0
        for i = 1, 6 do
            local v1 = vertices[i]
            local v2 = vertices[(i % 6) + 1]
            -- Find closest point on this edge to player center
            local closestX, closestY = Collision.closestPointOnSegment(
                playerCenterX, playerCenterY, v1.x, v1.y, v2.x, v2.y
            )
            -- Calculate distance from player center to this edge
            local dx = playerCenterX - closestX
            local dy = playerCenterY - closestY
            local dist = math.sqrt(dx * dx + dy * dy)
            -- Calculate how much we need to push
            local overlap = playerRadius - dist
            if overlap > 0 and dist < minPushDist then
                minPushDist = dist
                -- Normalize and scale by overlap
                if dist > 0 then
                    bestPushX = (dx / dist) * overlap
                    bestPushY = (dy / dist) * overlap
                else
                    -- Player center exactly on edge (rare), push away from hex center
                    local centerDx = playerCenterX - hexX
                    local centerDy = playerCenterY - hexY
                    local centerDist = math.sqrt(centerDx * centerDx + centerDy * centerDy)
                    if centerDist > 0 then
                        bestPushX = (centerDx / centerDist) * overlap
                        bestPushY = (centerDy / centerDist) * overlap
                    end
                end
            end
        end
        -- Add this hex's push to total
        totalPushX = totalPushX + bestPushX
        totalPushY = totalPushY + bestPushY
    end
    -- Apply accumulated push
    player.x = player.x + totalPushX
    player.y = player.y + totalPushY
end

return Collision
--- "collision.lua" ends here ---
function Player:updateJumpTimer(dt)
    if self.isJumping then --- line 299
        -- increment timer by delta time
        self.jumpTimer = self.jumpTimer + dt
        -- find peak of jump (half the timer)
        if self.jumpTimer >= (Settings.jumpTime / 2) and self.goingUp then
            if self.goingUp then
                self.zLayer = self.zLayer + 1
                self.goingUp = false
            end
        end
        if self.jumpTimer >= (Settings.jumpTime) then
            self.jumpTimer = 0
            if self.onGround then
                self.isJumping = false
            end
        end
    end
end