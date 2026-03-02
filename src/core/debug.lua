-- src/core/debug.lua
-- Debug overlays. Call Debug.draw(world, cam, cam_layer, sea_level) at end of draw pass.
-- Add new helpers here — keep them out of gameplay code.
--   F3  → toggle all debug overlays (master switch)
--   F1  → toggle HUD (FPS, layer, hover coords)
--   J   → toggle jade HUD (tile name under cursor, top-center)

local Hex          = require("src.core.hex")
local RenderCfg    = require("config.render")
local Renderer     = require("src.render.renderer")
local TileRegistry = require("src.world.tile_registry")

local LAYER_HEIGHT = RenderCfg.layer_height

local Debug = {}

local show_all  = true
local show_hud  = true
local show_jade = true

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

local function draw_jade()
    local _, _, _, tile_id = Renderer.get_hover()
    if not tile_id or tile_id == 0 then return end

    local W    = love.graphics.getWidth()
    local name
    if Renderer.get_hover_occluded() then
        name = "???"
    else
        local def = TileRegistry.get(tile_id)
        name = def and def.name or "unknown"
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
    if show_jade then draw_jade() end

    love.graphics.setColor(1, 1, 1)
end

return Debug
