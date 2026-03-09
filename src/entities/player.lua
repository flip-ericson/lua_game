-- src/entities/player.lua
-- Player entity: world position, velocity, hex coords, sprite rendering.
--
-- Phase 3.1.1 — static sprite on screen.
-- Phase 3.1.2 — WASD updates vx/vy → x/y each frame.
-- Phase 3.1.3 — depth injection into painter's algorithm.
-- Phase 3.2   — fixed-rate vertical physics + 2D wall collision.
--               Fall: 1 layer/s, floor check every frame, snap only on
--               integer crossing (< 3px visual). Jump: fixed-rate ascent,
--               1.5-tile clearance, no hover math. dt capped at 1/15.
-- Phase 3.4   — inventory (30 slots), hotbar_slot selection.

local Hex          = require("src.core.hex")
local RenderCfg    = require("config.render")
local TileRegistry = require("src.world.tile_registry")
local Physics      = require("src.core.physics")

local LAYER_HEIGHT = RenderCfg.layer_height

-- ── Spritesheet row layout (0-indexed) ────────────────────────────────────
local IDLE_ROW = { south=0, west=1, north=2, east=3 }
local WALK_ROW = { south=4, west=5, north=6, east=7 }
local WALK_FPS     = 10     -- walk animation frames per second
local BLINK_FRAME_T = 0.07  -- seconds per blink phase (3 phases ≈ 0.21 s total)
-- idle blink col sequence: phase 0=normal, 1=half-close, 2=closed, 3=half-close
local BLINK_COLS = { 0, 1, 2, 1 }   -- 1-indexed (phase+1)

-- ── Movement ──────────────────────────────────────────────────────────────
local SPEED       = 200   -- world-pixels / second
local AIR_CONTROL = 0.0   -- 0 = locked to launch velocity; 1 = full ground control

-- ── Vertical physics ── (tune these two; everything else derives from them) ──
local VERT_RATE   = 4.75   -- layers / s — rise and fall speed
local JUMP_HEIGHT = 1.25  -- layers — target peak height

-- ── Derived jump constants — DO NOT edit, change VERT_RATE/JUMP_HEIGHT above ──
local JUMP_DURATION  = JUMP_HEIGHT / VERT_RATE
local _jump_airtime  = 2 * JUMP_HEIGHT / VERT_RATE
local _hex_inradius  = RenderCfg.hex_size * math.sqrt(3) * 0.5
local _h_target      = 2.25 * _hex_inradius           -- px: 1.25 hex-widths (2.25 × inradius)
local JUMP_SPEED_MUL = _h_target / (SPEED * _jump_airtime)

local MAX_DT      = 1/15  -- never simulate > 4 frames at once

-- ── Spritesheet layout ────────────────────────────────────────────────────
-- Sheet: 1024×888 px, 10 columns × 8 rows.
-- 888 / 8 = 111 (exact).  1024 / 10 = 102.4 → FRAME_W = 102, 4 px dead on right edge.
local FRAME_W  = 102
local FRAME_H  = 111

-- Rendered size: 46×46 px square (hex side 48 − 2 px buffer).
local RENDER_W = 46
local RENDER_H = 46

local Player = {}
Player.__index = Player

local spritesheet
local all_quads = {}   -- [row][col], both 0-indexed; pre-built in Player.load()

-- Call once at startup (before Player.new).
function Player.load()
    spritesheet = love.graphics.newImage("assests/entities/player_animations.png")
    spritesheet:setFilter("nearest", "nearest")
    local sw, sh = spritesheet:getDimensions()
    for row = 0, 7 do
        all_quads[row] = {}
        for col = 0, 9 do
            all_quads[row][col] = love.graphics.newQuad(
                col * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H, sw, sh)
        end
    end
end

-- x, y  : world-pixel position (float; NOT snapped to hex centres).
-- z     : float layer index. math.floor(z) = the floor layer the player stands on.
--         z is an exact integer when grounded; fractional only while airborne.
function Player.new(x, y, layer)
    local p = setmetatable({
        x     = x,
        y     = y,
        z     = layer + 0.0,
        layer = layer,

        q = 0,
        r = 0,

        vx = 0,
        vy = 0,

        grounded = false,
        jumping  = false,
        falling  = false,
        jump_t   = 0,     -- seconds of ascent remaining
        floor_z  = layer, -- last known ground layer; shadow always uses this

        -- ── Inventory ─────────────────────────────────────────────────────
        -- 154 flat slots. Slots 1–10 are the hotbar; slots 11–154 are the
        -- 12×12 backpack. Each slot: { item_id = 0, count = 0 }. item_id 0 = empty.
        inventory    = (function()
            local inv = {}
            for i = 1, 154 do inv[i] = { item_id = 0, count = 0 } end
            return inv
        end)(),
        hotbar_slot   = 1,     -- 1–10; currently selected hotbar slot
        backpack_open = false, -- true while the backpack UI is visible

        -- ── Crafting ──────────────────────────────────────────────────────
        -- Set of recipe IDs the player has learned. { [id] = true }
        -- Populated at startup from recipes.lua learned_by_default,
        -- then extended by scrolls / NPC teaching / discovery at runtime.
        known_recipes = {},

        -- ── Animation ─────────────────────────────────────────────────────
        facing        = "south",  -- "north" | "south" | "east" | "west"
        anim_frame    = 0,        -- current walk frame index (0–9)
        anim_t        = 0,        -- walk frame timer accumulator (seconds)
        blink_phase   = 0,        -- 0=normal, 1=half-close, 2=closed, 3=half-close
        blink_phase_t = 0,        -- time spent in current blink phase (seconds)
        blink_timer   = 0,        -- time since last blink ended (seconds)
        blink_next    = 5,        -- seconds until next blink triggers
        _moving       = false,    -- true while WASD input is active
    }, Player)
    p.q, p.r = Hex.pixel_to_hex(x, y)
    return p
end

-- ── Collision constants ────────────────────────────────────────────────────
-- Helpers live in src/core/physics.lua (shared with mobs).
local PLAYER_HEX_R    = 24                              -- circumradius (px); tune here
local PLAYER_INRADIUS = PLAYER_HEX_R * math.sqrt(3) * 0.5

-- ── Animation update ───────────────────────────────────────────────────────
-- Called each frame with the movement intent (dx/dy from raw input, NOT velocity).
function Player:_update_anim(dt, moving)
    if moving then
        -- Advance walk cycle.
        self.anim_t = self.anim_t + dt
        local frame_dur = 1 / WALK_FPS
        while self.anim_t >= frame_dur do
            self.anim_t     = self.anim_t - frame_dur
            self.anim_frame = (self.anim_frame + 1) % 10
        end
        -- Reset blink state so it restarts cleanly on next idle.
        self.blink_phase   = 0
        self.blink_phase_t = 0
        self.blink_timer   = 0
    else
        -- Idle: reset walk frame, advance blink state.
        self.anim_frame = 0
        self.anim_t     = 0

        if self.blink_phase == 0 then
            -- Waiting for next blink.
            self.blink_timer = self.blink_timer + dt
            if self.blink_timer >= self.blink_next then
                self.blink_phase   = 1
                self.blink_phase_t = 0
            end
        else
            -- Mid-blink: advance through phases 1→2→3→0.
            self.blink_phase_t = self.blink_phase_t + dt
            if self.blink_phase_t >= BLINK_FRAME_T then
                self.blink_phase_t = 0
                self.blink_phase   = self.blink_phase + 1
                if self.blink_phase > 3 then
                    self.blink_phase = 0
                    self.blink_timer = 0
                    self.blink_next  = math.random(3, 7)
                end
            end
        end
    end
end

-- Called every frame from GameLoop.update(dt).
function Player:update(dt, world)
    dt = math.min(dt, MAX_DT)

    -- ── 1. Horizontal input ──────────────────────────────────────────────
    local dx, dy = 0, 0
    if love.keyboard.isDown("w") then dy = dy - 1 end
    if love.keyboard.isDown("s") then dy = dy + 1 end
    if love.keyboard.isDown("a") then dx = dx - 1 end
    if love.keyboard.isDown("d") then dx = dx + 1 end

    -- Update facing from raw input (before diagonal normalization).
    if dx ~= 0 or dy ~= 0 then
        if math.abs(dx) >= math.abs(dy) then
            self.facing = (dx > 0) and "east" or "west"
        else
            self.facing = (dy > 0) and "south" or "north"
        end
    end
    self._moving = (dx ~= 0 or dy ~= 0)
    self:_update_anim(dt, self._moving)

    if dx ~= 0 and dy ~= 0 then
        dx = dx * 0.7071
        dy = dy * 0.7071
    end

    if self.grounded then
        self.vx = dx * SPEED
        self.vy = dy * SPEED
    else
        self.vx = self.vx + (dx * SPEED - self.vx) * AIR_CONTROL
        self.vy = self.vy + (dy * SPEED - self.vy) * AIR_CONTROL
    end

    -- ── 2. Jump input ─────────────────────────────────────────────────────
    if love.keyboard.isDown("space") and self.grounded and not self.jumping then
        self.jumping  = true
        self.falling  = false
        self.grounded = false
        self.jump_t   = JUMP_DURATION
        self.vx       = self.vx * JUMP_SPEED_MUL
        self.vy       = self.vy * JUMP_SPEED_MUL
    end

    -- ── 3. Vertical movement — three explicit states ───────────────────────
    if self.jumping then
        -- GOING UP: rise, no floor checks ever.
        self.z      = self.z + VERT_RATE * dt
        self.jump_t = self.jump_t - dt
        if self.jump_t <= 0 then
            self.jumping = false
            self.falling = true   -- hand off to fall state; never touch grounded check
        end

    elseif self.falling then
        -- GOING DOWN: decrement z, check for floor only at integer crossings.
        local z_prev = self.z
        self.z = self.z - VERT_RATE * dt

        if math.floor(self.z) < math.floor(z_prev) then
            local fl_crossed = math.floor(z_prev)   -- the integer we just passed through
            if Physics.foot_grounded(world, self.x, self.y, fl_crossed) then
                self.z        = fl_crossed + 0.0
                self.falling  = false
                self.grounded = true
            end
        end

    else
        -- GROUNDED: z is always an exact integer here.
        -- Check floor every frame; if it disappears (walked off ledge), start falling.
        if Physics.foot_grounded(world, self.x, self.y, math.floor(self.z)) then
            self.grounded = true
            self.floor_z  = math.floor(self.z)  -- keep shadow pinned to current ground
        else
            self.grounded = false
            self.falling  = true
        end
    end

    -- ── 4. Horizontal movement with hex wall slide ────────────────────────
    local wall_layer = math.floor(self.z) + 1
    local nx = self.x + self.vx * dt
    local ny = self.y + self.vy * dt
    self.x, self.y = Physics.wall_resolve(world, nx, ny, wall_layer, PLAYER_INRADIUS)

    -- ── 5. Derive hex coords and integer layer ────────────────────────────
    self.q, self.r = Hex.pixel_to_hex(self.x, self.y)
    self.layer     = math.floor(self.z)
end

-- Draw in world-pixel space — call only while cam:apply() is active.
-- Renderer injects this at the correct painter's-algorithm row.
function Player:draw_world(draw_layer)
    -- Shadow: fixed to 2D ground position, does not rise with the player.
    -- Drawn first so the sprite renders on top of it.
    local ground_y = math.floor(self.y - self.floor_z * LAYER_HEIGHT)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.ellipse("fill", math.floor(self.x), ground_y, 14, 5)

    -- Player sprite, elevated by fractional z during jumps/falls.
    local scale_x = RENDER_W / FRAME_W
    local scale_y = RENDER_H / FRAME_H

    -- Select animation quad.
    local quad
    if self.jumping or self.falling then
        -- Airborne: mid-stride frame of the current facing direction.
        quad = all_quads[WALK_ROW[self.facing]][2]
    elseif self._moving then
        quad = all_quads[WALK_ROW[self.facing]][self.anim_frame]
    else
        -- Idle: north has only one frame; other directions support blinking.
        local col = (self.facing == "north") and 0 or BLINK_COLS[self.blink_phase + 1]
        quad = all_quads[IDLE_ROW[self.facing]][col]
    end

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(
        spritesheet, quad,
        math.floor(self.x - RENDER_W * 0.5),
        math.floor(self.y - self.z * LAYER_HEIGHT - RENDER_H),
        0, scale_x, scale_y)
end

return Player
