--- "camera.lua" begins here ---
local Settings = require('settings')

local Camera = {}

function Camera:new(mapWidth, mapHeight)
    local obj = {
        x = 0,
        y = 0,
        mapWidth = mapWidth or 0,
        mapHeight = mapHeight or 0
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Camera:update(target, windowWidth, windowHeight)
    -- Center camera on target
    self.x = -target.x + windowWidth / 2 - Settings.hexSize / 2
    self.y = -target.y + windowHeight / 2 - Settings.hexSize / 2
    -- Limit scrolling (keep camera within map bounds)
    -- Only apply limits if map dimensions are set (> 0)
    if self.mapWidth > 0 and self.mapHeight > 0 then
        self.x = math.min(0, self.x)
        self.y = math.min(0, self.y)
        self.x = math.max(-(self.mapWidth - windowWidth), self.x)
        self.y = math.max(-(self.mapHeight - windowHeight), self.y)
    end
end

function Camera:apply()
    -- This is called before drawing - it translates the coordinate system
    love.graphics.push()
    love.graphics.translate(self.x, self.y)
end

function Camera:unapply()
    -- This is called after drawing to restore normal coordinates
    love.graphics.pop()
end

return Camera
--- "camera.lua" ends here ---