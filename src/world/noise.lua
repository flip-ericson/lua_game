-- src/world/noise.lua
-- Phase 2.1 — Noise infrastructure.
--
-- Public API:
--   Noise.get2D(x, y, seed, scale, octaves)    → float in [0, 1]
--   Noise.get3D(x, y, z, seed, scale, octaves) → float in [0, 1]
--   Noise.hash(master_seed, system_id)         → integer sub-seed
--
-- All worldgen noise calls go through this module.
-- Use Noise.hash() to derive per-system sub-seeds so terrain, caves, ores, etc.
-- sample different regions of noise space and never visually correlate.
--
-- Parameters:
--   x, y, z   : world coordinates (hex q/r/layer — integers are fine)
--   seed      : integer sub-seed (use Noise.hash to derive from master seed)
--   scale     : spatial zoom. Smaller = smoother/larger features. Larger = noisier.
--               Typical values: island terrain 0.003, caves 0.05.
--   octaves   : number of detail layers stacked (1 = smooth, 4 = detailed).
--               Each octave doubles frequency and halves amplitude (fBm).

local Noise = {}

-- ── Gradient tables ────────────────────────────────────────────────────────
-- 2D: 8 directions (cardinal + diagonal). Diagonals have length √2, which is
--     accounted for by the 70× output scale below.
-- 3D: 12 edge-midpoints of a unit cube (standard Simplex noise gradient set).

local GRAD2 = {
    { 1, 0}, {-1, 0}, { 0, 1}, { 0,-1},
    { 1, 1}, {-1, 1}, { 1,-1}, {-1,-1},
}

local GRAD3 = {
    { 1, 1, 0}, {-1, 1, 0}, { 1,-1, 0}, {-1,-1, 0},
    { 1, 0, 1}, {-1, 0, 1}, { 1, 0,-1}, {-1, 0,-1},
    { 0, 1, 1}, { 0,-1, 1}, { 0, 1,-1}, { 0,-1,-1},
}

-- ── Permutation table ─────────────────────────────────────────────────────
-- A 512-entry doubled permutation array, rebuilt only when the seed changes.
-- Cost: one Fisher-Yates shuffle of 256 elements. In practice each worldgen
-- system uses one seed for millions of sample calls, so rebuilds are rare.

local _perm      = {}
local _perm_seed = nil

local function build_perm(seed)
    if _perm_seed == seed then return end
    _perm_seed = seed

    local p = {}
    for i = 0, 255 do p[i] = i end

    -- LCG seeded with `seed` drives Fisher-Yates in-place shuffle.
    local s = (math.abs(math.floor(seed)) % (2^31 - 1))
    if s == 0 then s = 1 end
    for i = 255, 1, -1 do
        s = (s * 1664525 + 1013904223) % (2^31)
        local j = s % (i + 1)
        p[i], p[j] = p[j], p[i]
    end

    -- Double the table (indices 0–511) to avoid modulo in hot path.
    for i = 0, 511 do
        _perm[i] = p[i % 256]
    end
end

-- ── Gradient dot products ──────────────────────────────────────────────────

local function grad2(h, x, y)
    local g = GRAD2[(h % 8) + 1]
    return g[1]*x + g[2]*y
end

local function grad3(h, x, y, z)
    local g = GRAD3[(h % 12) + 1]
    return g[1]*x + g[2]*y + g[3]*z
end

-- ── Raw 2D Simplex noise ───────────────────────────────────────────────────
-- Standard Ken Perlin simplex (2001). Output ≈ [-1, 1].

local F2 = 0.5  * (math.sqrt(3) - 1)   -- skew factor
local G2 = (3   - math.sqrt(3)) / 6    -- unskew factor

local function simplex2(x, y)
    -- Skew input space → find simplex cell.
    local s  = (x + y) * F2
    local i  = math.floor(x + s)
    local j  = math.floor(y + s)
    local t  = (i + j) * G2
    local x0 = x - (i - t)
    local y0 = y - (j - t)

    -- Which triangle are we in?
    local i1, j1
    if x0 > y0 then i1 = 1; j1 = 0
    else             i1 = 0; j1 = 1
    end

    -- Offsets for the other two corners in (x, y) coords.
    local x1 = x0 - i1 + G2;    local y1 = y0 - j1 + G2
    local x2 = x0 - 1  + 2*G2;  local y2 = y0 - 1  + 2*G2

    -- Permutation-table lookups (indices always land in [0, 511]).
    local ii = i % 256; if ii < 0 then ii = ii + 256 end
    local jj = j % 256; if jj < 0 then jj = jj + 256 end

    local gi0 = _perm[ii    + _perm[jj]]
    local gi1 = _perm[ii+i1 + _perm[jj+j1]]
    local gi2 = _perm[(ii+1)%256 + _perm[(jj+1)%256]]

    -- Corner contributions.
    local n0, n1, n2 = 0, 0, 0

    local t0 = 0.5 - x0*x0 - y0*y0
    if t0 >= 0 then t0 = t0*t0; n0 = t0*t0 * grad2(gi0, x0, y0) end

    local t1 = 0.5 - x1*x1 - y1*y1
    if t1 >= 0 then t1 = t1*t1; n1 = t1*t1 * grad2(gi1, x1, y1) end

    local t2 = 0.5 - x2*x2 - y2*y2
    if t2 >= 0 then t2 = t2*t2; n2 = t2*t2 * grad2(gi2, x2, y2) end

    return 70 * (n0 + n1 + n2)   -- output ≈ [-1, 1]
end

-- ── Raw 3D Simplex noise ───────────────────────────────────────────────────
-- Output ≈ [-1, 1].

local F3 = 1/3
local G3 = 1/6

local function simplex3(x, y, z)
    local s  = (x + y + z) * F3
    local i  = math.floor(x + s)
    local j  = math.floor(y + s)
    local k  = math.floor(z + s)
    local t  = (i + j + k) * G3
    local x0 = x - (i - t)
    local y0 = y - (j - t)
    local z0 = z - (k - t)

    -- Determine which tetrahedron we're in.
    local i1,j1,k1, i2,j2,k2
    if x0 >= y0 then
        if y0 >= z0 then      i1=1;j1=0;k1=0; i2=1;j2=1;k2=0
        elseif x0 >= z0 then  i1=1;j1=0;k1=0; i2=1;j2=0;k2=1
        else                  i1=0;j1=0;k1=1; i2=1;j2=0;k2=1
        end
    else
        if y0 < z0 then       i1=0;j1=0;k1=1; i2=0;j2=1;k2=1
        elseif x0 < z0 then   i1=0;j1=1;k1=0; i2=0;j2=1;k2=1
        else                  i1=0;j1=1;k1=0; i2=1;j2=1;k2=0
        end
    end

    local x1=x0-i1+G3;   local y1=y0-j1+G3;   local z1=z0-k1+G3
    local x2=x0-i2+2*G3; local y2=y0-j2+2*G3; local z2=z0-k2+2*G3
    local x3=x0-1+3*G3;  local y3=y0-1+3*G3;  local z3=z0-1+3*G3

    local ii = i%256; if ii<0 then ii=ii+256 end
    local jj = j%256; if jj<0 then jj=jj+256 end
    local kk = k%256; if kk<0 then kk=kk+256 end

    local gi0 = _perm[ii    + _perm[jj    + _perm[kk]]]
    local gi1 = _perm[ii+i1 + _perm[jj+j1 + _perm[kk+k1]]]
    local gi2 = _perm[ii+i2 + _perm[jj+j2 + _perm[kk+k2]]]
    local gi3 = _perm[(ii+1)%256 + _perm[(jj+1)%256 + _perm[(kk+1)%256]]]

    local n0,n1,n2,n3 = 0,0,0,0

    local t0 = 0.6-x0*x0-y0*y0-z0*z0
    if t0>=0 then t0=t0*t0; n0=t0*t0*grad3(gi0,x0,y0,z0) end

    local t1 = 0.6-x1*x1-y1*y1-z1*z1
    if t1>=0 then t1=t1*t1; n1=t1*t1*grad3(gi1,x1,y1,z1) end

    local t2 = 0.6-x2*x2-y2*y2-z2*z2
    if t2>=0 then t2=t2*t2; n2=t2*t2*grad3(gi2,x2,y2,z2) end

    local t3 = 0.6-x3*x3-y3*y3-z3*z3
    if t3>=0 then t3=t3*t3; n3=t3*t3*grad3(gi3,x3,y3,z3) end

    return 32 * (n0+n1+n2+n3)   -- output ≈ [-1, 1]
end

-- ── Public: fBm wrappers ───────────────────────────────────────────────────
-- Fractional Brownian motion stacks `octaves` octaves of simplex noise.
-- Each octave: frequency doubles, amplitude halves.
-- Result is normalized then clamped to [0, 1].

function Noise.get2D(x, y, seed, scale, octaves)
    build_perm(seed)

    local value     = 0
    local amplitude = 1
    local frequency = 1
    local max_val   = 0

    for _ = 1, octaves do
        value   = value   + simplex2(x * scale * frequency,
                                     y * scale * frequency) * amplitude
        max_val = max_val + amplitude
        amplitude = amplitude * 0.5
        frequency = frequency * 2
    end

    return math.max(0, math.min(1, value / max_val * 0.5 + 0.5))
end

function Noise.get3D(x, y, z, seed, scale, octaves)
    build_perm(seed)

    local value     = 0
    local amplitude = 1
    local frequency = 1
    local max_val   = 0

    for _ = 1, octaves do
        value   = value   + simplex3(x * scale * frequency,
                                     y * scale * frequency,
                                     z * scale * frequency) * amplitude
        max_val = max_val + amplitude
        amplitude = amplitude * 0.5
        frequency = frequency * 2
    end

    return math.max(0, math.min(1, value / max_val * 0.5 + 0.5))
end

-- ── Public: sub-seed derivation ────────────────────────────────────────────
-- Derives a unique integer seed for each worldgen system from the master seed.
-- system_id is a small positive integer. Different large primes per factor
-- ensure the resulting seeds are uncorrelated even for similar master seeds.
--
-- Usage:
--   local terrain_seed = Noise.hash(WorldgenCfg.seed, Noise.SEED_TERRAIN)
--   local h = Noise.get2D(q, r, terrain_seed, island.noise_scale, island.noise_octaves)

function Noise.hash(master_seed, system_id)
    local h = (master_seed * 2654435761 + system_id * 2246822519) % 999983
    return math.floor(math.abs(h)) + 1   -- always a positive integer ≥ 1
end

-- Predefined system IDs — use these so all worldgen modules agree on which
-- seed belongs to which system. Add more as new systems are built.
Noise.SEED_TERRAIN   = 1   -- island height map
Noise.SEED_BIOME_T   = 2   -- temperature overlay
Noise.SEED_BIOME_H   = 3   -- humidity overlay
Noise.SEED_CAVES     = 4   -- 3D cave carving
Noise.SEED_MARBLE    = 6   -- marble ribbon bands
Noise.SEED_GRIMSTONE = 7   -- grimstone per-column floor
Noise.SEED_DIRT      = 8   -- dirt ceiling depth variation
Noise.SEED_PLANT     = 9   -- plant rarity / tree dimension salts
Noise.SEED_LAVA      = 10  -- deep lava blob placement
-- Ore seeds start at 100 — wide gap above named seeds (1–10) so
-- SEED_ORE+i never aliases marble/grimstone/dirt/plant/lava noise.
Noise.SEED_ORE       = 100 -- ore[i] uses hash(seed, SEED_ORE + i)

return Noise
