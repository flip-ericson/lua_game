-- config/tiles.lua
-- Master tile definition list.
-- Each entry becomes one row in the TileRegistry at startup.
--
-- FIELDS
--   id          uint16  Permanent numeric ID. Never renumber — IDs are baked
--                       into every saved chunk. 0 = air, 1 = bedrock always.
--   name        string  Unique key used in code. Never change a name after
--                       world data exists.
--   category    string  Broad class of tile. Drives tool efficiency, sound
--                       selection, worldgen queries, and rendering groups.
--                       Values: "special" | "surface" | "stone" | "ore"
--                               "liquid"  | "organic" | "structural"
--   solid       bool    Has collision. False = walkable/swimmable through.
--   max_health  number  Base mining HP (type-level, tool-agnostic).
--                       math.huge = indestructible (bedrock).
--                       Current damage state is per-instance in the world —
--                       this is just the starting value.
--   transparent bool    Light and the canopy-opacity renderer pass through.
--                       False ≠ solid — salt_water is transparent but not solid.
--   luminous    number  Light radius emitted in tiles (0 = dark).
--   liquid      bool    Participates in water / lava flow physics.
--   drops       table   Array of { item_name, min_count, max_count }.
--                       Empty table = no drops. Count is a random roll each break.
--   color       table   {r,g,b} placeholder top-face color (Phase 1 renderer).
--   color_side  table   {r,g,b} optional override; auto-darkened from color if absent.
--
-- RULES
--   • IDs must be dense (no gaps) starting at 0.
--   • IDs and names must both be unique.
--   • Append new tiles at the bottom — never renumber or reorder above.

return {

    -- ── Special ───────────────────────────────────────────────────────────
    -- Air (id 0) is the ABSENCE of a tile — chunks store 0 to mean empty.
    -- It is defined here only so the registry is complete; it is never drawn.
    {
        id = 0,  name = "air",     category = "special",
        solid = false, max_health = 0,         transparent = true,
        luminous = 0,  liquid = false,
        drops = {},
        color = { 0.00, 0.00, 0.00 },
    },
    {
        id = 1,  name = "bedrock", category = "special",
        solid = true,  max_health = math.huge, transparent = false,
        luminous = 0,  liquid = false,
        drops = {},
        color = { 0.15, 0.14, 0.16 },
    },

    -- ── Surface ───────────────────────────────────────────────────────────
    {
        id = 2,  name = "grass",   category = "surface",
        solid = true,  max_health = 100.0,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"dirt_clod", 3, 5} },
        color      = { 0.25, 0.72, 0.20 },
        color_side = { 0.48, 0.33, 0.18 },
    },
    {
        id = 3,  name = "dirt",    category = "surface",
        solid = true,  max_health = 100.0,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"dirt_clod", 3, 5} },
        color = { 0.48, 0.33, 0.18 },
    },
    {
        id = 4,  name = "sand",    category = "surface",
        solid = true,  max_health = 50.0,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"sand", 3, 5} },
        color = { 0.84, 0.77, 0.50 },
    },

    -- ── Stone ─────────────────────────────────────────────────────────────
    -- stone:     default subsurface fill from dirt band down.
    -- marble:    pale horizontal ribbon bands at mid-depths (Phase 2.4 noise).
    -- grimstone: dark columns below a per-column noise floor (Phase 2.4 noise).
    {
        id = 5,  name = "stone",     category = "stone",
        solid = true,  max_health = 200,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"stone_chunk", 3, 5} },
        color = { 0.55, 0.53, 0.50 },
    },
    {
        id = 6,  name = "marble",    category = "stone",
        solid = true,  max_health = 200,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"marble_chunk", 3, 5} },
        color = { 0.84, 0.82, 0.80 },
    },
    {
        id = 7,  name = "grimstone", category = "stone",
        solid = true,  max_health = 500,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"grimstone_chunk", 3, 5} },
        color = { 0.22, 0.20, 0.26 },
    },

    -- ── Ores ──────────────────────────────────────────────────────────────
    {
        id = 8,  name = "coal_ore",    category = "ore",
        solid = true,  max_health = 300,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"coal_ore", 1, 3}, {"stone_chunk", 0, 2} },
        color = { 0.32, 0.24, 0.18 },   -- warm dark brown; distinct from stone/grimstone until sprites land
    },
    {
        id = 9,  name = "gold_ore",    category = "ore",
        solid = true,  max_health = 300,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"gold_ore", 1, 3}, {"stone_chunk", 0, 2} },
        color = { 0.82, 0.70, 0.18 },
    },
    {
        id = 10, name = "diamond_ore", category = "ore",
        solid = true,  max_health = 300,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"diamond_ore", 1, 3}, {"stone_chunk", 0, 2} },
        color = { 0.36, 0.88, 0.94 },
    },
    {
        id = 11, name = "mithril_ore", category = "ore",
        solid = true,  max_health = 300,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"mithril_ore", 1, 3}, {"stone_chunk", 0, 2} },
        color = { 0.48, 0.62, 0.84 },
    },

    -- ── Liquids ───────────────────────────────────────────────────────────
    {
        id = 12, name = "salt_water", category = "liquid",
        solid = false, max_health = math.huge, transparent = true,
        luminous = 0,  liquid = true,
        drops = {},
        color = { 0.18, 0.42, 0.80 },
    },
    {
        id = 13, name = "lava",       category = "liquid",
        solid = false, max_health = math.huge, transparent = false,
        luminous = 6,  liquid = true,
        drops = {},
        color = { 0.92, 0.42, 0.08 },
    },

    -- ── Organic ───────────────────────────────────────────────────────────
    -- oak_trunk / oak_leaves: placed by worldgen tree pass.
    -- bush: solid low shrub; blocks movement, placed by biome plant pass.
    -- tulip: non-solid decorative flower; placed by biome plant pass.
    {
        id = 14, name = "oak_trunk",  category = "organic",
        solid = true,  max_health = 200,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"oak_log", 3, 5} },
        color = { 0.42, 0.28, 0.14 },
    },
    {
        id = 15, name = "oak_leaves", category = "organic",
        solid = false, max_health = 25,   transparent = true,
        luminous = 0,  liquid = false,
        drops = { {"acorn", 0, 3}, {"stick", 1, 3} },
        color = { 0.28, 0.58, 0.18 },
    },
    {
        id = 16, name = "bush",   category = "organic",
        solid = true,  max_health = 100,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"stick", 1, 3} },
        color = { 0.18, 0.44, 0.10 },
    },
    {
        id = 17, name = "tulip",  category = "organic",
        solid = false, max_health = 1,    transparent = true,
        luminous = 0,  liquid = false,
        drops = { {"tulip", 1, 1} },
        color = { 0.90, 0.22, 0.34 },
    },

    -- ── Structural ────────────────────────────────────────────────────────
    -- Player-crafted building blocks. Placed by construction, not worldgen.
    -- Returns itself on break (1-for-1).
    {
        id = 18, name = "oak_planks",    category = "structural",
        solid = true,  max_health = 300,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"oak_planks", 1, 1} },
        color = { 0.60, 0.44, 0.24 },
    },
    {
        id = 19, name = "stone_bricks",  category = "structural",
        solid = true,  max_health = 300,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"stone_bricks", 1, 1} },
        color = { 0.50, 0.48, 0.46 },
    },
    {
        id = 20, name = "marble_bricks", category = "structural",
        solid = true,  max_health = 300,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"marble_bricks", 1, 1} },
        color = { 0.80, 0.78, 0.76 },
    },

    -- ── Tree variants ─────────────────────────────────────────────────────
    -- Each tree type gets its own trunk + leaves so colours differ per species.
    -- oak trunk/leaves defined above (ids 14–15).
    {
        id = 21, name = "palm_trunk",    category = "organic",
        solid = true,  max_health = 200,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"palm_log", 3, 5} },
        color = { 0.68, 0.54, 0.30 },
    },
    {
        id = 22, name = "palm_leaves",   category = "organic",
        solid = false, max_health = 25,   transparent = true,
        luminous = 0,  liquid = false,
        drops = { {"coconut", 0, 3}, {"stick", 1, 3} },
        color = { 0.22, 0.70, 0.28 },
    },
    {
        id = 23, name = "spruce_trunk",  category = "organic",
        solid = true,  max_health = 200,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"spruce_log", 3, 5} },
        color = { 0.34, 0.22, 0.12 },
    },
    {
        id = 24, name = "spruce_leaves", category = "organic",
        solid = false, max_health = 25,   transparent = true,
        luminous = 0,  liquid = false,
        drops = { {"pinecone", 0, 3}, {"stick", 1, 3} },
        color = { 0.16, 0.40, 0.20 },
    },
    {
        id = 25, name = "birch_trunk",   category = "organic",
        solid = true,  max_health = 200,  transparent = false,
        luminous = 0,  liquid = false,
        drops = { {"birch_log", 3, 5} },
        color = { 0.88, 0.86, 0.82 },
    },
    {
        id = 26, name = "birch_leaves",  category = "organic",
        solid = false, max_health = 25,   transparent = true,
        luminous = 0,  liquid = false,
        drops = { {"samara", 0, 3}, {"stick", 1, 3} },
        color = { 0.54, 0.74, 0.34 },
    },

    -- ── Decorative ground cover ───────────────────────────────────────────
    -- tulip defined above (id 17).
    -- All are non-solid and transparent — they sit on top of grass.
    {
        id = 27, name = "rose",      category = "organic",
        solid = false, max_health = 1,    transparent = true,
        luminous = 0,  liquid = false,
        drops = { {"rose", 1, 5} },
        color = { 0.90, 0.14, 0.22 },
    },
    {
        id = 28, name = "lavender",  category = "organic",
        solid = false, max_health = 1,    transparent = true,
        luminous = 0,  liquid = false,
        drops = { {"lavender", 1, 5} },
        color = { 0.62, 0.40, 0.84 },
    },
    {
        id = 29, name = "daisy",     category = "organic",
        solid = false, max_health = 1,    transparent = true,
        luminous = 0,  liquid = false,
        drops = { {"daisy", 1, 1} },
        color = { 0.94, 0.92, 0.86 },
    },

    -- ── Add new tiles below this line. Never renumber above. ─────────────
}
