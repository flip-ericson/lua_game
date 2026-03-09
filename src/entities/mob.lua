-- src/entities/mob.lua
-- Base mob entity: world position, HP, FSM, sprite rendering.
--
-- Step 1 — rendering only.
-- Step 2 — flat-terrain A* wander: Idle ↔ Wander FSM, smooth movement.
-- Step 3 — vertical pathfinding (extend Pathfinder neighbor expansion).
-- Step 4 — Flee state (turkey done).
-- Step 5 — Chase/Attack states (orc).
-- Step 6 — neutral→hostile on hit (wizard).

local Hex         = require("src.core.hex")
local RenderCfg   = require("config.render")
local Pathfinder  = require("src.core.pathfinder")
local Physics     = require("src.core.physics")

local LAYER_HEIGHT = RenderCfg.layer_height

-- All mobs render at exactly 46×46 px — same as the player sprite.
local RENDER_W = 46
local RENDER_H = 46

-- ── Wander parameters ─────────────────────────────────────────────────────
local IDLE_MIN      = 2.0   -- seconds before next wander attempt
local IDLE_MAX      = 5.0
local WANDER_RADIUS = 6     -- max hex distance for a wander target
local PATH_BUDGET   = 200   -- max A* nodes per call (frame-safety cap)
local ARRIVE_DIST   = 2.0   -- px: snap to step target when this close

-- ── Physics parameters ────────────────────────────────────────────────────
local HEX_SQRT3    = math.sqrt(3)
local MOB_HEX_R    = 24                              -- SAT hitbox circumradius (px)
local MOB_INRADIUS = MOB_HEX_R * HEX_SQRT3 * 0.5
local MOB_VERT_RATE = 4.75  -- layers/s fall rate (matches player)
local MOB_MAX_DT    = 1/15  -- clamp: never simulate more than ~4 frames
local LOS_HALF_W   = MOB_INRADIUS  -- corridor half-width for LoS checks
local HEX_SPACING  = RenderCfg.hex_size * HEX_SQRT3  -- px between adjacent hex centres

-- Pick a random wander target within radius hexes of (q, r).
-- Returns tq, tr (no guarantee it's walkable — pathfinder handles that).
local function pick_target(q, r, radius)
    for _ = 1, 20 do
        local dq = math.random(-radius, radius)
        local dr = math.random(-radius, radius)
        local d  = math.max(math.abs(dq), math.abs(dr), math.abs(dq + dr))
        if d >= 2 and d <= radius then
            return q + dq, r + dr
        end
    end
    -- Fallback: one step east.
    return q + 1, r
end

-- ── Mob class ─────────────────────────────────────────────────────────────

local Mob = {}
Mob.__index = Mob

-- def   : entry from config/mobs.lua
-- q, r  : starting hex coordinates
-- layer : floor layer (solid tile the mob stands on; body at layer+1)
function Mob.new(def, q, r, layer)
    local x, y = Hex.hex_to_pixel(q, r)

    local spr = love.graphics.newImage(def.sprite)
    spr:setFilter("nearest", "nearest")
    local iw, ih = spr:getDimensions()

    return setmetatable({
        def    = def,

        -- Position (mirrors player convention).
        q      = q,
        r      = r,
        layer  = layer,
        x      = x,
        y      = y,
        z      = layer + 0.0,   -- float layer; integer = grounded

        hp     = def.hp,

        -- Sprite.
        sprite   = spr,
        _scale_x = RENDER_W / iw,
        _scale_y = RENDER_H / ih,

        -- ── FSM ───────────────────────────────────────────────────────────
        -- States: "idle"  — standing still, waiting
        --         "wander"— following A* path to a random target
        state      = "idle",
        idle_timer = math.random() * (IDLE_MAX - IDLE_MIN) + IDLE_MIN,

        -- Physics state (mirrors player convention).
        grounded = true,
        falling  = false,

        -- Path-following (used in "wander" state).
        path     = nil,   -- array of {q, r, layer} steps
        path_idx = 1,     -- index of the next step to move toward

        -- Step-up state: set when the next waypoint is one layer higher.
        stepping_up    = false,
        _step_up_layer = 0,

        -- Awareness: timer counts down to next player-proximity check.
        awareness_timer = def.awareness_interval
                          and (math.random() * def.awareness_interval) or 0,
    }, Mob)
end

-- ── FSM helpers ───────────────────────────────────────────────────────────

function Mob:_enter_idle()
    self.state         = "idle"
    self.idle_timer    = math.random() * (IDLE_MAX - IDLE_MIN) + IDLE_MIN
    self.path          = nil
    self.path_idx      = 1
    self.stepping_up   = false
    self._step_up_layer = 0
end

function Mob:_start_wander(world)
    local tq, tr = pick_target(self.q, self.r, WANDER_RADIUS)

    -- Find the nearest walkable layer at the target hex (terrain may differ in height).
    local tl = Pathfinder.surface_layer(world, tq, tr, self.layer)
    if not tl then
        self:_enter_idle()
        return
    end

    local tx, ty = Hex.hex_to_pixel(tq, tr)

    -- 1. Direct line of sight (same layer only): skip A* if the corridor is clear.
    if tl == self.layer and
       Pathfinder.line_of_sight(world, self.x, self.y, tx, ty, self.layer, LOS_HALF_W) then
        self.path     = { {q = tq, r = tr, layer = tl} }
        self.path_idx = 1
        self.state    = "wander"
        return
    end

    -- 2. Fall back to A* (now vertical-aware), then reduce with string pulling.
    local raw = Pathfinder.find_path(
        world,
        self.q, self.r, self.layer,
        tq,     tr,     tl,
        PATH_BUDGET)

    if raw and #raw > 0 then
        self.path     = Pathfinder.string_pull(world, raw, self.x, self.y, self.layer, LOS_HALF_W)
        self.path_idx = 1
        self.state    = "wander"
    else
        -- No reachable path — wait and try again.
        self:_enter_idle()
    end
end

-- ── Awareness / Flee ──────────────────────────────────────────────────────

-- Called when the awareness timer fires.  Checks player distance and
-- transitions between idle/wander and flee as appropriate.
function Mob:_check_player(world, player)
    local def = self.def
    local interval = def.awareness_interval or 2.0

    if not player then
        self.awareness_timer = interval
        return
    end

    -- Axial hex distance.
    local dq   = self.q - player.q
    local dr   = self.r - player.r
    local dist = math.max(math.abs(dq), math.abs(dr), math.abs(dq + dr))

    self.awareness_timer = interval  -- always the same cadence
    if dist <= (def.sense_radius or 0) then
        self:_start_flee(world, player)
    elseif self.state == "flee" then
        self:_enter_idle()
    end
end

-- Computes a flee destination (opposite direction from the player, shyness hexes
-- away) and starts an A* path to it.  Sets state = "flee" unconditionally so the
-- FSM drives movement even if pathfinding has to retry next tick.
function Mob:_start_flee(world, player)
    local def     = self.def
    local shyness = def.shyness or 4

    -- Sanity guard: shyness must be at least sense_radius, otherwise the mob
    -- would flee to within its own detection range and re-trigger immediately.
    if shyness < (def.sense_radius or 0) then
        print("[MOB:" .. (def.name or "?") .. "] SHYNESS < SENSE_RADIUS — defaulting to sense_radius")
        shyness = def.sense_radius
    end

    -- Vector from mob toward player; flip to get flee direction.
    local to_px = player.x - self.x
    local to_py = player.y - self.y
    local mag   = math.sqrt(to_px * to_px + to_py * to_py)
    if mag < 1 then to_px, to_py, mag = 1, 0, 1 end  -- player on top: flee east

    -- Flee target in pixel space.
    local flee_px = self.x - (to_px / mag) * shyness * HEX_SPACING
    local flee_py = self.y - (to_py / mag) * shyness * HEX_SPACING
    local tq, tr  = Hex.pixel_to_hex(flee_px, flee_py)
    local tl      = Pathfinder.surface_layer(world, tq, tr, self.layer)

    self.state          = "flee"
    self.stepping_up    = false
    self._step_up_layer = 0

    if not tl then return end  -- No walkable surface; hold position until re-check.

    local tx, ty = Hex.hex_to_pixel(tq, tr)

    -- LoS fast path (same layer only).
    if tl == self.layer and
       Pathfinder.line_of_sight(world, self.x, self.y, tx, ty, self.layer, LOS_HALF_W) then
        self.path     = { {q = tq, r = tr, layer = tl} }
        self.path_idx = 1
        return
    end

    -- A* fallback.
    local raw = Pathfinder.find_path(world, self.q, self.r, self.layer, tq, tr, tl, PATH_BUDGET)
    if raw and #raw > 0 then
        self.path     = Pathfinder.string_pull(world, raw, self.x, self.y, self.layer, LOS_HALF_W)
        self.path_idx = 1
    else
        self.path = nil  -- Blocked; hold until next awareness tick re-picks direction.
    end
end

-- Debug: immediately redirect all mobs to an explicit destination.
-- tq, tr, tl must already be confirmed walkable by the caller.
function Mob:force_wander_to(world, tq, tr, tl)
    local tx, ty = Hex.hex_to_pixel(tq, tr)

    -- Same layer: try direct LoS first.
    if tl == self.layer and
       Pathfinder.line_of_sight(world, self.x, self.y, tx, ty, self.layer, LOS_HALF_W) then
        self.path           = { {q = tq, r = tr, layer = tl} }
        self.path_idx       = 1
        self.state          = "wander"
        self.stepping_up    = false
        self._step_up_layer = 0
        return
    end

    local raw = Pathfinder.find_path(world, self.q, self.r, self.layer, tq, tr, tl, PATH_BUDGET)
    if raw and #raw > 0 then
        self.path           = Pathfinder.string_pull(world, raw, self.x, self.y, self.layer, LOS_HALF_W)
        self.path_idx       = 1
        self.state          = "wander"
        self.stepping_up    = false
        self._step_up_layer = 0
    else
        self:_enter_idle()
    end
end

-- Smooth step-by-step movement along self.path.
-- Handles flat movement and step-ups (+1 layer); fall physics handles step-downs.
function Mob:_follow_path(dt)
    if not self.path or self.path_idx > #self.path then
        self:_enter_idle()
        return
    end

    -- Effective speed: boosted while fleeing.
    local speed = self.def.speed
    if self.state == "flee" and self.def.flee_speed_mul then
        speed = speed * self.def.flee_speed_mul
    end

    local step = self.path[self.path_idx]

    -- Initiate step-up when the next waypoint is one layer higher.
    if step.layer == self.layer + 1 and not self.stepping_up then
        self.stepping_up    = true
        self._step_up_layer = step.layer
    end

    if self.stepping_up then
        -- Move horizontally toward the destination while the vertical section handles rising.
        -- Both complete independently; we advance only when BOTH are done.
        local tx, ty = Hex.hex_to_pixel(step.q, step.r)
        local dx, dy = tx - self.x, ty - self.y
        local dist   = math.sqrt(dx * dx + dy * dy)
        if dist > ARRIVE_DIST then
            local inv = speed * dt / dist
            self.x = self.x + dx * inv
            self.y = self.y + dy * inv
        end
        -- Advance once risen to target layer AND horizontally arrived.
        if self.z >= self._step_up_layer and dist <= ARRIVE_DIST then
            self.stepping_up    = false
            self._step_up_layer = 0
            self.x, self.y      = tx, ty
            self.q, self.r      = step.q, step.r
            self.path_idx       = self.path_idx + 1
        end
        return
    end

    -- Flat or step-down movement: glide horizontally; fall physics drops z automatically.
    local tx, ty = Hex.hex_to_pixel(step.q, step.r)
    local dx, dy = tx - self.x, ty - self.y
    local dist   = math.sqrt(dx * dx + dy * dy)
    local move   = speed * dt

    if dist <= math.max(move, ARRIVE_DIST) then
        self.x, self.y = tx, ty
        self.q, self.r = step.q, step.r
        self.path_idx  = self.path_idx + 1
    else
        local inv = move / dist
        self.x = self.x + dx * inv
        self.y = self.y + dy * inv
        self.q, self.r = Hex.pixel_to_hex(self.x, self.y)
    end
end

-- ── Public update ─────────────────────────────────────────────────────────

-- Called by MobManager:update(dt, world, player) each frame.
function Mob:update(dt, world, player)
    dt = math.min(dt, MOB_MAX_DT)

    -- ── 0. Awareness check (only for mobs with sense_radius defined) ──────
    if self.def.sense_radius then
        self.awareness_timer = self.awareness_timer - dt
        if self.awareness_timer <= 0 then
            self:_check_player(world, player)
        end
    end

    -- ── 1. FSM — horizontal movement ──────────────────────────────────────
    if self.state == "idle" then
        self.idle_timer = self.idle_timer - dt
        if self.idle_timer <= 0 then
            self:_start_wander(world)
        end

    elseif self.state == "wander" then
        if self.path and self.path_idx <= #self.path then
            self:_follow_path(dt)
        else
            self:_enter_idle()
        end

    elseif self.state == "flee" then
        if self.path and self.path_idx <= #self.path then
            self:_follow_path(dt)
        else
            -- Path exhausted: re-evaluate player presence immediately rather than
            -- waiting up to awareness_interval seconds standing still.
            self:_check_player(world, player)
        end
    end

    -- ── 2. Vertical physics ────────────────────────────────────────────────
    if self.stepping_up then
        -- Controlled rise toward _step_up_layer; suppress fall check until arrived.
        if self.z < self._step_up_layer then
            self.z = math.min(self.z + MOB_VERT_RATE * dt, self._step_up_layer)
        end
        self.falling  = false
        self.grounded = false

    elseif self.falling then
        local z_prev = self.z
        self.z = self.z - MOB_VERT_RATE * dt
        if math.floor(self.z) < math.floor(z_prev) then
            local fl = math.floor(z_prev)
            if Physics.foot_grounded(world, self.x, self.y, fl) then
                self.z        = fl + 0.0
                self.falling  = false
                self.grounded = true
            end
        end
    else
        -- Grounded: check floor every frame; start falling if it disappears.
        if Physics.foot_grounded(world, self.x, self.y, math.floor(self.z)) then
            self.grounded = true
        else
            self.grounded = false
            self.falling  = true
        end
    end

    -- ── 3. Wall collision ──────────────────────────────────────────────────
    -- During a step-up rise, bump wall_layer by 1 so the destination floor
    -- tile doesn't block the mob's horizontal approach.
    local wall_layer = math.floor(self.z) + 1
    if self.stepping_up and self.z < self._step_up_layer then
        wall_layer = wall_layer + 1
    end
    self.x, self.y = Physics.wall_resolve(world, self.x, self.y, wall_layer, MOB_INRADIUS)

    -- ── 4. Sync hex coords and integer layer ──────────────────────────────
    self.q, self.r = Hex.pixel_to_hex(self.x, self.y)
    self.layer     = math.floor(self.z)
end

-- ── Draw ──────────────────────────────────────────────────────────────────

-- Draw in world-pixel space — call only while cam:apply() is active.
-- Sprite bottom-center anchored at (self.x, self.y - self.z * LAYER_HEIGHT).
function Mob:draw_world()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(
        self.sprite,
        math.floor(self.x - RENDER_W * 0.5),
        math.floor(self.y - self.z * LAYER_HEIGHT - RENDER_H),
        0, self._scale_x, self._scale_y)
end

-- Debug: draw the remaining A* path as a red polyline.
-- Call only while cam:apply() is active.
function Mob:draw_path()
    if not self.path or self.path_idx > #self.path then return end

    local pts = {}
    -- Start from the mob's current foot position.
    pts[#pts+1] = self.x
    pts[#pts+1] = self.y - self.z * LAYER_HEIGHT
    -- Append each remaining step.
    for i = self.path_idx, #self.path do
        local step = self.path[i]
        local sx, sy = Hex.hex_to_pixel(step.q, step.r)
        pts[#pts+1] = sx
        pts[#pts+1] = sy - step.layer * LAYER_HEIGHT
    end

    if #pts >= 4 then
        love.graphics.setColor(1, 0.2, 0.2, 0.85)
        love.graphics.setLineWidth(2)
        love.graphics.line(pts)
        love.graphics.setLineWidth(1)
    end
end

return Mob
