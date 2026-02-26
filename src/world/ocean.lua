-- src/world/ocean.lua
-- Phase 2.7 — Ocean flood-fill pre-pass.
-- Phase 2.8 — Beach zone expansion (baked into BFS, no per-chunk noise calls).
--
-- Public API:
--   Ocean.build(world_radius, sea_level, beach_radius) → is_ocean(q, r), is_beach(q, r)
--
-- Multi-source BFS seeded from every border hex (the ring at dist == world_radius).
-- Expands inward through any hex where surface_layer(q, r) < sea_level.
-- Stops dead at land tiles — island shape is irrelevant, correctness is guaranteed.
-- Inland depressions not reachable from the border are skipped (future fresh water pass).
--
-- After the ocean BFS, a second wave-front BFS expands beach_radius steps from
-- every ocean-land boundary cell, marking land cells within that distance as beach.
-- This replaces the per-column is_beach() noise scan (was ~37 surface_layer calls
-- per land column; now an O(1) array lookup during chunk generation).
--
-- Returns two closures:
--   is_ocean(q, r) → bool   (ocean_cols value == 1)
--   is_beach(q, r) → bool   (ocean_cols value == 2; land within beach_radius of ocean)
-- Runs once at startup during the loading screen blocking window.
--
-- MEMORY:
--   ocean_cols: uint8_t[STRIDE²]   — 1 byte/slot  × ~100 M slots = ~100 MB
--   queue:      int32_t[total_hex] — 4 bytes/slot × ~75 M slots  = ~300 MB
--   bqueue:     int32_t[beach_max] — 4 bytes/slot × ~3 M slots   = ~12 MB
--   Each hex stored once as a single encoded int32 (not a q+r Lua-value pair).
--   Lua table for 50 M+ entries ≈ 1.6 GB → OOM; FFI avoids that entirely.

local ffi      = require("ffi")
local Worldgen = require("src.world.worldgen")

local Ocean = {}

-- Axial hex neighbor offsets.
local NEIGHBORS = { {1,0},{-1,0},{0,1},{0,-1},{1,-1},{-1,1} }

-- Ring-walk directions: counterclockwise from east corner (world_radius, 0).
local RING_DIRS = { {-1,1},{-1,0},{0,-1},{1,-1},{1,0},{0,1} }

local function hex_dist(q, r)
    return math.max(math.abs(q), math.abs(r), math.abs(q + r))
end

function Ocean.build(world_radius, sea_level, beach_radius)
    beach_radius = beach_radius or 3
    local t0 = love.timer.getTime()

    -- Encoding: flatten (q, r) → single integer index.
    -- q and r each range in [-world_radius, world_radius].
    -- STRIDE × STRIDE covers all possible encoded values.
    local STRIDE = 2 * world_radius + 2
    local OFFSET = world_radius + 1

    local function encode(q, r)
        return (q + OFFSET) * STRIDE + (r + OFFSET)
    end

    local function decode(key)
        local q = math.floor(key / STRIDE) - OFFSET
        local r = (key % STRIDE) - OFFSET
        return q, r
    end

    -- FFI visited / zone array: 1 byte per slot, zero-initialised by ffi.new.
    --   0 = land (unvisited)
    --   1 = ocean (BFS-connected to world border, surface < sea_level)
    --   2 = beach (land within beach_radius steps of ocean)
    local ocean_cols = ffi.new("uint8_t[?]", STRIDE * STRIDE)

    -- FFI ocean queue: 4 bytes per slot, stores encoded (q,r) as a single int32.
    -- Worst-case capacity = every hex in the world (each enqueued at most once).
    local total_hexes = 3 * world_radius * world_radius + 3 * world_radius + 1
    local queue = ffi.new("int32_t[?]", total_hexes)
    local head  = 0   -- 0-indexed (C array)
    local tail  = 0
    local ocean_count = 0

    -- FFI beach queue: separate array for the beach-expansion wave-front BFS.
    -- Upper bound: coastline is at most ~6 * world_radius hexes per ring.
    -- beach_radius rings deep → generous allocation covers all presets.
    local beach_max = math.max(3000000, 20 * world_radius * beach_radius)
    local bqueue = ffi.new("int32_t[?]", beach_max)
    local btail  = 0   -- beach queue only appends; bhead tracks wave-front start

    -- ── Seed BFS from border ring + sanity check ──────────────────────────
    local border_fails = 0
    local bq, br = world_radius, 0   -- start at east corner

    for i = 1, 6 do
        local dq, dr = RING_DIRS[i][1], RING_DIRS[i][2]
        for _ = 1, world_radius do
            if Worldgen.surface_layer(bq, br) < sea_level then
                local key = encode(bq, br)
                if ocean_cols[key] == 0 then
                    ocean_cols[key] = 1
                    ocean_count     = ocean_count + 1
                    queue[tail]     = key
                    tail            = tail + 1
                end
            else
                border_fails = border_fails + 1
            end
            bq = bq + dq
            br = br + dr
        end
    end

    if border_fails > 0 then
        print(string.format(
            "[Ocean] WARNING: %d / %d border hexes above sea level — island may extend to world edge.",
            border_fails, 6 * world_radius))
    end

    -- ── Ocean BFS ─────────────────────────────────────────────────────────
    -- Simultaneously seeds the beach queue: any land cell found as a
    -- neighbor of an ocean cell is distance-1 from ocean → beach candidate.
    while head < tail do
        local cq, cr = decode(tonumber(queue[head]))
        head = head + 1

        for _, d in ipairs(NEIGHBORS) do
            local nq = cq + d[1]
            local nr = cr + d[2]

            if hex_dist(nq, nr) <= world_radius then
                local key = encode(nq, nr)
                if ocean_cols[key] == 0 then
                    if Worldgen.surface_layer(nq, nr) < sea_level then
                        -- Ocean cell: continue BFS expansion.
                        ocean_cols[key] = 1
                        ocean_count     = ocean_count + 1
                        queue[tail]     = key
                        tail            = tail + 1
                    else
                        -- Land cell adjacent to ocean: distance-1 beach seed.
                        ocean_cols[key] = 2
                        bqueue[btail]   = key
                        btail           = btail + 1
                    end
                end
            end
        end
    end

    -- ── Beach expansion ───────────────────────────────────────────────────
    -- Wave-front BFS from the distance-1 seeds collected above.
    -- Runs (beach_radius - 1) more steps to cover the full beach band.
    local bhead = 0
    for _ = 2, beach_radius do
        local wave_end = btail
        for bi = bhead, wave_end - 1 do
            local cq2, cr2 = decode(tonumber(bqueue[bi]))
            for _, d in ipairs(NEIGHBORS) do
                local nq2 = cq2 + d[1]
                local nr2 = cr2 + d[2]
                if hex_dist(nq2, nr2) <= world_radius then
                    local key2 = encode(nq2, nr2)
                    if ocean_cols[key2] == 0 then   -- unvisited land
                        ocean_cols[key2] = 2
                        bqueue[btail]    = key2
                        btail            = btail + 1
                    end
                end
            end
        end
        bhead = wave_end
    end

    -- ── Debug report ──────────────────────────────────────────────────────
    local total = 3 * world_radius * world_radius + 3 * world_radius + 1
    print(string.format(
        "[Ocean] BFS: %.2f s — %d / %d hexes = %.1f %% ocean  |  %d beach hexes",
        love.timer.getTime() - t0, ocean_count, total,
        100 * ocean_count / total, btail))

    -- ── Return lookup closures ────────────────────────────────────────────
    -- is_ocean: true for BFS-confirmed ocean cells (value 1).
    -- is_beach: true for land cells within beach_radius of ocean (value 2).
    --           Fast O(1) array lookup — no noise calls during chunk gen.
    return
        function(q, r) return ocean_cols[encode(q, r)] == 1 end,
        function(q, r) return ocean_cols[encode(q, r)] == 2 end
end

return Ocean
