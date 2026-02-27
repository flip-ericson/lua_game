-- src/world/world.lua
-- Manages the in-memory cache of ChunkColumns and exposes the two
-- hot-path functions the rest of the engine calls millions of times:
--
--   world:get_tile(q, r, layer)          → tile ID (0 = air)
--   world:set_tile(q, r, layer, tile_id) → void
--
-- For batch rendering, grab a column reference once and read directly:
--   local col = world:get_column(cq, cr, cl)
--   local id  = col:get(q_local, r_local, layer_local)
-- This skips the string-key cache lookup in the inner draw loop.
--
-- WORLD SHAPE
--   Hexagonal boundary: all hexes where hex-distance from (0,0) ≤ world_radius (5000).
--   ~75 million hex columns; equidistant edge in all 6 hex directions.
--
-- CHUNK GEOMETRY
--   Horizontal: 32 × 32 hex footprint  (CHUNK_SIZE  = 32)
--   Vertical:   8 layers per chunk      (CHUNK_DEPTH = 8)
--   Each chunk = 8,192 tile slots, ~16 KB.
--
-- LOADING STRATEGY
--   preload_near(q, r, layer) is called each frame with the camera focus.
--   It keeps 7 horizontal columns (focus + 6 hex neighbours) × 3 vertical
--   slices loaded at all times — 21 columns, ~336 KB ceiling.
--   Columns beyond MAX_COLUMNS are evicted LRU (save-on-evict in Phase 12).
--
-- GAME TIME
--   1 real second = 1 game minute.  world.game_time accumulates dt each
--   update and is the reference clock for all tick_list entries.

local ChunkColumn = require("src.world.chunk")
local WorldgenCfg = require("config.worldgen")
local Hex         = require("src.core.hex")
local Worldgen    = require("src.world.worldgen")
local Ocean       = require("src.world.ocean")

local CHUNK_SIZE    = ChunkColumn.SIZE    -- 32
local CHUNK_DEPTH   = ChunkColumn.DEPTH   -- 8
local WORLD_DEPTH   = WorldgenCfg.world_depth
local WORLD_RADIUS  = WorldgenCfg.world_radius  -- hex-distance; boundary is a regular hexagon
local MAX_COL_LAYER = math.floor(WORLD_DEPTH / CHUNK_DEPTH) - 1   -- 127
local MAX_COLUMNS   = 128   -- LRU eviction ceiling

local World = {}
World.__index = World

-- ── Constructor ───────────────────────────────────────────────────────────

function World.new()
    local is_ocean, is_beach = Ocean.build(
        WORLD_RADIUS,
        WorldgenCfg.sea_level,
        WorldgenCfg.island.beach_radius)
    return setmetatable({
        _columns  = {},   -- key → ChunkColumn
        _count    = 0,
        game_time = 0,    -- game minutes elapsed (1 real second = 1 game minute)
        _is_ocean = is_ocean,
        _is_beach = is_beach,  -- O(1) lookup; replaces Worldgen.is_beach noise scan
    }, World)
end

-- ── Coordinate helpers ────────────────────────────────────────────────────

local function col_coord_h(v)   return math.floor(v / CHUNK_SIZE)  end
local function local_coord_h(v) return v % CHUNK_SIZE               end
local function col_coord_v(v)   return math.floor(v / CHUNK_DEPTH) end
local function local_coord_v(v) return v % CHUNK_DEPTH              end

-- ── Game time ─────────────────────────────────────────────────────────────

function World:update(dt)
    self.game_time = self.game_time + dt
end

-- ── Column cache ──────────────────────────────────────────────────────────

function World:get_column(col_q, col_r, col_layer)
    local key = ChunkColumn.key(col_q, col_r, col_layer)
    local col = self._columns[key]

    if col then
        col.last_used = love.timer.getTime()
        return col
    end

    col              = self:_load_or_generate(col_q, col_r, col_layer)
    col.last_used    = love.timer.getTime()
    self._columns[key] = col
    self._count        = self._count + 1

    if self._count > MAX_COLUMNS then
        self:_evict_lru()
    end

    return col
end

-- ── get_tile / set_tile ───────────────────────────────────────────────────

-- Hex-distance out-of-bounds check (integer only, no sqrt).
-- The world boundary is a regular hexagon of radius WORLD_RADIUS.
local function out_of_bounds(q, r)
    return math.max(math.abs(q), math.abs(q + r), math.abs(r)) > WORLD_RADIUS
end

function World:get_tile(q, r, layer)
    if layer < 0 or layer >= WORLD_DEPTH then return 0 end
    if out_of_bounds(q, r) then return 0 end
    local col = self:get_column(col_coord_h(q), col_coord_h(r), col_coord_v(layer))
    return col:get(local_coord_h(q), local_coord_h(r), local_coord_v(layer))
end

function World:set_tile(q, r, layer, tile_id)
    if layer < 0 or layer >= WORLD_DEPTH then return end
    if out_of_bounds(q, r) then return end
    local col = self:get_column(col_coord_h(q), col_coord_h(r), col_coord_v(layer))
    col:set(local_coord_h(q), local_coord_h(r), local_coord_v(layer), tile_id)
end

-- ── Neighbourhood preloader ───────────────────────────────────────────────
-- Call once per frame. Keeps 7 × 3 = 21 columns warm in the cache.

function World:preload_near(q, r, layer)
    local cq = col_coord_h(q)
    local cr = col_coord_h(r)
    local cl = col_coord_v(layer)

    -- 7 horizontal positions: player column + 6 hex-direction neighbours.
    local positions = {{ cq = cq, cr = cr }}
    for _, d in ipairs(Hex.DIRECTIONS) do
        positions[#positions + 1] = { cq = cq + d.dq, cr = cr + d.dr }
    end

    -- 3 vertical slices per position.
    for _, pos in ipairs(positions) do
        for dl = -1, 1 do
            local target_cl = cl + dl
            if target_cl >= 0 and target_cl <= MAX_COL_LAYER then
                self:get_column(pos.cq, pos.cr, target_cl)
            end
        end
    end
end

-- ── How many columns are currently loaded ─────────────────────────────────

function World:loaded_count()
    return self._count
end

-- ── Full preload (debug / small worlds only) ───────────────────────────────
-- Generates every chunk column in the world without triggering LRU eviction.
-- Safe to call at startup (loading screen) for worlds where full preload is
-- feasible.  Large worlds (radius > 200) must use lazy preload_near instead.

function World:preload_all()
    local cq_max = math.ceil(WORLD_RADIUS / CHUNK_SIZE)
    local cl_max = MAX_COL_LAYER

    for cq = -cq_max, cq_max do
        for cr = -cq_max, cq_max do
            for cl = 0, cl_max do
                local key = ChunkColumn.key(cq, cr, cl)
                if not self._columns[key] then
                    local col      = self:_load_or_generate(cq, cr, cl)
                    col.last_used  = love.timer.getTime()
                    self._columns[key] = col
                    self._count        = self._count + 1
                end
            end
        end
    end
end

-- ── Column generation (Phase 2.2 – 2.5) ──────────────────────────────────
-- Uses Worldgen.surface_layer(q, r) for the island height map.
-- Tile assignment per world-layer wl, given surface layer sl:
--   wl == 0          → bedrock
--   0 < wl < sl      → soft_stone
--   wl == sl         → grass (sl ≥ sea) | soft_stone (sl < sea, underwater)
--   wl > sl          → air (nothing written; ChunkColumn default is 0)

local _TR   -- lazy reference to TileRegistry (already loaded before World)

local function get_TR()
    if not _TR then _TR = require("src.world.tile_registry") end
    return _TR
end

function World:_load_or_generate(col_q, col_r, col_layer)
    local col        = ChunkColumn.new(col_q, col_r, col_layer)
    local TR         = get_TR()
    local sea        = WorldgenCfg.sea_level
    local layer_base = col_layer * CHUNK_DEPTH

    -- Tile ID cache — looked up once, reused across the entire triple loop.
    local id_bedrock    = TR.id("bedrock")
    local id_grass      = TR.id("grass")
    local id_sand       = TR.id("sand")
    local id_salt_water = TR.id("salt_water")
    local id_lava       = TR.id("lava")
    local sub_ids = {
        dirt      = TR.id("dirt"),
        stone     = TR.id("stone"),
        marble    = TR.id("marble"),
        grimstone = TR.id("grimstone"),
    }
    for _, ore in ipairs(WorldgenCfg.ores) do
        sub_ids[ore.id] = TR.id(ore.id)
    end
    -- Tree trunk / leaves IDs (keyed by tile name)
    for _, tree_def in pairs(WorldgenCfg.trees) do
        sub_ids[tree_def.trunk]  = TR.id(tree_def.trunk)
        sub_ids[tree_def.leaves] = TR.id(tree_def.leaves)
    end
    -- Cover plant tile IDs
    for _, plant in ipairs(WorldgenCfg.biome.plants) do
        if plant.type == "cover" and not sub_ids[plant.id] then
            sub_ids[plant.id] = TR.id(plant.id)
        end
    end

    -- tree_roots: tree columns whose canopy may spread to neighbours.
    -- Collected during pass 1; canopy tiles written in pass 2 below.
    -- One entry per tree root: {ql, rl, sl, h, cr, leaves_id}
    local tree_roots = {}

    for ql = 0, CHUNK_SIZE - 1 do
        for rl = 0, CHUNK_SIZE - 1 do
            local wq = col_q * CHUNK_SIZE + ql
            local wr = col_r * CHUNK_SIZE + rl

            -- Per-column precomputes (one noise seed switch each).
            -- Order: TERRAIN → GRIMSTONE → MARBLE → DIRT → BIOME_T → BIOME_H (plant_spec).
            -- is_beach is now an O(1) closure lookup — no perm rebuild needed.
            local sl       = Worldgen.surface_layer(wq, wr)
            local gfloor   = Worldgen.grimstone_floor(wq, wr)
            local marble_n = Worldgen.marble_noise(wq, wr)
            local dirt_dep = Worldgen.dirt_depth(wq, wr)

            -- Surface tile: grass or sand above sea; sand for ocean floor; stone for inland depressions.
            local is_col_ocean = self._is_ocean(wq, wr)
            local surface_id
            if sl >= sea then
                surface_id = self._is_beach(wq, wr) and id_sand or id_grass
            elseif is_col_ocean then
                surface_id = id_sand        -- ocean floor
            else
                surface_id = sub_ids.stone  -- inland depression (no ocean water)
            end

            -- Plant query: only for above-sea grass columns (not sand / beach).
            -- Calls biome_temp + biome_humidity (2 perm rebuilds); rarity roll is
            -- a fast integer hash with no rebuild.
            local plant = nil
            if surface_id == id_grass then
                plant = Worldgen.plant_spec(wq, wr, sl)
            end

            for ll = 0, CHUNK_DEPTH - 1 do
                local wl = layer_base + ll
                if wl == 0 then
                    -- Bedrock: indestructible floor, never carved.
                    col:set(ql, rl, ll, id_bedrock)
                elseif wl == sl then
                    -- Surface tile: caves may breach it for natural cave entrances.
                    if not Worldgen.is_cave(wq, wr, wl) then
                        col:set(ql, rl, ll, surface_id)
                    end
                    -- Carved surface: leaves 0 (air) — an opening visible from overworld.
                elseif wl < sl then
                    if not Worldgen.is_cave(wq, wr, wl) then
                        local name    = Worldgen.subsurface_tile(sl - wl, wl, gfloor, marble_n, dirt_dep)
                        local tile_id = sub_ids[name]
                        -- Stone/grimstone zone: lava first, then ores in what remains.
                        -- Lava runs before ore so ores never spawn suspended in lava.
                        -- Dirt and marble are unaffected by both.
                        if name == "stone" or name == "grimstone" then
                            if Worldgen.lava_at(wq, wr, wl) then
                                tile_id = id_lava
                            else
                                local ore_name = Worldgen.ore_at(wq, wr, wl, sl)
                                if ore_name then tile_id = sub_ids[ore_name] end
                            end
                        end
                        col:set(ql, rl, ll, tile_id)
                    end
                    -- Carved subsurface: leaves 0 (air) — cave chamber.
                elseif is_col_ocean and wl <= sea then
                    -- Ocean water column: sl+1 through sea_level filled with salt_water.
                    col:set(ql, rl, ll, id_salt_water)
                end
                -- wl > sea, or above-sea non-ocean air: zero-initialised, nothing to write.
            end

            -- ── Plant placement (above-surface tiles) ─────────────────────
            if plant then
                if plant.type == "cover" then
                    -- Single tile one layer above the surface.
                    local cover_ll = sl + 1 - layer_base
                    if cover_ll >= 0 and cover_ll < CHUNK_DEPTH then
                        col:set(ql, rl, cover_ll, sub_ids[plant.id])
                    end
                elseif plant.type == "tree" then
                    local tree_def     = WorldgenCfg.trees[plant.id]
                    local h, cr        = Worldgen.tree_dims(wq, wr, plant.id)
                    local trunk_id     = sub_ids[tree_def.trunk]
                    local leaves_id    = sub_ids[tree_def.leaves]
                    -- Trunk: sl+1 through sl+h, in-chunk range only.
                    for dl = 1, h do
                        local trunk_ll = sl + dl - layer_base
                        if trunk_ll >= 0 and trunk_ll < CHUNK_DEPTH then
                            col:set(ql, rl, trunk_ll, trunk_id)
                        end
                    end
                    -- Collect root for the canopy spread pass.
                    tree_roots[#tree_roots + 1] = {
                        ql = ql, rl = rl, sl = sl, h = h, cr = cr,
                        leaves_id = leaves_id,
                    }
                end
            end
        end
    end

    -- ── Canopy spread pass ────────────────────────────────────────────────
    -- For each tree root collected above, spread leaf tiles to all hex
    -- columns within canopy_radius in THIS chunk.  Cross-chunk canopy is
    -- deferred — trees near chunk edges will have clipped canopies for now.
    --
    -- Canopy geometry:
    --   canopy_wl     (= sl + h):     leaves for all neighbour hexes (hex_dist > 0)
    --   canopy_wl + 1 (one above):    leaves for all hexes within cr (including centre)
    -- This gives a flat disc with a domed cap — trunk punches through the disc centre.
    for _, root in ipairs(tree_roots) do
        local canopy_wl = root.sl + root.h
        local cr        = root.cr
        local lid       = root.leaves_id
        for dql = -cr, cr do
            for drl = -cr, cr do
                local hex_d = math.max(math.abs(dql), math.abs(drl), math.abs(dql + drl))
                if hex_d <= cr then
                    local tql = root.ql + dql
                    local trl = root.rl + drl
                    if tql >= 0 and tql < CHUNK_SIZE
                    and trl >= 0 and trl < CHUNK_SIZE then
                        -- disc layer: skip home column centre (trunk is there)
                        if hex_d > 0 then
                            local ll = canopy_wl - layer_base
                            if ll >= 0 and ll < CHUNK_DEPTH
                            and col:get(tql, trl, ll) == 0 then
                                col:set(tql, trl, ll, lid)
                            end
                        end
                        -- cap layer: one above trunk-top for all within cr
                        local ll2 = canopy_wl + 1 - layer_base
                        if ll2 >= 0 and ll2 < CHUNK_DEPTH
                        and col:get(tql, trl, ll2) == 0 then
                            col:set(tql, trl, ll2, lid)
                        end
                    end
                end
            end
        end
    end

    return col
end

-- ── LRU eviction ──────────────────────────────────────────────────────────

function World:_evict_lru()
    local oldest_key  = nil
    local oldest_time = math.huge

    for key, col in pairs(self._columns) do
        if col.last_used < oldest_time then
            oldest_time = col.last_used
            oldest_key  = key
        end
    end

    if oldest_key then
        -- Phase 12: save dirty column to disk before evicting.
        self._columns[oldest_key] = nil
        self._count = self._count - 1
    end
end

return World
