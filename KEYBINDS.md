# Dwarf Island V4 — Keybinds

## Camera — Movement
| Key | Action |
|-----|--------|
| `W` / `↑` | Pan camera up |
| `S` / `↓` | Pan camera down |
| `A` / `←` | Pan camera left |
| `D` / `→` | Pan camera right |

## Camera — Zoom
| Key | Action |
|-----|--------|
| `=` / `+` | Zoom in |
| `-` | Zoom out |
| Scroll wheel | Zoom in / out (smooth) |

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

## UI
| Key | Action |
|-----|--------|
| `J` | Toggle jade HUD (tile name under cursor, top-center) |

## Debug Overlays
| Key | Action |
|-----|--------|
| `F3` | Toggle all debug overlays (master switch) |
| `F1` | Toggle HUD (FPS, layer, depth, hover coords, render mode) |

---

## HUD Reference
The HUD bar at the bottom of the screen shows:
```
FPS:60  |  overworld  |  layer 768 (sea)  |  (12,-4)  |  occl:on  |  Tab  PgUp/Dn  Home  O  F1  F3
```
- **mode** — `overworld` or `underground`
- **layer N (tag)** — current camera layer; tag is depth below sea (`↓`), above sea (`↑`), or `sea`
- **(q, r)** — hex coordinates under the mouse cursor
- **occl** — occlusion state (`on` = side faces culled, `OFF` = all faces drawn)
