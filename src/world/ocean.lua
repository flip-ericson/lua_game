-- src/world/ocean.lua
-- Phase 2.7 — Ocean flood-fill pre-pass.
--
-- Public API:
--   Ocean.build(world_radius, sea_level) → is_ocean(q, r)
--
-- Multi-source BFS seeded from every border hex (the ring at dist == world_radius).
-- Expands inward through any hex where surface_layer(q, r) < sea_level.
-- Stops dead at land tiles — island shape is irrelevant, correctness is guaranteed.
-- Inland depressions not reachable from the border are skipped (future fresh water pass).
--
-- Returns a closure is_ocean(q, r) → bool.
-- Runs once at startup during the loading screen blocking window.

local Worldgen = require("src.world.worldgen")

local Ocean = {}

-- Axial hex neighbor offsets.
local NEIGHBORS = { {1,0},{-1,0},{0,1},{0,-1},{1,-1},{-1,1} }

-- Ring-walk directions: counterclockwise from east corner (world_radius, 0).
local RING_DIRS = { {-1,1},{-1,0},{0,-1},{1,-1},{1,0},{0,1} }

local function hex_dist(q, r)
    return math.max(math.abs(q), math.abs(r), math.abs(q + r))
end

function Ocean.build(world_radius, sea_level)
    local t0 = love.timer.getTime()

    -- Flat integer key: (q + OFFSET) * STRIDE + (r + OFFSET).
    -- q and r each range in [-world_radius, world_radius].
    local STRIDE = 2 * world_radius + 2
    local OFFSET = world_radius + 1

    local function encode(q, r)
        return (q + OFFSET) * STRIDE + (r + OFFSET)
    end

    -- ocean_cols: integer-keyed visited set (also the final result).
    local ocean_cols = {}

    -- Queue stores q, r alternately to avoid per-entry table allocation.
    local queue = {}
    local head  = 1
    local tail  = 1

    -- ── Seed BFS from border ring + sanity check ──────────────────────────
    local border_fails = 0
    local bq, br = world_radius, 0   -- start at east corner

    for i = 1, 6 do
        local dq, dr = RING_DIRS[i][1], RING_DIRS[i][2]
        for _ = 1, world_radius do
            if Worldgen.surface_layer(bq, br) < sea_level then
                local key = encode(bq, br)
                if not ocean_cols[key] then
                    ocean_cols[key] = true
                    queue[tail]     = bq
                    queue[tail + 1] = br
                    tail            = tail + 2
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

    -- ── BFS ───────────────────────────────────────────────────────────────
    while head < tail do
        local cq = queue[head]
        local cr = queue[head + 1]
        head = head + 2

        for _, d in ipairs(NEIGHBORS) do
            local nq = cq + d[1]
            local nr = cr + d[2]

            if hex_dist(nq, nr) <= world_radius then
                local key = encode(nq, nr)
                if not ocean_cols[key] then
                    if Worldgen.surface_layer(nq, nr) < sea_level then
                        ocean_cols[key] = true
                        queue[tail]     = nq
                        queue[tail + 1] = nr
                        tail            = tail + 2
                    end
                end
            end
        end
    end

    -- ── Debug report ──────────────────────────────────────────────────────
    local ocean_count = 0
    for _ in pairs(ocean_cols) do ocean_count = ocean_count + 1 end
    local total = 3 * world_radius * world_radius + 3 * world_radius + 1
    print(string.format(
        "[Ocean] BFS: %.2f s — %d / %d hexes = %.1f %% ocean",
        love.timer.getTime() - t0, ocean_count, total,
        100 * ocean_count / total))

    -- ── Return lookup closure ─────────────────────────────────────────────
    return function(q, r)
        return ocean_cols[encode(q, r)] == true
    end
end

return Ocean
