-- src/render/effects.lua
-- Short-lived visual hit effects: tile shake + particle burst.
--
-- Public API
--   Effects.hit(q, r, layer, tile_id)  -- trigger on mining swing
--   Effects.update(dt)                  -- advance timers (call from gameloop)
--   Effects.get_shake(q, r, layer)      -- returns px offset for tile draw (0 when idle)
--   Effects.draw_particles()            -- draw live particles (call inside cam:apply())

local Hex          = require("src.core.hex")
local RenderCfg    = require("config.render")
local TileRegistry = require("src.world.tile_registry")

local LAYER_HEIGHT = RenderCfg.layer_height

local Effects = {}

-- ── Shake ──────────────────────────────────────────────────────────────────
local SHAKE_DUR  = 0.12   -- seconds total
local SHAKE_AMP  = 2      -- px offset per phase
local SHAKE_FLIP = 0.020  -- seconds per direction flip (~50 Hz)

local shakes = {}   -- ["q,r,l"] = { t = remaining_seconds }

local function skey(q, r, layer)
    return q .. "," .. r .. "," .. layer
end

-- Returns the horizontal pixel offset this frame for tile (q,r,layer).
-- Returns 0 when the tile has no active shake.
function Effects.get_shake(q, r, layer)
    local s = shakes[skey(q, r, layer)]
    if not s then return 0 end
    local phase = math.floor(s.t / SHAKE_FLIP)
    return (phase % 2 == 0) and SHAKE_AMP or -SHAKE_AMP
end

-- ── Particles ──────────────────────────────────────────────────────────────
local PART_COUNT  = 7     -- particles per hit
local PART_LIFE   = 0.35  -- seconds
local PART_SPEED  = 90    -- max launch speed (px/s)
local PART_GRAV   = 160   -- px/s² downward acceleration

local particles = {}  -- { x,y,vx,vy,life,max_life,cr,cg,cb,size }

-- ── Public: register a mining hit ─────────────────────────────────────────
function Effects.hit(q, r, layer, tile_id)
    -- Shake
    shakes[skey(q, r, layer)] = { t = SHAKE_DUR }

    -- Particles: burst from tile's visual top-face centre.
    local px, py = Hex.hex_to_pixel(q, r)
    local cx = px
    local cy = py - layer * LAYER_HEIGHT   -- top face visual y

    local sc = TileRegistry.COLOR_SIDE[tile_id] or { 0.6, 0.6, 0.6 }

    for _ = 1, PART_COUNT do
        -- Random direction, biased upward (y decreases upward in LÖVE).
        local angle = math.random() * math.pi * 2
        local speed = math.random(20, PART_SPEED)
        particles[#particles + 1] = {
            x        = cx + (math.random() - 0.5) * 24,
            y        = cy + (math.random() - 0.5) * 10,
            vx       = math.cos(angle) * speed,
            vy       = math.sin(angle) * speed - 50,   -- subtract to bias upward
            life     = PART_LIFE,
            max_life = PART_LIFE,
            cr       = sc[1],
            cg       = sc[2],
            cb       = sc[3],
            size     = math.random(2, 4),
        }
    end
end

-- ── Public: register a watering splash (no shake, blue particles) ─────────
function Effects.splash(q, r, layer)
    local px, py = Hex.hex_to_pixel(q, r)
    local cx = px
    local cy = py - layer * LAYER_HEIGHT

    for _ = 1, 10 do
        local angle = math.random() * math.pi * 2
        local speed = math.random(20, PART_SPEED)
        particles[#particles + 1] = {
            x        = cx + (math.random() - 0.5) * 24,
            y        = cy + (math.random() - 0.5) * 10,
            vx       = math.cos(angle) * speed,
            vy       = math.sin(angle) * speed - 60,   -- bias upward
            life     = PART_LIFE,
            max_life = PART_LIFE,
            cr       = 0.20,
            cg       = 0.55,
            cb       = 0.95,
            size     = math.random(2, 4),
        }
    end
end

-- ── Public: update (call from GameLoop.update) ────────────────────────────
function Effects.update(dt)
    -- Advance shake timers; prune expired.
    for key, s in pairs(shakes) do
        s.t = s.t - dt
        if s.t <= 0 then shakes[key] = nil end
    end

    -- Advance particles; prune expired.
    local i = 1
    while i <= #particles do
        local p = particles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            particles[i] = particles[#particles]
            particles[#particles] = nil
        else
            p.x  = p.x  + p.vx * dt
            p.y  = p.y  + p.vy * dt
            p.vy = p.vy + PART_GRAV * dt
            i = i + 1
        end
    end
end

-- ── Public: draw particles in world space ────────────────────────────────
-- Must be called inside a cam:apply() / cam:reset() block.
function Effects.draw_particles()
    for _, p in ipairs(particles) do
        local alpha = p.life / p.max_life
        love.graphics.setColor(p.cr, p.cg, p.cb, alpha)
        love.graphics.rectangle("fill",
            math.floor(p.x - p.size * 0.5),
            math.floor(p.y - p.size * 0.5),
            p.size, p.size)
    end
    love.graphics.setColor(1, 1, 1)
end

return Effects
