# Dwarf Island V4 — Keybinds

## Player Movement
| Key | Action |
|-----|--------|
| `W` / `A` / `S` / `D` | Move player |
| `Space` | Jump |

## Hotbar
| Key | Action |
|-----|--------|
| `1` – `9` | Select hotbar slot 1–9 |
| `0` | Select hotbar slot 10 |
| `Scroll wheel` | Cycle hotbar slot (up = prev, down = next, wraps) |

## Inventory
| Key | Action |
|-----|--------|
| `I` | Open / close backpack (12×12 grid, slots 11–154) |
| `Esc` | Quit game |

## Camera — Zoom
| Key | Action |
|-----|--------|
| `=` / `+` | Zoom in |
| `-` | Zoom out |

## Camera — Layer (Vertical)
| Key | Action |
|-----|--------|
| `]` / `Page Up` | Move up 1 layer |
| `[` / `Page Down` | Move down 1 layer |
| `Shift + Page Up` | Move up 20 layers |
| `Shift + Page Down` | Move down 20 layers |
| `Home` | Snap back to sea level (layer 768) |

## Render Modes
| Key | Action |
|-----|--------|
| `Tab` | Toggle overworld ↔ underground view |
| `O` | Toggle occlusion culling on/off |
| `M` | Toggle world overview (zoom to fit entire island) — overworld mode only |

## UI / Debug
| Key | Action |
|-----|--------|
| `J` | Toggle jade HUD (tile name + HP under cursor, top-center) |
| `X` | Toggle instamine — LMB instantly breaks hovered tile and spawns its drops |
| `F3` | Toggle all debug overlays (master switch) |
| `H` | Toggle HUD (FPS, layer, depth, hover coords, render mode) |

---

## HUD Reference
The HUD bar at the top of the screen shows:
```
FPS:60  |  overworld  |  layer 768 (sea)  |  (12,-4)  |  occl:on  |  Tab  PgUp/Dn  Home  O  X  H  F3
```
- **mode** — `overworld` or `underground`
- **layer N (tag)** — current camera layer; tag is depth below sea (`↓`), above sea (`↑`), or `sea`
- **(q, r)** — hex coordinates under the mouse cursor
- **occl** — occlusion state (`on` = side faces culled, `OFF` = all faces drawn)
