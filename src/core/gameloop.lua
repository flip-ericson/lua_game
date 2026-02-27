-- src/core/gameloop.lua — Core game loop

local Debug         = require("src.core.debug")
local Hex           = require("src.core.hex")
local LoadingScreen = require("src.core.loading_screen")
local TileRegistry  = require("src.world.tile_registry")
local World         = require("src.world.world")
local Worldgen      = require("src.world.worldgen")
local WorldgenCfg   = require("config.worldgen")
local RenderCfg     = require("config.render")
local Camera        = require("src.render.camera")
local Renderer      = require("src.render.renderer")
local Player        = require("src.entities.player")

local GameLoop = {}

local W, H
local world       -- the active World instance
local player      -- the player entity
local camera      -- Camera instance
local cam_layer   -- world layer the camera is focused on
local cam_q, cam_r
local _saved_zoom   -- zoom level saved when entering overview (M key)

local CAM_LERP = 8  -- camera follow speed (higher = snappier; 8 = smooth but responsive)

-- Search for a valid spawn point: a grass tile with air directly above.
-- Picks random hexes within the world boundary and retries up to max_attempts.
-- Returns (q, r, layer) of the spawn tile itself (player z = that layer).
local function find_spawn(world)
    local R     = WorldgenCfg.world_radius
    local sea   = WorldgenCfg.sea_level
    local grass = TileRegistry.id("grass")

    for _ = 1, 200 do
        -- Uniform random hex inside the hexagonal world boundary.
        local q, r
        repeat
            q = math.random(-R, R)
            r = math.random(-R, R)
        until math.max(math.abs(q), math.abs(q + r), math.abs(r)) <= R

        local sl = Worldgen.surface_layer(q, r)

        -- Surface must be above sea, a grass tile, with nothing on top of it.
        if sl >= sea
            and world:get_tile(q, r, sl)     == grass   -- solid grass, not sand/stone
            and world:get_tile(q, r, sl + 1) == 0       -- air above (no tree trunk etc.)
        then
            return q, r, sl
        end
    end

    -- Fallback: world origin at sea level. Logs a warning so it's visible.
    print("[Spawn] WARNING: no valid spawn found in 200 attempts — falling back to origin")
    return 0, 0, sea
end

function GameLoop.load()
    W, H = love.graphics.getDimensions()
    love.graphics.setDefaultFilter("nearest", "nearest")
    math.randomseed(os.time())

    Hex.SIZE = RenderCfg.hex_size

    TileRegistry.load()
    Player.load()

    -- Show loading screen before blocking worldgen.
    LoadingScreen.show()

    local t0  = love.timer.getTime()
    world     = World.new()

    -- Debug preset: generate every chunk now so find_spawn can query any tile freely.
    if WorldgenCfg.preload_all then
        world:preload_all()
    end

    -- Find a valid spawn: random grass tile, air above, above sea level.
    local sq, sr, sl = find_spawn(world)
    cam_q, cam_r     = sq, sr
    cam_layer        = sl

    local px, py = Hex.hex_to_pixel(sq, sr)
    camera = Camera.new(px, py - sl * RenderCfg.layer_height)
    player = Player.new(px, py, sl)

    -- Lazy presets: prime the neighbourhood around the chosen spawn point.
    if not WorldgenCfg.preload_all then
        world:preload_near(cam_q, cam_r, cam_layer)
    end

    print(string.format("[Startup] worldgen + spawn + preload: %.2f s", love.timer.getTime() - t0))
end

function GameLoop.update(dt)
    world:update(dt)

    -- ── Player movement (WASD) + physics (gravity / floor) ───────────────
    player:update(dt, world)

    -- ── Camera lerp-follow ────────────────────────────────────────────────
    -- Framerate-independent lerp: moves CAM_LERP × remaining distance per second.
    -- Skip in overview so the M-key flyout isn't overridden every frame.
    if not Renderer.get_overview() then
        local tx = player.x
        local ty = player.y - player.layer * RenderCfg.layer_height
        local t  = math.min(CAM_LERP * dt, 1)
        camera.x = camera.x + (tx - camera.x) * t
        camera.y = camera.y + (ty - camera.y) * t
    end

    cam_q, cam_r = player.q, player.r
    cam_layer    = player.layer

    world:preload_near(cam_q, cam_r, cam_layer)
end

function GameLoop.draw()
    love.graphics.clear(0.06, 0.06, 0.10)

    Renderer.draw(world, camera, cam_layer, player)

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
            _saved_zoom = camera.zoom
            local R  = WorldgenCfg.world_radius
            local pw = 3 * Hex.SIZE * R
            local ph = 2 * math.sqrt(3) * Hex.SIZE * R
            camera.zoom = math.min(W / pw, H / ph) * 0.85
            camera.x    = 0
            camera.y    = -WorldgenCfg.sea_level * RenderCfg.layer_height
        else
            camera.zoom = _saved_zoom
            -- camera.x/y snaps back to player on the next update tick
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
    -- Moves player.layer; cam_layer + camera.y follow via update() snap.
    -- Hold Shift for ×20 jump.
    local shift      = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
    local layer_step = shift and 20 or 1
    if key == "]" or key == "pageup" then
        player.layer = math.min(player.layer + layer_step, WorldgenCfg.world_depth - 1)
    end
    if key == "[" or key == "pagedown" then
        player.layer = math.max(player.layer - layer_step, 0)
    end
    if key == "home" then
        player.layer = WorldgenCfg.sea_level
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
