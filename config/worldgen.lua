-- config/worldgen.lua
-- All world generation constants. Tweak here, never in code.

return {
    seed         = 12345,
    world_radius = 5000,
    world_depth  = 1024,

    sea_level = 768,

    island = {
        falloff_radius    = 3200,
        falloff_sharpness = 3.0,
        noise_scale       = 0.003,
        noise_octaves     = 4,
        surface_floor     = 720,
        surface_peak      = 820,
        beach_radius      = 3,
    },

    -- Dirt ceiling: how many layers directly below the surface tile are dirt.
    -- Depth varies per-column via single-octave noise in [depth_min, depth_max].
    -- Stone is the default fill below the dirt band; marble/grimstone overlay it.
    dirt = {
        depth_min   = 1,    -- never less than 1 dirt layer below surface
        depth_max   = 10,   -- never more than 10
        noise_scale = 0.010, -- moderate scale → organic gradual variation
    },

    -- Marble: wide horizontal ribbon bands at mid-depths.
    -- A single-octave, very-slow noise field (noise_scale ~0.0003) controls lateral extent.
    -- Each band is a world-layer range; marble only appears inside these ranges AND
    -- where the noise exceeds threshold. Bands must sit inside the stone zone
    -- (below dirt band, above grimstone floor).
    marble = {
        noise_scale = 0.008,    -- moderate scale → patches ~120 hexes across, ~200 hex spacing
        threshold   = 0.65,     -- ~25 % coverage within each band
        bands = {
            { center = 688, half_width = 5  },  -- ~80 layers below sea_level
            { center = 638, half_width = 8  },  -- ~130 layers below sea_level
            { center = 568, half_width = 6  },  -- ~200 layers below sea_level
        },
    },

    -- Grimstone: per-column noise floor.  Below this world-layer, stone → grimstone.
    -- base_world_layer ± variation/2 gives the floor range (~380–460).
    grimstone = {
        noise_scale      = 0.002,
        base_world_layer = 420,   -- centre of the floor distribution
        variation        = 80,    -- floor varies ±40 layers per-column
    },

    ores = {
        { id = "coal_ore",    rarity = 0.040, depth_min = 2,   depth_max = 80,  cluster = 6 },
        { id = "gold_ore",    rarity = 0.014, depth_min = 60,  depth_max = 300, cluster = 4 },
        { id = "diamond_ore", rarity = 0.004, depth_min = 250, depth_max = 450, cluster = 2 },
        { id = "mithril_ore", rarity = 0.006, depth_min = 200, depth_max = 511, cluster = 3 },
    },

    caves = {
        threshold = 0.98,   -- top ~2 % of noise space → rare, well-spaced chambers
        scale_h   = 0.010,  -- horizontal frequency (2× larger than before)
        scale_v   = 0.050,  -- vertical frequency  (5:1 ratio maintained → flat ellipsoids)
    },

    -- Per-species tree geometry.  The tree-placement pass picks the species
    -- from the biome.plants table, then reads dimensions from here.
    trees = {
        oak    = { trunk = "trunk",        leaves = "leaves",
                   height_min = 3, height_max = 7,  canopy_min = 2, canopy_max = 4 },
        birch  = { trunk = "birch_trunk",  leaves = "birch_leaves",
                   height_min = 4, height_max = 8,  canopy_min = 1, canopy_max = 3 },
        spruce = { trunk = "spruce_trunk", leaves = "spruce_leaves",
                   height_min = 5, height_max = 10, canopy_min = 1, canopy_max = 2 },
        palm   = { trunk = "palm_trunk",   leaves = "palm_leaves",
                   height_min = 5, height_max = 9,  canopy_min = 2, canopy_max = 3 },
    },

    -- ── Soft biome system ─────────────────────────────────────────────────
    -- Two independent noise fields, both producing [0, 1].
    -- Temperature is also nudged downward by elevation:
    --   effective_temp = raw_temp - (surface_layer - sea_level) * elevation_rate
    --   clamped to [0, 1] before use.
    --
    -- Biome matrix (approximate quadrants — windows overlap for soft edges):
    --
    --              DRY (0.0–0.5)         HUMID (0.5–1.0)
    --  HOT  (0.6): palm  + lavender      palm  + rose
    --  MID  (0.5): oak   + bush          oak   + bush
    --  COOL (0.4): spruce + daisy        birch + tulip
    --
    biome = {
        temperature = {
            noise_scale    = 0.0008,  -- very slow lateral variation
            elevation_rate = 0.002,   -- subtract per layer above sea_level
        },
        humidity = {
            noise_scale    = 0.0010,
        },

        -- Plant spawn rules evaluated per grass tile after terrain is placed.
        -- Trees use full structure placement (trunk + canopy).
        -- Ground cover is a single tile on the layer above the grass surface.
        -- Rarity = per-tile probability of attempting a spawn.
        -- A tile can only hold ONE plant; first match wins (order matters).
        plants = {
            -- ── Trees ────────────────────────────────────────────────────
            { id = "oak",    type = "tree",
              temp_min = 0.35, temp_max = 0.70, humid_min = 0.45, humid_max = 1.00,
              rarity = 0.035 },
            { id = "birch",  type = "tree",
              temp_min = 0.15, temp_max = 0.50, humid_min = 0.50, humid_max = 1.00,
              rarity = 0.030 },
            { id = "spruce", type = "tree",
              temp_min = 0.00, temp_max = 0.42, humid_min = 0.15, humid_max = 0.80,
              rarity = 0.035 },
            { id = "palm",   type = "tree",
              temp_min = 0.58, temp_max = 1.00, humid_min = 0.25, humid_max = 1.00,
              rarity = 0.030 },

            -- ── Shrubs ───────────────────────────────────────────────────
            { id = "bush",     type = "cover",
              temp_min = 0.20, temp_max = 0.80, humid_min = 0.35, humid_max = 0.85,
              rarity = 0.050 },

            -- ── Ground cover ─────────────────────────────────────────────
            { id = "tulip",    type = "cover",
              temp_min = 0.15, temp_max = 0.52, humid_min = 0.50, humid_max = 1.00,
              rarity = 0.080 },
            { id = "rose",     type = "cover",
              temp_min = 0.42, temp_max = 0.78, humid_min = 0.52, humid_max = 1.00,
              rarity = 0.060 },
            { id = "lavender", type = "cover",
              temp_min = 0.50, temp_max = 1.00, humid_min = 0.05, humid_max = 0.52,
              rarity = 0.065 },
            { id = "daisy",    type = "cover",
              temp_min = 0.08, temp_max = 0.48, humid_min = 0.15, humid_max = 0.62,
              rarity = 0.080 },
        },
    },
}
