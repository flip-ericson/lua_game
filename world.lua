--- "world.lua" begins here ---
local Settings = require('settings')
local Tiles = require('tiles')
local Collision = require('collision')

local World = {}

-- World data storage
World.tiles = {}
World.nextID = 1
World.tilesModified = {}
World.SingleTickClock = 0
World.TickCounter = 0

-- Helper: Create coordinate key for efficient lookup
local function coordKey(q, r, z)
    return string.format("%d,%d,%d", q, r, z)
end

-- Helper: for midified tiles
function World.addModifiedTile(tile)
    World.tilesModified[tile] = true
end

function World.removeModifiedTile(tile)
    World.tilesModified[tile] = nil
end

-- Helper to iterate over modified tiles
function World.iterateModifiedTiles()
    local tiles = {}
    for tile, _ in pairs(World.tilesModified) do
        table.insert(tiles, tile)
    end
    return tiles
end

-- Create a new tile
function World.createTile(q, r, zLayer, tileType)
    local tile = {
        id = World.nextID,
        q = q,
        r = r,
        z = zLayer,
        type = tileType
    }
    --initialize the health if needed
    if tileType.maxHealth then
        tile.health = tileType.maxHealth
    end
    World.nextID = World.nextID + 1
    World.tiles[coordKey(q, r, zLayer)] = tile
    return tile
end

-- Get tile at coordinates
function World.getTile(q, r, z)
    return World.tiles[coordKey(q, r, z)]
end

-- Initialize world with simple generation
function World.generate()
    local hw = math.floor(Settings.gridWidth / 2)
    local hh = math.floor(Settings.gridHeight / 2)
    --- first handle the underground layer (bedrock for now)
    local zLayer = 0
    for q = -hw, hw do
        for r = -hh, hh do
            World.createTile(q, r, zLayer, Tiles.TileType.BEDROCK)
        end
    end
    --- first handle the "ground level"
    local zLayer = 1
    for q = -hw, hw do
        for r = -hh, hh do
            if math.random(20) == 1 then
                World.createTile(q, r, zLayer, Tiles.TileType.WATER)
            else
                World.createTile(q, r, zLayer, Tiles.TileType.GRASS)
            end
        end
    end
    --- next handle the "player level"
    zLayer = 2
    for q = -hw, hw do
        for r = -hh, hh do
            -- Create stone roughly every 10 tiles
            if math.random(10) == 1 then
                World.createTile(q, r, zLayer, Tiles.TileType.STONE)
            end
        end
    end
end

-- Get the 3 SOUTHERN neighbors and determine wall needs
function World.getWallNeighbors(q, r, z, tile)
    -- Southern directions for flat-top hex
    local SOUTHERN_DIRECTIONS = {
        {-1, 1},  -- SW (left wall)
        {0, 1},   -- S  (top/center wall)
        {1, 0}    -- SE (right wall)
    }
    local neighborTypes = {}
    
    for i = 1, 3 do
        local dir = SOUTHERN_DIRECTIONS[i]
        local neighbor_q = q + dir[1]
        local neighbor_r = r + dir[2]
        local neighborTile = World.getTile(neighbor_q, neighbor_r, z)
        
        if not neighborTile then
            -- No neighbor! Wall is exposed, use THIS tile's texture
            neighborTypes[i] = tile.type.sideTexturePath
        else
            -- Neighbor exists, no wall needed on this face
            neighborTypes[i] = "void"
        end
    end
    return neighborTypes
end

-- Check which tiles need walls
function World.whereWalls()
    for key, tile in pairs(World.tiles) do
        -- Check the 3 southern neighbors at THIS tile's level
        local neighborTypes = World.getWallNeighbors(tile.q, tile.r, tile.z, tile)
        
        -- If ANY wall is NOT void, this tile needs walls
        if neighborTypes[1] ~= "void" or neighborTypes[2] ~= "void" or neighborTypes[3] ~= "void" then
            tile.wallInfo = {
                left = neighborTypes[1],
                top = neighborTypes[2],
                right = neighborTypes[3]
            }
        else
            -- All faces covered by neighbors, no walls needed
            tile.wallInfo = nil
        end
    end
end

-- function to update tiles globally
function World.UpdateTiles(dt)
    World.SingleTickClock = World.SingleTickClock + dt

    if World.SingleTickClock >= Settings.tickSpeed then  -- default is 1 second
        World.SingleTickClock = World.SingleTickClock - Settings.tickSpeed
        World.TickCounter = World.TickCounter + 1
        --- check for tile health updates ---
        if World.TickCounter % Settings.healthTick == 0 then
            for tile, _ in pairs(World.tilesModified) do
                if tile and tile.type then
                end
                -- Only heal tiles that have health system
                if tile.type.maxHealth and tile.health then
                    if tile.health < tile.type.maxHealth then
                        tile.health = tile.health + 1
                    end
                end
            end
        end
        --- check for grass spread ---
        if World.TickCounter % Settings.grassSpreadTick == 0 then
            --- find loaded dirt
            local dirtTilesToConvert = {}
            for key, tile in pairs(World.tiles) do
                if tile.type.name == "dirt" then
                    -- check neighbors
                    local neighbors = Collision.getHexNeighbors(tile.q, tile.r)
                    -- find grass
                    local hasGrass = false
                    for _, neighborCoord in ipairs(neighbors) do
                        local neighborTile = World.getTile(neighborCoord.q, neighborCoord.r, tile.z)
                        if neighborTile and neighborTile.type.name == "grass" then
                            hasGrass = true
                            break
                        end
                    end
                    --- log candidate for grass spread
                    if hasGrass then
                        table.insert(dirtTilesToConvert, tile)
                    end
                end
            end
            -- convert tiles to grass
            for _, tile in ipairs(dirtTilesToConvert) do
                if math.random(1, Settings.grassSpreadChance) == 1 then
                    World.createTile(tile.q, tile.r, tile.z, Tiles.TileType.GRASS)
                end
            end
        end
        --- check for natural water watering tilled land ---
        if World.TickCounter % Settings.waterSpreadTick == 0 then
            --- find loaded dry tilled land
            local dryTilledTilesToConvert = {}
            for key, tile in pairs(World.tiles) do
                if tile.type.name == "dry_farmland" then
                    -- check neighbors
                    local neighbors = Collision.getHexNeighbors(tile.q, tile.r)
                    -- find water
                    local hasWater = false
                    for _, neighborCoord in ipairs(neighbors) do
                        local neighborTile = World.getTile(neighborCoord.q, neighborCoord.r, tile.z)
                        if neighborTile and neighborTile.type.name == "water" then
                            hasWater = true
                            break
                        end
                    end
                    --- log candidates for water spread
                    if hasWater then
                        table.insert(dryTilledTilesToConvert, tile)
                    end
                end
            end
            -- convert tiles to wet farmland
            for _, tile in ipairs(dryTilledTilesToConvert) do
                if math.random(1, Settings.waterSpreadChance) == 1 then
                    World.createTile(tile.q, tile.r, tile.z, Tiles.TileType.WET_FARMLAND)
                end
            end
        end
        --- wet land can become dry ---
        if World.TickCounter % Settings.landDriesTick == 0 then
            --- find wet tiles
            local wetTilesToConvert = {}
            for key, tile in pairs(World.tiles) do
                if tile.type.name == 'wet_farmland' then
                    -- check neighbors (farmland by water enver dries out)
                    local neighbors = Collision.getHexNeighbors(tile.q, tile.r)
                    -- find water
                    local hasWater = false
                    for _, neighborCoord in ipairs(neighbors) do
                        local neighborTile = World.getTile(neighborCoord.q, neighborCoord.r, tile.z)
                        if neighborTile and neighborTile.type.name == "water" then
                            hasWater = true
                            break
                        end
                    end
                    --- log candidates
                    if not hasWater then
                        table.insert(wetTilesToConvert, tile)
                    end
                end
            end
            --- convert to dry
            for _, tile in ipairs(wetTilesToConvert) do
                if math.random(1, Settings.landDriesChance) == 1 then
                    World.createTile(tile.q, tile.r, tile.z, Tiles.TileType.DRY_FARMLAND)
                end
            end
        end
        -- tilled land can become dirt -- 
        if World.TickCounter % Settings.tillFailTick == 0 then
            -- find tilled tiles
            local tilledTilesToConvert = {}
            for key, tile in pairs(World.tiles) do
                if tile.type.name == 'dry_farmland' then
                    --- log candidates
                    table.insert(tilledTilesToConvert, tile)
                end
            end
            --- convert to dirt
            for _, tile in ipairs(tilledTilesToConvert) do
                if math.random(1, Settings.tillFailChance) == 1 then
                    World.createTile(tile.q, tile.r, tile.z, Tiles.TileType.DIRT)
                end
            end
        end
        --- reset tick cycle AFTER all updates 
        if World.TickCounter >= Settings.tickFullCycle then
            World.TickCounter = 0
        end
    end
end

return World
--- "world.lua" ends here ---