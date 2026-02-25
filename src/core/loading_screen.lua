-- src/core/loading_screen.lua
-- Displays a static loading screen during blocking worldgen.
-- Call LoadingScreen.show() before any blocking work in GameLoop.load().
--
-- Polish-phase TODOs (do not implement now):
--   - Animated progress bar driven by worldgen stage callbacks
--   - Cheeky rotating loading tips
--   - Seed display
--   - Estimated time remaining

local LoadingScreen = {}

local IMAGE_PATH = "assests/ui/loading_screen.png"

function LoadingScreen.show()
    local W, H = love.graphics.getDimensions()

    love.graphics.clear(0, 0, 0)

    if love.filesystem.getInfo(IMAGE_PATH) then
        local img    = love.graphics.newImage(IMAGE_PATH)
        local scale_x = W / img:getWidth()
        local scale_y = H / img:getHeight()
        love.graphics.draw(img, 0, 0, 0, scale_x, scale_y)
    else
        -- Fallback: black screen with text if PNG not yet in place.
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Generating world...", 0, H / 2 - 10, W, "center")
        love.graphics.setColor(1, 1, 1)
    end

    -- Force this frame to the screen before blocking worldgen begins.
    love.graphics.present()
end

return LoadingScreen
