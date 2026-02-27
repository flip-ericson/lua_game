-- config/render.lua
-- Visual / rendering constants.
-- Tweak hex_size here and relaunch to test how the grid feels.

return {
    -- Hex circumradius in pixels (center to corner).
    -- This sets how large every tile appears on screen.
    --   32  → 64 px wide hex  (default, matches 64-px art tiles)
    --   24  → 48 px wide hex  (zoomed out)
    --   48  → 96 px wide hex  (zoomed in / large monitor)
    hex_size = 48,

    -- Vertical screen pixels per world layer.
    -- Controls how tall cliff-face side strips appear and how much
    -- of the layer below peeks out beneath the layer above.
    -- Higher = more dramatic depth. Lower = flatter, more top-down.
    layer_height = 48,

    -- How many layers below the player's layer to render in underground mode.
    layers_below = 2,

    -- Camera panning speed in world-pixels per second (WASD / arrow keys).
    cam_speed = 400,
}
