--- "selector.lua" begins here ---
local Settings = require('settings')
local Collision = require('collision')
local World = require('world')

--- SELECTOR MODULE ---
local Selector = {}

-- Cursor properties
Selector.cursorImage = nil
Selector.cursorX = 0
Selector.cursorY = 0
-- Current highlighted hex (nil if none)
Selector.highlightedHex = nil  -- {q, r, x, y}

function Selector.loadCursor()
    -- Load cursor image
    Selector.cursorImage = love.graphics.newImage("images/reticule.png")
    -- Hide the default system cursor
    love.mouse.setVisible(false)
end

function Selector.updateCursor()
    -- Update cursor position to mouse position
    Selector.cursorX, Selector.cursorY = love.mouse.getPosition()
end

function Selector.drawCursor()
    if Selector.cursorImage then
        -- Draw cursor centered on mouse position
        local width = Selector.cursorImage:getWidth()
        local height = Selector.cursorImage:getHeight()
        love.graphics.draw(
            Selector.cursorImage,
            Selector.cursorX - width / 2,
            Selector.cursorY - height / 2
        )
    end
end

function Selector.update(player, cursor, camera)
    -- Get player center in world space
    local playerCenterX = player.x + player.size / 2
    local playerCenterY = player.y + player.size / 2
    -- Convert cursor screen position to world space
    local cursorWorldX = cursor.x - camera.x
    local cursorWorldY = cursor.y - camera.y
    -- Step 1: Calculate direction vector from player to cursor
    local dx = cursorWorldX - playerCenterX
    local dy = cursorWorldY - playerCenterY
    -- Calculate distance to cursor
    local distToCursor = math.sqrt(dx * dx + dy * dy)
    -- Step 2: Find point B (end of tool reach)
    local reachPointX, reachPointY
    if distToCursor > 0 then
        -- Normalize direction vector
        local dirX = dx / distToCursor
        local dirY = dy / distToCursor
        -- Calculate point B at tool reach; use MINIMUM of cursor distance/tool reach
        local reachDistance = math.min(distToCursor, player.toolReach)
        reachPointX = playerCenterX + dirX * reachDistance
        reachPointY = playerCenterY + dirY * reachDistance
    else
        reachPointX = playerCenterX
        reachPointY = playerCenterY
    end 
    -- Step 3: Convert reach point to hex coordinates
    local hexQ, hexR = Collision.pixelToAxial(reachPointX, reachPointY)
    -- Convert back to pixel to get hex center
    local hexCenterX, hexCenterY = Collision.axialToPixel(hexQ, hexR)
    -- Step 4: Find the topmost visible tile
    local playerZlevel = player.zLayer
    local selectedZlevel = nil
    local selectedTile = nil
    -- check top layer first
    selectedTile = World.getTile(hexQ, hexR, playerZlevel)
    if selectedTile then
        selectedZlevel = playerZlevel
    else
        local groundLevel = playerZlevel - 1
        selectedTile = World.getTile(hexQ, hexR, groundLevel)
        if selectedTile then
            selectedZlevel = groundLevel
        end
    end
    if selectedTile and selectedZlevel then
    -- Store selected hex info if it exists
        Selector.highlightedHex = {
            q = hexQ,
            r = hexR,
            x = hexCenterX,
            y = hexCenterY,
            z = selectedZlevel,
            reachPointX = reachPointX,
            reachPointY = reachPointY
        }
    else
        Selector.highlightedHex = nil
    end
end

function Selector.draw(player)
    if not Selector.highlightedHex then
        return
    end
    local yOffset = 0
    local hex = Selector.highlightedHex
    if hex.z == player.zLayer then
        yOffset = Settings.tileHeightOffset
    end
    -- Generate hex corner points (flat-top orientation)
    local size = Settings.hexSize
    local corners = {}
    for i = 0, 5 do
        local angle = math.pi / 180 * (60 * i)
        table.insert(corners, hex.x + size * math.cos(angle))
        table.insert(corners, (hex.y - yOffset) + size * math.sin(angle))
    end
    -- Draw highlight outline (bright color, thicker line)
    love.graphics.setColor(1, 1, 1, 0.5)  -- 50% opacity
    love.graphics.setLineWidth(3)
    love.graphics.polygon("line", corners)
    -- Optional: Draw semi-transparent fill
    love.graphics.setColor(1, 1, 1, 0.2)  -- 20% opacity
    love.graphics.polygon("fill", corners)
    -- Reset graphics state
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

return Selector
--- "selector.lua" ends here ---