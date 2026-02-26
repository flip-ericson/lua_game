-- src/core/debug.lua
-- Debug overlays. Call Debug.draw(world, cam, cam_layer, sea_level) at end of draw pass.
-- Add new helpers here — keep them out of gameplay code.
--   F3  → toggle all debug overlays (master switch)
--   F1  → toggle HUD (FPS, layer, hover coords)
--   J   → toggle jade HUD (tile name under cursor, top-center)

local Hex          = require("src.core.hex")
local RenderCfg    = require("config.render")
local WorldgenCfg  = require("config.worldgen")
local Renderer     = require("src.render.renderer")
local TileRegistry = require("src.world.tile_registry")
local Worldgen     = require("src.world.worldgen")

local LAYER_HEIGHT = RenderCfg.layer_height
local SEA_LEVEL    = WorldgenCfg.sea_level

local Debug = {}

local show_all  = true
local show_hud  = true
local show_jade = false

-- ── Toggles ───────────────────────────────────────────────────────────────

function Debug.toggle()
    show_all = not show_all
end

function Debug.toggle_hud()
    show_hud = not show_hud
end

function Debug.toggle_jade()
    show_jade = not show_jade
end

-- ── FPS / HUD ─────────────────────────────────────────────────────────────

local function draw_hud(cam, cam_layer, sea_level)
    local W, H = love.graphics.getDimensions()

    local mx, my = love.mouse.getPosition()
    local wx, wy = cam:screen_to_world(mx, my)
    local hq, hr = Hex.pixel_to_hex(wx, wy + cam_layer * LAYER_HEIGHT)

    local depth     = sea_level - cam_layer
    local depth_tag
    if     depth > 0 then depth_tag = depth    .. "↓"
    elseif depth < 0 then depth_tag = (-depth) .. "↑"
    else                  depth_tag = "sea"
    end

    local mode_tag  = Renderer.get_mode()
    local occl_tag  = Renderer.get_occlusion() and "occl:on" or "occl:OFF"

    love.graphics.setColor(0.35, 0.35, 0.45)
    love.graphics.print(
        string.format("FPS:%d  |  %s  |  layer %d (%s)  |  (%d,%d)  |  %s  |  Tab  PgUp/Dn  Home  O  F1  F3",
            love.timer.getFPS(), mode_tag, cam_layer, depth_tag, hq, hr, occl_tag),
        10, H - 22
    )
end

-- ── Jade HUD ──────────────────────────────────────────────────────────────
-- Shows the name of the topmost tile under the hex cursor, top-center.
-- Independent of the F3 master switch — it's a gameplay UI element.

local function draw_jade(world, cam, cam_layer)
    local W = love.graphics.getWidth()

    local mx, my = love.mouse.getPosition()
    local wx, wy = cam:screen_to_world(mx, my)

    local tile_id
    if Renderer.get_mode() == "overworld" then
        -- Mirror the overworld hover convergence: 3 iterations to find terrain surface.
        local hover_dl = SEA_LEVEL
        local hq, hr
        for _ = 1, 3 do
            hq, hr    = Hex.pixel_to_hex(wx, wy + hover_dl * LAYER_HEIGHT)
            local hsl = Worldgen.surface_layer(hq, hr)
            hover_dl  = hsl >= SEA_LEVEL and hsl or SEA_LEVEL
        end
        -- Scan upward for topmost non-air tile (same as the renderer top-face pass).
        tile_id = world:get_tile(hq, hr, hover_dl) or 0
        for k = 1, 12 do
            local id = world:get_tile(hq, hr, hover_dl + k) or 0
            if id == 0 then break end
            tile_id = id
        end
    else
        -- Underground: tile at the exact cursor layer.
        local hq, hr = Hex.pixel_to_hex(wx, wy + cam_layer * LAYER_HEIGHT)
        tile_id = world:get_tile(hq, hr, cam_layer) or 0
    end

    local name
    if tile_id ~= 0 then
        local def = TileRegistry.get(tile_id)
        name = def and def.name or "unknown"
    else
        name = "air"
    end

    local font   = love.graphics.getFont()
    local text_w = font:getWidth(name)
    love.graphics.setColor(0.40, 0.85, 0.65)   -- jade green
    love.graphics.print(name, math.floor((W - text_w) / 2), 10)
end

-- ── Public draw (call last in GameLoop.draw) ──────────────────────────────

function Debug.draw(world, cam, cam_layer, sea_level)
    if show_all then
        if show_hud then draw_hud(cam, cam_layer, sea_level) end
    end

    -- Jade HUD is independent: toggled separately with J, not masked by F3.
    if show_jade then draw_jade(world, cam, cam_layer) end

    love.graphics.setColor(1, 1, 1)
end

return Debug
