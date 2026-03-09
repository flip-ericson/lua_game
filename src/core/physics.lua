-- src/core/physics.lua
-- Shared collision helpers used by the player and all mob entities.
--
-- foot_grounded  — 5-point floor-presence test.
-- wall_resolve   — SAT hex-vs-hex push-out (flat-top grid, same-orientation hexes).

local Hex          = require("src.core.hex")
local RenderCfg    = require("config.render")
local TileRegistry = require("src.world.tile_registry")

local SOLID        = TileRegistry.SOLID
local TILE_INRADIUS = RenderCfg.hex_size * math.sqrt(3) * 0.5

local Physics = {}

-- ── Floor detection ────────────────────────────────────────────────────────
-- 5 sample points around the entity centre; grounded if ANY has a solid tile
-- at floor_layer (the layer the entity's feet rest on).
local FOOT_R = 11   -- px; radius of foot-detection circle

local _foot = {
    {  0,       0 },
    {  FOOT_R,  0 }, { -FOOT_R,  0 },
    {  0,  FOOT_R }, {  0, -FOOT_R },
}

function Physics.foot_grounded(world, x, y, floor_layer)
    for _, off in ipairs(_foot) do
        local fq, fr = Hex.pixel_to_hex(x + off[1], y + off[2])
        if SOLID[world:get_tile(fq, fr, floor_layer)] then
            return true
        end
    end
    return false
end

-- ── SAT hex-vs-hex wall collision ─────────────────────────────────────────
-- Both the entity and every wall tile are flat-top regular hexagons with the
-- same orientation → they share exactly 6 face normals → SAT needs only 6
-- axis tests per wall hex.
--
-- entity_inradius: inradius of the entity's hex hitbox (px).
-- The tile inradius is constant (TILE_INRADIUS above).
local _S = math.sqrt(3) * 0.5

local _hex_normals = {
    { _S,  0.5 },   -- lower-right
    { 0,   1.0 },   -- bottom
    {-_S,  0.5 },   -- lower-left
    {-_S, -0.5 },   -- upper-left
    { 0,  -1.0 },   -- top
    { _S, -0.5 },   -- upper-right
}

local _hex_nbrs = {
    { 1,  0}, { 1, -1}, { 0, -1},
    {-1,  0}, {-1,  1}, { 0,  1},
}

function Physics.wall_resolve(world, x, y, wall_layer, entity_inradius)
    local sat_sum  = entity_inradius + TILE_INRADIUS
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
                if abs_sep > sat_sum then
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
                local overlap = sat_sum - max_abs_sep
                push_x = push_x + best_sign * best_nx * overlap
                push_y = push_y + best_sign * best_ny * overlap
            end
        end
    end

    return x + push_x, y + push_y
end

return Physics
