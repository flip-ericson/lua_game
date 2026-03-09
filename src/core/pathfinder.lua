-- src/core/pathfinder.lua
-- Hex A* pathfinder for mob navigation.
--
-- Step 2: flat terrain only — neighbors searched at the same layer.
-- Step 3: extend neighbor expansion to ±1 layer (vertical navigation).
--
-- find_path(world, sq,sr,sl, tq,tr,tl, max_nodes)
--   Returns an array of {q, r, layer} steps from start to target,
--   NOT including the start position itself.
--   Returns nil if no path exists or the node budget is exceeded.
--
-- line_of_sight(world, x1,y1, x2,y2, layer, half_width)
--   Returns true if a corridor of width 2×half_width is fully clear.
--
-- string_pull(world, path, ox,oy, start_layer, half_width)
--   Reduces an A* path to the minimum set of visible waypoints.

local TileRegistry = require("src.world.tile_registry")
local Hex          = require("src.core.hex")

local SOLID = TileRegistry.SOLID   -- flat array; by-ref, safe to cache

local Pathfinder = {}

-- 6 axial neighbor directions (flat-top hex grid).
local NEIGHBORS = {
    { 1,  0}, { 0,  1}, {-1,  1},
    {-1,  0}, { 0, -1}, { 1, -1},
}

-- Admissible heuristic: axial hex distance.
local function h(aq, ar, bq, br)
    return math.max(math.abs(bq - aq), math.abs(br - ar), math.abs((bq + br) - (aq + ar)))
end

-- A standing position is walkable when:
--   • the floor tile (at layer)   is solid  — something to stand on
--   • the body tile  (at layer+1) is not solid — mob can occupy it
local function walkable(world, q, r, layer)
    local floor = world:get_tile(q, r, layer)     or 0
    local body  = world:get_tile(q, r, layer + 1) or 0
    return SOLID[floor] and not SOLID[body]
end

-- ── Line of sight ─────────────────────────────────────────────────────────
-- Checks if a straight corridor from (x1,y1) to (x2,y2) is passable at
-- the given floor layer.  Samples the centre line and two parallel lines
-- offset ±half_width (entity inradius) perpendicular to the direction.
-- Returns true only if every sampled hex is walkable.
function Pathfinder.line_of_sight(world, x1, y1, x2, y2, layer, half_width)
    local dx   = x2 - x1
    local dy   = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then return true end

    -- Sample every half-hex — safe: can't miss a 1-tile-wide wall.
    local interval = Hex.SIZE * 0.5
    local steps    = math.max(1, math.ceil(dist / interval))

    local fwd_x = dx / dist   -- unit forward
    local fwd_y = dy / dist
    local perp_x = -fwd_y    -- unit perpendicular (90° CCW)
    local perp_y =  fwd_x

    -- Sample along centre and both corridor edges.
    local offsets = { 0, half_width, -half_width }
    for _, off in ipairs(offsets) do
        local ox = perp_x * off
        local oy = perp_y * off
        for i = 0, steps do
            local t  = i / steps
            local wx = x1 + dx * t + ox
            local wy = y1 + dy * t + oy
            local q, r = Hex.pixel_to_hex(wx, wy)
            if not walkable(world, q, r, layer) then
                return false
            end
        end
    end
    return true
end

-- ── String pulling ─────────────────────────────────────────────────────────
-- Reduces an A* path to the minimum set of visible waypoints.
-- Layer-change nodes are always preserved (mandatory elevation steps).
-- ox, oy      : mob's current pixel position (first anchor).
-- start_layer : mob's current floor layer.
-- half_width  : corridor half-width passed through to line_of_sight.
function Pathfinder.string_pull(world, path, ox, oy, start_layer, half_width)
    if not path or #path == 0 then return path end

    local result = {}
    local ax, ay, al = ox, oy, start_layer
    local i = 1

    while i <= #path do
        local node = path[i]
        if node.layer ~= al then
            -- Elevation change: mandatory waypoint, cannot skip.
            result[#result + 1] = node
            ax, ay = Hex.hex_to_pixel(node.q, node.r)
            al = node.layer
            i  = i + 1
        else
            -- Greedy: find the farthest node on the same layer with clear LoS.
            -- Break at the first failure (conservative but correct for A* paths).
            local best = i
            for j = i, #path do
                if path[j].layer ~= al then break end
                local jx, jy = Hex.hex_to_pixel(path[j].q, path[j].r)
                if Pathfinder.line_of_sight(world, ax, ay, jx, jy, al, half_width) then
                    best = j
                else
                    break
                end
            end
            local bn = path[best]
            result[#result + 1] = bn
            ax, ay = Hex.hex_to_pixel(bn.q, bn.r)
            i = best + 1
        end
    end

    return result
end

-- ── Surface layer finder ────────────────────────────────────────────────────
-- Returns the nearest walkable floor layer to near_layer at (q, r), searching
-- outward ±8 layers.  Returns nil if none found within that range.
function Pathfinder.surface_layer(world, q, r, near_layer)
    if walkable(world, q, r, near_layer) then return near_layer end
    for delta = 1, 8 do
        local l_up = near_layer + delta
        if l_up >= 0 and walkable(world, q, r, l_up) then return l_up end
        local l_dn = near_layer - delta
        if l_dn >= 0 and walkable(world, q, r, l_dn) then return l_dn end
    end
    return nil
end

-- ── Public API ─────────────────────────────────────────────────────────────

function Pathfinder.find_path(world, sq, sr, sl, tq, tr, tl, max_nodes)
    max_nodes = max_nodes or 200

    local start_key  = sq .. "," .. sr .. "," .. sl
    local target_key = tq .. "," .. tr .. "," .. tl

    -- Trivial case: already there.
    if start_key == target_key then return {} end

    -- Bail early if the target itself is not walkable.
    if not walkable(world, tq, tr, tl) then return nil end

    -- ── A* data structures ────────────────────────────────────────────────
    -- open: sorted array of {key, f, g}, ascending f (front = lowest cost).
    -- closed: set of processed keys.
    -- came_from[key] = parent_key  (predecessor in the best known path).
    -- node_data[key] = {q, r, layer}  (coordinates for each discovered node).
    -- g_score[key]   = best known cost from start to this node.

    local open      = { {key = start_key, f = h(sq, sr, tq, tr), g = 0} }
    local closed    = {}
    local came_from = {}
    local g_score   = { [start_key] = 0 }
    local node_data = { [start_key] = {q = sq, r = sr, layer = sl} }

    local expanded = 0

    while #open > 0 do
        -- Pop the node with the lowest f (always open[1] — list is sorted).
        local cur  = table.remove(open, 1)
        local ckey = cur.key

        -- Skip if already processed via a cheaper path.
        if closed[ckey] then goto continue_loop end
        closed[ckey] = true

        -- ── Goal reached: reconstruct path ────────────────────────────────
        if ckey == target_key then
            local path = {}
            local k = ckey
            while k ~= start_key do
                table.insert(path, 1, node_data[k])
                k = came_from[k]
            end
            return path
        end

        -- ── Budget guard ──────────────────────────────────────────────────
        expanded = expanded + 1
        if expanded > max_nodes then return nil end

        -- ── Expand neighbors ──────────────────────────────────────────────
        local cdata = node_data[ckey]
        local cg    = cur.g
        local cl    = cdata.layer

        for _, nb in ipairs(NEIGHBORS) do
            local nq = cdata.q + nb[1]
            local nr = cdata.r + nb[2]

            -- Step 3: same layer (delta=0), step down (delta=-1), step up (delta=+1).
            -- Single-layer moves only; fall physics handles visual descent.
            for delta = -1, 1 do
                local nl = cl + delta
                if nl >= 0 then
                    local nk = nq .. "," .. nr .. "," .. nl

                    if not closed[nk] and walkable(world, nq, nr, nl) then
                        local g = cg + 1   -- uniform edge cost (one hex step)
                        if not g_score[nk] or g < g_score[nk] then
                            g_score[nk]   = g
                            came_from[nk] = ckey
                            node_data[nk] = {q = nq, r = nr, layer = nl}

                            local f = g + h(nq, nr, tq, tr)

                            -- Insert into open maintaining ascending f order.
                            local inserted = false
                            for i = 1, #open do
                                if f < open[i].f then
                                    table.insert(open, i, {key = nk, f = f, g = g})
                                    inserted = true
                                    break
                                end
                            end
                            if not inserted then
                                open[#open + 1] = {key = nk, f = f, g = g}
                            end
                        end
                    end
                end
            end
        end

        ::continue_loop::
    end

    return nil  -- no path found within budget
end

return Pathfinder
