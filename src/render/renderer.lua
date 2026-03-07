-- src/render/renderer.lua
-- Unified painter's algorithm renderer.
--
-- ALGORITHM (same logic for both modes):
--   1. Pre-scan loaded chunk window to find:
--        layer_lo  = lowest of all topmost non-transparent tiles (floor)
--        layer_hi  = highest of any tile at all (ceiling)
--   2. Painter's loop: r ascending (back→front) → q ascending → layer ascending
--   3. Each non-air tile: check 4 visible faces (E-side, SE-side, SW-side, top).
--        Face drawn when neighbour in that direction is air or transparent.
--        Same check in both modes — no cliff conditions, no surface cache.
--   4. Underground: layer_hi capped at cam_layer. Overworld: run to actual ceiling.
--
-- HOVER SELECTION
--   Inline hit-test after every face draw; last writer wins (painter order).
--   Committed at end of frame, read next frame for outline — one-frame lag.

local Hex          = require("src.core.hex")
local TileRegistry = require("src.world.tile_registry")
local RenderCfg    = require("config.render")
local WorldgenCfg  = require("config.worldgen")
local ItemDrops    = require("src.entities.item_drops")
local Effects      = require("src.render.effects")

local LAYER_HEIGHT = RenderCfg.layer_height

local COL_OCCLUDED = {0.22, 0.22, 0.28}   -- colour for fully-buried tiles

local sqrt3 = math.sqrt(3)

-- ── Mining reach ──────────────────────────────────────────────────────────
-- 3D face-centre distance check (px).  Tune here.
local MINING_REACH = 120

-- Face centre offsets {dx, dy, vert_layer_offset} relative to tile hex centre.
-- vert_layer_offset added to tile layer gives the face's height in layer units.
--   top (0)  : centre of top surface  → hl + 1.0
--   E   (1)  : midpoint of E edge, mid-height → hl + 0.5
--   SE  (2)  : midpoint of SE edge   → hl + 0.5
--   SW  (3)  : midpoint of SW edge   → hl + 0.5
local _HS  = RenderCfg.hex_size          -- 48
local _S3  = _HS * math.sqrt(3) * 0.5   -- inradius ≈ 41.57
local _FACE_OFF = {
    [0] = {  0,        0,       1.0 },
    [1] = {  _HS*0.75, _S3*0.5, 0.5 },
    [2] = {  0,        _S3,     0.5 },
    [3] = { -_HS*0.75, _S3*0.5, 0.5 },
}

local function face_in_reach(player, hq, hr, hl, face)
    if not face then return false end
    local off = _FACE_OFF[face]
    if not off then return false end
    local hx, hy = Hex.hex_to_pixel(hq, hr)
    local dx  = hx + off[1] - player.x
    local dy  = hy + off[2] - player.y
    local dz  = (hl + off[3] - (player.layer + 1.5)) * LAYER_HEIGHT
    return dx*dx + dy*dy + dz*dz <= MINING_REACH * MINING_REACH
end

local Renderer = {}

-- ── Overview mode (M key) ─────────────────────────────────────────────────
local overview_mode = false
function Renderer.toggle_overview() overview_mode = not overview_mode end
function Renderer.get_overview()    return overview_mode              end

-- ── Render mode ───────────────────────────────────────────────────────────
local render_mode       = "overworld"
local occlusion_enabled = true

function Renderer.toggle_mode()
    render_mode = render_mode == "underground" and "overworld" or "underground"
end
function Renderer.get_mode() return render_mode end

function Renderer.toggle_occlusion() occlusion_enabled = not occlusion_enabled end
function Renderer.get_occlusion()    return occlusion_enabled                   end

-- ── Hover state ───────────────────────────────────────────────────────────
local hover_q        = nil
local hover_r        = nil
local hover_layer    = nil
local hover_tile     = 0
local hover_occluded = false
local hover_face     = nil    -- 0=top  1=E  2=SE  3=SW  (nil when nothing hovered)
local hover_in_reach = false  -- true when hovered face is within MINING_REACH

function Renderer.get_hover()          return hover_q, hover_r, hover_layer, hover_tile end
function Renderer.get_hover_occluded() return hover_occluded                            end
function Renderer.get_hover_face()     return hover_face                                end
function Renderer.get_hover_in_reach() return hover_in_reach                           end

-- ── Hex vertex array ──────────────────────────────────────────────────────
-- Flat-top hex centred at (cx,cy). Clockwise from E tip.
local function hex_verts(cx, cy)
    local S  = Hex.SIZE
    local s3 = S * sqrt3 / 2
    return {
        cx + S,   cy,        -- v0: E
        cx + S/2, cy + s3,   -- v1: SE
        cx - S/2, cy + s3,   -- v2: SW
        cx - S,   cy,        -- v3: W
        cx - S/2, cy - s3,   -- v4: NW
        cx + S/2, cy - s3,   -- v5: NE
    }
end

-- ── Hit-test helpers ──────────────────────────────────────────────────────
local function point_in_hex(px, py, cx, cy)
    local ir = Hex.SIZE * sqrt3 * 0.5
    local dx, dy = px - cx, py - cy
    return math.abs(dy)                           <= ir
       and math.abs(dx * sqrt3*0.5 + dy * 0.5)   <= ir
       and math.abs(dx * sqrt3*0.5 - dy * 0.5)   <= ir
end

local function point_in_quad(px,py, x1,y1, x2,y2, x3,y3, x4,y4)
    local function c(ax,ay,bx,by) return (bx-ax)*(py-ay)-(by-ay)*(px-ax) end
    local s1,s2,s3,s4 = c(x1,y1,x2,y2), c(x2,y2,x3,y3), c(x3,y3,x4,y4), c(x4,y4,x1,y1)
    return (s1>=0 and s2>=0 and s3>=0 and s4>=0)
        or (s1<=0 and s2<=0 and s3<=0 and s4<=0)
end

-- ── Side-face quad ────────────────────────────────────────────────────────
local function draw_side(x1, y1, x2, y2)
    love.graphics.polygon("fill",
        x1, y1, x2, y2,
        x2, y2 + LAYER_HEIGHT,
        x1, y1 + LAYER_HEIGHT)
end

-- ── Unified selection outline ─────────────────────────────────────────────
-- Outlines the hovered tile's top face and any exposed south-facing sides.
-- in_reach: true → bright green (mineble); false → dim white (out of reach).
local function draw_outline(world, hq, hr, hl, in_reach)
    local hpx, hpy = Hex.hex_to_pixel(hq, hr)
    local hv = hex_verts(hpx, hpy - hl * LAYER_HEIGHT)
    if in_reach then
        love.graphics.setColor(0.15, 1.0, 0.40, 0.90)   -- bright lime green
    else
        love.graphics.setColor(1, 1, 1, 0.6)             -- out-of-reach white
    end
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", hv)
    local TR = TileRegistry.TRANSPARENT
    local n1 = world:get_tile(hq+1, hr,   hl) or 0
    local n2 = world:get_tile(hq,   hr+1, hl) or 0
    local n3 = world:get_tile(hq-1, hr+1, hl) or 0
    if n1 == 0 or TR[n1] then
        love.graphics.polygon("line", hv[1],hv[2], hv[3],hv[4], hv[3],hv[4]+LAYER_HEIGHT, hv[1],hv[2]+LAYER_HEIGHT)
    end
    if n2 == 0 or TR[n2] then
        love.graphics.polygon("line", hv[3],hv[4], hv[5],hv[6], hv[5],hv[6]+LAYER_HEIGHT, hv[3],hv[4]+LAYER_HEIGHT)
    end
    if n3 == 0 or TR[n3] then
        love.graphics.polygon("line", hv[5],hv[6], hv[7],hv[8], hv[7],hv[8]+LAYER_HEIGHT, hv[5],hv[6]+LAYER_HEIGHT)
    end
    love.graphics.setLineWidth(1)
end

-- ── Unified tile renderer ─────────────────────────────────────────────────
local function draw_tiles(world, cam, cam_layer, player)
    local W, H   = love.graphics.getDimensions()
    local zoom   = cam.zoom
    local half_w = W / (2 * zoom)
    local half_h = H / (2 * zoom)
    local pad    = Hex.SIZE * 3

    local is_ow   = (render_mode == "overworld")
    local world_r = WorldgenCfg.world_radius
    local TR      = TileRegistry.TRANSPARENT

    -- Scan range (established before hex bounds so py can account for layer offsets).
    -- Tiles draw at visual_y = hex_y - layer*LAYER_HEIGHT.  To find which hex rows
    -- contain visible tiles across the full layer window, expand py by that offset:
    --   hex_y_min = cam.y - half_h - pad + scan_lo * LAYER_HEIGHT
    --   hex_y_max = cam.y + half_h + pad + scan_hi * LAYER_HEIGHT
    local scan_lo = math.max(0, cam_layer - 32)
    local scan_hi = cam_layer + 32

    local px_lo = cam.x - half_w - pad
    local px_hi = cam.x + half_w + pad
    local py_lo = cam.y + scan_lo * LAYER_HEIGHT - half_h - pad
    local py_hi = cam.y + scan_hi * LAYER_HEIGHT + half_h + pad

    local qa, ra = Hex.pixel_to_hex(px_lo, py_lo)
    local qb, rb = Hex.pixel_to_hex(px_hi, py_lo)
    local qc, rc = Hex.pixel_to_hex(px_lo, py_hi)
    local qd, rd = Hex.pixel_to_hex(px_hi, py_hi)
    local q_lo = math.min(qa, qb, qc, qd) - 1
    local q_hi = math.max(qa, qb, qc, qd) + 1
    local r_lo = math.min(ra, rb, rc, rd) - 1
    local r_hi = math.max(ra, rb, rc, rd) + 1

    -- ── Overview (M key): fast sampled top-down, early return ─────────────
    if overview_mode and is_ow then
        local sea   = WorldgenCfg.sea_level
        local R     = world_r
        local boundary = {{ R,0},{ R,-R},{0,-R},{-R,0},{-R,R},{0,R}}
        local bverts = {}
        for _, c in ipairs(boundary) do
            local bx, by = Hex.hex_to_pixel(c[1], c[2])
            local sx, sy = cam:world_to_screen(bx, by - sea * LAYER_HEIGHT)
            bverts[#bverts+1] = sx; bverts[#bverts+1] = sy
        end
        local wtc = TileRegistry.COLOR[TileRegistry.id("salt_water")]
        love.graphics.setColor(wtc[1], wtc[2], wtc[3])
        love.graphics.polygon("fill", bverts)

        local step = math.max(1, math.ceil((q_hi - q_lo) / 300))
        cam:apply()
        -- Overview scan window: just around cam_layer (loaded range)
        local ov_lo = math.max(0, cam_layer - 32)
        local ov_hi = cam_layer + 32
        for r = r_lo, r_hi, step do
            for q = q_lo, q_hi, step do
                if math.max(math.abs(q), math.abs(r), math.abs(q+r)) > world_r then
                    goto ov_next
                end
                -- Find topmost visible tile (transparent or not)
                local top_id, top_l = 0, 0
                for l = ov_hi, ov_lo, -1 do
                    local tid = world:get_tile(q, r, l) or 0
                    if tid ~= 0 then top_id = tid; top_l = l; break end
                end
                if top_id == 0 then goto ov_next end
                local tc  = TileRegistry.COLOR[top_id]
                local px2, py2 = Hex.hex_to_pixel(q, r)
                love.graphics.setColor(tc[1], tc[2], tc[3])
                local cw = step * Hex.SIZE * 1.5
                local ch = step * Hex.SIZE * sqrt3
                love.graphics.rectangle("fill", px2 - cw*0.5, (py2 - top_l*LAYER_HEIGHT) - ch*0.5, cw, ch)
                ::ov_next::
            end
        end
        hover_q, hover_r, hover_layer, hover_tile = nil, nil, nil, 0
        hover_occluded = false
        cam:reset()
        love.graphics.setColor(1, 1, 1)
        return
    end

    -- ── Pre-scan loaded chunk window ──────────────────────────────────────
    -- scan_lo/scan_hi already defined above for py bounds.
    -- Find:
    --   layer_lo = minimum of each column's topmost non-transparent layer (floor)
    --   layer_hi = maximum of any tile at all across all columns (ceiling)
    local layer_lo = scan_hi
    local layer_hi = scan_lo

    for r = r_lo, r_hi do
        for q = q_lo, q_hi do
            if math.max(math.abs(q), math.abs(r), math.abs(q+r)) > world_r then
                goto prescan_col
            end
            for l = scan_hi, scan_lo, -1 do
                local tid = world:get_tile(q, r, l) or 0
                if tid ~= 0 then
                    if l > layer_hi then layer_hi = l end
                    if not TR[tid] then
                        if l < layer_lo then layer_lo = l end
                        break  -- found this column's floor; move to next column
                    end
                end
            end
            ::prescan_col::
        end
    end

    if layer_hi <= scan_lo then return end          -- nothing loaded yet
    layer_lo = math.max(scan_lo, layer_lo - 1)     -- one below floor (side faces)

    -- Underground: ceiling = cam_layer. Overworld: ceiling = highest tile found.
    if not is_ow and layer_hi > cam_layer then layer_hi = cam_layer end

    -- ── Cursor ────────────────────────────────────────────────────────────
    local mx, my = love.mouse.getPosition()
    local wx, wy = cam:screen_to_world(mx, my)
    local nq, nr, nl, ntid = nil, nil, nil, 0
    local n_occluded = false
    local n_face     = nil   -- last-written face under cursor (0=top,1=E,2=SE,3=SW)

    cam:apply()

    -- ── Painter's algorithm ───────────────────────────────────────────────
    -- r ascending (back→front) → q ascending → layer ascending (deep→surface).
    for r = r_lo, r_hi do
        for q = q_lo, q_hi do
            if math.max(math.abs(q), math.abs(r), math.abs(q+r)) > world_r then
                goto col_next
            end

            local px, py = Hex.hex_to_pixel(q, r)

            for layer = layer_lo, layer_hi do
                local tid = world:get_tile(q, r, layer) or 0
                if tid == 0 then goto layer_next end

                local alpha = TR[tid] and 0.5 or 1.0
                local sdx   = Effects.get_shake(q, r, layer)
                local v     = hex_verts(px + sdx, py - layer * LAYER_HEIGHT)

                -- 4 visible faces. Exposed = neighbour is air or transparent.
                -- Identical check in both overworld and underground.
                local n_e   = world:get_tile(q+1, r,   layer) or 0
                local n_se  = world:get_tile(q,   r+1, layer) or 0
                local n_sw  = world:get_tile(q-1, r+1, layer) or 0
                local n_top = world:get_tile(q,   r,   layer+1) or 0

                local show_e   = n_e   == 0 or TR[n_e]
                local show_se  = n_se  == 0 or TR[n_se]
                local show_sw  = n_sw  == 0 or TR[n_sw]
                -- Underground ceiling: layer+1 is cut off and doesn't exist to us,
                -- so always show the top face at cam_layer regardless of what's above.
                local show_top = (n_top == 0 or TR[n_top])
                              or (not is_ow and layer == cam_layer)

                -- ── Side faces ────────────────────────────────────────────
                local sc = TileRegistry.COLOR_SIDE[tid]
                love.graphics.setColor(sc[1], sc[2], sc[3], alpha)

                if show_e then
                    draw_side(v[1], v[2], v[3], v[4])
                    if point_in_quad(wx,wy, v[1],v[2], v[3],v[4], v[3],v[4]+LAYER_HEIGHT, v[1],v[2]+LAYER_HEIGHT) then
                        nq, nr, nl, ntid = q, r, layer, tid; n_occluded = false; n_face = 1
                    end
                end
                if show_se then
                    draw_side(v[3], v[4], v[5], v[6])
                    if point_in_quad(wx,wy, v[3],v[4], v[5],v[6], v[5],v[6]+LAYER_HEIGHT, v[3],v[4]+LAYER_HEIGHT) then
                        nq, nr, nl, ntid = q, r, layer, tid; n_occluded = false; n_face = 2
                    end
                end
                if show_sw then
                    draw_side(v[5], v[6], v[7], v[8])
                    if point_in_quad(wx,wy, v[5],v[6], v[7],v[8], v[7],v[8]+LAYER_HEIGHT, v[5],v[6]+LAYER_HEIGHT) then
                        nq, nr, nl, ntid = q, r, layer, tid; n_occluded = false; n_face = 3
                    end
                end

                -- ── Top face ──────────────────────────────────────────────
                if show_top then
                    local draw_tc = TileRegistry.COLOR[tid]
                    -- Underground only: fully-buried tiles at cam_layer drawn gray.
                    if not is_ow and occlusion_enabled and layer == cam_layer then
                        local ob1 = world:get_tile(q+1, r,   layer) or 0
                        local ob2 = world:get_tile(q-1, r,   layer) or 0
                        local ob3 = world:get_tile(q,   r+1, layer) or 0
                        local ob4 = world:get_tile(q,   r-1, layer) or 0
                        local ob5 = world:get_tile(q+1, r-1, layer) or 0
                        local ob6 = world:get_tile(q-1, r+1, layer) or 0
                        local ob7 = world:get_tile(q,   r,   layer+1) or 0
                        if ob1~=0 and not TR[ob1] and ob2~=0 and not TR[ob2]
                        and ob3~=0 and not TR[ob3] and ob4~=0 and not TR[ob4]
                        and ob5~=0 and not TR[ob5] and ob6~=0 and not TR[ob6]
                        and ob7~=0 and not TR[ob7] then
                            draw_tc = COL_OCCLUDED
                        end
                    end
                    love.graphics.setColor(draw_tc[1], draw_tc[2], draw_tc[3], alpha)
                    love.graphics.polygon("fill", v)
                    if point_in_hex(wx, wy, px, py - layer * LAYER_HEIGHT) then
                        nq, nr, nl, ntid = q, r, layer, tid
                        n_occluded = (draw_tc == COL_OCCLUDED)
                        n_face = 0
                    end
                end

                -- ── Selection outline (painter-order injection) ────────────
                if hover_q and hover_q == q and hover_r == r and hover_layer == layer then
                    local ir = player and face_in_reach(player, hover_q, hover_r, hover_layer, hover_face)
                    draw_outline(world, hover_q, hover_r, hover_layer, ir)
                end

                ::layer_next::
            end
            ::col_next::
        end

        -- Player and item drops injected at their r row (painter depth-correct)
        if player and player.r == r then
            player:draw_world(cam_layer)
        end
        for _, d in ipairs(ItemDrops.get_drops()) do
            if d.r == r then ItemDrops.draw_drop(d) end
        end
    end

    Effects.draw_particles()

    hover_q, hover_r, hover_layer, hover_tile = nq, nr, nl, ntid
    hover_occluded   = n_occluded
    hover_face       = n_face
    hover_in_reach   = nq ~= nil and player ~= nil
                       and face_in_reach(player, nq, nr, nl, n_face)
    cam:reset()
    love.graphics.setColor(1, 1, 1)
end

-- ── Public draw ────────────────────────────────────────────────────────────
function Renderer.draw(world, cam, center_layer, player)
    draw_tiles(world, cam, center_layer, player)
end

return Renderer
