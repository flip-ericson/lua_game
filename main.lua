--- "main.lua" begins here ---
-- Require Modules
local Settings = require('settings')
local World = require('world')
local Player = require('player')
local Camera = require('camera')
local Time = require('time')
local Selector = require('selector')
local GameDebug = require('gamedebug')
local Items = require('items')
local Collision = require('collision')
local Tiles = require('tiles')

-- Game objects
local player
local camera
local time

-- Convert axial coordinates to pixel position (flat-top hex)
local function hexToPixel(q, r)
    local size = Settings.hexSize
    local x = size * (3/2 * q)
    local y = size * (math.sqrt(3)/2 * q + math.sqrt(3) * r)
    return x, y
end

-- Generate hex corner points (flat-top orientation)
local function getHexCorners(cx, cy)
    local size = Settings.hexSize
    local corners = {}
    for i = 0, 5 do
        local angle = math.pi / 180 * (60 * i)
        table.insert(corners, cx + size * math.cos(angle))
        table.insert(corners, cy + size * math.sin(angle))
    end
    return corners
end

-- Draw a single hex tile with texture masking
local function drawHex(tile, x, y)
    local corners = getHexCorners(x, y)
    -- Determine which texture to use
    local texture = nil
    if tile.type.animated then
        -- Use current animation frame from global animation
        local Tiles = require('tiles')
        if #Tiles.waterAnimation.frames > 0 then
            texture = Tiles.waterAnimation.frames[Tiles.waterAnimation.currentFrame]
        end
    else
        -- Use static texture for non-animated tiles
        texture = tile.type.texture
    end
    -- If tile has a texture, draw it masked to hex shape
    if texture then
        -- Method 1: Using stencil (cleanest for hexagons)
        love.graphics.stencil(function()
            love.graphics.polygon("fill", corners)
        end, "replace", 1)
        love.graphics.setStencilTest("equal", 1)
        -- Calculate texture scaling to fit hex
        local hexWidth = Settings.hexSize * 2
        local hexHeight = Settings.hexSize * math.sqrt(3)
        local scaleX = hexWidth / texture:getWidth()
        local scaleY = hexHeight / texture:getHeight()
        -- Draw texture centered on hex, scaled to fit
        love.graphics.draw(texture, x - hexWidth / 2, y - hexHeight / 2, 0, scaleX, scaleY)
        love.graphics.setStencilTest()
    end  
    -- Draw outline (semi-transparent)
    love.graphics.setColor(0.7, 0.7, 0.7, 0.3)  --30% opacity
    love.graphics.setLineWidth(1)
    love.graphics.polygon("line", corners)
    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

-- Love2D callbacks
function love.load()
    love.window.setMode(Settings.windowWidth, Settings.windowHeight)
    love.window.setTitle("Dwarf Island")
    local wallMeshTemplates = Tiles.createWallMeshTemplates()
    allWallMeshes = Tiles.createAllWallMeshes(wallMeshTemplates)
    World.generate()
    World.whereWalls() --- also called when a tile is removed/added
    Selector.loadCursor()
    -- Create player at origin (camera will center on them)
    local spawnX, spawnY = hexToPixel(0, 0)
    player = Player:new(spawnX, spawnY)
    player.world = World    
    -- Create camera (map boundaries can be set later when I calculate world size)
    camera = Camera:new()
    -- Create time system
    time = Time:new()
end

function love.update(dt)
    local Tiles = require('tiles')
    local mouseX, mouseY = love.mouse.getPosition()
    player:update(dt)
    Selector.updateCursor()
    Selector.update(player, {x = mouseX, y = mouseY}, camera)
    camera:update(player, Settings.windowWidth, Settings.windowHeight)
    World.UpdateTiles(dt)
    Items.updateDroppedItems(dt, World)
    Tiles.updateAnimation(dt)
    time:update(dt)
end

--- Draw walls for a specific zLayer (in "main.lua" or "world.lua")
function World.drawWalls(zLayer, allWallMeshes, yOffset)
    -- Loop through all tiles at this zLayer
    for key, tile in pairs(World.tiles) do
        if tile.z == zLayer and tile.wallInfo then
            -- This tile needs walls! Get its position
            local x, y = hexToPixel(tile.q, tile.r)
            -- Translate to tile position (with height offset)
            love.graphics.push()
            love.graphics.translate(x, y + yOffset)
            -- Draw left wall if needed
            if tile.wallInfo.left ~= "void" then
                love.graphics.draw(allWallMeshes[tile.wallInfo.left].left)
            end
            -- Draw top wall if needed
            if tile.wallInfo.top ~= "void" then
                love.graphics.draw(allWallMeshes[tile.wallInfo.top].top)
            end
            -- Draw right wall if needed
            if tile.wallInfo.right ~= "void" then
                love.graphics.draw(allWallMeshes[tile.wallInfo.right].right)
            end
            love.graphics.pop()
        end
    end
end

function love.draw()
    -- Apply camera transformation for world and player
    camera:apply()
    -- Draw layers below player
    local zLayer = player.zLayer - 2
    World.drawWalls(zLayer, allWallMeshes, Settings.tileHeightOffset)
    for key, tile in pairs(World.tiles) do
        if tile.z == zLayer then
            local x, y = hexToPixel(tile.q, tile.r)
            drawHex(tile, x, y + Settings.tileHeightOffset)
            GameDebug.drawTileHealth(tile, x, y)
            GameDebug.drawTileCoordinates(tile, x, y)
        end
    end
    zLayer = player.zLayer - 1
    World.drawWalls(zLayer, allWallMeshes, 0)
    for key, tile in pairs(World.tiles) do
        if tile.z == zLayer then
            local x, y = hexToPixel(tile.q, tile.r)
            drawHex(tile, x, y)
            GameDebug.drawTileHealth(tile, x, y)
            GameDebug.drawTileCoordinates(tile, x, y)
        end
    end
    --- draw selector if on ground
    if Selector.highlightedHex then
        if Selector.highlightedHex.z == zLayer then
            Selector.draw(player)
        end
    end
    -- need depth sorting here
    zLayer = player.zLayer
    local drawables = {}
    for key, tile in pairs(World.tiles) do
        if tile.z == zLayer then
            local x, y = hexToPixel(tile.q, tile.r)
            table.insert(drawables, {
                type = "tile",
                y = y - Settings.tileHeightOffset,
                sortY = y - Settings.tileHeightOffset + (Settings.hexSize * math.sqrt(3) / 2),
                tile = tile,
                x = x,
                drawY = y
            })
            -- add walls for this tile if they exist
            if tile.wallInfo then
                table.insert(drawables, {
                    type = "wall",
                    y = y - Settings.tileHeightOffset,
                    sortY = y - Settings.tileHeightOffset + (Settings.hexSize * math.sqrt(3) / 2),
                    tile = tile,
                    x = x
                })
            end
        end
    end
    -- add player to drawables
    table.insert(drawables, {
        type = "player",
        y = player.y + player.size - Settings.tileHeightOffset,  -- Keep for reference
        sortY = player.y + player.size - Settings.tileHeightOffset  -- Sort by feet
    })
    -- sort by Y coords
    table.sort(drawables, function(a, b) return a.sortY < b.sortY end)
    -- draw in sorted order
    for _, drawable in ipairs(drawables) do
        if drawable.type == "tile" then
            drawHex(drawable.tile, drawable.x, drawable.y)
            GameDebug.drawTileHealth(drawable.tile, drawable.x, drawable.drawY)
            GameDebug.drawTileCoordinates(drawable.tile, drawable.x, drawable.drawY)
        elseif drawable.type == "wall" then
            love.graphics.push()
            love.graphics.translate(drawable.x, drawable.y)
            if drawable.tile.wallInfo.left ~= "void" then
                love.graphics.draw(allWallMeshes[drawable.tile.wallInfo.left].left)
            end
            if drawable.tile.wallInfo.top ~= "void" then
                love.graphics.draw(allWallMeshes[drawable.tile.wallInfo.top].top)
            end
            if drawable.tile.wallInfo.right ~= "void" then
                love.graphics.draw(allWallMeshes[drawable.tile.wallInfo.right].right)
            end
            love.graphics.pop()
        elseif drawable.type == "player" then
            player:draw()
        end
    end
    -- Draw selector if on player level
    if Selector.highlightedHex then
        if Selector.highlightedHex.z == zLayer then
            Selector.draw(player)
        end
    end
    -- debug draw 
    GameDebug.drawSelectorRay(player, Selector)
    --- draw items
    Items.drawDroppedItems()
    -- Draw item animation
    player:drawItemAnimation()
    -- Unapply camera transformation
    camera:unapply()    
    -- Draw night overlay (covers entire screen)
    time:drawNightOverlay(Settings.windowWidth, Settings.windowHeight)
    -- Draw cursor
    Selector.drawCursor()
    -- Draw time display (top right)
    time:draw(Settings.windowWidth, Settings.windowHeight)
    -- Draw hotbar (bottom center, on top of everything)
    player:drawHotbar(Settings.windowWidth, Settings.windowHeight)
    -- Debug overlays
    GameDebug.drawFPS(10, 10)
    GameDebug.drawPlayerInfo(player, 10, 45)
end

-- Capture keypresses
function love.keypressed(key)
    if player then
        player:keypressed(key)
    end
end

-- Capture Mouse presses
function love.mousepressed(x, y, button)
    if player then
        player:mousepressed(button)
    end
end
--- "main.lua" ends here ---