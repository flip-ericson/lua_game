-- tests/test_hex.lua
-- Unit tests for src/core/hex.lua
-- Called from gameloop.lua during Phase 1. Remove the call once all pass.
--
-- Returns a results table:
--   { passed=N, failed=N, total=N, failures={ "message", ... } }

local Hex = require("src.core.hex")

local results = { passed = 0, failed = 0, total = 0, failures = {} }

-- ── Assertion helpers ─────────────────────────────────────────────────────

local function pass(label)
    results.passed = results.passed + 1
    results.total  = results.total  + 1
end

local function fail(label, msg)
    results.failed = results.failed + 1
    results.total  = results.total  + 1
    results.failures[#results.failures + 1] =
        string.format("FAIL  [%s]  %s", label, msg)
end

local function eq(label, got, expected)
    if got == expected then
        pass(label)
    else
        fail(label, string.format("got %s  expected %s",
            tostring(got), tostring(expected)))
    end
end

local function near(label, got, expected, tol)
    tol = tol or 0.001
    if math.abs(got - expected) <= tol then
        pass(label)
    else
        fail(label, string.format("got %.5f  expected %.5f  tol %.5f",
            got, expected, tol))
    end
end

-- ── axial_to_cube / cube_to_axial ─────────────────────────────────────────

do
    -- Origin
    local x, y, z = Hex.axial_to_cube(0, 0)
    eq("axial_to_cube(0,0) x", x,  0)
    eq("axial_to_cube(0,0) y", y,  0)
    eq("axial_to_cube(0,0) z", z,  0)

    -- Known hex
    x, y, z = Hex.axial_to_cube(2, -1)
    eq("axial_to_cube(2,-1) x",    x,  2)
    eq("axial_to_cube(2,-1) y",    y, -1)
    eq("axial_to_cube(2,-1) z",    z, -1)
    eq("axial_to_cube sum=0",  x+y+z, 0)

    -- cube → axial round-trip
    local q, r = Hex.cube_to_axial(3, -5, 2)
    eq("cube_to_axial q", q, 3)
    eq("cube_to_axial r", r, 2)

    -- Round-trip: axial → cube → axial
    local q0, r0 = 7, -3
    x, y, z = Hex.axial_to_cube(q0, r0)
    q, r = Hex.cube_to_axial(x, y, z)
    eq("round-trip axial→cube→axial q", q, q0)
    eq("round-trip axial→cube→axial r", r, r0)
end

-- ── hex_to_pixel ──────────────────────────────────────────────────────────

do
    local S = Hex.SIZE   -- 32 by default

    -- Origin hex → pixel origin
    local px, py = Hex.hex_to_pixel(0, 0)
    near("hex_to_pixel(0,0) px", px, 0)
    near("hex_to_pixel(0,0) py", py, 0)

    -- One step East (q=1, r=0): x = S*(3/2), y = S*(√3/2)
    px, py = Hex.hex_to_pixel(1, 0)
    near("hex_to_pixel(1,0) px", px,  S * 1.5)
    near("hex_to_pixel(1,0) py", py,  S * math.sqrt(3) / 2)

    -- One step SE (q=0, r=1): x=0, y = S*√3
    px, py = Hex.hex_to_pixel(0, 1)
    near("hex_to_pixel(0,1) px", px, 0)
    near("hex_to_pixel(0,1) py", py, S * math.sqrt(3))
end

-- ── pixel_to_hex ──────────────────────────────────────────────────────────

do
    local S = Hex.SIZE

    -- Pixel at exact hex center → same hex
    local function roundtrip(q, r, label)
        local px, py = Hex.hex_to_pixel(q, r)
        local gq, gr = Hex.pixel_to_hex(px, py)
        eq(label .. " q", gq, q)
        eq(label .. " r", gr, r)
    end

    roundtrip( 0,  0, "pixel_to_hex roundtrip (0,0)")
    roundtrip( 3, -2, "pixel_to_hex roundtrip (3,-2)")
    roundtrip(-4,  1, "pixel_to_hex roundtrip (-4,1)")
    roundtrip( 0,  5, "pixel_to_hex roundtrip (0,5)")
    roundtrip(-2, -3, "pixel_to_hex roundtrip (-2,-3)")

    -- Pixel slightly off-center still rounds to the right hex
    local px, py = Hex.hex_to_pixel(2, 1)
    local gq, gr = Hex.pixel_to_hex(px + 4, py - 3)   -- 4 px nudge
    eq("pixel_to_hex nudged q", gq, 2)
    eq("pixel_to_hex nudged r", gr, 1)
end

-- ── hex_neighbors ─────────────────────────────────────────────────────────

do
    local n = Hex.hex_neighbors(0, 0)

    -- Exactly 6 neighbors
    eq("hex_neighbors count", #n, 6)

    -- Every neighbor is at distance 1
    for i, nb in ipairs(n) do
        eq("hex_neighbors[" .. i .. "] distance",
            Hex.hex_distance(0, 0, nb.q, nb.r), 1)
    end

    -- No duplicates
    local seen = {}
    for _, nb in ipairs(n) do
        local key = nb.q .. "," .. nb.r
        eq("hex_neighbors no dup " .. key, seen[key], nil)
        seen[key] = true
    end

    -- Neighbor of a non-origin hex
    local n2 = Hex.hex_neighbors(3, -1)
    eq("hex_neighbors off-origin count", #n2, 6)
    for i, nb in ipairs(n2) do
        eq("hex_neighbors off-origin[" .. i .. "] dist",
            Hex.hex_distance(3, -1, nb.q, nb.r), 1)
    end
end

-- ── hex_distance ──────────────────────────────────────────────────────────

do
    -- Same hex → 0
    eq("hex_distance same",          Hex.hex_distance(0,0,  0, 0), 0)
    eq("hex_distance same non-origin", Hex.hex_distance(3,-2, 3,-2), 0)

    -- Adjacent hexes → 1
    eq("hex_distance E",  Hex.hex_distance(0,0,  1, 0), 1)
    eq("hex_distance NE", Hex.hex_distance(0,0,  1,-1), 1)
    eq("hex_distance NW", Hex.hex_distance(0,0,  0,-1), 1)
    eq("hex_distance W",  Hex.hex_distance(0,0, -1, 0), 1)
    eq("hex_distance SW", Hex.hex_distance(0,0, -1, 1), 1)
    eq("hex_distance SE", Hex.hex_distance(0,0,  0, 1), 1)

    -- Known larger distances
    eq("hex_distance 2",  Hex.hex_distance(0,0,  2, 0), 2)
    eq("hex_distance 3",  Hex.hex_distance(0,0,  0, 3), 3)
    eq("hex_distance 5",  Hex.hex_distance(0,0,  3,-2), 3)  -- (|3|+|3-2|+|2|)/2 = (3+1+2)/2=3

    -- Symmetry: distance(A,B) == distance(B,A)
    eq("hex_distance symmetric",
        Hex.hex_distance(2,-3, -1,4),
        Hex.hex_distance(-1,4,  2,-3))
end

-- ── hex_ring ──────────────────────────────────────────────────────────────

do
    -- Radius 0 → exactly the center
    local r0 = Hex.hex_ring(0, 0, 0)
    eq("hex_ring(0) count", #r0, 1)
    eq("hex_ring(0) q",     r0[1].q, 0)
    eq("hex_ring(0) r",     r0[1].r, 0)

    -- Radius 1 → 6 hexes, all at distance 1
    local r1 = Hex.hex_ring(0, 0, 1)
    eq("hex_ring(1) count", #r1, 6)
    for i, h in ipairs(r1) do
        eq("hex_ring(1)[" .. i .. "] dist", Hex.hex_distance(0,0, h.q, h.r), 1)
    end

    -- Radius 2 → 12 hexes, all at distance 2
    local r2 = Hex.hex_ring(0, 0, 2)
    eq("hex_ring(2) count", #r2, 12)
    for i, h in ipairs(r2) do
        eq("hex_ring(2)[" .. i .. "] dist", Hex.hex_distance(0,0, h.q, h.r), 2)
    end

    -- Radius 3 → 18 hexes
    eq("hex_ring(3) count", #Hex.hex_ring(0,0,3), 18)

    -- Off-origin ring: all hexes still at correct distance from center
    local center_q, center_r = 4, -2
    local roff = Hex.hex_ring(center_q, center_r, 3)
    eq("hex_ring off-origin count", #roff, 18)
    for i, h in ipairs(roff) do
        eq("hex_ring off-origin[" .. i .. "] dist",
            Hex.hex_distance(center_q, center_r, h.q, h.r), 3)
    end

    -- No duplicates in ring(2)
    local seen = {}
    for _, h in ipairs(r2) do
        local key = h.q .. "," .. h.r
        eq("hex_ring(2) no dup " .. key, seen[key], nil)
        seen[key] = true
    end
end

-- ── hex_in_range ──────────────────────────────────────────────────────────

do
    -- Radius 0 → 1 hex (the center)
    local h0 = Hex.hex_in_range(0, 0, 0)
    eq("hex_in_range(0) count", #h0, 1)

    -- Radius 1 → 7 hexes
    local h1 = Hex.hex_in_range(0, 0, 1)
    eq("hex_in_range(1) count", #h1, 7)

    -- Radius 2 → 19 hexes
    local h2 = Hex.hex_in_range(0, 0, 2)
    eq("hex_in_range(2) count", #h2, 19)

    -- Radius 3 → 37 hexes
    local h3 = Hex.hex_in_range(0, 0, 3)
    eq("hex_in_range(3) count", #h3, 37)

    -- All hexes in range(2) are at distance ≤ 2
    for i, h in ipairs(h2) do
        local d = Hex.hex_distance(0, 0, h.q, h.r)
        if d > 2 then
            fail("hex_in_range(2)[" .. i .. "] dist",
                string.format("got %d  expected <=2", d))
        else
            pass("hex_in_range(2)[" .. i .. "] dist ok")
        end
    end

    -- All 3 rings are subsets of range(3): every ring hex is at distance ≤ 3
    for ring = 0, 3 do
        for i, h in ipairs(Hex.hex_ring(0, 0, ring)) do
            local d = Hex.hex_distance(0, 0, h.q, h.r)
            if d > 3 then
                fail("ring" .. ring .. "_in_range3[" .. i .. "]",
                    "distance " .. d .. " > radius 3")
            else
                pass("ring" .. ring .. "_in_range3 hex ok")
            end
        end
    end

    -- Center hex always present in every in_range call
    local found_center = false
    for _, h in ipairs(h3) do
        if h.q == 0 and h.r == 0 then found_center = true; break end
    end
    eq("hex_in_range center always present", found_center, true)
end

-- ── Summary ───────────────────────────────────────────────────────────────

results.summary = string.format(
    "hex.lua tests: %d passed, %d failed, %d total",
    results.passed, results.failed, results.total
)

return results
