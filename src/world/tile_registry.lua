-- src/world/tile_registry.lua
-- Loads tile definitions from config/tiles.lua and exposes two lookup paths:
--
--   TileRegistry.get(id)    → full definition table   (O(1) array access)
--   TileRegistry.id(name)   → numeric uint16 ID       (O(1) hash lookup)
--
-- HOT-PATH FLAT ARRAYS  (use these in tight loops — one table lookup, no chasing)
--   TileRegistry.SOLID[id]        → bool    collision / pathfinding
--   TileRegistry.TRANSPARENT[id]  → bool    lighting + canopy-opacity renderer
--   TileRegistry.LIQUID[id]       → bool    water / lava physics
--   TileRegistry.HARDNESS[id]     → number  base mining difficulty (type-level)
--   TileRegistry.LUMINOUS[id]     → number  light radius emitted (0 = dark)
--   TileRegistry.CATEGORY[id]     → string  "special"|"surface"|"stone"|"ore"|
--                                            "liquid"|"organic"
--   TileRegistry.COLOR[id]        → {r,g,b} placeholder top-face color
--   TileRegistry.COLOR_SIDE[id]   → {r,g,b} pre-darkened side-face color
--
-- REVERSE CATEGORY LOOKUP
--   TileRegistry.by_category["ore"]  → array of IDs in that category
--   Useful in worldgen: "give me every ore ID" without iterating all tiles.

local TileRegistry = {}

-- ── Public flat arrays (populated by load()) ─────────────────────────────

TileRegistry.SOLID       = {}
TileRegistry.TRANSPARENT = {}
TileRegistry.LIQUID      = {}
TileRegistry.HARDNESS    = {}
TileRegistry.LUMINOUS    = {}
TileRegistry.CATEGORY    = {}
TileRegistry.COLOR       = {}
TileRegistry.COLOR_SIDE  = {}

TileRegistry.by_category = {}   -- by_category["stone"] = { 7, 8, 9, 10 }

-- ── Private storage ───────────────────────────────────────────────────────

local _by_id   = {}
local _by_name = {}
local _count   = 0

-- ── Internal helpers ──────────────────────────────────────────────────────

local SIDE_DARKEN = 0.55

local function darken(c)
    return { c[1] * SIDE_DARKEN, c[2] * SIDE_DARKEN, c[3] * SIDE_DARKEN }
end

local VALID_CATEGORIES = {
    special    = true, surface = true, stone   = true,
    ore        = true, liquid  = true, organic = true,
    structural = true,
}

local REQUIRED = {
    "id", "name", "category", "solid", "hardness",
    "transparent", "luminous", "liquid", "color",
}

local function validate(def, index)
    for _, field in ipairs(REQUIRED) do
        assert(def[field] ~= nil,
            string.format("tiles.lua entry #%d (%s): missing field '%s'",
                index, tostring(def.name), field))
    end
    assert(type(def.id) == "number" and def.id >= 0 and def.id <= 65535,
        string.format("tiles.lua entry #%d: id must be uint16 (0–65535)", index))
    assert(type(def.name) == "string" and def.name ~= "",
        string.format("tiles.lua entry #%d: name must be a non-empty string", index))
    assert(VALID_CATEGORIES[def.category],
        string.format("tiles.lua entry #%d (%s): unknown category '%s'",
            index, tostring(def.name), tostring(def.category)))
end

-- ── Public API ────────────────────────────────────────────────────────────

function TileRegistry.load()
    local tile_list = require("config.tiles")

    -- Pass 1: validate before committing anything.
    local seen_ids   = {}
    local seen_names = {}

    for i, def in ipairs(tile_list) do
        validate(def, i)
        assert(not seen_ids[def.id],
            string.format("tiles.lua: duplicate id %d (entry #%d)", def.id, i))
        assert(not seen_names[def.name],
            string.format("tiles.lua: duplicate name '%s' (entry #%d)", def.name, i))
        seen_ids[def.id]     = true
        seen_names[def.name] = true
    end

    local max_id = #tile_list - 1
    for id = 0, max_id do
        assert(seen_ids[id],
            string.format("tiles.lua: missing id %d — IDs must be contiguous from 0", id))
    end

    -- Pass 2: commit.
    for _, def in ipairs(tile_list) do
        local id = def.id

        _by_id[id]         = def
        _by_name[def.name] = id

        TileRegistry.SOLID[id]       = def.solid
        TileRegistry.TRANSPARENT[id] = def.transparent
        TileRegistry.LIQUID[id]      = def.liquid
        TileRegistry.HARDNESS[id]    = def.hardness
        TileRegistry.LUMINOUS[id]    = def.luminous
        TileRegistry.CATEGORY[id]    = def.category
        TileRegistry.COLOR[id]       = def.color
        TileRegistry.COLOR_SIDE[id]  = def.color_side or darken(def.color)

        -- Reverse category lookup.
        local cat = def.category
        if not TileRegistry.by_category[cat] then
            TileRegistry.by_category[cat] = {}
        end
        local bucket = TileRegistry.by_category[cat]
        bucket[#bucket + 1] = id

        _count = _count + 1
    end

    -- print(string.format("[TileRegistry] loaded %d tiles (IDs 0–%d)", _count, max_id))
end

-- Full definition for UI, tooltips, crafting. NOT for tight loops.
function TileRegistry.get(id)
    return _by_id[id]
end

-- Numeric ID by name. Use in worldgen/crafting so you never hardcode numbers.
function TileRegistry.id(name)
    return _by_name[name]
end

function TileRegistry.count()
    return _count
end

return TileRegistry
