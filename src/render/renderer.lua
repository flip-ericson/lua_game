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
--
-- HOVER SELECTION
--   Inline hit-test after every face draw; last writer wins (painter order).
--   Hover state is committed at the end of each draw pass and read next frame
--   for outline injection — one-frame lag is imperceptible at 60 fps.
--   Outline is injected at r == hover_r inside the painter loop so tiles with
--   higher r (visually in front) naturally occlude it.

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

-- ── Debug flags ───────────────────────────────────────────────────────────
local DBG_HIDE_LEAVES = false   -- true = skip leaf tiles in vegetation pass

-- ── Overview mode (M key) ─────────────────────────────────────────────────
local overview_mode = false

function Renderer.toggle_overview() overview_mode = not overview_mode end
function Renderer.get_overview()    return overview_mode              end

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

-- ── Hover state ───────────────────────────────────────────────────────────
-- Updated inline each frame (detection pass), read next frame (outline pass).
-- One frame of lag between detection and drawing — imperceptible at 60 fps.

local hover_q        = nil
local hover_r        = nil
local hover_layer    = nil
local hover_tile     = 0
local hover_occluded = false   -- true when hovered tile is rendered as COL_OCCLUDED

-- Returns (q, r, layer, tile_id) of the topmost rendered face under the cursor.
-- nil q/r means nothing is hovered (cursor off-world or over air).
function Renderer.get_hover()
    return hover_q, hover_r, hover_layer, hover_tile
end

-- Returns true when the hovered tile is occluded (drawn gray).
function Renderer.get_hover_occluded()
    return hover_occluded
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

-- ── Hit-test helpers (world-space; no allocation) ─────────────────────────

-- Point (px,py) inside flat-top hex centred at (cx,cy) with SIZE = Hex.SIZE.
-- Three half-plane checks using the 3 unique face normals of a flat-top hex.
local function point_in_hex(px, py, cx, cy)
    local ir = Hex.SIZE * sqrt3 * 0.5
    local dx, dy = px - cx, py - cy
    return math.abs(dy)                            <= ir
       and math.abs(dx * sqrt3 * 0.5 + dy * 0.5)  <= ir
       and math.abs(dx * sqrt3 * 0.5 - dy * 0.5)  <= ir
end

-- Point (px,py) inside convex quad defined by four vertices in winding order.
local function point_in_quad(px, py, x1,y1, x2,y2, x3,y3, x4,y4)
    local function c(ax,ay,bx,by) return (bx-ax)*(py-ay)-(by-ay)*(px-ax) end
    local s1 = c(x1,y1, x2,y2)
    local s2 = c(x2,y2, x3,y3)
    local s3 = c(x3,y3, x4,y4)
    local s4 = c(x4,y4, x1,y1)
    return (s1 >= 0 and s2 >= 0 and s3 >= 0 and s4 >= 0)
        or (s1 <= 0 and s2 <= 0 and s3 <= 0 and s4 <= 0)
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

-- ── Outline helpers ────────────────────────────────────────────────────────

-- Draw selection outline for (hq, hr, hl) in underground mode.
-- Called inside the painter loop at r == hover_r.
local function draw_outline_underground(world, hq, hr, hl)
    local hpx, hpy = Hex.hex_to_pixel(hq, hr)
    local hv = hex_verts(hpx, hpy - hl * LAYER_HEIGHT)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", hv)
    if (world:get_tile(hq+1, hr,   hl) or 0) == 0 then
        love.graphics.polygon("line", hv[1],hv[2], hv[3],hv[4], hv[3],hv[4]+LAYER_HEIGHT, hv[1],hv[2]+LAYER_HEIGHT)
    end
    if (world:get_tile(hq,   hr+1, hl) or 0) == 0 then
        love.graphics.polygon("line", hv[3],hv[4], hv[5],hv[6], hv[5],hv[6]+LAYER_HEIGHT, hv[3],hv[4]+LAYER_HEIGHT)
    end
    if (world:get_tile(hq-1, hr+1, hl) or 0) == 0 then
        love.graphics.polygon("line", hv[5],hv[6], hv[7],hv[8], hv[7],hv[8]+LAYER_HEIGHT, hv[5],hv[6]+LAYER_HEIGHT)
    end
    love.graphics.setLineWidth(1)
end

-- Draw selection outline for (hq, hr, hl) in overworld mode.
-- If hl > surface draw-layer: treats it as a vegetation tile (top + visible sides).
-- Otherwise: surface/cliff tile (top face + cliff edge outlines).
local function draw_outline_overworld(world, sea, hq, hr, hl)
    local hpx, hpy = Hex.hex_to_pixel(hq, hr)
    local hsl = Worldgen.surface_layer(hq, hr)
    local hdl = hsl >= sea and hsl or sea

    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.setLineWidth(2)

    if hl > hdl then
        -- Vegetation tile.
        local hv = hex_verts(hpx, hpy - hl * LAYER_HEIGHT)
        love.graphics.polygon("line", hv)
        local n1 = world:get_tile(hq+1, hr,   hl)
        local n2 = world:get_tile(hq,   hr+1, hl)
        local n3 = world:get_tile(hq-1, hr+1, hl)
        if n1 == 0 or TileRegistry.TRANSPARENT[n1] then
            love.graphics.polygon("line", hv[1],hv[2], hv[3],hv[4], hv[3],hv[4]+LAYER_HEIGHT, hv[1],hv[2]+LAYER_HEIGHT)
        end
        if n2 == 0 or TileRegistry.TRANSPARENT[n2] then
            love.graphics.polygon("line", hv[3],hv[4], hv[5],hv[6], hv[5],hv[6]+LAYER_HEIGHT, hv[3],hv[4]+LAYER_HEIGHT)
        end
        if n3 == 0 or TileRegistry.TRANSPARENT[n3] then
            love.graphics.polygon("line", hv[5],hv[6], hv[7],hv[8], hv[7],hv[8]+LAYER_HEIGHT, hv[5],hv[6]+LAYER_HEIGHT)
        end
    else
        -- Surface / cliff tile: outline at hdl with cliff edge extents.
        local hv = hex_verts(hpx, hpy - hdl * LAYER_HEIGHT)
        love.graphics.polygon("line", hv)
        local sl_e  = Worldgen.surface_layer(hq+1, hr)
        local dl_e  = sl_e >= sea and sl_e or sea
        if hdl > dl_e then
            local ch = (hdl - dl_e) * LAYER_HEIGHT
            love.graphics.polygon("line", hv[1],hv[2], hv[3],hv[4], hv[3],hv[4]+ch, hv[1],hv[2]+ch)
        end
        local sl_se = Worldgen.surface_layer(hq, hr+1)
        local dl_se = sl_se >= sea and sl_se or sea
        if hdl > dl_se then
            local ch = (hdl - dl_se) * LAYER_HEIGHT
            love.graphics.polygon("line", hv[3],hv[4], hv[5],hv[6], hv[5],hv[6]+ch, hv[3],hv[4]+ch)
        end
        local sl_sw = Worldgen.surface_layer(hq-1, hr+1)
        local dl_sw = sl_sw >= sea and sl_sw or sea
        if hdl > dl_sw then
            local ch = (hdl - dl_sw) * LAYER_HEIGHT
            love.graphics.polygon("line", hv[5],hv[6], hv[7],hv[8], hv[7],hv[8]+ch, hv[5],hv[6]+ch)
        end
    end

    love.graphics.setLineWidth(1)
end

-- ── Underground renderer ───────────────────────────────────────────────────

local function draw_underground(world, cam, center_layer, player)
    local W, H   = love.graphics.getDimensions()
    local zoom   = cam.zoom
    local half_w = W / (2 * zoom)
    local half_h = H / (2 * zoom)
    local pad    = Hex.SIZE * 3

    local layer_lo = 0               -- render everything from bedrock up
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

    -- Cursor in world space for inline hit testing.
    local mx, my = love.mouse.getPosition()
    local wx, wy = cam:screen_to_world(mx, my)
    -- Next-frame hover candidates (last write wins = painter order).
    local nq, nr, nl, ntid = nil, nil, nil, 0
    local n_occluded = false

    cam:apply()

    -- Painter's algorithm: r ascending (back→front), q ascending, layer ascending
    -- within each column (deep→surface).
    for r = r_lo, r_hi do
        for q = q_lo, q_hi do
            local px, py = Hex.hex_to_pixel(q, r)

            for layer = layer_lo, layer_hi do
                local tile_id = world:get_tile(q, r, layer)

                if tile_id ~= 0 then
                    local v     = hex_verts(px, py - layer * LAYER_HEIGHT)
                    local alpha = TileRegistry.TRANSPARENT[tile_id] and 0.5 or 1.0

                    -- Side faces: draw when neighbour is air or transparent (mirrors overworld).
                    local sc = TileRegistry.COLOR_SIDE[tile_id]
                    love.graphics.setColor(sc[1], sc[2], sc[3], alpha)
                    local n1 = world:get_tile(q + 1, r,     layer) or 0
                    local n2 = world:get_tile(q,     r + 1, layer) or 0
                    local n3 = world:get_tile(q - 1, r + 1, layer) or 0
                    if n1 == 0 or TileRegistry.TRANSPARENT[n1] then
                        draw_side(v[1], v[2], v[3], v[4])
                        if point_in_quad(wx,wy, v[1],v[2], v[3],v[4], v[3],v[4]+LAYER_HEIGHT, v[1],v[2]+LAYER_HEIGHT) then
                            nq, nr, nl, ntid = q, r, layer, tile_id
                            n_occluded = false   -- side faces are always visible
                        end
                    end
                    if n2 == 0 or TileRegistry.TRANSPARENT[n2] then
                        draw_side(v[3], v[4], v[5], v[6])
                        if point_in_quad(wx,wy, v[3],v[4], v[5],v[6], v[5],v[6]+LAYER_HEIGHT, v[3],v[4]+LAYER_HEIGHT) then
                            nq, nr, nl, ntid = q, r, layer, tile_id
                            n_occluded = false
                        end
                    end
                    if n3 == 0 or TileRegistry.TRANSPARENT[n3] then
                        draw_side(v[5], v[6], v[7], v[8])
                        if point_in_quad(wx,wy, v[5],v[6], v[7],v[8], v[7],v[8]+LAYER_HEIGHT, v[5],v[6]+LAYER_HEIGHT) then
                            nq, nr, nl, ntid = q, r, layer, tile_id
                            n_occluded = false
                        end
                    end

                    -- Top face: only when nothing opaque is above in the rendered range.
                    local above_id = world:get_tile(q, r, layer + 1) or 0
                    if layer == layer_hi or above_id == 0 or TileRegistry.TRANSPARENT[above_id] then
                        local tc
                        if occlusion_enabled and layer == layer_hi then
                            local TR  = TileRegistry.TRANSPARENT
                            local ob1 = world:get_tile(q + 1, r,     layer    ) or 0
                            local ob2 = world:get_tile(q - 1, r,     layer    ) or 0
                            local ob3 = world:get_tile(q,     r + 1, layer    ) or 0
                            local ob4 = world:get_tile(q,     r - 1, layer    ) or 0
                            local ob5 = world:get_tile(q + 1, r - 1, layer    ) or 0
                            local ob6 = world:get_tile(q - 1, r + 1, layer    ) or 0
                            local ob7 = world:get_tile(q,     r,     layer + 1) or 0
                            if ob1 ~= 0 and not TR[ob1]
                               and ob2 ~= 0 and not TR[ob2]
                               and ob3 ~= 0 and not TR[ob3]
                               and ob4 ~= 0 and not TR[ob4]
                               and ob5 ~= 0 and not TR[ob5]
                               and ob6 ~= 0 and not TR[ob6]
                               and ob7 ~= 0 and not TR[ob7]
                            then
                                tc = COL_OCCLUDED
                            else
                                tc = TileRegistry.COLOR[tile_id]
                            end
                        else
                            tc = TileRegistry.COLOR[tile_id]
                        end
                        local tile_occ = (tc == COL_OCCLUDED)
                        love.graphics.setColor(tc[1], tc[2], tc[3], alpha)
                        love.graphics.polygon("fill", v)
                        if point_in_hex(wx, wy, px, py - layer * LAYER_HEIGHT) then
                            nq, nr, nl, ntid = q, r, layer, tile_id
                            n_occluded = tile_occ
                        end
                    end

                    -- Selection outline: drawn immediately after this tile's faces so
                    -- anything painted after (higher layer, further-forward row) occludes it.
                    if hover_r ~= nil and q == hover_q and r == hover_r and layer == hover_layer then
                        draw_outline_underground(world, hover_q, hover_r, hover_layer)
                    end
                end
            end
        end

        -- Depth-correct player.
        if player and player.r == r then
            player:draw_world(center_layer)
        end
    end

    -- Commit this frame's detection result for use next frame.
    hover_q, hover_r, hover_layer, hover_tile = nq, nr, nl, ntid
    hover_occluded = n_occluded

    cam:reset()
    love.graphics.setColor(1, 1, 1)
end

-- ── Overworld renderer ─────────────────────────────────────────────────────

local function draw_overworld(world, cam, player)
    local W, H   = love.graphics.getDimensions()
    local zoom   = cam.zoom
    local half_w = W / (2 * zoom)
    local half_h = H / (2 * zoom)
    local pad    = Hex.SIZE * 3

    local sea = WorldgenCfg.sea_level
    local sf  = WorldgenCfg.island.edge_height
    local sp  = WorldgenCfg.island.center_height + WorldgenCfg.island.noise_amplitude * 0.5

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

    -- Overview: blue world-boundary hexagon drawn before cam:apply().
    if overview_mode then
        local R = WorldgenCfg.world_radius
        local boundary = {
            { R,  0}, { R, -R}, { 0, -R},
            {-R,  0}, {-R,  R}, { 0,  R},
        }
        local verts = {}
        for _, c in ipairs(boundary) do
            local wx, wy = Hex.hex_to_pixel(c[1], c[2])
            local sx, sy = cam:world_to_screen(wx, wy - sea * LAYER_HEIGHT)
            verts[#verts + 1] = sx
            verts[#verts + 1] = sy
        end
        love.graphics.setColor(water_tc[1], water_tc[2], water_tc[3])
        love.graphics.polygon("fill", verts)
    end

    local step = overview_mode
        and math.max(1, math.ceil((q_hi - q_lo) / 300))
        or  1

    -- Cursor in world space for inline hit testing (overview suppresses hit tests).
    local mx, my = love.mouse.getPosition()
    local wx, wy = cam:screen_to_world(mx, my)
    local nq, nr, nl, ntid = nil, nil, nil, 0

    cam:apply()

    local world_r = WorldgenCfg.world_radius
    for r = r_lo, r_hi, step do
        for q = q_lo, q_hi, step do
            if math.max(math.abs(q), math.abs(r), math.abs(q + r)) > world_r then
                goto continue
            end
            local sl        = Worldgen.surface_layer(q, r)
            local above_sea = sl >= sea
            local dl        = above_sea and sl or sea

            local px, py = Hex.hex_to_pixel(q, r)
            local cy     = py - dl * LAYER_HEIGHT

            if overview_mode then
                if above_sea then
                    local top_id = world:get_tile(q, r, dl)
                    for k = 1, 12 do
                        local id = world:get_tile(q, r, dl + k)
                        if id == 0 then break end
                        top_id = id
                    end
                    local tc = (top_id ~= 0) and TileRegistry.COLOR[top_id] or grass_tc
                    love.graphics.setColor(tc[1], tc[2], tc[3])
                    local cw = step * Hex.SIZE * 1.5
                    local ch = step * Hex.SIZE * sqrt3
                    love.graphics.rectangle("fill", px - cw * 0.5, cy - ch * 0.5, cw, ch)
                end
            else
                local v = hex_verts(px, cy)

                -- Cliff faces: land tiles only; water is a flat plane.
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
                                if point_in_quad(wx,wy,
                                    v[1],v[2]+yt, v[3],v[4]+yt,
                                    v[3],v[4]+yb, v[1],v[2]+yb) then
                                    nq, nr, nl, ntid = q, r, l, tid
                                end
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
                                if point_in_quad(wx,wy,
                                    v[3],v[4]+yt, v[5],v[6]+yt,
                                    v[5],v[6]+yb, v[3],v[4]+yb) then
                                    nq, nr, nl, ntid = q, r, l, tid
                                end
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
                                if point_in_quad(wx,wy,
                                    v[5],v[6]+yt, v[7],v[8]+yt,
                                    v[7],v[8]+yb, v[5],v[6]+yb) then
                                    nq, nr, nl, ntid = q, r, l, tid
                                end
                            end
                        end
                    end
                end

                -- Top face.
                local sid = world:get_tile(q, r, dl)
                if sid and sid ~= 0 then
                    local tc = TileRegistry.COLOR[sid]
                    love.graphics.setColor(tc[1], tc[2], tc[3])
                    love.graphics.polygon("fill", v)
                    if point_in_hex(wx, wy, px, cy) then
                        nq, nr, nl, ntid = q, r, dl, sid
                    end
                end
                -- Selection outline for surface / cliff hits (hover_layer <= dl).
                if hover_r ~= nil and q == hover_q and r == hover_r
                    and hover_layer ~= nil and hover_layer <= dl then
                    draw_outline_overworld(world, sea, hover_q, hover_r, hover_layer)
                end

                -- Vegetation pass.
                for k = 1, 12 do
                    local vl  = dl + k
                    local tid = world:get_tile(q, r, vl)
                    local def = tid and tid ~= 0 and TileRegistry.get(tid)
                    if def and def.category == "organic"
                        and not (DBG_HIDE_LEAVES and def.name:find("leaves")) then
                        local vv    = hex_verts(px, py - vl * LAYER_HEIGHT)
                        local alpha = TileRegistry.TRANSPARENT[tid] and 0.5 or 1.0
                        local sc = TileRegistry.COLOR_SIDE[tid]
                        love.graphics.setColor(sc[1], sc[2], sc[3], alpha)
                        local n1 = world:get_tile(q+1, r,   vl)
                        local n2 = world:get_tile(q,   r+1, vl)
                        local n3 = world:get_tile(q-1, r+1, vl)
                        if n1 == 0 or TileRegistry.TRANSPARENT[n1] then
                            draw_side(vv[1], vv[2], vv[3], vv[4])
                            if point_in_quad(wx,wy, vv[1],vv[2], vv[3],vv[4], vv[3],vv[4]+LAYER_HEIGHT, vv[1],vv[2]+LAYER_HEIGHT) then
                                nq, nr, nl, ntid = q, r, vl, tid
                            end
                        end
                        if n2 == 0 or TileRegistry.TRANSPARENT[n2] then
                            draw_side(vv[3], vv[4], vv[5], vv[6])
                            if point_in_quad(wx,wy, vv[3],vv[4], vv[5],vv[6], vv[5],vv[6]+LAYER_HEIGHT, vv[3],vv[4]+LAYER_HEIGHT) then
                                nq, nr, nl, ntid = q, r, vl, tid
                            end
                        end
                        if n3 == 0 or TileRegistry.TRANSPARENT[n3] then
                            draw_side(vv[5], vv[6], vv[7], vv[8])
                            if point_in_quad(wx,wy, vv[5],vv[6], vv[7],vv[8], vv[7],vv[8]+LAYER_HEIGHT, vv[5],vv[6]+LAYER_HEIGHT) then
                                nq, nr, nl, ntid = q, r, vl, tid
                            end
                        end
                        local above = world:get_tile(q, r, vl + 1)
                        if above == 0 or TileRegistry.TRANSPARENT[above] then
                            local tc = TileRegistry.COLOR[tid]
                            love.graphics.setColor(tc[1], tc[2], tc[3], alpha)
                            love.graphics.polygon("fill", vv)
                            if point_in_hex(wx, wy, px, py - vl * LAYER_HEIGHT) then
                                nq, nr, nl, ntid = q, r, vl, tid
                            end
                        end
                        -- Selection outline for vegetation hits.
                        if hover_r ~= nil and q == hover_q and r == hover_r and vl == hover_layer then
                            draw_outline_overworld(world, sea, hover_q, hover_r, hover_layer)
                        end
                    end
                end
            end
            ::continue::
        end

        -- Depth-correct player.
        if player and not overview_mode and player.r == r then
            local pl_dl = math.max(Worldgen.surface_layer(player.q, player.r), sea)
            player:draw_world(pl_dl)
        end
    end

    -- Commit this frame's detection result for use next frame.
    -- Overworld has no occlusion, so hover_occluded is always false here.
    hover_q, hover_r, hover_layer, hover_tile = nq, nr, nl, ntid
    hover_occluded = false

    cam:reset()
    love.graphics.setColor(1, 1, 1)
end

-- ── Public draw ────────────────────────────────────────────────────────────

function Renderer.draw(world, cam, center_layer, player)
    if render_mode == "overworld" then
        draw_overworld(world, cam, player)
    else
        draw_underground(world, cam, center_layer, player)
    end
end

return Renderer
