--- "gamedebug.lua" begins here ---
-- Debug Module
-- Handles all debug drawing and information display
local Settings = require('settings')

local GameDebug = {}

-- Debug flags (toggle these to show/hide different debug info)
GameDebug.showTileHealth = false
GameDebug.showSelectorRay = false
GameDebug.showPlayerInfo = false
GameDebug.showFPS = false
GameDebug.showTileCoordinates = false
GameDebug.noClip = false

-- Draw tile health overlay
function GameDebug.drawTileHealth(tile, x, y)
    if not GameDebug.showTileHealth then return end
    if not tile.type.health then return end
    
    -- Draw semi-transparent background for text
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 20, y - 10, 40, 20, 3, 3)
    
    -- Draw health text in white
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(
        tostring(tile.health),
        x - 20,
        y - 8,
        40,
        "center"
    )
    
    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw tile coordinates
function GameDebug.drawTileCoordinates(tile, x, y)
    if not GameDebug.showTileCoordinates then return end
    
    local coordText = string.format("(%d,%d)", tile.q, tile.r)
    
    -- Draw semi-transparent background
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 25, y + 10, 50, 20, 3, 3)
    
    -- Draw coordinates in cyan
    love.graphics.setColor(0, 1, 1, 1)
    love.graphics.printf(
        coordText,
        x - 25,
        y + 12,
        50,
        "center"
    )
    
    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw selector ray (from player to reach point)
function GameDebug.drawSelectorRay(player, Selector)
    if not GameDebug.showSelectorRay then return end
    if not Selector.highlightedHex then return end
    
    local playerCenterX = player.x + player.size / 2
    local playerCenterY = player.y + player.size / 2
    local hex = Selector.highlightedHex
    
    -- Draw ray line
    love.graphics.setColor(1, 0, 0, 0.5)  -- Red, 50% opacity
    love.graphics.setLineWidth(2)
    love.graphics.line(playerCenterX, playerCenterY, hex.reachPointX, hex.reachPointY)
    
    -- Draw reach point
    love.graphics.setColor(1, 0, 0, 1)  -- Red
    love.graphics.circle("fill", hex.reachPointX, hex.reachPointY, 4)
    
    -- Reset
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- Draw player info (position, state, etc.) - call in screen space
function GameDebug.drawPlayerInfo(player, x, y)
    if not GameDebug.showPlayerInfo then return end
    
    local info = {
        string.format("Pos: (%.1f, %.1f)", player.x, player.y),
        string.format("State: %s", player.state),
        string.format("Direction: %s", player.direction),
        string.format("Swimming: %s", tostring(player.isInWater)),
        string.format("Selected Slot: %d", player.hotbarSelected),
        string.format("NoClip: %s", tostring(GameDebug.noClip))
    }
    
    -- Draw background
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x, y, 200, #info * 20 + 10, 5, 5)
    
    -- Draw text
    love.graphics.setColor(1, 1, 1, 1)
    for i, line in ipairs(info) do
        love.graphics.print(line, x + 5, y + 5 + (i - 1) * 20)
    end
    
    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw FPS counter - call in screen space
function GameDebug.drawFPS(x, y)
    if not GameDebug.showFPS then return end
    
    local fps = love.timer.getFPS()
    
    -- Draw background
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x, y, 80, 25, 3, 3)
    
    -- Draw FPS text
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("FPS: %d", fps), x + 5, y + 5)
    
    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

-- Toggle a specific debug flag
function GameDebug.toggle(flagName)
    if GameDebug[flagName] ~= nil then
        GameDebug[flagName] = not GameDebug[flagName]
        print(string.format("Debug.%s = %s", flagName, tostring(GameDebug[flagName])))
    else
        print(string.format("Unknown debug flag: %s", flagName))
    end
end

-- Toggle all debug features on/off
function GameDebug.toggleAll(state)
    GameDebug.showTileHealth = state
    GameDebug.showSelectorRay = state
    GameDebug.showPlayerInfo = state
    GameDebug.showFPS = state
    GameDebug.showTileCoordinates = state
    print(string.format("All debug features: %s", state and "ON" or "OFF"))
end

return GameDebug
--- "gamedebug.lua" ends here ---
