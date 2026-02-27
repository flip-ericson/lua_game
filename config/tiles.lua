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
--   hardness    number  Base mining difficulty (type-level, tool-agnostic).
--                       Think of it as the tile's max health.
--                       math.huge = indestructible (bedrock).
--                       Current damage state is per-instance in the chunk —
--                       this is just the starting value.
--   transparent bool    Light and the canopy-opacity renderer pass through.
--                       False ≠ solid — salt_water is transparent but not solid.
--   luminous    number  Light radius emitted in tiles (0 = dark).
--   liquid      bool    Participates in water / lava flow physics.
--   drop_item   string  Item name spawned on mine completion (nil = nothing).
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
        solid = false, hardness = 0,          transparent = true,
        luminous = 0,  liquid = false,         drop_item = nil,
        color = { 0.00, 0.00, 0.00 },
    },
    {
        id = 1,  name = "bedrock", category = "special",
        solid = true,  hardness = math.huge,  transparent = false,
        luminous = 0,  liquid = false,         drop_item = nil,
        color = { 0.15, 0.14, 0.16 },
    },

    -- ── Surface ───────────────────────────────────────────────────────────
    {
        id = 2,  name = "grass",   category = "surface",
        solid = true,  hardness = 0.8,   transparent = false,
        luminous = 0,  liquid = false,   drop_item = "dirt_clod",
        color      = { 0.25, 0.72, 0.20 },
        color_side = { 0.48, 0.33, 0.18 },
    },
    {
        id = 3,  name = "dirt",    category = "surface",
        solid = true,  hardness = 1.2,   transparent = false,
        luminous = 0,  liquid = false,   drop_item = "dirt_clod",
        color = { 0.48, 0.33, 0.18 },
    },
    {
        id = 4,  name = "sand",    category = "surface",
        solid = true,  hardness = 0.8,   transparent = false,
        luminous = 0,  liquid = false,   drop_item = "sand_pile",
        color = { 0.84, 0.77, 0.50 },
    },

    -- ── Stone ─────────────────────────────────────────────────────────────
    -- stone:     default subsurface fill from dirt band down.
    -- marble:    pale horizontal ribbon bands at mid-depths (Phase 2.4 noise).
    -- grimstone: dark columns below a per-column noise floor (Phase 2.4 noise).
    {
        id = 5,  name = "stone",     category = "stone",
        solid = true,  hardness = 3.0,  transparent = false,
        luminous = 0,  liquid = false,  drop_item = "stone_chunk",
        color = { 0.55, 0.53, 0.50 },
    },
    {
        id = 6,  name = "marble",    category = "stone",
        solid = true,  hardness = 5.0,  transparent = false,
        luminous = 0,  liquid = false,  drop_item = "marble_chunk",
        color = { 0.84, 0.82, 0.80 },
    },
    {
        id = 7,  name = "grimstone", category = "stone",
        solid = true,  hardness = 8.0,  transparent = false,
        luminous = 0,  liquid = false,  drop_item = "grimstone_chunk",
        color = { 0.22, 0.20, 0.26 },
    },

    -- ── Ores ──────────────────────────────────────────────────────────────
    {
        id = 8,  name = "coal_ore",    category = "ore",
        solid = true,  hardness = 4.0,   transparent = false,
        luminous = 0,  liquid = false,   drop_item = "coal",
        color = { 0.32, 0.24, 0.18 },   -- warm dark brown; distinct from stone/grimstone until sprites land
    },
    {
        id = 9,  name = "gold_ore",    category = "ore",
        solid = true,  hardness = 8.0,   transparent = false,
        luminous = 0,  liquid = false,   drop_item = "gold_ore",
        color = { 0.82, 0.70, 0.18 },
    },
    {
        id = 10, name = "diamond_ore", category = "ore",
        solid = true,  hardness = 12.0,  transparent = false,
        luminous = 0,  liquid = false,   drop_item = "diamond",
        color = { 0.36, 0.88, 0.94 },
    },
    {
        id = 11, name = "mithril_ore", category = "ore",
        solid = true,  hardness = 14.0,  transparent = false,
        luminous = 0,  liquid = false,   drop_item = "mithril_ore",
        color = { 0.48, 0.62, 0.84 },
    },

    -- ── Liquids ───────────────────────────────────────────────────────────
    {
        id = 12, name = "salt_water", category = "liquid",
        solid = false, hardness = 0,     transparent = true,
        luminous = 0,  liquid = true,    drop_item = nil,
        color = { 0.18, 0.42, 0.80 },
    },
    {
        id = 13, name = "lava",       category = "liquid",
        solid = false, hardness = 0,     transparent = false,
        luminous = 6,  liquid = true,    drop_item = nil,
        color = { 0.92, 0.42, 0.08 },
    },

    -- ── Organic ───────────────────────────────────────────────────────────
    -- trunk / leaves: tree structure placed by the tree-planting pass.
    -- bush:  solid low shrub; blocks movement, placed by biome plant pass.
    -- tulip: non-solid decorative flower; placed by biome plant pass.
    {
        id = 14, name = "trunk",  category = "organic",
        solid = true,  hardness = 2.0,  transparent = false,
        luminous = 0,  liquid = false,  drop_item = "wood_log",
        color = { 0.42, 0.28, 0.14 },
    },
    {
        id = 15, name = "leaves", category = "organic",
        solid = false, hardness = 0.3,  transparent = true,
        luminous = 0,  liquid = false,  drop_item = nil,
        color = { 0.28, 0.58, 0.18 },
    },
    {
        id = 16, name = "bush",   category = "organic",
        solid = true,  hardness = 0.5,  transparent = false,
        luminous = 0,  liquid = false,  drop_item = "wood_stick",
        color = { 0.18, 0.44, 0.10 },
    },
    {
        id = 17, name = "tulip",  category = "organic",
        solid = false, hardness = 0.1,  transparent = true,
        luminous = 0,  liquid = false,  drop_item = nil,
        color = { 0.90, 0.22, 0.34 },
    },

    -- ── Structural ────────────────────────────────────────────────────────
    -- Player-crafted building blocks. Placed by construction, not worldgen.
    {
        id = 18, name = "oak_planks",    category = "structural",
        solid = true,  hardness = 2.0,  transparent = false,
        luminous = 0,  liquid = false,  drop_item = "oak_planks",
        color = { 0.60, 0.44, 0.24 },
    },
    {
        id = 19, name = "stone_bricks",  category = "structural",
        solid = true,  hardness = 5.0,  transparent = false,
        luminous = 0,  liquid = false,  drop_item = "stone_bricks",
        color = { 0.50, 0.48, 0.46 },
    },
    {
        id = 20, name = "marble_bricks", category = "structural",
        solid = true,  hardness = 6.0,  transparent = false,
        luminous = 0,  liquid = false,  drop_item = "marble_bricks",
        color = { 0.80, 0.78, 0.76 },
    },

    -- ── Tree variants ─────────────────────────────────────────────────────
    -- Each tree type gets its own trunk + leaves so colours differ per species.
    -- oak trunk/leaves already defined above (ids 14–15).
    {
        id = 21, name = "palm_trunk",    category = "organic",
        solid = true,  hardness = 1.8,  transparent = false,
        luminous = 0,  liquid = false,  drop_item = "wood_log",
        color = { 0.68, 0.54, 0.30 },
    },
    {
        id = 22, name = "palm_leaves",   category = "organic",
        solid = false, hardness = 0.2,  transparent = true,
        luminous = 0,  liquid = false,  drop_item = nil,
        color = { 0.22, 0.70, 0.28 },
    },
    {
        id = 23, name = "spruce_trunk",  category = "organic",
        solid = true,  hardness = 2.2,  transparent = false,
        luminous = 0,  liquid = false,  drop_item = "wood_log",
        color = { 0.34, 0.22, 0.12 },
    },
    {
        id = 24, name = "spruce_leaves", category = "organic",
        solid = false, hardness = 0.3,  transparent = true,
        luminous = 0,  liquid = false,  drop_item = nil,
        color = { 0.16, 0.40, 0.20 },
    },
    {
        id = 25, name = "birch_trunk",   category = "organic",
        solid = true,  hardness = 1.6,  transparent = false,
        luminous = 0,  liquid = false,  drop_item = "wood_log",
        color = { 0.88, 0.86, 0.82 },
    },
    {
        id = 26, name = "birch_leaves",  category = "organic",
        solid = false, hardness = 0.3,  transparent = true,
        luminous = 0,  liquid = false,  drop_item = nil,
        color = { 0.54, 0.74, 0.34 },
    },

    -- ── Decorative ground cover ───────────────────────────────────────────
    -- tulip already defined above (id 17).
    -- All are non-solid and transparent — they sit on top of grass.
    {
        id = 27, name = "rose",      category = "organic",
        solid = false, hardness = 0.1,  transparent = true,
        luminous = 0,  liquid = false,  drop_item = nil,
        color = { 0.90, 0.14, 0.22 },
    },
    {
        id = 28, name = "lavender",  category = "organic",
        solid = false, hardness = 0.1,  transparent = true,
        luminous = 0,  liquid = false,  drop_item = nil,
        color = { 0.62, 0.40, 0.84 },
    },
    {
        id = 29, name = "daisy",     category = "organic",
        solid = false, hardness = 0.1,  transparent = true,
        luminous = 0,  liquid = false,  drop_item = nil,
        color = { 0.94, 0.92, 0.86 },
    },

    -- ── Add new tiles below this line. Never renumber above. ─────────────
}
