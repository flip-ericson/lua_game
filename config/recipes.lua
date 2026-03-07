-- config/recipes.lua
-- Hand-crafting recipe list. Loaded by src/ui/crafting.lua at draw time.
--
-- FIELDS
--   id                  uint   Permanent ID. Never renumber.
--   name                string Internal key.
--   display_name        string Shown in the crafting UI.
--   station             string "hand" = no station needed. Future: "workbench" etc.
--   inputs              table  Array of { name = item_name, count = n }.
--   output              table  { name = item_name, count = n }.
--   learned_by_default  bool   Player knows this recipe from the start.
--                               false = must be taught by scroll / NPC / discovery.
--
-- RULES
--   • IDs must be dense starting at 1. Never renumber above existing entries.
--   • item names must match exactly the `name` field in config/items.lua.
--   • Append new recipes at the bottom.

return {

    {
        id           = 1,
        name         = "sharp_stone",
        display_name = "Sharp Stone",
        station      = "hand",
        inputs       = { { name = "stone_chunk", count = 2 } },
        output       = { name = "sharp_stone",   count = 1 },
        learned_by_default = true,
    },
    {
        id           = 2,
        name         = "fire_drill",
        display_name = "Fire Drill",
        station      = "hand",
        inputs       = { { name = "stick", count = 2 } },
        output       = { name = "fire_drill",  count = 1 },
        learned_by_default = true,
    },
    {
        id           = 3,
        name         = "dirt_tile",
        display_name = "Dirt Tile",
        station      = "hand",
        inputs       = { { name = "dirt_clod", count = 6 } },
        output       = { name = "dirt_tile",   count = 1 },
        learned_by_default = true,
    },
    {
        id           = 4,
        name         = "sand_tile",
        display_name = "Sand Tile",
        station      = "hand",
        inputs       = { { name = "sand", count = 6 } },
        output       = { name = "sand_tile",  count = 1 },
        learned_by_default = true,
    },
    {
        id           = 5,
        name         = "stone_tile",
        display_name = "Stone Tile",
        station      = "hand",
        inputs       = { { name = "stone_chunk", count = 6 } },
        output       = { name = "stone_tile",  count = 1 },
        learned_by_default = true,
    },
    {
        id           = 6,
        name         = "marble_tile",
        display_name = "Marble Tile",
        station      = "hand",
        inputs       = { { name = "marble_chunk", count = 6 } },
        output       = { name = "marble_tile",  count = 1 },
        learned_by_default = true,
    },
    {
        id           = 7,
        name         = "grimstone_tile",
        display_name = "Grimstone Tile",
        station      = "hand",
        inputs       = { { name = "grimstone_chunk", count = 6 } },
        output       = { name = "grimstone_tile",  count = 1 },
        learned_by_default = true,
    },

    -- ── Add new recipes below this line. Never renumber above. ────────────
}
