-- src/core/gameloop.lua — Core game loop

local Debug         = require("src.core.debug")
local Hex           = require("src.core.hex")
local LoadingScreen = require("src.core.loading_screen")
local TileRegistry  = require("src.world.tile_registry")
local World         = require("src.world.world")
local WorldgenCfg   = require("config.worldgen")
local RenderCfg     = require("config.render")
local Camera        = require("src.render.camera")
local Renderer      = require("src.render.renderer")

local GameLoop = {}

local W, H
local world       -- the active World instance
local camera      -- Camera instance
local cam_layer   -- world layer the camera is focused on
local cam_q, cam_r
local _saved_zoom, _saved_cam_x, _saved_cam_y  -- restored when overview exits

function GameLoop.load()
    W, H = love.graphics.getDimensions()
    love.graphics.setDefaultFilter("nearest", "nearest")
    math.randomseed(os.time())

    Hex.SIZE = RenderCfg.hex_size

    TileRegistry.load()

    -- Show loading screen before blocking worldgen.
    LoadingScreen.show()

    local t0  = love.timer.getTime()
    world     = World.new()
    cam_layer = WorldgenCfg.sea_level
    cam_q     = 0
    cam_r     = 0

    -- Camera world-pixel position: centre the view on hex (0,0) at sea level.
    -- Tiles at layer L render at world-pixel y = hex_py - L * layer_height.
    -- So to see hex (0,0) at sea level: camera.y = 0 - sea_level * layer_height.
    local px, py = Hex.hex_to_pixel(cam_q, cam_r)
    camera = Camera.new(px, py - cam_layer * RenderCfg.layer_height)

    -- Warm the neighbourhood immediately so the first frame has no load stutter.
    world:preload_near(cam_q, cam_r, cam_layer)

    print(string.format("[Startup] worldgen + preload: %.2f s", love.timer.getTime() - t0))
end

function GameLoop.update(dt)
    world:update(dt)

    -- ── Camera panning (WASD / arrow keys) ───────────────────────────────
    local spd = RenderCfg.cam_speed / camera.zoom   -- faster when zoomed out
    if love.keyboard.isDown("w", "up")    then camera.y = camera.y - spd * dt end
    if love.keyboard.isDown("s", "down")  then camera.y = camera.y + spd * dt end
    if love.keyboard.isDown("a", "left")  then camera.x = camera.x - spd * dt end
    if love.keyboard.isDown("d", "right") then camera.x = camera.x + spd * dt end

    -- Derive cam_q, cam_r from current camera position for chunk preloading.
    -- Reverse: hex_py = camera.y + cam_layer * layer_height
    cam_q, cam_r = Hex.pixel_to_hex(camera.x,
                       camera.y + cam_layer * RenderCfg.layer_height)

    world:preload_near(cam_q, cam_r, cam_layer)
end

function GameLoop.draw()
    love.graphics.clear(0.06, 0.06, 0.10)

    Renderer.draw(world, camera, cam_layer)

    Debug.draw(world, camera, cam_layer, WorldgenCfg.sea_level)
end

function GameLoop.keypressed(key, scancode, isrepeat)
    -- Render mode
    if key == "tab" then Renderer.toggle_mode()      end
    if key == "o"   then Renderer.toggle_occlusion() end

    -- Debug overlays
    if key == "f3" then Debug.toggle()      end
    if key == "f1" then Debug.toggle_hud()  end
    if key == "j"  then Debug.toggle_jade() end

    -- World overview (M): zoom to fit entire world, blue ocean plane, sampled land.
    -- Only works in overworld mode. Press M again to restore camera position.
    if key == "m" and Renderer.get_mode() == "overworld" then
        if not Renderer.get_overview() then
            _saved_zoom  = camera.zoom
            _saved_cam_x = camera.x
            _saved_cam_y = camera.y
            local R     = WorldgenCfg.world_radius
            local pw    = 3 * Hex.SIZE * R
            local ph    = 2 * math.sqrt(3) * Hex.SIZE * R
            camera.zoom = math.min(W / pw, H / ph) * 0.85
            camera.x    = 0
            camera.y    = -WorldgenCfg.sea_level * RenderCfg.layer_height
        else
            camera.zoom = _saved_zoom
            camera.x    = _saved_cam_x
            camera.y    = _saved_cam_y
        end
        Renderer.toggle_overview()
    end

    -- Zoom  (= / + zooms in,  - zooms out)
    if key == "=" or key == "+" then
        camera.zoom = math.min(camera.zoom * 1.25, 4.0)
    end
    if key == "-" then
        camera.zoom = math.max(camera.zoom / 1.25, 0.25)
    end

    -- Layer shift  ([ = deeper,  ] = higher;  PageUp/PageDown = same;  Home = reset)
    -- Hold Shift for ×10 jump.
    local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
    local layer_step = shift and 20 or 1
    if key == "]" or key == "pageup" then
        local delta = math.min(layer_step, WorldgenCfg.world_depth - 1 - cam_layer)
        cam_layer = cam_layer + delta
        camera.y  = camera.y - delta * RenderCfg.layer_height
    end
    if key == "[" or key == "pagedown" then
        local delta = math.min(layer_step, cam_layer)
        cam_layer = cam_layer - delta
        camera.y  = camera.y + delta * RenderCfg.layer_height
    end
    -- Home: snap back to sea level (swap for player layer once a player exists)
    if key == "home" then
        local target = WorldgenCfg.sea_level
        local delta  = target - cam_layer
        cam_layer    = target
        camera.y     = camera.y - delta * RenderCfg.layer_height
    end
end

function GameLoop.keyreleased(key, scancode)  end
function GameLoop.mousepressed(x, y, button, istouch, presses)  end
function GameLoop.mousereleased(x, y, button, istouch, presses) end
function GameLoop.mousemoved(x, y, dx, dy, istouch)             end

function GameLoop.wheelmoved(x, y)
    -- Scroll up = zoom in, scroll down = zoom out.
    if y > 0 then camera.zoom = math.min(camera.zoom * 1.1, 4.0)  end
    if y < 0 then camera.zoom = math.max(camera.zoom / 1.1, 0.25) end
end

function GameLoop.resize(w, h)
    W, H = w, h
end

return GameLoop
