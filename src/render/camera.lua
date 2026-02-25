-- src/render/camera.lua
-- 2D camera in world-pixel space.
--
-- Usage:
--   camera:apply()          push love.graphics transform (draw world geometry after this)
--   camera:reset()          pop the transform
--   camera:world_to_screen  convert a world-pixel point to a screen-pixel point
--   camera:screen_to_world  convert a screen-pixel point to a world-pixel point
--
-- Phase 1.5: camera is moved directly by the game loop (WASD).
-- Phase 3:   replace direct movement with lerp-follow of the player entity.

local Camera = {}
Camera.__index = Camera

function Camera.new(x, y)
    return setmetatable({
        x    = x or 0,   -- world-pixel position shown at screen centre
        y    = y or 0,
        zoom = 1.0,
    }, Camera)
end

-- ── Transform ─────────────────────────────────────────────────────────────

-- Push the camera transform onto the love.graphics stack.
-- Everything drawn after this is in world-pixel space.
function Camera:apply()
    local W, H = love.graphics.getDimensions()
    love.graphics.push()
    love.graphics.translate(W / 2, H / 2)
    love.graphics.scale(self.zoom, self.zoom)
    love.graphics.translate(-self.x, -self.y)
end

-- Pop the camera transform.
function Camera:reset()
    love.graphics.pop()
end

-- ── Coordinate conversion ─────────────────────────────────────────────────

-- World-pixel → screen-pixel.
function Camera:world_to_screen(wx, wy)
    local W, H = love.graphics.getDimensions()
    return (wx - self.x) * self.zoom + W / 2,
           (wy - self.y) * self.zoom + H / 2
end

-- Screen-pixel → world-pixel.
function Camera:screen_to_world(sx, sy)
    local W, H = love.graphics.getDimensions()
    return (sx - W / 2) / self.zoom + self.x,
           (sy - H / 2) / self.zoom + self.y
end

return Camera
