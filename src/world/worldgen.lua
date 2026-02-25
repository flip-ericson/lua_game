-- src/world/worldgen.lua
-- Phase 2.2 — Island height map.
-- Phase 2.4 — Subsurface material query functions.
-- Phase 2.6 — Cave carving.
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
--   Worldgen.is_beach(q, r)                                         → bool
--   Worldgen.subsurface_tile(depth, wl, gfloor, marble_n, dirt_dep) → string tile name
--   Worldgen.is_cave(q, r, wl)                                      → bool
--
-- Caller pattern in world.lua (precompute per-column to minimise perm rebuilds):
--   local sl        = Worldgen.surface_layer(wq, wr)   -- TERRAIN seed
--   local gfloor    = Worldgen.grimstone_floor(wq, wr) -- GRIMSTONE seed (rebuild)
--   local marble_n  = Worldgen.marble_noise(wq, wr)    -- MARBLE seed   (rebuild)
--   local dirt_dep  = Worldgen.dirt_depth(wq, wr)      -- DIRT seed     (rebuild)
--   local beach     = Worldgen.is_beach(wq, wr)        -- TERRAIN seed  (rebuild; next col free)
--   for each layer:
--     Worldgen.subsurface_tile(depth, wl, gfloor, marble_n, dirt_dep)  -- no noise calls

local Noise       = require("src.world.noise")
local WorldgenCfg = require("config.worldgen")

-- ── Phase 2.2 — Height map ────────────────────────────────────────────────

local _cfg_island       = WorldgenCfg.island
local _seed_terrain     = Noise.hash(WorldgenCfg.seed, Noise.SEED_TERRAIN)
local _falloff_radius   = _cfg_island.falloff_radius
local _falloff_sharp    = _cfg_island.falloff_sharpness
local _noise_scale      = _cfg_island.noise_scale
local _noise_octaves    = _cfg_island.noise_octaves
local _surface_floor    = _cfg_island.surface_floor
local _surface_range    = _cfg_island.surface_peak - _cfg_island.surface_floor
local _sea_level        = WorldgenCfg.sea_level

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

local _beach_radius     = _cfg_island.beach_radius         -- = 3
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

-- One derived seed per ore entry.  SEED_ORE = 100 so hash(seed, 100+i)
-- never aliases the named seeds 1–8 (marble/grimstone/dirt etc).
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
    local falloff = 1 / (1 + math.exp(_falloff_sharp * (dist / _falloff_radius - 1)))
    local n       = Noise.get2D(q, r, _seed_terrain, _noise_scale, _noise_octaves)
    return math.floor(_surface_floor + n * falloff * _surface_range)
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

-- ── is_beach ──────────────────────────────────────────────────────────────
-- Returns true if any hex within beach_radius rings of (q, r) has its
-- surface below sea_level.  Uses surface_layer() only — chunk-safe.
-- Call AFTER surface_layer() so the perm table stays on TERRAIN seed.
function Worldgen.is_beach(q, r)
    local R = _beach_radius
    for dq = -R, R do
        for dr = -R, R do
            if (dq ~= 0 or dr ~= 0)
            and math.max(math.abs(dq), math.abs(dr), math.abs(dq + dr)) <= R
            and Worldgen.surface_layer(q + dq, r + dr) < _sea_level
            then
                return true
            end
        end
    end
    return false
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

return Worldgen
