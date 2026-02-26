-- src/world/worldgen.lua
-- Phase 2.2 — Island height map.
-- Phase 2.4 — Subsurface material query functions.
-- Phase 2.6 — Cave carving.
-- Phase 2.8 — Biome system and plant placement queries.
-- Phase 2.9 — Lava seeding.
--
-- All functions here are PURE: (q, r[, layer], seed) only.
-- Never call world:get_tile() from this module — that would load chunks
-- and break the chunk-isolation guarantee.
--
-- Public API:
--   Worldgen.surface_layer(q, r)                                    → integer world-layer
--   Worldgen.grimstone_floor(q, r)                                  → integer world-layer
--   Worldgen.marble_noise(q, r)                                     → float [0,1]
--   Worldgen.dirt_depth(q, r)                                       → integer [depth_min, depth_max]
--   Worldgen.subsurface_tile(depth, wl, gfloor, marble_n, dirt_dep) → string tile name
--   Worldgen.is_cave(q, r, wl)                                      → bool
--   Worldgen.lava_at(q, r, wl)                                      → bool
--   Worldgen.biome_temp(q, r, sl)                                   → float [0,1] elevation-adjusted
--   Worldgen.biome_humidity(q, r)                                   → float [0,1]
--   Worldgen.plant_spec(q, r, sl)                                   → plant-table or nil
--   Worldgen.tree_dims(q, r, plant_id)                              → height, canopy_radius
--
-- Caller pattern in world.lua (precompute per-column to minimise perm rebuilds):
--   local sl        = Worldgen.surface_layer(wq, wr)   -- TERRAIN seed
--   local gfloor    = Worldgen.grimstone_floor(wq, wr) -- GRIMSTONE seed (rebuild)
--   local marble_n  = Worldgen.marble_noise(wq, wr)    -- MARBLE seed   (rebuild)
--   local dirt_dep  = Worldgen.dirt_depth(wq, wr)      -- DIRT seed     (rebuild)
--   local spec      = Worldgen.plant_spec(wq, wr, sl)  -- BIOME_T + BIOME_H seeds (2 rebuilds)
--   (beach: world._is_beach(wq, wr) — O(1) closure; ocean BFS pre-computes during startup)
--   for each layer:
--     Worldgen.subsurface_tile(depth, wl, gfloor, marble_n, dirt_dep)  -- no noise calls

local Noise       = require("src.world.noise")
local WorldgenCfg = require("config.worldgen")

-- ── Phase 2.2 — Height map ────────────────────────────────────────────────

local _cfg_island       = WorldgenCfg.island
local _seed_terrain     = Noise.hash(WorldgenCfg.seed, Noise.SEED_TERRAIN)
local _sigma            = _cfg_island.sigma
local _falloff_n        = _cfg_island.falloff_n
local _edge_height      = _cfg_island.edge_height
local _center_height    = _cfg_island.center_height
local _noise_amp        = _cfg_island.noise_amplitude
local _noise_scale      = _cfg_island.noise_scale
local _noise_octaves    = _cfg_island.noise_octaves
local _sea_level          = WorldgenCfg.sea_level
local _world_radius       = WorldgenCfg.world_radius
local _noise_fade_start   = _world_radius * 0.90  -- noise at full strength inside here
local _noise_fade_range   = _world_radius * 0.07  -- fades to zero by 97% of world radius

-- ── Phase 2.4 — Subsurface materials ──────────────────────────────────────

local _cfg_marble    = WorldgenCfg.marble
local _cfg_grim      = WorldgenCfg.grimstone
local _cfg_dirt      = WorldgenCfg.dirt

local _seed_marble    = Noise.hash(WorldgenCfg.seed, Noise.SEED_MARBLE)
local _seed_grimstone = Noise.hash(WorldgenCfg.seed, Noise.SEED_GRIMSTONE)
local _seed_dirt      = Noise.hash(WorldgenCfg.seed, Noise.SEED_DIRT)

local _dirt_min   = _cfg_dirt.depth_min    -- = 1
local _dirt_range = _cfg_dirt.depth_max - _cfg_dirt.depth_min  -- = 9
local _dirt_scale = _cfg_dirt.noise_scale

local _marble_threshold = _cfg_marble.threshold
local _marble_bands     = _cfg_marble.bands
local _marble_scale     = _cfg_marble.noise_scale
local _grim_base        = _cfg_grim.base_world_layer
local _grim_var         = _cfg_grim.variation
local _grim_scale       = _cfg_grim.noise_scale

-- ── Phase 2.5 — Ores ──────────────────────────────────────────────────────

local _cfg_ores = WorldgenCfg.ores

-- ── Phase 2.6 — Caves ─────────────────────────────────────────────────────

local _cfg_caves    = WorldgenCfg.caves
local _cave_seed    = Noise.hash(WorldgenCfg.seed, Noise.SEED_CAVES)
local _cave_thresh  = _cfg_caves.threshold
local _cave_scale_h = _cfg_caves.scale_h
local _cave_scale_v = _cfg_caves.scale_v

-- ── Phase 2.9 — Lava seeding ──────────────────────────────────────────────

local _cfg_lava     = WorldgenCfg.lava
local _lava_seed    = Noise.hash(WorldgenCfg.seed, Noise.SEED_LAVA)
local _lava_flat    = _cfg_lava.flat_layer       -- constant max-density zone top
local _lava_ceil    = _cfg_lava.ceiling_layer    -- no lava at or above this layer
local _lava_scale   = _cfg_lava.noise_scale
local _lava_thresh  = _cfg_lava.threshold_floor  -- threshold at wl <= flat_layer

-- One derived seed per ore entry.  SEED_ORE = 100 so hash(seed, 100+i)
-- never aliases the named seeds 1–10 (marble/grimstone/dirt/plant/lava etc).
local _ore_seeds = {}
for i = 1, #_cfg_ores do
    _ore_seeds[i] = Noise.hash(WorldgenCfg.seed, Noise.SEED_ORE + i)
end

local Worldgen = {}

-- ── surface_layer ─────────────────────────────────────────────────────────
-- Returns the topmost solid world-layer for hex column (q, r).
-- Terrain below this layer is filled solid; above is air.
-- Uses TERRAIN seed — call before grimstone/marble to avoid a perm rebuild.
function Worldgen.surface_layer(q, r)
    local dist    = math.sqrt(q*q + q*r + r*r)
    local falloff = math.exp(-((dist / _sigma) ^ _falloff_n))
    local base    = _edge_height + (_center_height - _edge_height) * falloff
    -- Hard boundary: world-edge hexes (hex distance = world_radius) get base only.
    -- base is always < sea_level here, so this guarantees a clean ocean ring
    -- regardless of noise — fixes the E/W flat-edge hexes that sit at Euclidean
    -- dist ≈ 4330, closer to the island than the N/S corners at 5000.
    if math.max(math.abs(q), math.abs(r), math.abs(q + r)) >= _world_radius then
        return math.floor(base)
    end
    -- Noise fade: linearly drop noise weight from 1.0 at 90% world radius to 0.0 at 97%.
    local t = (dist - _noise_fade_start) / _noise_fade_range
    if t >= 1 then
        return math.floor(base)
    end
    local n = Noise.get2D(q, r, _seed_terrain, _noise_scale, _noise_octaves)
    local weight = t > 0 and (1 - t) or 1
    return math.floor(base + (n - 0.5) * _noise_amp * falloff * weight)
end

-- ── grimstone_floor ───────────────────────────────────────────────────────
-- Returns the world-layer below which all stone becomes grimstone.
-- Varies per column using single-octave slow noise (±variation/2 around base).
-- Precompute once per column; result used for all 8 layers in the chunk slice.
function Worldgen.grimstone_floor(q, r)
    local n = Noise.get2D(q, r, _seed_grimstone, _grim_scale, 1)
    return math.floor(_grim_base + (n - 0.5) * _grim_var)
end

-- ── marble_noise ──────────────────────────────────────────────────────────
-- Returns a [0,1] marble presence value for column (q, r).
-- Single-octave, very-slow noise → bands hundreds of hexes wide.
-- Precompute once per column; compared against threshold for each layer.
function Worldgen.marble_noise(q, r)
    return Noise.get2D(q, r, _seed_marble, _marble_scale, 1)
end


-- ── dirt_depth ────────────────────────────────────────────────────────────
-- Returns the number of dirt layers directly below the surface tile for
-- column (q, r).  Varies organically in [depth_min, depth_max] via noise.
-- Precompute once per column; passed into subsurface_tile for each layer.
function Worldgen.dirt_depth(q, r)
    local n = Noise.get2D(q, r, _seed_dirt, _dirt_scale, 1)
    return _dirt_min + math.floor(n * _dirt_range)
end

-- ── subsurface_tile ───────────────────────────────────────────────────────
-- Returns the tile name for a solid subsurface world-layer.
-- No noise calls — all per-column values are precomputed by the caller.
--
--   depth    = surface_layer - wl   (always ≥ 1 for subsurface tiles)
--   wl       = absolute world-layer being filled
--   gfloor   = Worldgen.grimstone_floor(q, r)
--   marble_n = Worldgen.marble_noise(q, r)
--   dirt_dep = Worldgen.dirt_depth(q, r)
--
-- Material precedence (top to bottom of column):
--   dirt      → top N layers (noise-varied 1–10) directly under the surface tile
--   stone     → default fill
--   marble    → stone-zone ribbons where marble_n > threshold
--   grimstone → everything below the per-column floor
function Worldgen.subsurface_tile(depth, wl, gfloor, marble_n, dirt_dep)
    -- Dirt ceiling: depth varies 1–10 per column.
    if depth <= dirt_dep then
        return "dirt"
    end

    -- Grimstone floor: deep rock from bedrock upward to per-column threshold.
    if wl < gfloor then
        return "grimstone"
    end

    -- Marble ribbons: only within the stone zone, where slow noise is strong.
    if marble_n > _marble_threshold then
        for _, band in ipairs(_marble_bands) do
            if math.abs(wl - band.center) <= band.half_width then
                return "marble"
            end
        end
    end

    return "stone"
end

-- ── ore_at ────────────────────────────────────────────────────────────────
-- Returns the ore tile name if any ore generates at (q, r, wl), or nil.
-- sl = surface_layer(q, r) precomputed by the caller.
-- Only call this for stone/grimstone tiles — caller is responsible for filtering.
--
-- Uses 3D noise so clusters are true blobs (vary per layer, not just per column).
-- Noise scale is derived from cluster: larger cluster → lower scale → bigger blobs.
--   cluster=6 → scale=0.05 → blobs ~20 hex wide (coal veins)
--   cluster=2 → scale=0.15 → blobs ~7 hex wide  (diamond clusters)
--
-- Threshold = 1 - rarity.  rarity=0.040 → threshold=0.960 (top ~2–4% of noise).
-- Ores are evaluated in config order — first match wins, so shallower ores
-- declared first won't be shadowed by deeper ores in overlapping depth ranges.
function Worldgen.ore_at(q, r, wl, sl)
    local depth = sl - wl
    for i, ore in ipairs(_cfg_ores) do
        if depth >= ore.depth_min and depth <= ore.depth_max then
            local scale = 0.3 / ore.cluster
            local n     = Noise.get3D(q, r, wl, _ore_seeds[i], scale, 1)
            if n > (1.0 - ore.rarity) then
                return ore.id
            end
        end
    end
    return nil
end

-- ── is_cave ───────────────────────────────────────────────────────────────
-- Returns true if position (q, r, wl) should be carved to air.
--
-- Anisotropic 3D noise: coordinates are pre-scaled before being passed to
-- get3D so the noise kernel sees different frequencies horizontally and
-- vertically.  With scale_h=0.04 and scale_v=0.10 the resulting noise
-- features are ~2.5× wider than they are tall — flat ellipsoidal chambers
-- instead of spheres.
--
-- Threshold 0.98 targets ~2 % of subsurface positions (rare, well-spaced).
-- scale_h=0.010 / scale_v=0.050 → 5:1 ratio → large, flat elongated chambers.
-- Tune in config/worldgen.lua: threshold higher = rarer; lower scales = larger chambers.
-- No minimum-depth gate — caves can breach the surface layer naturally.
-- Bedrock (wl == 0) is never carved — the caller skips it.
function Worldgen.is_cave(q, r, wl)
    local n = Noise.get3D(
        q  * _cave_scale_h,
        r  * _cave_scale_h,
        wl * _cave_scale_v,
        _cave_seed, 1, 1
    )
    return n > _cave_thresh
end

-- ── lava_at ───────────────────────────────────────────────────────────────
-- Returns true if (q, r, wl) should contain lava.
-- Two-segment depth curve:
--   wl 1–flat_layer:       constant ~30% coverage (constant danger zone).
--   wl flat–ceiling_layer: threshold rises linearly → 0% at ceiling.
--   wl >= ceiling_layer:   always false (safe zone, dirt/surface depth).
-- Lava overrides any tile already placed (solid or cave air) — bedrock excluded
-- by caller (wl > 0 guard in world.lua).
function Worldgen.lava_at(q, r, wl)
    if wl >= _lava_ceil then return false end
    local threshold
    if wl <= _lava_flat then
        threshold = _lava_thresh
    else
        local t = (wl - _lava_flat) / (_lava_ceil - _lava_flat)
        threshold = _lava_thresh + (1.0 - _lava_thresh) * t
    end
    local n = Noise.get3D(q, r, wl, _lava_seed, _lava_scale, 1)
    return n > threshold
end

-- ── Phase 2.8 — Biome system & plant placement ────────────────────────────

local _cfg_biome    = WorldgenCfg.biome
local _cfg_trees    = WorldgenCfg.trees
local _plants       = _cfg_biome.plants
local _temp_scale   = _cfg_biome.temperature.noise_scale
local _temp_elev    = _cfg_biome.temperature.elevation_rate
local _humid_scale  = _cfg_biome.humidity.noise_scale

local _seed_biome_t = Noise.hash(WorldgenCfg.seed, Noise.SEED_BIOME_T)
local _seed_biome_h = Noise.hash(WorldgenCfg.seed, Noise.SEED_BIOME_H)
local _seed_plant   = Noise.hash(WorldgenCfg.seed, Noise.SEED_PLANT)

-- Lightweight integer hash → [0, 1).
-- Avoids noise perm rebuilds for per-tile rarity rolls and tree dimensions.
-- `extra` is a small integer salt that separates independent streams
-- (rarity=_seed_plant, height=_seed_plant+1, canopy=_seed_plant+2).
local function _plant_hash(q, r, extra)
    local h = (q * 374761393 + r * 1234567891 + extra) % 1000003
    if h < 0 then h = h + 1000003 end
    return h / 1000003
end

-- ── biome_temp ────────────────────────────────────────────────────────────
-- Returns effective temperature at (q, r) for surface layer sl.
-- Raw temperature (slow noise) is reduced by elevation above sea level.
function Worldgen.biome_temp(q, r, sl)
    local raw_t = Noise.get2D(q, r, _seed_biome_t, _temp_scale, 1)
    local elev_penalty = math.max(0, sl - _sea_level) * _temp_elev
    return math.max(0, math.min(1, raw_t - elev_penalty))
end

-- ── biome_humidity ────────────────────────────────────────────────────────
-- Returns humidity at (q, r) in [0, 1].
function Worldgen.biome_humidity(q, r)
    return Noise.get2D(q, r, _seed_biome_h, _humid_scale, 1)
end

-- ── plant_spec ────────────────────────────────────────────────────────────
-- Returns the plant config table for column (q, r, sl), or nil.
-- Only meaningful for grass tiles (sl >= sea_level); caller must filter.
--
-- Uses slow biome noise for temp/humidity (2 perm rebuilds) and a fast
-- integer hash for the per-tile rarity roll (no rebuild).
-- First matching plant entry wins — order in config/worldgen.lua matters.
function Worldgen.plant_spec(q, r, sl)
    local temp  = Worldgen.biome_temp(q, r, sl)
    local humid = Worldgen.biome_humidity(q, r)
    local roll  = _plant_hash(q, r, _seed_plant)
    for _, spec in ipairs(_plants) do
        if temp  >= spec.temp_min  and temp  <= spec.temp_max
        and humid >= spec.humid_min and humid <= spec.humid_max
        and roll < spec.rarity
        then
            return spec
        end
    end
    return nil
end

-- ── tree_dims ─────────────────────────────────────────────────────────────
-- Returns (height, canopy_radius) for a tree rooted at (q, r).
-- plant_id must be a key in config/worldgen.lua trees table ("oak" etc.).
-- Dimensions are deterministic per-column via integer hash — no noise call.
function Worldgen.tree_dims(q, r, plant_id)
    local def = _cfg_trees[plant_id]
    if not def then return 4, 2 end
    local h1 = _plant_hash(q, r, _seed_plant + 1)
    local h2 = _plant_hash(q, r, _seed_plant + 2)
    local height = def.height_min + math.floor(h1 * (def.height_max - def.height_min + 1))
    local canopy = def.canopy_min + math.floor(h2 * (def.canopy_max - def.canopy_min + 1))
    -- Clamp in case hash lands exactly on 1.0
    height = math.min(height, def.height_max)
    canopy = math.min(canopy, def.canopy_max)
    return height, canopy
end

return Worldgen
