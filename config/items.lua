-- config/items.lua
-- Master item definition list. Loaded by ItemRegistry at startup.
--
-- FIELDS (all items)
--   id           uint16   Permanent numeric ID. 0 = empty slot. Never renumber.
--   name         string   Unique key used in code (matches tile drop strings).
--   display_name string   Human-readable name shown in UI.
--   max_stack    number   Max count per inventory slot.
--                         99 for consumables/materials. 1 for tools/weapons/armour.
--   category     string   "material" | "organic" | "block" | "tool"
--   weight       number   Mass in kg per single unit. Groundwork for encumbrance.
--                         Not enforced yet — carry limit and penalties deferred.
--   sprite       string   Path to PNG used in hotbar/inventory UI. Omit if no art yet.
--                         Images are alpha placeholders; resize/replace when spriting.
--
-- FIELDS (tools only — omit for non-tools)
--   is_tool        bool     Marks item as a tool; ItemRegistry indexes it separately.
--   base_damage    number   HP removed per swing, before penalty.
--   swing_cooldown number   Seconds between swings (higher = slower).
--   durability     number   Uses before the tool breaks. math.huge = never breaks.
--   preferred      table    Categories this tool excels at. No penalty when the target
--                           tile's category matches. Empty = no preference (fists).
--   penalty_mul    number   Damage multiplier when target category is NOT in preferred.
--                           Fists omit this field (always full damage, no penalty).
--
-- RULES
--   • IDs must be dense (no gaps) starting at 1. 0 is reserved for "empty slot".
--   • names must match the strings used in tile `drops` tables exactly.
--   • Append new items at the bottom — never renumber or reorder above.
--
-- FISTS BEHAVIOUR
--   Fists (id 26) are defined here so their stats can be looked up by name.
--   They never occupy an inventory slot — an EMPTY hotbar slot uses fists stats.
--   weight = 0 because fists are not a carried item.

return {

    -- ── Raw Materials ─────────────────────────────────────────────────────

    {
        id = 1,  name = "dirt_clod",       display_name = "Dirt Clod",
        max_stack = 99, category = "material", weight = 0.3,
        sprite = "assests/items/item_dirt_clod.png",
    },
    {
        id = 2,  name = "sand",            display_name = "Sand",
        max_stack = 99, category = "material", weight = 0.4,
        sprite = "assests/items/item_sand.png",
    },
    {
        id = 3,  name = "stone_chunk",     display_name = "Stone Chunk",
        max_stack = 99, category = "material", weight = 0.8,
        sprite = "assests/items/item_chunk_stone.png",
    },
    {
        id = 4,  name = "marble_chunk",    display_name = "Marble Chunk",
        max_stack = 99, category = "material", weight = 0.9,
        sprite = "assests/items/item_chunk_marble.png",
    },
    {
        id = 5,  name = "grimstone_chunk", display_name = "Grimstone Chunk",
        max_stack = 99, category = "material", weight = 1.0,
        sprite = "assests/items/item_chunk_grimstone.png",
    },
    {
        id = 6,  name = "coal_ore",        display_name = "Coal Ore",
        max_stack = 99, category = "material", weight = 0.5,
        sprite = "assests/items/item_ore_coal.png",
    },
    {
        id = 7,  name = "gold_ore",        display_name = "Gold Ore",
        max_stack = 99, category = "material", weight = 2.0,
        sprite = "assests/items/item_ore_gold.png",
    },
    {
        id = 8,  name = "diamond_ore",     display_name = "Diamond Ore",
        max_stack = 99, category = "material", weight = 0.4,
        sprite = "assests/items/item_ore_diamond.png",
    },
    {
        id = 9,  name = "mithril_ore",     display_name = "Mithril Ore",
        max_stack = 99, category = "material", weight = 1.5,
        sprite = "assests/items/item_ore_mithril.png",
    },

    -- ── Logs ──────────────────────────────────────────────────────────────

    {
        id = 10, name = "oak_log",         display_name = "Oak Log",
        max_stack = 99, category = "material", weight = 4.0,
        sprite = "assests/items/item_log_oak.png",
    },
    {
        id = 11, name = "palm_log",        display_name = "Palm Log",
        max_stack = 99, category = "material", weight = 3.5,
        sprite = "assests/items/item_log_palm.png",
    },
    {
        id = 12, name = "spruce_log",      display_name = "Spruce Log",
        max_stack = 99, category = "material", weight = 4.5,
        sprite = "assests/items/item_log_spruce.png",
    },
    {
        id = 13, name = "birch_log",       display_name = "Birch Log",
        max_stack = 99, category = "material", weight = 3.0,
        sprite = "assests/items/item_log_birch.png",
    },

    -- ── Organic Drops ─────────────────────────────────────────────────────

    {
        id = 14, name = "stick",           display_name = "Stick",
        max_stack = 99, category = "material", weight = 0.2,
        sprite = "assests/items/item_stick.png",
    },
    {
        id = 15, name = "acorn",           display_name = "Acorn",
        max_stack = 99, category = "organic",  weight = 0.1,
        sprite = "assests/items/item_seed_acorn.png",
    },
    {
        id = 16, name = "coconut",         display_name = "Coconut",
        max_stack = 99, category = "organic",  weight = 0.8,
        sprite = "assests/items/item_seed_coconut.png",
    },
    {
        id = 17, name = "pinecone",        display_name = "Pinecone",
        max_stack = 99, category = "organic",  weight = 0.1,
        sprite = "assests/items/item_seed_pinecone.png",
    },
    {
        id = 18, name = "samara",          display_name = "Samara",   -- birch seed wing
        max_stack = 99, category = "organic",  weight = 0.05,
        sprite = "assests/items/item_seed_samara.png",
    },

    -- ── Flowers (placeable items, same name as tile) ───────────────────────

    {
        id = 19, name = "tulip",           display_name = "Tulip",
        max_stack = 99, category = "organic",  weight = 0.05,
        sprite = "assests/items/item_flower_tulip.png",
    },
    {
        id = 20, name = "rose",            display_name = "Rose",
        max_stack = 99, category = "organic",  weight = 0.05,
        sprite = "assests/items/item_flower_rose.png",
    },
    {
        id = 21, name = "lavender",        display_name = "Lavender",
        max_stack = 99, category = "organic",  weight = 0.05,
        sprite = "assests/items/item_flower_lavender.png",
    },
    {
        id = 22, name = "daisy",           display_name = "Daisy",
        max_stack = 99, category = "organic",  weight = 0.05,
        sprite = "assests/items/item_flower_daisy.png",
    },

    -- ── Blocks (structural — placed by player, drop themselves) ───────────
    -- No sprites yet — hotbar falls back to category colour placeholder.

    {
        id = 23, name = "oak_planks",      display_name = "Oak Planks",
        max_stack = 99, category = "block",    weight = 3.0,
    },
    {
        id = 24, name = "stone_bricks",    display_name = "Stone Bricks",
        max_stack = 99, category = "block",    weight = 4.0,
    },
    {
        id = 25, name = "marble_bricks",   display_name = "Marble Bricks",
        max_stack = 99, category = "block",    weight = 4.5,
    },

    -- ── Tools ─────────────────────────────────────────────────────────────
    -- Fists are always available even with an empty hotbar slot.
    -- They are defined here so their stats can be looked up by name.
    -- preferred = {} means no category gets the penalty — fists are universal.

    {
        id = 26, name = "fists",           display_name = "Fists",
        max_stack = 1,  category = "tool",     weight = 0,    -- not a carried item
        sprite = "assests/items/fist.png",     -- used for swing flash; not shown in hotbar slot
        is_tool        = true,
        base_damage    = 1,
        swing_cooldown = 0.8,
        durability     = math.huge,
        preferred      = {},       -- no preferred category; no penalty applied
    },
    {
        id = 27, name = "diamond_pickaxe", display_name = "Diamond Pickaxe",
        max_stack = 1,  category = "tool",     weight = 2.5,
        sprite = "assests/items/tool_pickaxe.png",
        is_tool        = true,
        base_damage    = 100,
        swing_cooldown = 1.0,
        durability     = 120,
        preferred      = {"stone", "ore"},
        penalty_mul    = 0.1,
        tool_class     = "pickaxe",
    },
    {
        id = 28, name = "diamond_shovel",  display_name = "Diamond Shovel",
        max_stack = 1,  category = "tool",     weight = 2.0,
        sprite = "assests/items/tool_shovel.png",
        is_tool        = true,
        base_damage    = 100,
        swing_cooldown = 1.0,
        durability     = 100,
        preferred      = {"surface"},
        penalty_mul    = 0.1,
        tool_class     = "shovel",
    },
    {
        id = 29, name = "diamond_axe",     display_name = "Diamond Axe",
        max_stack = 1,  category = "tool",     weight = 2.2,
        sprite = "assests/items/tool_axe.png",
        is_tool        = true,
        base_damage    = 100,
        swing_cooldown = 1.0,
        durability     = 100,
        preferred      = {"organic", "structural"},
        penalty_mul    = 0.1,
        tool_class     = "axe",
    },

    -- ── Primitive Crafted Items ───────────────────────────────────────────

    {
        id = 30, name = "sharp_stone",  display_name = "Sharp Stone",
        max_stack = 99, category = "material", weight = 0.2,
        sprite = "assests/items/item_sharp_stone.png",
    },
    {
        id = 31, name = "fire_drill",   display_name = "Fire Drill",
        max_stack = 99, category = "material", weight = 0.1,
        sprite = "assests/items/item_fire_drill.png",
    },

    -- ── Placeable Tiles ───────────────────────────────────────────────────

    {
        id = 32, name = "dirt_tile",       display_name = "Dirt Tile",
        max_stack = 99, category = "block", weight = 0.3,
        sprite = "assests/items/item_tile_dirt.png",
        places_tile = "dirt",
    },
    {
        id = 33, name = "sand_tile",       display_name = "Sand Tile",
        max_stack = 99, category = "block", weight = 0.4,
        sprite = "assests/items/item_tile_sand.png",
        places_tile = "sand",
    },
    {
        id = 34, name = "stone_tile",      display_name = "Stone Tile",
        max_stack = 99, category = "block", weight = 0.8,
        sprite = "assests/items/item_tile_stone.png",
        places_tile = "stone",
    },
    {
        id = 35, name = "marble_tile",     display_name = "Marble Tile",
        max_stack = 99, category = "block", weight = 0.9,
        sprite = "assests/items/item_tile_marble.png",
        places_tile = "marble",
    },
    {
        id = 36, name = "grimstone_tile",  display_name = "Grimstone Tile",
        max_stack = 99, category = "block", weight = 1.0,
        sprite = "assests/items/item_tile_grimstone.png",
        places_tile = "grimstone",
    },

    -- ── Primitive Fibers ──────────────────────────────────────────────────

    {
        id = 37, name = "grass",        display_name = "Grass",
        max_stack = 99, category = "organic", weight = 0.05,
        sprite = "assests/items/item_grass.png",
    },
    {
        id = 38, name = "crude_twine",  display_name = "Crude Twine",
        max_stack = 99, category = "component", weight = 0.05,
        sprite = "assests/items/item_component_crude_twine.png",
    },

    -- ── Placeable Grass Tile ───────────────────────────────────────────────

    {
        id = 39, name = "grass_tile",   display_name = "Grass Tile",
        max_stack = 99, category = "block", weight = 0.3,
        sprite = "assests/items/item_tile_grass.png",
        places_tile = "grass",
    },

    -- ── Crafting Tools ─────────────────────────────────────────────────
    -- Overworld restriction deferred — implement when underground mode is complete.

    {
        id = 40, name = "crude_chisel", display_name = "Crude Chisel",
        max_stack = 1,  category = "tool", weight = 0.3,
        sprite = "assests/items/item_tool_crude_chisel.png",
        is_tool        = true,
        base_damage    = 1,
        swing_cooldown = 1.2,
        durability     = 10,
        preferred      = {},     -- crafting tool; no category bonus or penalty
        tool_class     = "chisel",
    },

    -- ── Components ────────────────────────────────────────────────────────
    -- Intermediate crafting parts. No direct use on their own.

    {
        id = 41, name = "stone_pickaxe_head", display_name = "Stone Pickaxe Head",
        max_stack = 99, category = "component", weight = 0.7,
        sprite = "assests/items/item_component_stone_pickaxe_head.png",
    },
    {
        id = 42, name = "wooden_handle", display_name = "Wooden Handle",
        max_stack = 99, category = "component", weight = 0.2,
        sprite = "assests/items/item_component_wooden_handle.png",
    },

    -- ── Farming Tools ─────────────────────────────────────────────────────

    {
        id = 43, name = "diamond_hoe", display_name = "Diamond Hoe",
        max_stack = 1, category = "tool", weight = 1.8,
        sprite = "assests/items/tool_hoe.png",
        is_tool        = true,
        base_damage    = 1,
        swing_cooldown = 0.8,
        durability     = 150,
        preferred      = {},     -- farming tool; tills tiles, not for combat
        tool_class     = "hoe",
    },

    -- ── Farming Tools (continued) ─────────────────────────────────────────

    {
        id = 44, name = "watering_can", display_name = "Watering Can",
        max_stack = 1, category = "tool", weight = 1.4,
        sprite = "assests/items/item_tool_watering_can.png",
        is_tool        = true,
        base_damage    = 0,
        swing_cooldown = 0.8,
        water          = 25,     -- water capacity; replaces durability for this tool
        preferred      = {},
        tool_class     = "watering_can",
    },

    -- ── Seeds & Crops ─────────────────────────────────────────────────────

    {
        id = 45, name = "rye_seed",  display_name = "Rye Seed",
        max_stack = 99, category = "organic", weight = 0.02,
        sprite = "assests/items/item_seed_rye.png",
    },
    {
        id = 46, name = "rye_grain", display_name = "Rye Grain",
        max_stack = 99, category = "organic", weight = 0.05,
        sprite = "assests/items/item_crop_rye.png",
    },

    -- ── Add new items below this line. Never renumber above. ─────────────
}
