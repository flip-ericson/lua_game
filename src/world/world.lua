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
    return setmetatable({
        _columns  = {},   -- key → ChunkColumn
        _count    = 0,
        game_time = 0,    -- game minutes elapsed (1 real second = 1 game minute)
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
    local id_bedrock = TR.id("bedrock")
    local id_grass   = TR.id("grass")
    local id_sand    = TR.id("sand")
    local sub_ids = {
        dirt      = TR.id("dirt"),
        stone     = TR.id("stone"),
        marble    = TR.id("marble"),
        grimstone = TR.id("grimstone"),
    }
    for _, ore in ipairs(WorldgenCfg.ores) do
        sub_ids[ore.id] = TR.id(ore.id)
    end

    for ql = 0, CHUNK_SIZE - 1 do
        for rl = 0, CHUNK_SIZE - 1 do
            local wq = col_q * CHUNK_SIZE + ql
            local wr = col_r * CHUNK_SIZE + rl

            -- Per-column precomputes (one noise seed switch each).
            -- Order: TERRAIN → GRIMSTONE → MARBLE → DIRT → TERRAIN (is_beach),
            -- so the next column's surface_layer call costs no rebuild.
            local sl       = Worldgen.surface_layer(wq, wr)
            local gfloor   = Worldgen.grimstone_floor(wq, wr)
            local marble_n = Worldgen.marble_noise(wq, wr)
            local dirt_dep = Worldgen.dirt_depth(wq, wr)

            -- Surface tile: grass or sand above sea; stone for underwater surface.
            -- is_beach runs last to leave perm on TERRAIN for the next column.
            local surface_id
            if sl >= sea then
                surface_id = Worldgen.is_beach(wq, wr) and id_sand or id_grass
            else
                surface_id = sub_ids.stone
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
                        -- Ore overlay: only replaces stone or grimstone, never dirt or marble.
                        if name == "stone" or name == "grimstone" then
                            local ore_name = Worldgen.ore_at(wq, wr, wl, sl)
                            if ore_name then tile_id = sub_ids[ore_name] end
                        end
                        col:set(ql, rl, ll, tile_id)
                    end
                    -- Carved subsurface: leaves 0 (air) — cave chamber.
                end
                -- wl > sl: air — ChunkColumn is zero-initialised, nothing to write.
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
