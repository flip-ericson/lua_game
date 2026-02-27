# Dwarf Island — Project Overview

**Engine:** LÖVE2D (Lua) | **View:** 2.5D Isometric Hex Grid | **Art:** 64×64 Scale Pixel Art (flat-top hex tiles)

---

## Vision Statement

You are a dwarf. You arrive on a procedurally generated island, and it is yours to claim. Mine into the earth, build a hold, forge weapons, grow crops, battle monsters, trade with wandering merchants, and master the arcane. The world is alive — seasons turn, water rushes through broken dams, the economy reacts to what you sell, the moon shapes your magic.

**The four games we're channeling:**
- **Dwarf Fortress** — layered world, simulation depth, the satisfaction of dwarves delving deep
- **Hyper Light Drifter / Moonshire** — fluid, punishing combat with dash/parry/dodge, visual style
- **Minecraft** — sandbox freedom, building a home, the ore progression ladder, that tactile digging loop
- **Stardew Valley** - we farm, we ranch, we pay attention to the passing of seasons

**The north star of this project: EFFICIENCY.** This is an ambitious scope. Every system must be designed to run well *before* it's designed to look good. If it lags, it fails.

---

## Core Architecture Decisions

These are decided now, not later. Changing them mid-project is catastrophic.

### Coordinate System
- **Axial hex coordinates** `(q, r)` for all horizontal tile math. Familiar, clean, no wasted storage.
- **Full tile address:** `(q, r, layer)` — the layer index is the vertical dimension.
- Axial coords mean neighbors are always simple integer offsets. Cube coords only when distance/rotation math requires it (convert on the fly).

### World Dimensions
- **Width/Length:** `8192 × 8192` hexes — power of 2, so `8192 / 32 = 256` chunks per axis. Clean.
- **Depth:** `1024` layers — power of 2, chunk math stays trivial.
- **Bedrock:** Layer `0`, indestructible everywhere. Prevents infinite falling.
- **Sea level:** Layer `768` (we're dwarves, most of the world is underground).
- These are starting values — live in `config/worldgen.lua` and can be changed before first generation.

### World Size Presets
All size parameters live in `config/worldgen.lua`. Changing them before first generation is safe and costs nothing. The ocean coverage debug report (Phase 2.7) tells you what % of the 2D sea-level slice is ocean, which is the primary signal for tuning presets.

| Preset | `world_radius` | `falloff_radius` | `world_depth` | Notes |
|---|---|---|---|---|
| **Dev / Loop Test** | 64 | 40 | 64 | All chunks pre-generated at startup (~5 MB). No streaming lag. Ideal for testing combat, mining, farming, NPCs without worldgen noise. |
| **Small Island** | 512 | 320 | 256 | Fast gen, quick to explore. Good for early playtesting. |
| **Medium Island** | 2000 | 1200 | 512 | Comfortable play session size. |
| **Full Vision** | 5000 | 3200 | 1024 | The shipped target. Loading screen BFS ~5–10 sec on first gen. |

**Dev preset notes:**
- At `world_radius=64`, total hex columns ≈ 12,000. With `world_depth=64` (8 vertical chunks per column), total chunks ≈ 1,500 — fits entirely in RAM.
- Pre-generate all chunks at startup: skip the lazy-load system entirely, generate every chunk in the load loop before handing control to the game loop.
- The player spawns normally; the world just happens to already be fully generated.
- This eliminates chunk-pop-in and streaming stutter entirely during game loop development. Switch to Full Vision preset when stress-testing generation performance.

### Chunk System
- **Horizontal chunks:** 32×32 hexes per chunk footprint.
- **Vertical chunk columns:** Group layers into vertical chunks of **8 layers** each. So a full ChunkColumn is `32 × 32 × 8` tiles = **8,192 tile IDs**. `1024 / 8 = 128` vertical chunk layers (col_layer 0–127).
- Only chunks near the player are loaded. Distant chunks sleep on disk.
- A ChunkColumn of `uint16` tile IDs = **16 KB**. 21 columns loaded at once (~336 KB ceiling).
- **Why 8 layers (not 32)?** The renderer shows 3–5 layers at once. 8-layer chunks = 24 loaded layers per camera position — appropriate overhead. Worst-case simulation tile density is also 8× lower per chunk versus the original 32.
- Coordinate split: horizontal uses `CHUNK_SIZE = 32` (q, r axes); vertical uses `CHUNK_DEPTH = 8` (layer axis). They are separate constants with separate coord helpers in `world.lua`.

### Tile ID System
- Tile IDs are `uint16` integers (0–65535). More than enough for all tile types.
- Global `TileRegistry` maps ID → definition table: `{ name, solid, hardness, transparent, luminous, liquid, category, drop_item, color }`
- `mineable` does not exist — all tiles are mineable. Bedrock is indestructible via `hardness = math.huge`.
- `category` groups tiles into classes: `"special"`, `"surface"`, `"stone"`, `"ore"`, `"liquid"`, `"organic"`, `"structural"`. Used for tool efficiency multipliers (Phase 3).
- ID `0` = air. ID `1` = bedrock. All others loaded from data files.
- **Never** store tile type names in the chunk arrays — only IDs. Names are for humans, IDs are for the engine.

### Sprites & Art (2.5D Isometric Model)
The game renders in **2.5D** — top-down hex grid with isometric side faces, like Link to the Past or Pokémon. Think of it this way: if a stone tile sits one layer above a grass field, you don't just see a stone hexagon from above. You see the stone top face *and* the 3 front-facing side walls below it. This is what gives the world its sense of elevation and volume.

**Each solid tile is composed of up to 2 parts:**
- **Top face:** The flat hex polygon seen from above. This is the tile's "floor."
- **Side faces:** Up to 3 parallelogram-shaped wall strips on the front-facing edges. For a fixed camera angle, only the front 3 of the 6 hex edges are ever visible — the back 3 are always hidden behind the top face.

**Sprite breakdown per tile type:**
- 1 top face sprite (flat hex shape)
- 1 side face sprite (a single parallelogram strip — in most cases all 3 visible sides use the same texture, so you only need one and render it 3 times)
- Some tiles may have distinct left/center/right side sprites for variety or directional detail

**Draw order matters (painter's algorithm):**
Tiles must be drawn back-to-front so that front tiles' side faces don't clip through tiles behind them. In hex isometric, this means sorting by `layer` first (lower layers drawn first), then by row within a layer (rows further from camera drawn first). Getting this sort order right is critical — implement and verify it in Phase 1.

**Character and entity sprites** (dwarf, NPCs, enemies): rectangular pixel art that sits on the top face, same as Pokémon overworld characters. The character does not need to be hex-shaped — just position it centered on the tile's top face pixel coordinates. "Normal" sized players and mobs are 1 pixel less than a hex side.

**Wall segments** (placeable by the player): not an entire hex, only one side, keep in mind this makes the 2.5 tricky.

**Do not reshape sprites in Lua at runtime.** Draw every sprite to its correct final shape in your art tool. The parallelogram side faces should be drawn as parallelograms, not rectangles that get skewed by code. The one-time cost of drawing them correctly is trivial; the ongoing CPU cost of transforming them every frame is not.

**Sprite format decision — transparent corners (settled):**
Draw all sprites on a square canvas in Aseprite. Cut the hex corners to transparent (alpha = 0).
The engine draws the full square quad as normal — no masking, no stencils, no runtime clipping.
The transparent corner pixels are processed by the GPU but output nothing, which is negligible
overhead on any modern hardware for a 2D tile game. This is the right tradeoff.

The theoretically optimal alternative (UV-mapped hex mesh via `love.graphics.newMesh()`) would
eliminate corner fragment waste entirely, but requires authoring UV coordinates per vertex and
is significantly more complex to set up. Not worth it here.

**Practical sizes at `hex_size = 48`:**
- Top face sprite canvas: **96 × 84 px** (fits the flat-top hex with a few px margin; hex height
  = `hex_size * sqrt(3)` ≈ 83px). Cut the 6 corners to transparent.
- Side face sprite canvas: **48 × 20 px** (width = hex_size, height = layer_height). This is
  already a rectangle — no corners to cut, it fills the parallelogram naturally.

### Time-Dependent Tile Simulation (Crops, Animals, NPC Production)

**Decision: per-chunk sorted tick_list + real-time next_stage_time. No random ticks. No global tick lists.**

**Game clock:** `1 real second = 1 game minute`. `world.game_time` accumulates `dt` each frame.
- 60 real seconds = 1 game hour
- 24 real minutes = 1 game day
- 168 real minutes = 1 game week

**How it works:**
- When a time-dependent tile is placed (crop planted, liquid seeded, fire started):
  1. Compute `next_stage_time = world.game_time + growth_duration` (in game minutes).
  2. Store `{ crop_id, stage, next_stage_time }` in `ChunkColumn.meta` at that tile's index.
  3. Call `chunk:register_tick(tile_idx, next_stage_time)` — inserts into the chunk's sorted `tick_list`.
- **`tick_list`** is a sorted array of `{ idx, next_stage_time }`, ascending by time. Binary search insertion keeps it ordered.
- **Each frame** (or on a short timer): iterate the `tick_list` of each loaded chunk from the front. Process any entry where `next_stage_time <= world.game_time`. Stop at the first future entry — O(k) not O(all tiles).
- After advancing a tile's stage: update its metadata and re-insert it with the new `next_stage_time` if it has more stages to go.
- On tile removal (harvest, mining): call `chunk:deregister_tick(tile_idx)` to pull it from the list.
- **When a chunk is evicted and reloaded:** `tick_list` is rebuilt from `meta` on load. Any entries past due are processed immediately (catch-up). Crops grow correctly even when unloaded.
- **Seeded deterministic weather (for crop validity):** `rained_on_day(N) = hash(world_seed, N) < rain_chance(season_of_N)`. No weather history stored — any past day's rain reconstructed from seed.

**Which systems use which approach:**

| System | Approach | Reason |
|---|---|---|
| Crops | Lazy eval (calendar) | Must grow while away. Set-and-forget. |
| Animal production (eggs, milk, wool) | Lazy eval (calendar) | Same reason. |
| NPC position when off-screen | Deterministic from schedule + current hour | No pathfinding needed. |
| Water / lava spread | Loaded chunks only, freeze when unloaded | Spatial spread. Player won't notice frozen water they can't see. |
| Fire spread | Loaded chunks only | Same as water. |
| Mining damage (partial hits) | Per-tile metadata, persisted with chunk | Needs to survive reload. |

**Chunk metadata:** `ChunkColumn.meta` is a sparse table (same index key as `data`).
Only tiles with non-default state have entries. Systems that need per-tile state
(crops, liquids, partial damage) read/write here. Nil = no metadata = default state.

**Chunk tick_list:** `ChunkColumn.tick_list` is a sorted array of `{ idx, next_stage_time }`.
Only tiles that actively need simulation have entries. The sort means the update loop is
O(k) where k = tiles ready this tick, not O(all tiles in chunk).

### Performance Rules (Non-Negotiable)
- **Never iterate all tiles every frame.** Dirty flags and event queues only.
- **Sleeping tile system:** tiles that haven't changed and have no active neighbors don't compute. Critical for water, farming, fire spread.
- **Chunk-level culling first**, then tile-level. Don't even look at chunks outside the camera view.
- **Time-sliced AI:** enemies don't all pathfind on the same frame. Stagger updates.
- **Delta time everywhere.** All movement, animation, and timing driven by `dt` (LÖVE's delta time, passed into every `update(dt)` call). No frame-rate-dependent logic. Ever.

---

## Pending Discussions

Things that need a real answer before the relevant phase can be implemented.
Have the conversation, write the decision down, delete the question.

---

### TILE SET — V1 Decided

**Discussion held. Decisions locked. Implement these and nothing more for v1.**

The goal is enough tiles to test the full game loop (mining, building, farming, combat basics).
Everything not on this list stays as a placeholder or is deferred to a later pass.

---

#### Liquids (2 tiles for v1)

| Tile | Notes |
|------|-------|
| `salt_water` | Ocean only. Flood-filled inward from world boundary up to `sea_level`. No lakes in v1. |
| `lava` | Deep underground pockets/pools. Generates in layers 1–200 only. Hot, damaging. |

Lakes and rivers deferred. Lakes are above/below sea level in real life — seeding them
correctly is a separate problem. `fresh_water` tile can stay in the registry for later.
For v1: if it's liquid and it's not lava, it's the ocean.

---

#### Surface Tiles (3 tiles)

| Tile | Generation rule |
|------|----------------|
| `grass` | Conversion pass: any `dirt` tile at `surface_layer` with air directly above → grass. |
| `dirt` | Land only (surface_layer ≥ sea_level). Top 1–10 layers, noise-varied thickness. |
| `sand` | Two distinct rules (see below). |

**Sand generation rules:**

1. **Beach sand** — ring-by-ring scan using `Worldgen.surface_layer()` (pure function, no chunk data).
   For each land column `(q, r)`:
   - Compute `beach_reach(q, r) = floor(beach_noise(q, r) * max_reach) + 1`  (config: `max_reach = 3`)
   - Scan rings at distance 1, 2, 3 in order — **exit immediately** on first ocean tile found
   - If any neighbour within `beach_reach` has `surface_layer < sea_level` → sand
   Ring-by-ring order matters: coastal tiles (most common sand candidates) find ocean in ring 1
   (6 calls) or ring 2 (18 total). Inland tiles exhaust the full radius (36 calls at radius 3)
   but that's 60% cheaper than radius 5 (90 calls). Radius 3 gives max beach width of ~3 tiles
   with noise variation ranging 1–3, which matches real-looking beaches.
   Inland valley patches impossible: interior land has no ocean within radius 3 regardless of height.
   `beach_noise` uses its own seed. All parameters configurable.

   **Why `surface_layer()` and not `world:get_tile()`:** `surface_layer()` is a pure noise
   function — no chunk loading, no state. Calling it on up to 36 neighbours is just noise math,
   fully chunk-isolated. `world:get_tile()` loads chunks, creates ordering dependencies, breaks
   isolation. Always use pure worldgen functions for neighbour checks during generation.

2. **Shallow ocean floor** — any ocean column where `sea_level - surface_layer ≤ shallow_ocean_depth`
   (config, ~15 layers) → surface tile is sand. Deeper ocean floor stays stone.
   Dirt does not generate on ocean floor at all (dirt band is land-only).

---

#### Stone (3 tiles + bedrock)

| Tile | Generation rule |
|------|----------------|
| `bedrock` | Layer 0 only. Indestructible. |
| `stone` | Default subsurface fill. Replaces current `soft_stone` placeholder. |
| `marble` | Horizontal ribbon bands. A few layers tall, very wide (100+ hex). Multiple bands at different depth ranges. Per-band: 2D noise with large horizontal scale determines which columns in that layer range are marble. Rarity, band thickness, and band depth all configurable. |
| `grimstone` | Deep stone with a noise-varied floor per column: `grimstone_floor(q,r) = base_depth + Noise.get2D(q, r, seed, large_scale) * variation`. Any tile at `depth_from_surface > grimstone_floor(q,r)` is grimstone. Hard cutoff per-column (no scattered blocks), but the floor varies organically across the world (e.g., 350 in one region, 430 in another). Separate noise seed from terrain. |

`granite`, `deep_stone`, `obsidian` stay in `tiles.lua` — IDs permanent, just not generated.
Renaming `soft_stone` → `stone` is safe (no saved chunks exist yet).

---

#### Ores (4 tiles)

| Tile | Depth | Rarity | Cluster |
|------|-------|--------|---------|
| `coal_ore` | High in stone layer | Very common | Large veins (6–10 blocks) |
| `gold_ore` | Deep in stone | Uncommon | Small veins (3–5 blocks) |
| `diamond` | Grimstone layer only | Rare | Singular blocks — no cluster. Per-tile probability check only. |
| `mithril_ore` | Deepest stone, near lava layer | Very rare | Tiny veins (2–3 blocks) |

All rarity and cluster values configurable. `copper_ore`, `iron_ore`, `silver_ore`,
`adamantite_ore` stay in the registry, not generated in v1.

---

#### Plants / Organics (5 tiles)

| Tile | Solid | Generation |
|------|-------|------------|
| `trunk` (oak) | Yes | Phase 2.8. Height 2–5 blocks. |
| `leaves` (oak) | No (transparent) | Phase 2.8. Bushy canopy on top of trunk. |
| `bush` | **Yes** | Phase 2.8. One tile, surface decoration, solid. |
| `tulip` | No | Phase 2.8. Full-size tile, no collision. Pre-sprite: just a pink/red color swatch. Transparent non-solid is how the engine handles it — the art makes it look small. |

Trees are trunk + leaves. Leaves transparent so canopy isn't a solid wall of colour.

---

#### Structural / Crafted (3 tiles — no natural generation)

| Tile | Notes |
|------|-------|
| `oak_planks` | Crafted from wood. Player-placed. |
| `stone_bricks` | Crafted from stone. Player-placed. |
| `marble_bricks` | Crafted from marble. Player-placed. |

These have no worldgen. Found in player builds or future structure generation (Phase 9).

---

#### Deferred (not in v1)
Snow, volcanic_rock, sand biome variants, underground mushrooms, moss, ancient roots,
copper/iron/silver/adamantite ores, all magic ores, lava variants, poisonous sludge.

---

## Implementation Phases

---

### ✅ PHASE 1 — Engine Foundation — COMPLETE

Full hex math library (`hex.lua`), tile registry with category validation and auto-darkened side colors, ChunkColumn system (32×32×8, uint16 flat array, LRU cache, lazy generation), camera with zoom + world-space transform, two-mode renderer (overworld surface+cliffs, underground painter's-algo cross-section), occlusion toggle, hover outline, and debug HUD (F1/F3, FPS, layer, depth, coords, render mode). Key bindings: WASD pan, scroll/+/- zoom, `[`/`]`/PageUp/PageDn layer shift, Home → sea level, Tab mode toggle, O occlusion toggle.

---

### PHASE 2 — World Generation
*Highest-risk system. Nail it early so you can iterate on the feel of the world.*
*All worldgen functions must be pure and deterministic — same seed always produces the same world.*

**✅ 2.1 — Noise Infrastructure** — COMPLETE
Hand-rolled 2D and 3D simplex noise with fBm octave stacking, output normalized to [0,1]. `Noise.get2D`, `Noise.get3D`, `Noise.hash()` for sub-seed derivation. Named seed constants (TERRAIN=1 … DIRT=8, ORE=100+i) ensure no system aliases another.

**✅ 2.2 — Island Shape & Height Map** — COMPLETE
`Worldgen.surface_layer(q, r)`: 4-octave simplex noise + sigmoid radial falloff. Surface layers span `surface_floor=720` (deep ocean bed) to `surface_peak=820` (mountain peak), `sea_level=768`. Overworld renderer verified — green island, brown cliffs, blue ocean.

**⏳ 2.3 — Soft Biome System** — CONFIG DEFINED, IMPLEMENTATION DEFERRED (before 2.8)
Config lives in `config/worldgen.lua` → `biome`. Two noise fields: `temperature(q,r)` and `humidity(q,r)`, both [0,1]. Plant rules are a list of `{ id, type, temp_min, temp_max, humid_min, humid_max, rarity }` evaluated per grass tile. 4 tree types (oak, birch, spruce, palm) and 5 ground cover types (bush, tulip, rose, lavender, daisy) defined. **Implementation begins just before Phase 2.8 (vegetation pass).** Do not touch this until caves and water are done.

**✅ 2.4 — Subsurface Bands** — COMPLETE
Dirt ceiling: noise-varied 1–10 layers below surface. Marble ribbons: 3 bands at layers 683–693, 630–646, 562–574; 2D noise (scale=0.008) gates ~25% coverage per band. Grimstone floor: per-column noise varies the stone→grimstone boundary ±40 layers around world layer 420. Sand beaches: ring-3 hex scan of `surface_layer()` — no chunk loading, chunk-safe. All values in `config/worldgen.lua`.

**✅ 2.5 — Ore Generation** — COMPLETE
3D noise per ore type gives true blob shapes (vary per layer). Noise scale derived from `cluster` config: larger cluster → lower scale → bigger veins. Threshold = `1 - rarity`. Ores only replace stone/grimstone, never dirt or marble. Per-ore seeds use `SEED_ORE=100+i` to avoid aliasing marble/grimstone/dirt seeds. V1 ores: coal (shallow, common), gold (mid), diamond (deep), mithril (deepest). See `config/worldgen.lua → ores`.

**✅ 2.6 — Caves** — COMPLETE
Anisotropic 3D noise threshold carving. `Worldgen.is_cave(q, r, wl)` pre-scales coordinates — `q * scale_h, r * scale_h, wl * scale_v` — before the 3D noise kernel (scale=1 inside). Final params: `scale_h=0.010`/`scale_v=0.050` → 5:1 H:V ratio → large, flat elongated chambers. Threshold `0.98` targets ~2% of subsurface tiles, rare and well-spaced. Bedrock (wl=0) is never carved. Caves **can breach the surface layer** — carved surface tiles leave an air opening visible from the overworld as a natural cave entrance. Worm caves deferred. Config in `config/worldgen.lua → caves`.

**2.7 — Water Seeding**

**Design (pinned — implementation after further discussion):**

Ocean seeding is a 2D BFS pre-pass run **once** during the first-gen loading screen. Starting from all border hexes (`world_radius = 5000` ring), the BFS propagates inward, marking every hex reachable from the border whose `surface_layer(q, r) < sea_level` as ocean. Below-sea-level columns not reachable from the border (inland depressions) are ignored for now — fresh water is a separate future pass.

**Performance (estimated):**
- BFS only visits ocean hexes — it stops dead at any land tile. The island shape is irrelevant; correctness is guaranteed by the BFS itself regardless of `world_radius` or `falloff_radius`.
- `surface_layer` calls ≈ number of ocean hexes + their land-border neighbors. At ~2.5M calls/sec in LuaJIT, expected **5–10 seconds** for the full-vision preset on a one-time loading screen.

**Result storage and persistence:**
`ocean_cols` is a **worldgen artifact, not a live world state tracker.** It is written once during first gen and saved to the world save file alongside the seed. It is never modified again — not by player actions, not by subsequent loads.

It answers exactly one question: *"was this column ocean at the moment the world was first generated?"* It is consulted exactly once per column — when that column's chunk is generated for the first time. After that, the chunk's tile data on disk is the ground truth. Player modifications (filling ocean, converting sand to stone, digging channels) are stored in chunk tile data, not in `ocean_cols`.

Load sequence:
- **First ever launch:** BFS runs on loading screen → `ocean_cols` written to world save.
- **Chunk first generation:** Column not yet on disk → consult `ocean_cols` to place water and sand → generate → write chunk to disk.
- **Chunk subsequent loads:** Already on disk → load tile data directly. `ocean_cols` is never consulted for this chunk again.
- **Player modifies ocean tiles:** Changes are in chunk tile data. Phase 10 water physics handles spread. `ocean_cols` is irrelevant.

**Vertical fill (at chunk first generation):** If `ocean_cols[wq, wr]`, fill every layer from `surface_layer + 1` up to `sea_level` with `salt_water`. Ocean tiles get `volume = math.huge` (infinite source for Phase 10 water physics).

**Sand — two systems, both required:**
- **`is_beach()` (above water, already implemented):** Scans a ring of radius `beach_radius` around each land tile. If any neighbor is an ocean column, the surface tile becomes sand. The ring radius is what gives the beach natural width — without it you'd get a single-tile-wide sandy stripe.
- **Water-contact sand (below water, new — runs during vertical fill):** Every solid tile that directly neighbours a `salt_water` tile becomes sand. In practice: the topmost solid tile in each ocean column (directly below the water) becomes sand, plus any solid tile horizontally adjacent to a water tile at any depth. Rule: if you touch salt water on any face, you are sand. This covers the ocean floor and the submerged base of the island's coastline.

**Fresh water / lakes:** Separate future pass. All liquid in v1 is `salt_water` or `lava`.

**Debug / validation checks (run after BFS, print to console):**
1. **Border sanity check** — before BFS begins, assert that every hex on the world border ring (`dist == world_radius`) has `surface_layer < sea_level`. If any border hex is above sea level the BFS start set is incomplete and the flood fill will miss connected ocean. Fail loudly.
2. **Ocean coverage report** — after BFS completes, count `ocean_cols` entries vs total hex count. Print:
   ```
   [Worldgen] Ocean coverage: 183,241 / 750,150 hexes = 24.4 %
   ```
   This gives an immediate read on how much of the 2D sea-level slice is ocean vs land. Use this number to calibrate the world size presets (see Core Architecture → World Size Presets). Target range is probably 15–40% ocean for a playable island. Run this report across all presets before locking them in.

**2.8 — Trees (Multi-Tile Entities)**
Trees come after caves and water so cave openings near the surface are fully carved before
tree placement — avoids rooting a tree over a thin ceiling. Density driven by biome (2.3).
- Trees are **not tiles** — they are world entities placed during generation.
- A tree has: a root `(q, r, layer)`, a trunk height (N layers), a canopy radius.
- Trunk = a column of "trunk" tile IDs placed in the tile grid.
- Canopy = a cluster of "leaf" tiles at the top layers, hex-ring shaped.
- Canopy tiles are `transparent = true` so light passes through.
- Felling a tree: mining the bottom trunk tile causes the whole tree entity to collapse (drop logs + leaves).
- Trees placed during worldgen: density driven by biome (forest = dense, highland = sparse, beach = none).

**2.9 — Structures**
- Final worldgen pass. Scan for valid placement locations, stamp templates.
- Templates: hand-authored Lua tables defining relative tile placements.
- Starter structures: abandoned mine shaft, ruined tower, goblin camp, hermit cave, sunken shipwreck.
- Structures can span multiple layers (mine shafts go deep).
- Revisit and expand this phase throughout development — it's never "done."

---

---

### ⚠️ PIN — Chunk Streaming & Load-Lag Mitigation (resolve before Phase 3)

**Problem:** Chunk generation on first access blocks the main thread, causing visible FPS drops
when the player moves into unloaded territory. In Phase 2 this is tolerable (no player, no combat).
In Phase 3 it is not — a stutter mid-swing or mid-dodge is a gameplay defect.

**Why full pregeneration isn't the answer:**
The world is `world_radius = 5000` hex, `world_depth = 1024` layers, chunked at 32×32×8.
Rough column count: ~75 M hex cells / (32×32) ≈ **73,000 horizontal chunk positions × 128 vertical**
= ~9.4 M chunk-columns. At 16 KB each that's ~150 GB on disk and hours of CPU time to generate.
Full up-front pregeneration is not feasible.

**The architectural options (pick one before writing a single line of Phase 3):**

| Option | How | Trade-offs |
|---|---|---|
| **A — Spawn-area pre-gen** | On new game, show a loading screen and generate all chunks within N hex of spawn (e.g. radius 150). Stream the rest lazily as the player explores. | Simple. Player has a large buffer before any stream stutter. Most of the accessible early game is pre-warmed. |
| **B — Background thread generation** | Push chunk gen onto a `love.thread`. Main thread requests a chunk; gen thread builds it; main thread polls. Chunk comes in with 1–2 frame delay (invisible). | Correct solution long-term. `love.thread` + channels is LÖVE's built-in answer. Slightly more complex bookkeeping (pending queue, not-yet-ready fallback tile). |
| **C — Time-sliced gen budget** | Cap chunk generation to N ms per frame (e.g. 4 ms). Queue pending requests; drain the queue within budget each frame. | No threading complexity. Visible stutter only if generation queue grows faster than budget drains (fast camera pan). Simpler than B, less robust. |

**Recommendation:** Implement **A** first (it's a one-weekend job and unblocks Phase 3 immediately),
then retrofit **B** when performance profiling shows it's needed. Option C is a fallback if threads
prove painful.

**Combat constraint:** Once Phase 8 exists, no chunk-load stutter is acceptable during combat.
Option B (threads) is the only solution that fully guarantees this. Set Option A's spawn radius
large enough that combat almost never touches an unloaded chunk (radius 200+ should cover it for
normal island exploration), and accept that edge-of-world scenarios can still hitch until B lands.

**Decision to make:**
- [ ] Chosen option: ___
- [ ] Spawn pre-gen radius (if A): ___
- [ ] Acceptable gen budget per frame in ms (if C): ___

---

**Tactics for reducing per-chunk generation cost** — apply these regardless of which option above
is chosen. Ordered highest-impact first.

🔴 **Must-do (biggest spike killers)**

1. **Frame budget cap** — never generate a full chunk in one frame. Measure with `love.timer.getTime()`, stop when `elapsed > budget_ms`. Queue the rest for next frame. A 2–4 ms cap per frame keeps the main thread alive even during fast camera pans.

2. **Limit concurrent generators** — allow only 1–2 chunks to actively generate per frame. Add a priority queue: player's current chunk first, horizontal neighbors next, vertical neighbors last. Never kick off all 7+ neighbors on the same frame.

🟠 **High-value (reduce work per chunk)**

3. **Profile before anything else** — wrap generation phases with `os.clock()` and print per phase (terrain noise, subsurface bands, ore pass, cave pass, render build). Find the actual bottleneck. Guessing wastes sessions.

4. **Reduce noise calls** — 3D noise is the most expensive call in the pipeline. Confirm no redundant perm * Chunk lag happens when too much deterministic work happens in a single frame.
Control *how much*, *how often*, and *how many at once* — not the size of the world.

---rebuilds (the current design precomputes per-column values to avoid this, but verify with profiling). Fewer octaves for lower-priority systems (ores and caves are already 1 octave — good).

5. **No per-tile allocations inside loops** — creating a `{}` table per tile in the generation loop causes GC spikes that mimic load-lag. ChunkColumn already uses a flat `uint16` array. Keep all generation logic free of table creation inside the triple loop.

🟡 **Medium-value (reduce downstream cost)**

6. **Separate data gen from render build** — when a chunk generates, don't trigger a renderer draw-list rebuild on the same frame. Mark it dirty, let the renderer pick it up next frame within its own budget.

7. **Defer vertical-neighbor chunks** — load the player's horizontal layer first, delay `col_layer ± 1` chunks by 1–2 frames. The player almost never needs layers above/below instantly.

🟢 **Structural (for later)**

8. **Smaller chunks if profiling shows volume is the bottleneck** — `32×32×8` = 8,192 tiles per column. Dropping to `16×16×8` quarters the work per generate call, at the cost of 4× more chunk objects. Only worth it if profiling confirms tile count is the issue (vs noise math).

9. **`love.thread` (Option B above)** — the real fix for combat-safe streaming. But threads fix total throughput; frame budgets fix per-frame spikes. Build the budget system first. Threading an architecture that doesn't already break work into small units just moves the spike into the thread.

**Core principle:*

### PHASE 3 — Player & Basic Interaction
*Get the dwarf on screen. Make him move. Make him dig. Make him fall.*

**3.1 — Player Entity** ✅ `src/entities/player.lua`
- World-pixel position `(x, y, z)` — z is float layer index, integer when grounded.
- WASD movement at 200 px/s. Diagonal normalised (×0.7071).
- Spritesheet loaded at startup: standing frame (col 0, row 0), airborne frame (col 1, row 4).
- Depth-injected into painter's algorithm by renderer at the correct row.
- Shadow ellipse pinned to `floor_z` (doesn't rise during jump).

**3.2 — Vertical Movement & Collision** ✅
- **Physics:** Fixed-rate symmetric arc. `VERT_RATE` drives both rise and fall. `JUMP_HEIGHT` sets peak. `JUMP_DURATION` and `JUMP_SPEED_MUL` are derived — do not hardcode.
- **Three states:** `jumping` (rise, no floor checks), `falling` (floor check only at integer z crossings), grounded (floor check every frame; start falling if floor disappears).
- **dt cap:** `MAX_DT = 1/15` — prevents tunnelling at any framerate.
- **Air control:** `AIR_CONTROL = 0` (locked to launch velocity). `JUMP_SPEED_MUL` scales horizontal velocity at jump launch to target 2.25 × inradius horizontal distance.
- **Wall collision:** SAT hex-vs-hex. Player hitbox = flat-top regular hexagon, `PLAYER_HEX_R = 24` px circumradius. Checks player's hex + 6 axial neighbours (7 total). 6-axis SAT per solid hex; push along minimum-overlap axis. Exact face alignment — no circle approximation.
- **Floor detection:** 5-point foot sample (`FOOT_R = 11`). Independent of SAT hitbox.

**3.3 — Layer Visibility** ✅ (overworld canopy done; underground toggle deferred)
- **Canopy opacity:** `TileRegistry.TRANSPARENT[id]` tiles render at 50% alpha in the vegetation pass. All leaf variants transparent; bush/trunk opaque.
- **Trunk rendering:** Top face draws if tile above is air or transparent (leaves no longer hide trunk tops). Side faces draw if neighbour is air or transparent.
- **Underground auto-toggle:** deferred — implement alongside 3.8 underground lighting.

**3.4 — Mining**
- Player aims at an adjacent hex (within reach, drawn with a highlight ring).
- Hold interact → mining progress drains tile's `hardness` value over time.
- Visual feedback: tile cracks (3-stage damage sprite overlay), screen-space dust particles.
- Audio: different dig sounds per tile material (dirt thud, stone clank, ore ring).
- Tool affects speed: bare hands → slow; pickaxe → faster; iron pickaxe → faster still. Tool–material matchups in `config/balance.lua`.
- On break: tile → air, spawn item drop entity at that location.
- Player sprite eventually shows the equipped tool visually (Phase 3 can start with a simple flash; full tool-in-hand sprite comes later with combat polish).

**3.5 — Building & Placing Tiles**
- Select a tile from hotbar, aim at a target hex, press place key.
- Can only place on air tiles adjacent to an existing solid tile.
- Wall placement: aim at a hex *edge* (between two hexes) to place a wall segment on that edge.
- Wall segments: stored separately from the tile grid (a hex has 6 possible wall slots, each independently filled/empty).

**3.6 — Tile Highlight & Selection**
- `hovered_hex` updated every frame from mouse position via `pixel_to_hex`.
- Reach constraint: only highlight hexes within N hex distance of player (configurable).
- Draw the highlight as an outline on the **top face polygon** of the hovered tile — not a flat ground-level ring, since tiles sit at different heights. The outline should sit at the correct isometric elevation.
- For placement: show a ghost preview of the tile/wall being placed on valid target locations (green tint = valid, red = invalid).
- Show a tooltip on hover: tile name, material, hardness remaining. *(Inspired by Jade mod for Minecraft — a small info box in the corner or near the cursor.)*

> ⚠️ **DEFER to Phase 4.7.** The current hover outline (white polygon on top face) is a placeholder only. The full selector — reach constraint, correct per-mode isometric elevation, ghost preview, tooltip — is specced in **Phase 4.7** and should be built alongside the rest of the HUD. Getting the visual right requires knowing the final art pipeline. Do not spend iteration time on it now.

**3.7 — Item Drops & Basic Inventory**
- Dropped item: a small world entity at a tile position, with a gentle float/bob animation.
- Player walks over → auto-collect into inventory (with a small magnet radius).
- Inventory: flat array of `{ item_id, count }`. Max stack size per item type defined in `items.lua`.
- Hotbar: first 10 slots, rendered at bottom-center of screen.

**3.8 — Underground Lighting (placeholder)**
The player needs some lighting model the moment they go underground. Full light propagation comes in Phase 5.6 — this step is the minimum viable version that ships with Phase 3.

- Surface: no change, full ambient light.
- Underground (player below `surface_layer(q, r)`): apply a dark overlay tint to all rendered tiles. A simple `love.graphics.setColor` multiplier at the end of the underground draw pass works fine.
- Light sources (torches, lava tiles, luminous ore): each has a `luminous` radius in tiles. For each drawn tile, check distance to nearest known light source in the visible set. If within radius → full color. Beyond radius → blended toward the dark overlay. This is O(tiles × lights) per frame — acceptable for a small number of torches.
- Torch is an entity (not a tile) placed by the player. Entities are Phase 3, so light sources and inventory torches ship together.
- `luminous` field already exists in TileRegistry for every tile — lava (radius 6), glowing ores (radius 1–2). No changes needed to tile data.
- The hard BFS propagation system (occlusion-correct, chunk-aware) is Phase 5.6. Don't build it now.

---

### PHASE 4 — GUI & HUD
*Get the information architecture right. This screen real estate will be looked at for hundreds of hours.*

> **Minimum HUD ships alongside Phase 3.1 (player entity).** The moment the dwarf is on screen, you need at minimum: hotbar (even empty), vitals bars (even placeholder values), and a working pause/options screen. Everything else in this phase can be stubbed and filled in. Do not start Phase 3.2+ without a pause menu — you need Escape → Quit during development.

**4.1 — Hotbar**
- Bottom-center, Minecraft-style 10 slots.
- Shows: item sprite, stack count, selected slot highlight.
- Scroll wheel or `1–0` keys to select active slot.
- Active item name shown as a brief fade-in tooltip above hotbar on switch.

**4.2 — Vitals Bar**
- Health, Stamina, Mana, Hunger, Thirst.
- Don't stack all 5 as identical bars — differentiate visually. Suggestion: Health and Stamina left side (combat-critical), Hunger/Thirst right side (management), Mana above hotbar (tied to spellcasting).
- All driven by values on the player entity; update reactively, not every frame.

**4.3 — Time / Calendar / Moon Display**
- Top-right corner widget.
- Shows: current in-game time (hour:minute), day number, month name (dwarfy name), season, year.
- Moon phase: a small pixel art icon cycling through 8 phases. Visually distinct, not just a label.
- This system feeds directly into magic power, weather probability, NPC schedules, and crop growth — it's not cosmetic.

**4.4 — Inventory Screen**
- Toggle: Tab or B.
- Grid layout. Click-to-move items between slots (drag-and-drop as a polish pass later).
- Equipment slots visible: Head, Chest, Legs, Boots, Weapon, Offhand, Ring, Amulet.
- Crafting shortcut from inventory (opens crafting UI filtered to what the player can currently make).

**4.5 — Tile Identifier (Jade-style, top of screen)**
- Fixed panel anchored to the **top-center** of the screen (not floating near the cursor).
- Updates as the player hovers over different tiles. Shows: tile name, category, hardness remaining, any embedded ore name, biome tag if relevant.
- **Toggleable** — keybind (e.g. `I`) hides/shows the panel entirely. Off by default or on by default, decide at implementation time.
- Inspired by the Jade mod for Minecraft: the panel is informative but stays out of the main viewport action. Moving it to the top keeps the area around the cursor clean.

**4.6 — Pause / System Menu & Options**
This is the first screen built in Phase 4 (or even late Phase 3) — you need Escape → Quit before anything else.

*Pause menu (Escape key):*
- Resume
- Save Game (placeholder — writes nothing until Phase 12 serialization, but the button must exist)
- Load Game (same — disabled/grayed if no saves exist)
- Settings → opens the Options screen
- Quit to Desktop

*Options screen — bare bones required for ship:*
- **Audio:** Master volume, Music volume, SFX volume (three sliders, 0–100).
- **Video:** Fullscreen toggle, UI scale selector (1×/2×/3×), zoom limits (min/max slider).
- **Controls:** Key rebinding table. Each action listed, current key shown, click to rebind. At minimum: move (WASD), jump, dash, interact/mine, place, inventory, map, pause.
- **Worldgen:** Seed input field. Only editable before a new game is created. Shown read-only once a world exists.
- Apply / Cancel / Reset to Defaults buttons.

*Implementation notes:*
- All settings persist to a `config/user_settings.lua` file (simple key=value table). Loaded at startup, written on Apply.
- The key rebinding table drives input handling in `gameloop.lua` — all inputs checked against the rebind table, not hardcoded keys.
- Missing or corrupt `user_settings.lua` → silently falls back to defaults. Never crash on missing config.

**4.7 — Hex Selector & Tile Targeting**
The full tile-targeting system, deferred from Phase 3.6. Build this alongside sprites — it requires knowing the art pipeline to get the elevation correct.

- `hovered_hex` updated every frame via `camera:screen_to_world()` + `hex.pixel_to_hex()`.
- **Reach constraint:** only tiles within N hexes of player are targetable (configurable in `config/balance.lua`). Tiles out of reach show a dimmed highlight, not the active selector color.
- **Elevation-correct outline:** draw the selection ring on the top-face polygon at the tile's actual isometric height — not flat on the ground plane. This is the tricky part; it requires the same `world_to_screen` pipeline the renderer uses.
- **Mode-aware behavior:**
  - *Mining mode:* highlight the targeted solid tile; show crack overlay if partially damaged.
  - *Place mode:* highlight the target air tile adjacent to a solid face; show ghost preview of the item being placed (green tint = valid placement, red = invalid).
  - *Inspect mode (default):* hover tooltip showing tile name, category, hardness remaining, any embedded ore. Jade-style: small floating panel, doesn't obscure the target.
- **Wall targeting:** aim between two hexes (at a shared edge) to target a wall slot. The selector switches from a hex outline to an edge-segment highlight.
- Ghost preview and tooltip are the two visual elements most dependent on sprite assets — stub them with colored rectangles until sprites exist.

---

### PHASE 5 — Calendar, Time & Weather
*The heartbeat of the world. Every other system listens to this one.*

**5.1 — Tick System & Delta Time** (`src/systems/clock.lua`)
- Master `game_time` counter in ticks. A tick = one `update(dt)` call.
- Real time → game time conversion: configurable ratio in `config/worldgen.lua`.
- All time-dependent systems derive from `game_time` via pure functions: `Clock.get_hour()`, `Clock.get_day()`, `Clock.get_month()`, `Clock.get_season()`, `Clock.get_year()`.
- **Delta time (`dt`) is passed to every single update function.** No exceptions. This ensures the game runs identically at 30fps and 144fps.

**5.2 — Calendar**
- 12 months with dwarfy names (e.g., *Stonehearth, Ironbloom, Ashfall, Frostdeep*...). Varying day counts per month — totals something like 364 in-game days per year.
- 4 seasons, each spanning 3 months.
- Day length varies by season: sinusoidal offset on sunrise/sunset hours. Midsummer days are ~50% longer than midwinter. This is a real feel difference, not cosmetic.
- Calendar drives: crop growth validity, NPC behavior, weather probability, ambient light color.

**5.3 — Moon Cycle**
- Independent 28-day cycle (doesn't need to align perfectly with the calendar — keeps it feeling natural).
- 8 phases: New → Waxing Crescent → First Quarter → Waxing Gibbous → Full → Waning Gibbous → Last Quarter → Waning Crescent.
- Phase `0..7` exposed as a global for magic system to read.
- Full moon: magic power peaks, certain enemies are stronger, rare events can trigger.
- New moon: magic is weakest, certain stealth bonuses.

**5.4 — Weather System**
- State machine: Clear → Cloudy → [Rain | Snow | Storm] → Clearing → Clear.
- Transition probability weights shift by season: spring is rainy, summer has occasional storms, autumn has wind/leaves, winter brings snow.
- Storm intensity is a separate variable — a storm state can be "light shower," "heavy rain," or "thunderstorm" (with lightning strikes as rare events).
- Visual overlays: falling pixel streaks for rain/snow, intensity-scaled opacity.
- Snow accumulates on surface tiles as a cosmetic overlay layer.
- Rain auto-waters tilled soil tiles — interacts with farming system.
- Ambient particles: falling leaves in autumn, snow flurries in winter, pollen motes in spring, heat shimmer hints in summer. These are purely cosmetic but make the world *feel* alive.

**5.5 — Ambient Lighting**
- Time-of-day lighting: dawn (warm orange), midday (bright white), dusk (amber), night (cool dark blue).
- Season tint: winter has a cooler cast, summer warmer.
- Underground: feeds into 5.6 — the ambient level sets the base darkness that source lights brighten from.
- Implement as a fullscreen color multiply pass — relatively cheap, high visual impact.

**5.6 — Source Lighting & Light Propagation**
The proper underground lighting system. Phase 3.8 gives a basic placeholder (distance falloff, no occlusion). This replaces it.

- **Light map:** A per-tile integer `light_level` in [0, MAX_LIGHT]. Stored in a transient table for the currently loaded chunk set — not persisted (regenerated on load from tile luminosity + entity positions).
- **BFS flood-fill from each source:** Each luminous tile or torch entity seeds a BFS. Each step away from the source decreases `light_level` by 1. Stop at 0. Solid opaque tiles block propagation (light doesn't bend around corners). This gives correct occlusion — light pools behind walls, doesn't bleed through stone.
- **Render integration:** In the underground draw pass, each tile's color is multiplied by `light_level / MAX_LIGHT` before draw. At `light_level = 0`, the tile renders fully dark (the `COL_OCCLUDED` dark grey becomes the floor, not black — add a separate `COL_DARK` for true unlit tiles).
- **Source types:** Torch entity (radius ~8), Lava tile (radius 6, already `luminous = 6` in registry), Glow ore like diamond (radius 1–2).
- **Dynamic updates:** When a torch is placed/removed or a lava tile changes, re-run BFS for that source region only. Don't rebuild the entire light map per frame — only dirty regions. The sleeping-tile model from the chunk system applies here.
- **Performance ceiling:** Limit concurrent active light sources per loaded chunk set (e.g., 64 max). Beyond that, oldest sources are demoted to the ambient floor. In practice players rarely place 64 torches in one area.
- **MAX_LIGHT = 15** (Minecraft convention; fits in 4 bits, could be packed into chunk metadata later).

---

### PHASE 6 — Crafting System

**6.1 — Recipe Registry** (`config/recipes.lua`)
- `Recipe = { output_id, output_count, inputs = { {item_id, count}, ... }, station, skill_req }`
- Loaded at startup, never modified at runtime.
- Station types: Hand (no station), Workbench, Anvil/Forge, Furnace/Smelter, Alchemy Table, Cooking Pot, Kiln, Enchanting Circle.

**6.2 — Crafting UI**
- Recipe book: all recipes are visible from the start, but unavailable ones are grayed out.
- Filter by station and by "craftable now."
- Hovering a recipe shows: inputs needed, what you have, what's missing.
- Pressing craft consumes ingredients and produces the item instantly (or queues it for station-based recipes).

**6.3 — Station-Based Processing**
- Furnace / Smelter: fuel slot + ore slot → metal bar over time. Different ores → different smelt times.
- Cooking Pot: ingredient slots → cooked meal with temporary buff effects (healing, stamina regen, strength, etc.).
- Kiln: clay → ceramic tiles, bricks.
- Alchemy Table: reagents → potions, poisons, enchanting materials.
- All processing times in `config/balance.lua`.

---

### PHASE 7 — Farming & Animals

**7.1 — Tilled Soil**
- Hoe tool converts grass/dirt hex → tilled soil tile.
- Tilled soil state: `dry` or `watered`. Dries out after N in-game hours. Rain auto-waters.
- Crops die on dry soil after a grace period.

**7.2 — Crop System**
- Each crop: `{ valid_seasons[], growth_stages, ticks_per_stage, yield_item, yield_range, water_required }`
- Tile tracks: `crop_id`, `growth_stage`, `ticks_in_stage`.
- Stage advance each game tick if: correct season, soil watered, tile has adequate light.
- Sprite changes per stage. Final stage: shows harvestable visual cue.
- Out-of-season crops stop growing; planted in wrong season die after a delay.

**7.3 — Walls & Pens (prerequisite for animals)**
- Wall segments live on hex edges, not in the tile grid.
- Each hex has 6 edge slots. A wall occupies one edge slot.
- Wall data stored separately: `wall_grid[q][r][edge_index] = wall_type_id` (or nil if empty).
- Rendered as a short parallelogram strip along that hex edge.
- An "enclosed" region: flood-fill from a hex — if no un-walled path exits, the region is enclosed.
- Animals will only stay in enclosed regions.

**7.4 — Animals**
- Passive animals (chicken, sheep, cow, goat) spawn in the world; player must catch and pen them.
- Penned animals: produce resource on a timer (egg, milk, wool). Require a feed tile nearby.
- Hunger: no feed → production stops → animal eventually dies.
- Slaughter: interact with butcher option → drops meat (and hide/bone if applicable).
- Wild animals (deer, boar, rabbit): roam the overworld, can be hunted for meat and materials.

---

### PHASE 8 — Combat System
*This is where the game either feels great or feels like a chore. Spend the most iteration time here.*

**8.1 — Combat Foundation**
- All combat entities share: `health`, `max_health`, `defense`, `stagger_points`, `stagger_threshold`.
- Damage model: `damage_dealt = max(1, attack_power - defense)`.
- Stagger: accumulate stagger points on hit; when threshold reached, enemy staggers (briefly unable to act). Resets on stagger recovery.
- Hitboxes: per-entity polygon or radius. Checked when attack arc is active.

**8.2 — Melee**
- Attack input: LMB or button press.
- Swing arc: a cone polygon in the player's facing direction, active for N frames.
- Each swing tracks a "hit list" — an entity can only be hit once per swing. No hit-stun spam.
- Knockback: push the hit entity along the attack direction vector.
- Weapon stats: `attack_power`, `swing_speed`, `arc_width`, `reach`. All in item definition.

**8.3 — Dodge / Dash**
- Separate inputs: dash (movement with brief i-frames), dodge roll (longer i-frames, shorter distance).
- During i-frames: entity is intangible to all attacks.
- Visual: ghost trail (draw sprite at previous positions with fading alpha).
- Stamina cost. No stamina = no dash. Forces the player to manage resources mid-combat.

**8.4 — Parry**
- Timing window opens when an incoming attack is within N frames of landing.
- Player presses parry button in window: success → reflect 25% damage, stagger the attacker, brief global slow (0.3s at 0.2 timescale).
- Miss the window: take full damage, no partial mitigation.
- This should feel rewarding but rare. The window is tight.

**8.5 — Archery**
- Hold charge → draw meter fills → release fires.
- Arrow entity: has velocity, applies gravity in the current layer (arcs downward). Collision with tiles = embeds. Collision with enemies = damage + pin chance.
- Quiver count is a real resource. Running out mid-fight is a real risk.
- Arrows: craftable (wood + feather + iron tip). Variant arrows: fire arrow, poison arrow (alchemy table recipes).

**8.6 — Magic**
- Spells cost mana. Mana regens slowly over time (config-driven rate).
- Moon phase multiplier: Full moon = `1.5×` power, New moon = `0.7×` power.
- Scrolls in hotbar: one-time-use powerful spells. Craftable at Alchemy Table or found as loot.
- Starter spells (unlocked/learned): Fireball (projectile), Frost Nova (area slow), Blink (short teleport utility), Barrier (brief shield).
- Enchanting at the Alchemy Table: apply permanent spell properties to weapons/armor. Moon phase at time of enchanting affects quality.

**8.7 — Enemy AI**
*Big task. Build in layers — start dumb, get smart.*

- **Layer 1 (ship it):** Simple state machine. States: Idle → Patrol (wander nearby) → Alert (player spotted) → Chase → Attack → Flee (low health).
- **Layer 2 (polish):** A* pathfinding on the current layer's hex grid. Limit search radius (e.g., 20 hexes max). Time-slice: each enemy only pathfinds every N frames, staggered so no two enemies pathfind on the same frame.
- **Layer 3 (late game):** Multi-layer awareness — enemies can use stairs, react to sounds from other layers.
- Enemy types: Melee Brute (charge + heavy hit), Ranged Skirmisher (keep distance, kite), Caster (area spells, requires line of sight), Pack Leader (buffs nearby allies).
- Spawning: spawn points placed by worldgen in structures and wilderness. Respawn rules per area (some areas respawn, cleared dungeons stay clear).

---

### PHASE 9 — Economy & NPCs
*Moved before water — the world needs people before it needs flooding.*

**9.1 — NPC Entities**
- Early game: NPCs as rare random encounters — found in structures, wandering the overworld. A hermit mage, a lost merchant, a goblin trader.
- Late game: build an **Enchanted Summoning Hex** at your hold to permanently attract a merchant class. Expensive to build, game-changing when complete.
- Each NPC has: `class`, `shop_inventory`, `coin_balance`, `dialogue_state`.
- Dialogue: simple state machine. Greeting → Browse/Trade → Farewell. No branching quest dialogue yet (that's a future feature).

**9.2 — Dynamic Economy**
The economy should *react* to the player. If you flood the market with pumpkins, pumpkin prices drop. This discourages single-item farming and encourages diversification.

- Each item has a `base_price` and a `supply_level` (how much the player has sold recently).
- Price formula: `current_price = base_price * (1 / (1 + supply_level * elasticity))`.
- `elasticity`: how sensitive the price is to supply. Food = low elasticity (always needed). Luxury goods = high elasticity (market saturates fast).
- Supply levels decay over time (market recovers).
- Denominations: Copper, Silver, Gold coins. Automatic conversion (100 copper = 1 silver, 100 silver = 1 gold). Items priced in a single "value" unit, converted to coins on display.
- NPC preferences: a Farmer NPC won't pay well for a fireball scroll. Class-based buy lists in NPC definition.

**9.3 — NPC Scheduling**
- NPCs follow schedules driven by `Clock.get_hour()`.
- Day: at their post/shop. Night: at their home location (wander radius, or specific "home" tile).
- Some NPCs have special schedule entries (market day, festival day — hooks for future content).

---

### PHASE 10 — Water Physics
*Implement after the core loop is fun. Water is technically complex and perf-sensitive.*

**10.1 — Volume Model**
- Each water tile stores `volume` (0.0 to 1.0, where 1.0 = full tile).
- Ocean and spring source tiles: `volume = math.huge` — they never empty.
- Each tick: water equalizes with neighbors. Flow rate = function of volume difference and gravity.
- Gravity priority: always fill the tile directly below before spreading horizontally.
- Sleeping tiles: a water tile that is full and all neighbors are full doesn't compute. Wake it when a neighbor changes.

**10.2 — Layer Flow**
- If a water tile's volume overflows and the tile at `(q, r, layer - 1)` is air → spawn water tile there with the overflow volume.
- This creates waterfalls across layers.
- Cap simultaneous active water tiles per frame. Queue overflow for next frame if cap is hit.

**10.3 — Destruction Events**
- When a tile is mined: check all 6 neighbors + the tile above. If any are water → trigger a "flow wake" event for that water tile.
- Flow wake: that tile and all adjacent water tiles become active (un-sleep) for physics.
- This is how you get the Dwarf Fortress moment of "oops, I mined the wall holding back the lake."

**10.4 — Rendering**
- Animated water surface: sine-wave vertical pixel offset, slightly different phase per tile (so it doesn't ripple in sync).
- Partial volume: tile draws water filling only the bottom `volume * hex_height` pixels.
- Semi-transparent: underlying tile faintly visible through shallow water.
- Depth color: shallow water → light blue, deep water → dark navy.

---

### PHASE 11 — Fishing
*Pinned. Revisit when the core loop feels complete and you want a chill counterpoint to combat.*

Options when ready:
- **Rhythm window:** A fish tension indicator bounces back and forth. Hit the button when it's in the sweet spot.
- **Tension bar (Stardew-style):** Fish pulls the hook around, you reel — balance between too much and too little tension. Proven to feel good.
- Fish variety: type depends on biome, season, time of day, weather, moon phase (tie it to the calendar system).
- Rare catches: legendary fish as trophies, quest items, or high-value trade goods.

---

### PHASE 12 — Polish & Systems Integration
*The endless phase. Never truly done, but the most satisfying.*

- **Audio:** ambient loops per biome/time, SFX per action (mining, footstep per surface, combat hits, spell sounds), musical stings for events (enemy spotted, boss fight, full moon).
- **Particles:** mining dust (color per material), blood on combat hit, spell trails, leaf particles from trees, rain splash on water, firefly ambience at night.
- **Save/Load:** serialize world chunks to disk (binary + zlib), serialize entity state and player inventory. Save to named files. Autosave on day change.
- **Settings Menu:** key rebinding, volume sliders, rendering options (zoom limits, UI scale), worldgen seed input.
- **Title Screen:** world seed input, load existing saves, settings, credits.
- **Death Screen:** brief cause-of-death message, respawn at last bed or world start.
- **Balancing pass:** all tunable values live in `config/balance.lua`. Do a full playthrough pass adjusting them.

---

## Phase Build Order (TL;DR)

```
✅ Phase 1   → Foundation: hex math, tile registry, chunk system, camera, renderer
✅ Phase 2.1 → Noise infrastructure (simplex 2D/3D, fBm, seed hashing)
✅ Phase 2.2 → Island height map (surface_layer, sigmoid falloff)
✅ Phase 2.4 → Subsurface bands (dirt, marble, grimstone, sand/beach)
✅ Phase 2.5 → Ore generation (coal, gold, diamond, mithril — 3D noise blobs)
⏳ Phase 2.3 → Soft biome config defined; implementation just before 2.8
✅ Phase 2.6 → Caves (anisotropic noise carving, surface breaching)
   Phase 2.7 → Water seeding (ocean flood-fill from world edge)
   Phase 2.8 → Trees & vegetation (multi-tile entities, biome-driven density)
   Phase 2.9 → Structures (mine shafts, towers, camps — stamp templates)
   ── resolve chunk streaming PIN before Phase 3 ──
   Phase 3   → Player: movement, vertical travel, mining, building, inventory, lighting placeholder
   Phase 4   → HUD & GUI: hotbar, vitals, tooltip, inventory screen
   Phase 5   → Calendar, time, weather, ambient + source lighting
   Phase 6   → Crafting: recipes, stations, smelting
   Phase 7   → Farming & animals: walls, crops, pens
   Phase 8   → Combat: melee → dodge/parry → archery → magic → enemy AI
   Phase 9   → Economy & NPCs: encounters, trading, dynamic prices
   Phase 10  → Water physics: volume model, flow, destruction events
   Phase 11  → Fishing (when inspired)
   Phase 12  → Polish: audio, particles, save/load, balancing
```

---

## Config Files

Config files are the source of truth. Read them directly — don't trust any snapshot in this doc.

- [`config/worldgen.lua`](worldgen.lua) — all world generation constants (seed, island shape, dirt/marble/grimstone/ore/cave/biome params)
- [`config/tiles.lua`](tiles.lua) — 30 tiles (IDs 0–29), permanent IDs, never renumber
- `config/balance.lua` — gameplay tuning (player stats, mining speed, combat timing, economy decay) — **not yet created**
- `config/items.lua` — item definitions — **not yet created**
- `config/recipes.lua` — crafting recipes — **not yet created**

---

## Running Performance Checklist

Before shipping any system, verify:
- [ ] No per-frame full-world iteration
- [ ] Sleeping tiles implemented for any tile-simulation system (water, fire, crop growth)
- [ ] Enemy AI pathfinding is time-sliced across frames
- [ ] Chunk culling happens before any per-tile draw calls
- [ ] Delta time (`dt`) used in every movement and timing calculation
- [ ] New system profiled with LÖVE's built-in stats (`love.graphics.getStats()`)

---

---

## Noted Ideas (not yet phased — revisit when core loop is solid)

These came up during Phase 1 design. They are deliberate deferments, not forgotten.

### Tile Gravity
Some tiles should fall when unsupported: sand, gravel, loose dirt.
Beyond that: a **RimWorld-style structural support simulation** where any block
not connected (within some radius) to a pillar or ground collapses. This makes
mining feel genuinely dangerous — undercut a cliff and it comes down.
- Simplest version: `gravity = true` flag on tile types; on `set_tile`, if the
  tile below is air, queue the tile for a fall-tick next frame.
- Full structural version: much more complex. Defer until post-Phase 8 when the
  world simulation layer is mature.

### Tile Spread / Growth
Tiles that convert adjacent tiles over time:
- Grass spreads onto bare dirt if the dirt tile has sky exposure.
- Mycelium spreads in dark/damp areas underground.
- Fire spreads to adjacent organic tiles, burns out after N ticks.
- Crops grow stage-by-stage (already planned in Phase 7 — this is the same
  mechanism applied more broadly).
Implementation path: a `behavior` table on tile definitions (e.g.,
`behavior = { spread_to = "dirt", chance_per_tick = 0.002 }`).
Wire into the sleeping-tile event system so it only runs when a tile is "awake".

### Tool–Category Efficiency
The `category` field already sets this up. When the mining system is built
(Phase 3.4), tool efficiency should be a multiplier table keyed by category:
`pickaxe = { stone = 3.0, ore = 3.0, surface = 1.5, organic = 0.8 }`
`axe     = { organic = 4.0, surface = 1.2, stone = 0.5 }`
Store in `config/balance.lua`. No changes to the tile definitions needed.

### Frustum Culling Debug Visualizer
The chunk culling logic (skipping chunks outside the camera rectangle) has never been
visually verified — it *looks* right from normal zoom but hasn't been unit-tested at the
chunk boundary level. Before Phase 3, add a debug overlay that:
- Draws an **orange bounding box** in world-pixel space showing the current camera frustum
  (the exact rectangle the renderer uses to cull chunks).
- Optionally draws chunk boundary grid lines so you can see which chunks fall inside/outside.
- Lets you zoom far out to watch chunks load and unload at the edges as you pan — confirming
  the LRU eviction and `preload_near` radius are working correctly.

The current behaviour (lots of land visible when zoomed out) is correct. This is just about
making the correctness *visible* and auditable. Add to `src/core/debug.lua` as a new toggle.

### Worm Cave Generation (post-game-loop)
The current noise-cave system produces flat ellipsoidal chambers — good enough to nail the game loop. Worm caves would add navigable, branching tunnel corridors with inertia-driven heading (think Terraria worm enemies, but as the cave shape itself). They would feel more natural and explorable than noise pockets.

The blocker is performance: worm cave generation requires tracing deterministic paths from seeded origin points, which means each chunk needs to reconstruct which worms enter it from neighbouring chunks. This is fundamentally more expensive than a per-tile noise threshold check, and the current chunk load latency is already hitting ~6 FPS spikes. Worm caves are not viable until the chunk streaming PIN is resolved (Option B — `love.thread` background generation).

**When to revisit:** after chunk streaming is thread-safe and generation spikes are gone. The worm pass would sit alongside the noise caves (add tunnels that connect existing chambers) rather than replacing them.

### Richer Drop Tables
Currently each tile has one `drop_item` string. Eventually tiles should
support weighted drop tables with tool requirements:
`drops = { { item = "coal", count = {1,3}, min_tool = "pickaxe" }, ... }`
Defer until the item and crafting systems exist (Phases 3.7 / 6).

---

## Polish (Deferred)

Items accepted as "good enough for alpha" with a known root cause. Collect here so they are not lost; revisit in a dedicated polish pass after core gameplay is solid.

### Painter's Algorithm Edge-Clip
**Symptom:** Player sprite briefly appears behind tiles for 1–2 frames when crossing a hex row boundary. Most visible when moving west (screen-left).

**Root cause:** The painter's algorithm depth-sorts entities by their axial hex row (`player.r`), which is an integer that snaps at hex boundaries. The sprite, however, moves continuously in world-pixel space. For the frame(s) when the player's visual position straddles two rows, the row key does not match the sprite's visual depth, causing a momentary clip.

**Why it is worse moving west:** In flat-top axial coordinates, moving screen-left (−x) simultaneously decreases `q` *and* increases `r` (because `r = (−px/3 + py√3/3) / SIZE`). Row transitions therefore happen more frequently per unit distance than when moving east or north/south.

**Real fix:** Per-pixel depth compositing, a depth buffer, or a Y-sorted sprite layer separate from the tile pass. All require a different rendering architecture.

**Practical mitigations (deferred):**
1. Collision (Phase 3.2) — player stays on valid surface tiles, reducing continuous mid-hex traversal.
2. PNG sprite transparency — once vegetation tiles use real sprites with alpha, the "clipping behind a tree" case is largely invisible.
3. Sub-row injection — compute painter row from the sprite *foot* pixel rather than the hex centre (minor improvement, complex to tune).

---

*Living document — update the phase status and add notes as features are built.*
*Version: 0.7 — Phase 2.6 complete: anisotropic noise caves (flat ellipsoidal chambers, surface breaching). Next: Phase 2.7 water seeding.*
