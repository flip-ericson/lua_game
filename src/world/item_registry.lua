-- src/world/item_registry.lua
-- Loads item definitions from config/items.lua and exposes two lookup paths:
--
--   ItemRegistry.get(id)    → full definition table   (O(1) array access)
--   ItemRegistry.id(name)   → numeric uint16 ID       (O(1) hash lookup)
--
-- HOT-PATH FLAT ARRAYS  (use these in tight loops — one table lookup, no chasing)
--   ItemRegistry.IS_TOOL[id]        → bool    true if item is a tool
--   ItemRegistry.BASE_DAMAGE[id]    → number  damage per swing (0 for non-tools)
--   ItemRegistry.SWING_COOLDOWN[id] → number  seconds between swings (0 non-tools)
--   ItemRegistry.DURABILITY[id]     → number  uses before break (math.huge = never)
--   ItemRegistry.MAX_WATER[id]      → number  water capacity (0 for non-watering tools)
--   ItemRegistry.MAX_STACK[id]      → number  max items per inventory slot
--   ItemRegistry.CATEGORY[id]       → string  "material"|"organic"|"block"|"tool"
--   ItemRegistry.WEIGHT[id]         → number  kg per unit (groundwork for encumbrance)
--   ItemRegistry.SPRITE[id]         → Image   loaded Love2D image, or nil if no sprite
--
-- REVERSE CATEGORY LOOKUP
--   ItemRegistry.by_category["tool"] → array of IDs in that category

local TileRegistry = require("src.world.tile_registry")

local ItemRegistry = {}

-- ── Public flat arrays (populated by load()) ─────────────────────────────

ItemRegistry.IS_TOOL        = {}
ItemRegistry.BASE_DAMAGE    = {}
ItemRegistry.SWING_COOLDOWN = {}
ItemRegistry.DURABILITY     = {}
ItemRegistry.MAX_STACK      = {}
ItemRegistry.CATEGORY       = {}
ItemRegistry.WEIGHT         = {}
ItemRegistry.SPRITE         = {}   -- loaded Image object, nil if no sprite defined
ItemRegistry.PLACES_TILE    = {}   -- [item_id] = tile_id to place, or 0 if not placeable
ItemRegistry.TOOL_CLASS     = {}   -- [item_id] = "pickaxe"|"shovel"|"axe"|"chisel"|nil
ItemRegistry.MAX_WATER      = {}   -- [item_id] = water capacity (0 for non-watering tools)

ItemRegistry.by_category = {}  -- by_category["tool"] = { 26, 27, 28, 29 }

-- ── Private storage ───────────────────────────────────────────────────────

local _by_id   = {}
local _by_name = {}
local _count   = 0

-- ── Public API ────────────────────────────────────────────────────────────

function ItemRegistry.load()
    local item_list = require("config.items")

    -- Validate and commit in one pass (items.lua is small; no two-pass needed).
    local seen_ids   = {}
    local seen_names = {}

    for i, def in ipairs(item_list) do
        assert(type(def.id) == "number" and def.id >= 1 and def.id <= 65535,
            string.format("items.lua entry #%d: id must be a uint16 >= 1", i))
        assert(type(def.name) == "string" and def.name ~= "",
            string.format("items.lua entry #%d: name must be a non-empty string", i))
        assert(not seen_ids[def.id],
            string.format("items.lua: duplicate id %d (entry #%d)", def.id, i))
        assert(not seen_names[def.name],
            string.format("items.lua: duplicate name '%s' (entry #%d)", def.name, i))
        seen_ids[def.id]     = true
        seen_names[def.name] = true

        local id = def.id
        _by_id[id]     = def
        _by_name[def.name] = id

        ItemRegistry.IS_TOOL[id]        = def.is_tool or false
        ItemRegistry.BASE_DAMAGE[id]    = def.base_damage    or 0
        ItemRegistry.SWING_COOLDOWN[id] = def.swing_cooldown or 0
        ItemRegistry.DURABILITY[id]     = def.durability     or 0
        ItemRegistry.MAX_STACK[id]      = def.max_stack      or 1
        ItemRegistry.CATEGORY[id]       = def.category       or "material"
        ItemRegistry.WEIGHT[id]         = def.weight         or 0
        ItemRegistry.PLACES_TILE[id]    = (def.places_tile and TileRegistry.id(def.places_tile)) or 0
        ItemRegistry.TOOL_CLASS[id]     = def.tool_class or nil
        ItemRegistry.MAX_WATER[id]      = def.water or 0

        -- Sprite image — loaded once at startup, nil if no path provided.
        -- Uses love.filesystem.getInfo to verify the file exists before loading,
        -- so missing sprites produce a clear assert rather than a silent nil.
        if def.sprite then
            assert(love.filesystem.getInfo(def.sprite),
                string.format("items.lua '%s': sprite file not found: '%s'", def.name, def.sprite))
            local img = love.graphics.newImage(def.sprite)
            img:setFilter("nearest", "nearest")
            ItemRegistry.SPRITE[id] = img
        end

        -- Reverse category lookup.
        local cat = def.category
        if not ItemRegistry.by_category[cat] then
            ItemRegistry.by_category[cat] = {}
        end
        local bucket = ItemRegistry.by_category[cat]
        bucket[#bucket + 1] = id

        _count = _count + 1
    end

    -- print(string.format("[ItemRegistry] loaded %d items", _count))
end

-- Full definition for UI, crafting. NOT for tight loops.
function ItemRegistry.get(id)
    return _by_id[id]
end

-- Numeric ID by name. Use so you never hardcode numbers.
function ItemRegistry.id(name)
    return _by_name[name]
end

function ItemRegistry.count()
    return _count
end

return ItemRegistry
