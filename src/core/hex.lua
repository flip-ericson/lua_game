-- src/core/hex.lua
-- Hex grid math library — flat-top orientation, axial coordinates.
-- Pure functions only. No state. Require once, call from anywhere.
--
-- COORDINATE SYSTEMS
--   Axial  (q, r)    : q = column axis, r = diagonal row axis.
--   Cube   (x, y, z) : x + y + z = 0.  Used internally for rounding/distance.
--   Pixel  (px, py)  : screen-space pixels measured from a chosen origin point.
--
-- FLAT-TOP ORIENTATION
--   Two vertices point left and right; the q-axis runs horizontally.
--   Width  (tip-to-tip)    = 2 * SIZE   = 64 px at default size
--   Height (flat-to-flat)  = √3 * SIZE  ≈ 55 px at default size

local Hex = {}

local sqrt3 = math.sqrt(3)

-- Circumradius (pixels, center to corner).
-- At SIZE=32 the top face is 64 px wide — matches 64-px flat-top art tiles.
-- Change this before Phase 1.5 once the final art dimensions are locked in.
Hex.SIZE = 32

-- ── Direction vectors (1-based, flat-top CCW starting East) ──────────────
-- Used by hex_neighbors, hex_ring, and any code that needs explicit directions.
Hex.DIRECTIONS = {
    { dq =  1, dr =  0 },   -- 1: E
    { dq =  1, dr = -1 },   -- 2: NE
    { dq =  0, dr = -1 },   -- 3: NW
    { dq = -1, dr =  0 },   -- 4: W
    { dq = -1, dr =  1 },   -- 5: SW
    { dq =  0, dr =  1 },   -- 6: SE
}

-- ── Coordinate conversion ─────────────────────────────────────────────────

-- Axial → pixel   (returns the CENTER of the hex in screen pixels)
function Hex.hex_to_pixel(q, r)
    local px = Hex.SIZE * (3/2 * q)
    local py = Hex.SIZE * (sqrt3/2 * q + sqrt3 * r)
    return px, py
end

-- Pixel → axial   (rounds to the nearest integer hex)
function Hex.pixel_to_hex(px, py)
    local q = ( 2/3 * px) / Hex.SIZE
    local r = (-1/3 * px + sqrt3/3 * py) / Hex.SIZE
    return Hex._round_axial(q, r)
end

-- Axial → cube    (x + y + z = 0 guaranteed)
function Hex.axial_to_cube(q, r)
    local x = q
    local z = r
    local y = -x - z
    return x, y, z
end

-- Cube → axial
function Hex.cube_to_axial(x, y, z)
    return x, z
end

-- ── Rounding (internal) ───────────────────────────────────────────────────

-- Round fractional axial coords to the nearest hex.
-- Must go via cube to keep the x+y+z=0 constraint intact.
function Hex._round_axial(q, r)
    local x = q
    local z = r
    local y = -x - z

    local rx = math.floor(x + 0.5)
    local ry = math.floor(y + 0.5)
    local rz = math.floor(z + 0.5)

    -- Whichever component had the biggest rounding error gets corrected.
    local dx = math.abs(rx - x)
    local dy = math.abs(ry - y)
    local dz = math.abs(rz - z)

    if dx > dy and dx > dz then
        rx = -ry - rz
    elseif dy > dz then
        ry = -rx - rz
    else
        rz = -rx - ry
    end

    return rx, rz   -- axial: q=cube_x, r=cube_z
end

-- ── Neighbors ─────────────────────────────────────────────────────────────

-- Returns array[6] of {q, r} tables — the 6 adjacent hexes in direction order.
function Hex.hex_neighbors(q, r)
    local n = {}
    for i, d in ipairs(Hex.DIRECTIONS) do
        n[i] = { q = q + d.dq, r = r + d.dr }
    end
    return n
end

-- ── Distance ──────────────────────────────────────────────────────────────

-- Integer step-distance between two axial coordinates.
function Hex.hex_distance(q1, r1, q2, r2)
    local dq = q2 - q1
    local dr = r2 - r1
    return (math.abs(dq) + math.abs(dq + dr) + math.abs(dr)) / 2
end

-- ── Ring ──────────────────────────────────────────────────────────────────

-- All hexes at EXACTLY `radius` steps from (q, r).
-- Returns array of {q, r} tables.
--   radius 0 → 1 entry  (the center itself)
--   radius N → 6*N entries
function Hex.hex_ring(q, r, radius)
    if radius < 0 then return {} end
    if radius == 0 then return { { q = q, r = r } } end

    local results = {}

    -- Start at the hex `radius` steps SW from center (direction 5 = SW).
    local cq = q + Hex.DIRECTIONS[5].dq * radius
    local cr = r + Hex.DIRECTIONS[5].dr * radius

    -- Walk 6 legs, each `radius` steps, in direction order 1→6.
    for side = 1, 6 do
        local d = Hex.DIRECTIONS[side]
        for _ = 1, radius do
            results[#results + 1] = { q = cq, r = cr }
            cq = cq + d.dq
            cr = cr + d.dr
        end
    end

    return results
end

-- ── In range ──────────────────────────────────────────────────────────────

-- All hexes within `radius` steps from (q, r), including the center.
-- Returns array of {q, r} tables.
--   radius 0 → 1 entry
--   radius N → 3*N*N + 3*N + 1 entries
function Hex.hex_in_range(q, r, radius)
    if radius < 0 then return {} end

    local results = {}

    -- Iterate cube-coordinate offsets; convert each to axial.
    for dx = -radius, radius do
        local dy_min = math.max(-radius, -dx - radius)
        local dy_max = math.min( radius, -dx + radius)
        for dy = dy_min, dy_max do
            local dz = -dx - dy
            -- cube offset (dx, dy, dz) → axial offset (dx, dz)
            results[#results + 1] = { q = q + dx, r = r + dz }
        end
    end

    return results
end

return Hex
