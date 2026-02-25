-- src/render/renderer.lua
-- Two render modes, toggled with Tab:
--
--   "overworld"   (default) — topmost tile per hex column, variable cliff faces.
--                             Use this to read island shape and surface terrain.
--   "underground"           — fixed layer slice at center_layer and below.
--                             center_layer = player's inhabited layer (walls).
--                             center_layer-1 = floor (top face visible).
--                             center_layer+1 and above = never rendered.
--                             Use this for mining / subsurface exploration.
--
-- OVERWORLD GEOMETRY
--   Each (q,r) column draws its surface tile at world-pixel y = hex_py - sl*LH
--   where sl = Worldgen.surface_layer(q,r).
--   Cliff faces are quads hanging from the 3 south-facing hex edges, with height
--   proportional to the elevation difference to each neighbour. Water hexes
--   (surface < sea_level) are drawn flat at sea_level in water-blue; no cliff.
--
-- UNDERGROUND GEOMETRY (painter's algorithm)
--   Layer ascending → row (r) ascending → column (q) ascending.
--   For each solid tile: side faces (always LAYER_HEIGHT tall) then top face.

local Hex          = require("src.core.hex")
local TileRegistry = require("src.world.tile_registry")
local RenderCfg    = require("config.render")
local WorldgenCfg  = require("config.worldgen")
local Worldgen     = require("src.world.worldgen")

local LAYER_HEIGHT  = RenderCfg.layer_height
local LAYERS_BELOW  = RenderCfg.layers_below
local WORLD_DEPTH   = WorldgenCfg.world_depth

-- Colour for tiles completely enclosed on all 7 sides (6 hex neighbours at the
-- same layer + the tile above).  The player cannot see or reach these tiles.
local COL_OCCLUDED  = {0.22, 0.22, 0.28}

local sqrt3 = math.sqrt(3)

local Renderer = {}

-- ── Mode ──────────────────────────────────────────────────────────────────

local render_mode       = "overworld"   -- "overworld" | "underground"
local occlusion_enabled = true          -- false → show real tile colour even for buried tiles

function Renderer.toggle_mode()
    render_mode = render_mode == "underground" and "overworld" or "underground"
end

function Renderer.get_mode()
    return render_mode
end

function Renderer.toggle_occlusion()
    occlusion_enabled = not occlusion_enabled
end

function Renderer.get_occlusion()
    return occlusion_enabled
end

-- ── Shared: hex vertex array ───────────────────────────────────────────────
-- Returns {x0,y0, x1,y1, …, x5,y5} flat-top hex centred at (cx, cy).
-- Vertex order (east-origin, clockwise):
--   v0=(1,2) E tip     v1=(3,4) lower-right   v2=(5,6) lower-left
--   v3=(7,8) W tip     v4=(9,10) upper-left   v5=(11,12) upper-right

local function hex_verts(cx, cy)
    local S  = Hex.SIZE
    local s3 = S * sqrt3 / 2
    return {
        cx + S,   cy,        -- v0: E
        cx + S/2, cy + s3,   -- v1: lower-right
        cx - S/2, cy + s3,   -- v2: lower-left
        cx - S,   cy,        -- v3: W
        cx - S/2, cy - s3,   -- v4: upper-left
        cx + S/2, cy - s3,   -- v5: upper-right
    }
end

-- ── Underground helpers ────────────────────────────────────────────────────

-- Fixed-height side quad hanging down from edge (x1,y1)→(x2,y2).
local function draw_side(x1, y1, x2, y2)
    love.graphics.polygon("fill",
        x1, y1,
        x2, y2,
        x2, y2 + LAYER_HEIGHT,
        x1, y1 + LAYER_HEIGHT)
end

-- ── Underground renderer ───────────────────────────────────────────────────

local function draw_underground(world, cam, center_layer)
    local W, H   = love.graphics.getDimensions()
    local zoom   = cam.zoom
    local half_w = W / (2 * zoom)
    local half_h = H / (2 * zoom)
    local pad    = Hex.SIZE * 3

    local layer_lo = math.max(0, center_layer - LAYERS_BELOW)
    local layer_hi = center_layer   -- never render above the player's layer

    local py_lo = cam.y + layer_lo * LAYER_HEIGHT - half_h - pad
    local py_hi = cam.y + layer_hi * LAYER_HEIGHT + half_h + pad
    local px_lo = cam.x - half_w - pad
    local px_hi = cam.x + half_w + pad

    local qa, ra = Hex.pixel_to_hex(px_lo, py_lo)
    local qb, rb = Hex.pixel_to_hex(px_hi, py_lo)
    local qc, rc = Hex.pixel_to_hex(px_lo, py_hi)
    local qd, rd = Hex.pixel_to_hex(px_hi, py_hi)

    local q_lo = math.min(qa, qb, qc, qd) - 1
    local q_hi = math.max(qa, qb, qc, qd) + 1
    local r_lo = math.min(ra, rb, rc, rd) - 1
    local r_hi = math.max(ra, rb, rc, rd) + 1

    cam:apply()

    -- Painter's algorithm: r ascending (back→front), q ascending, layer ascending
    -- within each column (deep→surface).  Mirrors the overworld loop structure;
    -- the only difference is the inner layer loop capped at center_layer.
    for r = r_lo, r_hi do
        for q = q_lo, q_hi do
            local px, py = Hex.hex_to_pixel(q, r)

            for layer = layer_lo, layer_hi do
                local tile_id = world:get_tile(q, r, layer)

                if tile_id ~= 0 then
                    local v = hex_verts(px, py - layer * LAYER_HEIGHT)

                    -- Side faces: south-facing neighbour at same layer is air → draw.
                    local sc = TileRegistry.COLOR_SIDE[tile_id]
                    love.graphics.setColor(sc[1], sc[2], sc[3])
                    if world:get_tile(q + 1, r,     layer) == 0 then draw_side(v[1], v[2], v[3], v[4]) end
                    if world:get_tile(q,     r + 1, layer) == 0 then draw_side(v[3], v[4], v[5], v[6]) end
                    if world:get_tile(q - 1, r + 1, layer) == 0 then draw_side(v[5], v[6], v[7], v[8]) end

                    -- Top face: only when nothing solid is above in the rendered range.
                    -- (Matches overworld: surface tile = topmost visible tile per column.)
                    if layer == layer_hi or world:get_tile(q, r, layer + 1) == 0 then
                        -- At center_layer, check full 7-side occlusion: all 6 hex neighbours
                        -- at the same layer + the tile directly above.  A tile with no air
                        -- touching any face is unreachable — render dark instead of its material.
                        local tc
                        if occlusion_enabled
                            and layer == layer_hi
                            and world:get_tile(q + 1, r,     layer    ) ~= 0
                            and world:get_tile(q - 1, r,     layer    ) ~= 0
                            and world:get_tile(q,     r + 1, layer    ) ~= 0
                            and world:get_tile(q,     r - 1, layer    ) ~= 0
                            and world:get_tile(q + 1, r - 1, layer    ) ~= 0
                            and world:get_tile(q - 1, r + 1, layer    ) ~= 0
                            and world:get_tile(q,     r,     layer + 1) ~= 0
                        then
                            tc = COL_OCCLUDED
                        else
                            tc = TileRegistry.COLOR[tile_id]
                        end
                        love.graphics.setColor(tc[1], tc[2], tc[3])
                        love.graphics.polygon("fill", v)
                    end
                end
            end
        end
    end

    -- Hover outline.
    local mx, my   = love.mouse.getPosition()
    local wx, wy   = cam:screen_to_world(mx, my)
    local hq, hr   = Hex.pixel_to_hex(wx, wy + center_layer * LAYER_HEIGHT)
    local hpx, hpy = Hex.hex_to_pixel(hq, hr)
    local hv       = hex_verts(hpx, hpy - center_layer * LAYER_HEIGHT)

    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", hv)
    love.graphics.setLineWidth(1)

    cam:reset()
    love.graphics.setColor(1, 1, 1)
end

-- ── Overworld renderer ─────────────────────────────────────────────────────

local function draw_overworld(world, cam)
    local W, H   = love.graphics.getDimensions()
    local zoom   = cam.zoom
    local half_w = W / (2 * zoom)
    local half_h = H / (2 * zoom)
    local pad    = Hex.SIZE * 3

    local sea = WorldgenCfg.sea_level
    local sf  = WorldgenCfg.island.surface_floor
    local sp  = WorldgenCfg.island.surface_peak

    -- Tile colors (looked up once per frame).
    local grass_id = TileRegistry.id("grass")
    local water_id = TileRegistry.id("salt_water")
    local grass_tc = TileRegistry.COLOR[grass_id]
    local water_tc = TileRegistry.COLOR[water_id]

    -- Hex range must cover the full surface-height span (sf → sp).
    local py_lo = cam.y + sf * LAYER_HEIGHT - half_h - pad
    local py_hi = cam.y + sp * LAYER_HEIGHT + half_h + pad
    local px_lo = cam.x - half_w - pad
    local px_hi = cam.x + half_w + pad

    local qa, ra = Hex.pixel_to_hex(px_lo, py_lo)
    local qb, rb = Hex.pixel_to_hex(px_hi, py_lo)
    local qc, rc = Hex.pixel_to_hex(px_lo, py_hi)
    local qd, rd = Hex.pixel_to_hex(px_hi, py_hi)

    local q_lo = math.min(qa, qb, qc, qd) - 1
    local q_hi = math.max(qa, qb, qc, qd) + 1
    local r_lo = math.min(ra, rb, rc, rd) - 1
    local r_hi = math.max(ra, rb, rc, rd) + 1

    cam:apply()

    for r = r_lo, r_hi do
        for q = q_lo, q_hi do
            local sl        = Worldgen.surface_layer(q, r)
            local above_sea = sl >= sea
            local dl        = above_sea and sl or sea   -- visual draw level

            local px, py = Hex.hex_to_pixel(q, r)
            local cy     = py - dl * LAYER_HEIGHT
            local v      = hex_verts(px, cy)

            -- Cliff faces: land tiles only; water is a flat plane.
            -- Each layer is drawn individually using world:get_tile so that
            -- mined-out gaps and player-placed blocks always show correctly.
            -- Air layers (tile_id == 0) are simply skipped — they show as holes.
            if above_sea then
                -- E face  (v0→v1), neighbour dq=+1, dr=0
                local sl_e = Worldgen.surface_layer(q + 1, r)
                local dl_e = sl_e >= sea and sl_e or sea
                if dl > dl_e then
                    for l = dl_e, dl - 1 do
                        local tid = world:get_tile(q, r, l)
                        if tid ~= 0 then
                            local sc = TileRegistry.COLOR_SIDE[tid]
                            love.graphics.setColor(sc[1], sc[2], sc[3])
                            local yt = (dl - 1 - l) * LAYER_HEIGHT
                            local yb = (dl - l) * LAYER_HEIGHT
                            love.graphics.polygon("fill",
                                v[1], v[2]+yt, v[3], v[4]+yt,
                                v[3], v[4]+yb, v[1], v[2]+yb)
                        end
                    end
                end

                -- SE face (v1→v2), neighbour dq=0, dr=+1
                local sl_se = Worldgen.surface_layer(q, r + 1)
                local dl_se = sl_se >= sea and sl_se or sea
                if dl > dl_se then
                    for l = dl_se, dl - 1 do
                        local tid = world:get_tile(q, r, l)
                        if tid ~= 0 then
                            local sc = TileRegistry.COLOR_SIDE[tid]
                            love.graphics.setColor(sc[1], sc[2], sc[3])
                            local yt = (dl - 1 - l) * LAYER_HEIGHT
                            local yb = (dl - l) * LAYER_HEIGHT
                            love.graphics.polygon("fill",
                                v[3], v[4]+yt, v[5], v[6]+yt,
                                v[5], v[6]+yb, v[3], v[4]+yb)
                        end
                    end
                end

                -- SW face (v2→v3), neighbour dq=-1, dr=+1
                local sl_sw = Worldgen.surface_layer(q - 1, r + 1)
                local dl_sw = sl_sw >= sea and sl_sw or sea
                if dl > dl_sw then
                    for l = dl_sw, dl - 1 do
                        local tid = world:get_tile(q, r, l)
                        if tid ~= 0 then
                            local sc = TileRegistry.COLOR_SIDE[tid]
                            love.graphics.setColor(sc[1], sc[2], sc[3])
                            local yt = (dl - 1 - l) * LAYER_HEIGHT
                            local yb = (dl - l) * LAYER_HEIGHT
                            love.graphics.polygon("fill",
                                v[5], v[6]+yt, v[7], v[8]+yt,
                                v[7], v[8]+yb, v[5], v[6]+yb)
                        end
                    end
                end
            end

            -- Top face.
            if above_sea then
                love.graphics.setColor(grass_tc[1], grass_tc[2], grass_tc[3])
            else
                love.graphics.setColor(water_tc[1], water_tc[2], water_tc[3])
            end
            love.graphics.polygon("fill", v)
        end
    end

    -- Hover hex: iterate 3 times to converge on the right surface height.
    local mx, my    = love.mouse.getPosition()
    local wx, wy    = cam:screen_to_world(mx, my)
    local hover_dl  = sea
    local hq, hr
    for _ = 1, 3 do
        hq, hr    = Hex.pixel_to_hex(wx, wy + hover_dl * LAYER_HEIGHT)
        local hsl = Worldgen.surface_layer(hq, hr)
        hover_dl  = hsl >= sea and hsl or sea
    end
    local hpx, hpy = Hex.hex_to_pixel(hq, hr)
    local hv       = hex_verts(hpx, hpy - hover_dl * LAYER_HEIGHT)

    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", hv)
    love.graphics.setLineWidth(1)

    cam:reset()
    love.graphics.setColor(1, 1, 1)
end

-- ── Public draw ────────────────────────────────────────────────────────────

function Renderer.draw(world, cam, center_layer)
    if render_mode == "overworld" then
        draw_overworld(world, cam)
    else
        draw_underground(world, cam, center_layer)
    end
end

return Renderer
