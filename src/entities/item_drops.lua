-- src/entities/item_drops.lua
-- World-space item drop entities.  Spawned when a tile breaks; collected by
-- walking near them.  Full SAT hex-vs-hex wall collision (same as player).
--
-- Public API
--   ItemDrops.spawn(item_id, count, x, y, layer)  -- call once per drop table entry
--   ItemDrops.update(dt, world)                    -- physics, aging
--   ItemDrops.draw_drop(d)                         -- called by renderer per painter row
--   ItemDrops.get_drops()                          -- returns live list (read-only use)

local Hex          = require("src.core.hex")
local RenderCfg    = require("config.render")
local TileRegistry = require("src.world.tile_registry")
local ItemRegistry = require("src.world.item_registry")

local LAYER_HEIGHT = RenderCfg.layer_height
local SOLID        = TileRegistry.SOLID

-- ── Physics constants ──────────────────────────────────────────────────────
local GRAVITY   = 4.75   -- layers/s² downward acceleration (matches player VERT_RATE)
local FRICTION  = 6.0    -- ground drag: vx/vy *= (1 - FRICTION*dt) per frame
local MAX_DT    = 1/15   -- prevents tunnelling on lag spikes

-- ── Lifetime ──────────────────────────────────────────────────────────────
local MAX_AGE   = 60     -- seconds before auto-despawn

-- ── Spawn toss ────────────────────────────────────────────────────────────
local SPAWN_VEL = 50     -- max horizontal speed (px/s) per axis
local SPAWN_VZ  = 2.0    -- max upward launch speed (layers/s)

-- ── Hitbox (flat-top hex, smaller than player) ────────────────────────────
local ITEM_HEX_R    = 10
local ITEM_INRADIUS = ITEM_HEX_R * math.sqrt(3) * 0.5
local TILE_INRADIUS = RenderCfg.hex_size * math.sqrt(3) * 0.5
local SAT_SUM       = ITEM_INRADIUS + TILE_INRADIUS   -- ~50 px

-- ── Collection ────────────────────────────────────────────────────────────
local COLLECT_RADIUS  = 40    -- px, horizontal distance to trigger pickup
local MIN_COLLECT_AGE = 0.5   -- seconds; prevents re-collecting a just-tossed item

local HOTBAR_START   = 1
local HOTBAR_END     = 10
local BACKPACK_START = 11
local BACKPACK_END   = 154   -- 10 + 12×12

-- Tries to add (item_id, count) to player inventory using the pickup priority:
--   1. merge into existing hotbar stack
--   2. merge into existing backpack stack
--   3. first empty hotbar slot
--   4. first empty backpack slot
-- Returns the remaining count (0 = fully collected, >0 = inventory full).
local function try_add_item(player, item_id, count)
    local max_st    = ItemRegistry.MAX_STACK[item_id] or 1
    local remaining = count

    -- 1. Hotbar merge
    for i = HOTBAR_START, HOTBAR_END do
        local s = player.inventory[i]
        if s and s.item_id == item_id and s.count < max_st then
            local add = math.min(remaining, max_st - s.count)
            s.count   = s.count + add
            remaining = remaining - add
            if remaining == 0 then return 0 end
        end
    end

    -- 2. Backpack merge
    for i = BACKPACK_START, BACKPACK_END do
        local s = player.inventory[i]
        if s and s.item_id == item_id and s.count < max_st then
            local add = math.min(remaining, max_st - s.count)
            s.count   = s.count + add
            remaining = remaining - add
            if remaining == 0 then return 0 end
        end
    end

    -- 3. First empty hotbar slot
    for i = HOTBAR_START, HOTBAR_END do
        local s = player.inventory[i]
        if s and s.item_id == 0 then
            s.item_id = item_id
            s.count   = remaining
            return 0
        end
    end

    -- 4. First empty backpack slot
    for i = BACKPACK_START, BACKPACK_END do
        local s = player.inventory[i]
        if s and s.item_id == 0 then
            s.item_id = item_id
            s.count   = remaining
            return 0
        end
    end

    return remaining   -- inventory full; caller keeps the drop alive
end

-- ── Draw ──────────────────────────────────────────────────────────────────────
local DRAW_SIZE  = 24   -- rendered sprite square (px)
local SPRITE_PAD = 3    -- inset from draw square for the sprite/swatch

-- ── SAT geometry (identical to player) ───────────────────────────────────
local _S = math.sqrt(3) * 0.5
local _hex_normals = {
    { _S,  0.5 }, { 0,  1.0 }, {-_S,  0.5 },
    {-_S, -0.5 }, { 0, -1.0 }, { _S, -0.5 },
}
local _hex_nbrs = {
    { 1, 0 }, { 1,-1 }, { 0,-1 },
    {-1, 0 }, {-1, 1 }, { 0, 1 },
}

-- ── Category placeholder colours ──────────────────────────────────────────
local CAT_COLOR = {
    material = { 0.72, 0.60, 0.38 },
    organic  = { 0.30, 0.72, 0.26 },
    block    = { 0.52, 0.52, 0.58 },
    tool     = { 0.48, 0.68, 0.88 },
}
local CAT_COLOR_FALLBACK = { 0.60, 0.60, 0.60 }

-- ── Module ────────────────────────────────────────────────────────────────
local ItemDrops = {}
local drops = {}   -- list of active drop entities

-- ── Internal: SAT wall resolution ─────────────────────────────────────────
local function wall_resolve(world, x, y, wall_layer)
    local push_x, push_y = 0, 0
    local pq, pr = Hex.pixel_to_hex(x, y)

    local candidates = { {pq, pr} }
    for _, nb in ipairs(_hex_nbrs) do
        candidates[#candidates + 1] = { pq + nb[1], pr + nb[2] }
    end

    for _, hc in ipairs(candidates) do
        local fq, fr = hc[1], hc[2]
        if SOLID[world:get_tile(fq, fr, wall_layer)] then
            local hx, hy = Hex.hex_to_pixel(fq, fr)
            local rx = x - hx
            local ry = y - hy

            local max_abs_sep = -math.huge
            local best_nx, best_ny = 1, 0
            local best_sign = 1
            local colliding = true

            for _, n in ipairs(_hex_normals) do
                local sep     = rx * n[1] + ry * n[2]
                local abs_sep = math.abs(sep)
                if abs_sep > SAT_SUM then
                    colliding = false
                    break
                end
                if abs_sep > max_abs_sep then
                    max_abs_sep = abs_sep
                    best_nx, best_ny = n[1], n[2]
                    best_sign = (sep >= 0) and 1 or -1
                end
            end

            if colliding then
                local overlap = SAT_SUM - max_abs_sep
                push_x = push_x + best_sign * best_nx * overlap
                push_y = push_y + best_sign * best_ny * overlap
            end
        end
    end

    return x + push_x, y + push_y
end

-- ── Public: spawn ─────────────────────────────────────────────────────────
-- Spawns one entity per item — no stacking on the ground.
-- Call once per drop-table entry; count controls how many individual entities.
-- ovx/ovy/ovz: optional explicit velocity (px/s for x/y, layers/s for z).
--              If omitted, random scatter is used.
function ItemDrops.spawn(item_id, count, x, y, layer, ovx, ovy, ovz)
    for _ = 1, count do
        local vx = ovx ~= nil and ovx or (math.random() - 0.5) * 2 * SPAWN_VEL
        local vy = ovy ~= nil and ovy or (math.random() - 0.5) * 2 * SPAWN_VEL
        local vz = ovz ~= nil and ovz or (math.random() * SPAWN_VZ)

        local d = {
            item_id  = item_id,
            count    = 1,
            x        = x,
            y        = y,
            z        = layer + 0.0,
            layer    = layer,
            q        = 0,
            r        = 0,
            vx       = vx,
            vy       = vy,
            vz       = vz,
            grounded = false,
            age      = 0,
        }
        d.q, d.r = Hex.pixel_to_hex(x, y)
        drops[#drops + 1] = d
    end
end

-- ── Public: update ────────────────────────────────────────────────────────
function ItemDrops.update(dt, world, player)
    dt = math.min(dt, MAX_DT)

    local i = 1
    while i <= #drops do
        local d = drops[i]
        d.age = d.age + dt

        if d.age >= MAX_AGE then
            -- Swap-remove (order unimportant).
            drops[i] = drops[#drops]
            drops[#drops] = nil
        else
            -- ── Vertical physics ──────────────────────────────────────────
            if d.grounded then
                -- Check floor still solid each frame (tile could be mined away).
                local fq, fr = Hex.pixel_to_hex(d.x, d.y)
                if not SOLID[world:get_tile(fq, fr, math.floor(d.z))] then
                    d.grounded = false
                    d.vz = 0
                end
            else
                -- Airborne: apply gravity acceleration, then move.
                d.vz = d.vz - GRAVITY * dt
                local z_prev = d.z
                d.z = d.z + d.vz * dt

                -- Floor check only when moving downward through a layer boundary.
                if d.vz < 0 and math.floor(d.z) < math.floor(z_prev) then
                    local fl = math.floor(z_prev)
                    local fq, fr = Hex.pixel_to_hex(d.x, d.y)
                    if SOLID[world:get_tile(fq, fr, fl)] then
                        d.z        = fl + 0.0
                        d.vz       = 0
                        d.grounded = true
                        -- vx/vy kept: friction on the ground will bleed them off
                    end
                end
            end

            -- ── Horizontal movement + friction ────────────────────────────
            if d.grounded then
                local f = math.max(0, 1 - FRICTION * dt)
                d.vx = d.vx * f
                d.vy = d.vy * f
            end

            local wall_layer = math.floor(d.z) + 1
            local nx = d.x + d.vx * dt
            local ny = d.y + d.vy * dt
            d.x, d.y = wall_resolve(world, nx, ny, wall_layer)

            d.q, d.r = Hex.pixel_to_hex(d.x, d.y)
            d.layer  = math.floor(d.z)

            -- ── Proximity pickup ──────────────────────────────────────────
            local collected = false
            if player and d.age >= MIN_COLLECT_AGE and d.layer == player.layer then
                local dx2 = (d.x - player.x) ^ 2 + (d.y - player.y) ^ 2
                if dx2 <= COLLECT_RADIUS * COLLECT_RADIUS then
                    if try_add_item(player, d.item_id, d.count) == 0 then
                        drops[i] = drops[#drops]
                        drops[#drops] = nil
                        collected = true
                    end
                end
            end

            if not collected then i = i + 1 end
        end
    end
end

-- ── Public: draw a single drop (called by renderer per painter row) ────────
function ItemDrops.draw_drop(d)
    local img    = ItemRegistry.SPRITE[d.item_id]
    local draw_x = math.floor(d.x - DRAW_SIZE * 0.5)
    local draw_y = math.floor(d.y - d.z * LAYER_HEIGHT - DRAW_SIZE)
    local inner  = DRAW_SIZE - SPRITE_PAD * 2

    if img then
        local iw, ih = img:getDimensions()
        local scale  = math.min(inner / iw, inner / ih)
        local dw, dh = iw * scale, ih * scale
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img,
            math.floor(draw_x + (DRAW_SIZE - dw) * 0.5),
            math.floor(draw_y + (DRAW_SIZE - dh) * 0.5),
            0, scale, scale)
    else
        local def = ItemRegistry.get(d.item_id)
        local col = (def and CAT_COLOR[def.category]) or CAT_COLOR_FALLBACK
        love.graphics.setColor(col[1], col[2], col[3])
        love.graphics.rectangle("fill",
            draw_x + SPRITE_PAD, draw_y + SPRITE_PAD,
            inner, inner, 2, 2)
    end

    love.graphics.setColor(1, 1, 1)
end

-- ── Public: accessor ──────────────────────────────────────────────────────
function ItemDrops.get_drops()
    return drops
end

return ItemDrops
