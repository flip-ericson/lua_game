--- "tiles.lua" begins here ---
local Settings = require('settings')
local Tiles = {}

-- Tile types
Tiles.TileType = {
    GRASS = { 
        name = "grass",
        texturePath = "images/grass.png",
        sideTexturePath = "images/grass_side.png",
        texture = nil,  -- Will be loaded below
        solid = true,
        zLayer = nil,
        maxHealth = 100,
        health = 100,
        correctTool = {["Pickaxe"] = false, ["Shovel"] = true, ["Hoe"] = true}
    },
    STONE = {
        name = "stone",
        texturePath = "images/stone.png",
        sideTexturePath = "images/stone.png",
        texture = nil,  -- Will be loaded below
        solid = true,
        zLayer = nil,
        maxHealth = 100,
        health = 100,
        correctTool = {["Pickaxe"] = true, ["Shovel"] = false, ["Hoe"] = false}
    },
    WATER = {
        name = "water",
        sideTexturePath = "images/water_side.png",
        isWater = true,
        zLayer = nil,
        animated = true,
        correctTool = {["Pickaxe"] = false, ["Shovel"] = false, ["Hoe"] = false}
    },
    DIRT = {
        name = 'dirt',
        texturePath = "images/dirt.png",
        sideTexturePath = "images/dirt.png",
        texture = nil, -- Will be loaded below
        solid = true,
        zLayer = nil,
        maxHealth = 100,
        health = 100,
        correctTool = {["Pickaxe"] = false, ["Shovel"] = true, ["Hoe"] = true}
    },
    DRY_FARMLAND = {
        name = 'dry_farmland',
        texturePath = "images/farmland_dry.png",
        sideTexturePath = "images/dirt.png",
        texture = nil, -- Will be loaded below
        solid = true,
        zLayer = nil,
        maxHealth = 100,
        health = 100,
        correctTool = {["Pickaxe"] = false, ["Shovel"] = true, ["Hoe"] = true}
    },
    WET_FARMLAND = {
        name = 'wet_farmland',
        texturePath = "images/farmland_wet.png",
        sideTexturePath = "images/dirt.png",
        texture = nil, -- Will be loaded below
        solid = true,
        zLayer = nil,
        maxHealth = 100,
        health = 100,
        correctTool = {["Pickaxe"] = false, ["Shovel"] = true, ["Hoe"] = true}
    },
    BEDROCK = {
        name = 'bedrock',
        texturePath = "images/bedrock.png",
        sideTexturePath = "images/bedrock.png",
        solid = true,
        zLayer = nil
    }
}

-- Helper function to load a texture (with error handling)
local function loadTexture(path)
    if not path then return nil end
    local success, result = pcall(function()
        local img = love.graphics.newImage(path)
        img:setFilter("nearest", "nearest")  -- Pixel-perfect scaling
        return img
    end)
    if success then
        return result
    else
        print("Warning: Could not load texture:", path)
        return nil
    end
end

-- Load all textures when module is required
for _, tileType in pairs(Tiles.TileType) do
    if tileType.texturePath then
        tileType.texture = loadTexture(tileType.texturePath)
    end
end

-- Global animation state for water
Tiles.waterAnimation = {
    frames = {},
    currentFrame = 1,
    animationTimer = 0,
    animationSpeed = 0.5
}

-- Load water animation frames into global animation state
Tiles.waterAnimation.frames = {
    loadTexture("images/water_1.png"),
    loadTexture("images/water_2.png")
}

-- Function to update water animation (call this in love.update)
function Tiles.updateAnimation(dt)
    local anim = Tiles.waterAnimation
    if #anim.frames > 0 then
        anim.animationTimer = anim.animationTimer + dt
        if anim.animationTimer >= anim.animationSpeed then
            anim.animationTimer = 0
            anim.currentFrame = anim.currentFrame + 1
            -- Loop back to first frame
            if anim.currentFrame > #anim.frames then
                anim.currentFrame = 1
            end
        end
    end
end

function Tiles.createWallMeshTemplates()
    local hexSize = Settings.hexSize
    local height = Settings.tileHeightOffset
    local cos30 = math.sqrt(3) / 2
    local sin30 = 0.5
    
    -- LEFT WALL - on BOTTOM-LEFT edge (from left vertex to bottom-left vertex)
    local leftWallVertices = {
        {-hexSize, 0, 0, 0},                              -- top-left (left vertex)
        {-hexSize * sin30, hexSize * cos30, 1, 0},        -- top-right (bottom-left vertex)
        {-hexSize * sin30, hexSize * cos30 + height, 1, 1},  -- bottom-right
        {-hexSize, height, 0, 1}                          -- bottom-left
    }
    
    -- TOP WALL (rectangle) - on BOTTOM edge (from bottom-left to bottom-right)
    local topWallVertices = {
        {-hexSize * sin30, hexSize * cos30, 0, 0},        -- top-left (bottom-left vertex)
        {hexSize * sin30, hexSize * cos30, 1, 0},         -- top-right (bottom-right vertex)
        {hexSize * sin30, hexSize * cos30 + height, 1, 1},   -- bottom-right
        {-hexSize * sin30, hexSize * cos30 + height, 0, 1}   -- bottom-left
    }
    
    -- RIGHT WALL - on BOTTOM-RIGHT edge (from bottom-right to right vertex)
    local rightWallVertices = {
        {hexSize * sin30, hexSize * cos30, 0, 0},         -- top-left (bottom-right vertex)
        {hexSize, 0, 1, 0},                               -- top-right (right vertex)
        {hexSize, height, 1, 1},                          -- bottom-right
        {hexSize * sin30, hexSize * cos30 + height, 0, 1}    -- bottom-left
    }
    
    return {
        left = leftWallVertices,
        top = topWallVertices,
        right = rightWallVertices
    }
end

function Tiles.createAllWallMeshes(meshTemplates)
    local wallMeshes = {}
    local uniqueTextures = {} 
    -- Collect unique sideTexturePaths
    for tileName, tileType in pairs(Tiles.TileType) do
        if tileType.sideTexturePath and not uniqueTextures[tileType.sideTexturePath] then
            uniqueTextures[tileType.sideTexturePath] = true
        end
    end
    -- Create 3 meshes for each unique texture
    for texturePath, _ in pairs(uniqueTextures) do
        local texture = love.graphics.newImage(texturePath)
        -- Create left mesh
        local leftMesh = love.graphics.newMesh(meshTemplates.left, "fan") --line 180 as in error
        leftMesh:setTexture(texture)
        -- Create top mesh
        local topMesh = love.graphics.newMesh(meshTemplates.top, "fan")
        topMesh:setTexture(texture)
        -- Create right mesh
        local rightMesh = love.graphics.newMesh(meshTemplates.right, "fan")
        rightMesh:setTexture(texture)
        wallMeshes[texturePath] = {
            left = leftMesh,
            top = topMesh,
            right = rightMesh
        }
    end
    return wallMeshes
end

return Tiles
--- "tiles.lua" ends here ---