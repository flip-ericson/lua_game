-- src/world/chunk.lua
-- ChunkColumn: the atomic unit of world storage.
-- Covers a 32 × 32 hex footprint × 8 layers = 8,192 tile slots.
--
-- Tile IDs are uint16 (0–65535).  ID 0 = air = empty slot.
-- Data is a sparse Lua table; absent entries implicitly return 0 (air).
--
-- tick_list: sorted array of { idx, next_stage_time } for tiles that need
-- periodic simulation (crops, liquids, fire, etc.).  Sorted ascending by
-- next_stage_time so the update loop can bail on the first future entry.

local CHUNK_SIZE  = 32   -- horizontal footprint (q and r axes)
local CHUNK_DEPTH = 8    -- vertical layers per chunk

local LAYER_STRIDE = CHUNK_SIZE * CHUNK_SIZE   -- 1024 tiles per horizontal slice

local ChunkColumn = {}
ChunkColumn.__index = ChunkColumn

ChunkColumn.SIZE  = CHUNK_SIZE
ChunkColumn.DEPTH = CHUNK_DEPTH

-- ── Constructor ───────────────────────────────────────────────────────────

function ChunkColumn.new(col_q, col_r, col_layer)
    return setmetatable({
        col_q     = col_q,
        col_r     = col_r,
        col_layer = col_layer,  -- vertical index: 0 = world layers 0–7, 1 = 8–15, …
        data      = {},         -- sparse tile IDs: absent key = 0 (air)
        meta      = {},         -- sparse per-tile metadata (same index key as data)
                                --   crops:   { crop_id, stage, next_stage_time }
                                --   liquids: { volume }
                                --   damage:  { hp_remaining }
                                -- nil = no metadata (default state)
        tick_list = {},         -- sorted array of { idx, next_stage_time }
                                -- ascending by next_stage_time; bail on first future entry
        dirty     = false,      -- true when modified since last disk write
        last_used = 0,          -- timestamp updated on every cache hit (LRU)
    }, ChunkColumn)
end

-- ── Index formula ─────────────────────────────────────────────────────────
-- 1-based so Lua treats it as an array part (faster than hash part).
-- layer_l ∈ [0, CHUNK_DEPTH-1], max index = 7*1024 + 31*32 + 31 + 1 = 8,192.

local function make_idx(q_l, r_l, layer_l)
    return layer_l * LAYER_STRIDE + r_l * CHUNK_SIZE + q_l + 1
end

-- ── Tile access ───────────────────────────────────────────────────────────

-- Returns the tile ID at local coordinates [0, CHUNK_SIZE-1] / [0, CHUNK_DEPTH-1].
-- Missing entry → 0 (air).
function ChunkColumn:get(q_l, r_l, layer_l)
    return self.data[make_idx(q_l, r_l, layer_l)] or 0
end

-- Sets a tile. tile_id = 0 removes the entry to keep air tiles sparse.
function ChunkColumn:set(q_l, r_l, layer_l, tile_id)
    local i = make_idx(q_l, r_l, layer_l)
    self.data[i] = (tile_id ~= 0) and tile_id or nil
    self.dirty   = true
end

-- ── Tile metadata access ──────────────────────────────────────────────────

-- Returns the metadata table for a tile, or nil if none exists.
-- Callers should treat the returned table as mutable (it IS the stored ref).
function ChunkColumn:get_meta(q_l, r_l, layer_l)
    return self.meta[make_idx(q_l, r_l, layer_l)]
end

-- Stores a metadata table for a tile.  Pass nil to clear it.
function ChunkColumn:set_meta(q_l, r_l, layer_l, data)
    self.meta[make_idx(q_l, r_l, layer_l)] = data
    self.dirty = true
end

-- ── Tick list ─────────────────────────────────────────────────────────────

-- Inserts a tick entry in sorted order (ascending next_stage_time).
-- Call when a tile becomes simulation-active (crop planted, liquid placed, …).
-- next_stage_time is a game_time value (game minutes elapsed since world start).
function ChunkColumn:register_tick(idx, next_stage_time)
    local list = self.tick_list
    local lo, hi = 1, #list
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if list[mid].next_stage_time <= next_stage_time then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    table.insert(list, lo, { idx = idx, next_stage_time = next_stage_time })
end

-- Removes the tick entry for a given tile index.
-- Call on harvest, destruction, or when a tile becomes inert.
function ChunkColumn:deregister_tick(idx)
    local list = self.tick_list
    for i = 1, #list do
        if list[i].idx == idx then
            table.remove(list, i)
            return
        end
    end
end

-- ── Tile fill helpers ─────────────────────────────────────────────────────

-- Fills every tile in one horizontal slice (one world-layer) with tile_id.
-- Passing 0 removes all entries in that slice.
function ChunkColumn:fill_layer(layer_l, tile_id)
    local base = layer_l * LAYER_STRIDE
    if tile_id == 0 then
        for i = base + 1, base + LAYER_STRIDE do
            self.data[i] = nil
        end
    else
        for i = base + 1, base + LAYER_STRIDE do
            self.data[i] = tile_id
        end
    end
    self.dirty = true
end

-- Fills the entire column (all 8 slices) with tile_id.
-- Passing 0 wipes the column back to all-air.
function ChunkColumn:fill(tile_id)
    if tile_id == 0 then
        self.data = {}
    else
        local total = CHUNK_SIZE * CHUNK_SIZE * CHUNK_DEPTH   -- 8,192
        for i = 1, total do
            self.data[i] = tile_id
        end
    end
    self.dirty = true
end

-- ── Cache key ─────────────────────────────────────────────────────────────

-- Static helper: returns the string key used by the World cache.
function ChunkColumn.key(col_q, col_r, col_layer)
    return col_q .. "," .. col_r .. "," .. col_layer
end

return ChunkColumn
