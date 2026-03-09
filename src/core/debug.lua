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

local show_all       = true
local show_hud       = true
local show_jade      = true
local instamine      = false
local show_mob_paths = false

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

function Debug.toggle_instamine()
    instamine = not instamine
end

function Debug.instamine_on()
    return instamine
end

function Debug.toggle_mob_paths()
    show_mob_paths = not show_mob_paths
end

function Debug.mob_paths_active()
    return show_mob_paths
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

    local mode_tag = Renderer.get_mode()

    love.graphics.setColor(0.35, 0.35, 0.45)
    love.graphics.print(
        string.format("FPS:%d  |  %s  |  layer %d (%s)  |  (%d,%d)  |  Tab  PgUp/Dn  Home  O  X  H  P  F3",
            love.timer.getFPS(), mode_tag, cam_layer, depth_tag, hq, hr),
        10, 10
    )
end

-- ── Jade HUD ──────────────────────────────────────────────────────────────
-- Shows the name of the topmost tile under the hex cursor, top-center.
-- Independent of the F3 master switch — it's a gameplay UI element.

local function draw_jade(world)
    local hq, hr, hl, tile_id = Renderer.get_hover()
    if not tile_id or tile_id == 0 then return end

    local W    = love.graphics.getWidth()
    local name
    if Renderer.get_hover_occluded() then
        name = "???"
    else
        local def = TileRegistry.get(tile_id)
        name = def and def.name or "unknown"
    end

    -- Health line: reads from world.tile_damage sparse table (may not exist yet).
    local max_hp  = TileRegistry.MAX_HEALTH[tile_id] or 1
    local dmg     = 0
    if world.tile_damage and hq then
        local by_q = world.tile_damage[hq]
        local by_r = by_q and by_q[hr]
        dmg = (by_r and by_r[hl]) or 0
    end
    local max_str = max_hp == math.huge and "\xe2\x88\x9e" or tostring(math.floor(max_hp))
    local cur_str = max_hp == math.huge and "\xe2\x88\x9e" or tostring(math.max(0, math.floor(max_hp - dmg)))
    local hp_line = "HP: " .. cur_str .. " / " .. max_str

    -- Tick line: show remaining time until next state change, if any.
    local tick_line
    local next_tick = world:get_tile_tick(hq, hr, hl)
    if next_tick then
        local rem    = math.max(0, math.floor(next_tick - world.game_time))
        local h      = math.floor(rem / 60)
        local m      = rem % 60
        local label  = TileRegistry.IS_CROP[tile_id] and "Grows in" or "Dries in"
        if h > 0 then
            tick_line = string.format("%s %dh %dm", label, h, m)
        else
            tick_line = string.format("%s %dm", label, m)
        end
    end

    local font = love.graphics.getFont()
    local lh   = font:getHeight() + 2
    love.graphics.setColor(0.40, 0.85, 0.65)   -- jade green
    love.graphics.print(name,    math.floor((W - font:getWidth(name))    / 2), 10)
    love.graphics.print(hp_line, math.floor((W - font:getWidth(hp_line)) / 2), 10 + lh)
    if tick_line then
        love.graphics.print(tick_line, math.floor((W - font:getWidth(tick_line)) / 2), 10 + lh * 2)
    end
end

-- ── Active-flag sidebar ───────────────────────────────────────────────────
-- Right side, 25% from top, dark red, one line per active non-default flag.
-- Always visible regardless of F3 so you never forget what's enabled.

local function draw_active_flags()
    -- Each entry: { hotkey, label }. Only shown when the flag is active.
    local active = {}
    if instamine                    then active[#active+1] = { "X", "instamine"  } end
    if not Renderer.get_occlusion() then active[#active+1] = { "O", "occl:off"   } end
    if show_hud                     then active[#active+1] = { "H", "hud"        } end
    if show_mob_paths               then active[#active+1] = { "P", "mob:paths"  } end

    if #active == 0 then return end

    local W, H  = love.graphics.getDimensions()
    local font  = love.graphics.getFont()
    local lh    = font:getHeight() + 3
    local y     = H * 0.25

    love.graphics.setColor(0.65, 0.12, 0.12)
    for _, entry in ipairs(active) do
        local key, label = entry[1], entry[2]
        local line = key .. "  " .. label
        local tw   = font:getWidth(line)
        love.graphics.print(line, W - tw - 10, y)
        y = y + lh
    end
end

-- ── Public draw (call last in GameLoop.draw) ──────────────────────────────

function Debug.draw(world, cam, cam_layer, sea_level, mob_manager)
    if show_all then
        if show_hud then draw_hud(cam, cam_layer, sea_level) end
    end

    -- Jade HUD is independent: toggled separately with J, not masked by F3.
    if show_jade then draw_jade(world) end

    -- Mob path overlay: drawn in world space (requires camera transform).
    if show_mob_paths and mob_manager then
        cam:apply()
        mob_manager:draw_paths()
        cam:reset()
    end

    draw_active_flags()

    love.graphics.setColor(1, 1, 1)
end

return Debug
