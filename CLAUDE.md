# Dwarf Island V4 — Claude Session Reference

## Process (always)
- Read `config/dwarf_island_v4.md` before any significant task.
- Break tasks into granular sub-steps. Present the plan. Get user approval. Then implement one step at a time.
- The user reads at human speed. Do not implement an entire phase in one message.

## Current Status
- **Phase 1 — COMPLETE:** hex math, tile registry, chunk system, camera, basic renderer.
- **Phase 2 — COMPLETE:**
  - ✅ 2.1 Noise infra · ✅ 2.2 Island shape · ✅ 2.3 Biome config · ✅ 2.4 Subsurface bands
  - ✅ 2.5 Ores · ✅ 2.6 Caves · ✅ 2.7 Ocean BFS (FFI, ~100 MB, beach baked in) · ✅ 2.8 Plants/trees
- **Phase 3 — IN PROGRESS:**
  - ✅ 3.1 Player entity — WASD, world-pixel position, spritesheet (static + airborne frame), painter's-algo depth injection
  - ✅ 3.2 Vertical physics & collision — fixed-rate physics (VERT_RATE), three-state system (jumping/falling/grounded), integer-boundary floor checks, dt cap, shadow, SAT hex-vs-hex wall collision, air control + jump speed multiplier
  - ✅ 3.3 Layer visibility — canopy opacity (transparent tiles render at 50% alpha), trunk top/side rendering through transparent neighbours
  - 🔲 3.4 Mining — **next up**

## North Star
**Efficiency above all.** Design to run well before it looks good. If it lags, it fails.

## Architecture — Locked In, Do Not Change
| Concern | Decision |
|---|---|
| Coordinates | Axial hex `(q, r, layer)`. Cube only for distance/rotation math. |
| World size | 8192×8192×1024 tiles. Sea level = layer 768. Bedrock = layer 0. |
| Chunk geometry | 32×32×8 tiles. CHUNK_SIZE=32 (h), CHUNK_DEPTH=8 (v). 128 vertical chunk layers. |
| Chunk loading | 7 horizontal × 3 vertical = 21 chunks. MAX_COLUMNS=128 LRU cache. |
| Tile IDs | uint16. 0=air, 1=bedrock. Never renumber. No `mineable` field — bedrock uses `hardness=math.huge`. |
| Tile categories | `"special"`, `"surface"`, `"stone"`, `"ore"`, `"liquid"`, `"organic"` |
| Renderer | Painter's algorithm: layer asc → row asc → col. Side faces culled per-frame via neighbor check. Do NOT precompute face visibility unless profiling proves it's a bottleneck. |
| Game clock | 1 real second = 1 game minute. `world.game_time` += `dt` each frame. |
| Tick system | Per-chunk sorted `tick_list` `{idx, next_stage_time}`. register_tick on place, deregister_tick on remove/harvest. |
| Render config | hex_size=48, layer_height=48, layers_above=1, layers_below=2, cam_speed=400. |

## Performance Rules (Non-Negotiable)
- Never iterate all tiles every frame. Dirty flags and event queues only.
- Chunk-level culling first, tile-level second.
- Sleeping tiles: water, fire, crops only compute when "awake" (neighbor changed).
- Time-sliced AI: enemies stagger pathfinding across frames.
- `dt` everywhere. No frame-rate-dependent logic. Ever.

## ⚠️ PIN — Chunk Load-Lag (resolve before Phase 3)
Chunk generation blocks the main thread. Not acceptable in Phase 3 (combat). Key tactics:
1. **Frame budget cap** — never generate a full chunk in one frame. Cap to ~2–4 ms, queue the rest.
2. **Limit concurrency** — max 1–2 chunks generating per frame, priority-queued (current chunk first).
3. **Profile first** — wrap gen phases with `os.clock()`. Find the real bottleneck before touching anything.
4. **No per-tile allocations** — no `{}` inside the triple generation loop (GC spikes = lag).
5. **Separate gen from render build** — mark chunk dirty, let renderer pick it up next frame.
6. **Long-term: `love.thread`** — background gen is the only combat-safe solution. Build budget system first.
Full discussion in `config/dwarf_island_v4.md` → "PIN — Chunk Streaming & Load-Lag Mitigation".

## Key File Locations
```
main.lua / conf.lua          → project root (MUST be here for LÖVE2D)
src/core/hex.lua             → all hex math (flat-top axial, SIZE set at runtime)
src/core/gameloop.lua        → LÖVE2D callbacks, camera panning, zoom, layer shift
src/core/debug.lua           → F3=toggle all, F1=toggle HUD, H=toggle hex grid
src/world/chunk.lua          → ChunkColumn: data, meta, tick_list, register/deregister_tick
src/world/world.lua          → World cache, get/set_tile, preload_near, game_time
src/world/tile_registry.lua  → SOLID/TRANSPARENT/HARDNESS/COLOR/COLOR_SIDE flat arrays (hot path)
src/render/camera.lua        → Camera: apply/reset, world_to_screen, screen_to_world
src/render/renderer.lua      → Tile draw: painter order, face culling, hover highlight, canopy alpha
src/entities/player.lua      → Player: world-pixel pos, SAT collision, fixed-rate physics, sprite
config/tiles.lua             → 30 tile definitions, IDs 0–29, never renumber
config/worldgen.lua          → seed, world dims, sea_level, ore/cave/tree params
config/render.lua            → hex_size, layer_height, layers_above/below, cam_speed
config/dwarf_island_v4.md    → full design doc, phase breakdown, architecture decisions
```

## Worldgen Config (already in worldgen.lua)
- Subsurface bands: dirt (1–10 layers) → stone → marble ribbons (3 bands) → grimstone floor (per-column noise)
- Ores: coal, gold, diamond, mithril — 3D noise blobs, depth-relative, only replace stone/grimstone
- Caves: anisotropic 3D noise threshold=0.98, scale_h=0.010, scale_v=0.050, ~2% of subsurface tiles, 5:1 elongation ratio, surface breaching allowed
- Trees: oak/birch/spruce/palm per species, height 3–10, canopy 1–4 (Phase 2.8)
- Island: radial falloff + sigmoid, 4-octave noise, surface_floor=720, surface_peak=820, sea_level=768

## Player Physics Constants (player.lua — tune here)
| Constant | Value | Notes |
|---|---|---|
| `SPEED` | 200 px/s | Ground movement speed |
| `VERT_RATE` | 4.75 layers/s | Rise AND fall — change this, everything derives |
| `JUMP_HEIGHT` | 1.25 layers | Peak height — change this, duration + multiplier auto-derive |
| `JUMP_SPEED_MUL` | derived | 2.25 × inradius ÷ (SPEED × airtime) — do not hardcode |
| `AIR_CONTROL` | 0.0 | 0 = locked to launch velocity; 1 = full steering |
| `PLAYER_HEX_R` | 24 px | SAT hitbox circumradius — half of tile size |

## Polish (Deferred — not forgotten)
Items accepted as "good enough for alpha" with a known root cause. Revisit in a dedicated polish pass.
- **Painter's algorithm edge-clip** — player sprite briefly pops behind tiles when crossing a hex row boundary; most visible moving west. Root cause: `player.r` is a discrete integer that snaps at hex boundaries while the sprite position moves continuously. Real fix: per-pixel depth compositing or a depth buffer (different rendering architecture). Natural mitigation: collision (3.2) stops mid-hex drifting; PNG sprite transparency hides vegetation clips.
- **Leaf side-face culling** — transparent leaf tiles don't cull side faces against each other inside the canopy. Visually harmless for now; will be replaced entirely by sprites.

## Noted Ideas (deferred, not forgotten)
- Tile gravity (sand/gravel) + structural support simulation (post-Phase 8)
- Tile spread (grass→dirt, mycelium, fire) via `behavior` table on tile defs
- Tool–category efficiency multiplier table in `config/balance.lua`
- Richer drop tables with weighted entries and min_tool requirements
