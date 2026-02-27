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

local Hex          = require("src.core.hex")
local RenderCfg    = require("config.render")
local TileRegistry = require("src.world.tile_registry")

local LAYER_HEIGHT = RenderCfg.layer_height

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

-- ── Floor-detection circle ─────────────────────────────────────────────────
-- 5 sample points in world-pixel space (horizontal plane).
-- Grounded if ANY point has a solid tile at the floor layer.
local FOOT_R = 11   -- px; radius = half of 23 px diameter (= half sprite width)

local _foot = {
    {  0,      0 },
    {  FOOT_R, 0 }, { -FOOT_R, 0 },
    {  0,  FOOT_R }, {  0, -FOOT_R },
}

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
local frame_quad
local air_quad

-- Call once at startup (before Player.new).
function Player.load()
    spritesheet = love.graphics.newImage("assests/entities/player_animations.png")
    spritesheet:setFilter("nearest", "nearest")
    -- Top-left frame (column 0, row 0) = default standing pose.
    frame_quad = love.graphics.newQuad(0, 0, FRAME_W, FRAME_H,
                     spritesheet:getDimensions())
    -- Row 5, column 2 (1-indexed) = row 4, col 1 (0-indexed) = airborne frame.
    air_quad = love.graphics.newQuad(1 * FRAME_W, 4 * FRAME_H, FRAME_W, FRAME_H,
                     spritesheet:getDimensions())
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
    }, Player)
    p.q, p.r = Hex.pixel_to_hex(x, y)
    return p
end

-- ── Internal helpers ───────────────────────────────────────────────────────
local SOLID = TileRegistry.SOLID  -- flat array; by-ref, safe to cache

local function foot_grounded(world, x, y, floor_layer)
    for _, off in ipairs(_foot) do
        local fq, fr = Hex.pixel_to_hex(x + off[1], y + off[2])
        if SOLID[world:get_tile(fq, fr, floor_layer)] then
            return true
        end
    end
    return false
end

-- ── SAT hex-vs-hex wall collision ─────────────────────────────────────────
-- Both the player and every wall tile are flat-top regular hexagons with the
-- same orientation → they share exactly 6 face normals → SAT needs only 6
-- axis tests per wall hex.
--
-- On each axis i:  sep_i = dot(player_center - wall_center, normal_i)
-- Overlap on axis i:  SAT_SUM - sep_i   (SAT_SUM = sum of both inradii)
-- If any sep_i > SAT_SUM → shapes don't overlap, skip this hex.
-- Otherwise the axis with the smallest sep (= smallest overlap) is the MTV.
-- Push along that normal by (SAT_SUM - min_sep).
local _S = math.sqrt(3) * 0.5

-- 6 outward face normals for flat-top hexes (same for every hex in the grid).
local _hex_normals = {
    { _S,  0.5 },   -- lower-right face
    { 0,   1.0 },   -- bottom face
    {-_S,  0.5 },   -- lower-left face
    {-_S, -0.5 },   -- upper-left face
    { 0,  -1.0 },   -- top face
    { _S, -0.5 },   -- upper-right face
}

-- 6 axial neighbor offsets (same order as normals — coincidence, but handy).
local _hex_nbrs = {
    { 1,  0}, { 1, -1}, { 0, -1},
    {-1,  0}, {-1,  1}, { 0,  1},
}

local PLAYER_HEX_R    = 24                          -- circumradius (px); tune here
local PLAYER_INRADIUS = PLAYER_HEX_R * math.sqrt(3) * 0.5
local TILE_INRADIUS   = RenderCfg.hex_size * math.sqrt(3) * 0.5
local SAT_SUM         = PLAYER_INRADIUS + TILE_INRADIUS  -- ≈ 62.4 px

local function wall_resolve(world, x, y, wall_layer)
    local push_x, push_y = 0, 0

    -- Player's current hex + its 6 neighbors = the only hexes close enough to collide.
    local pq, pr = Hex.pixel_to_hex(x, y)

    local candidates = { {pq, pr} }
    for _, nb in ipairs(_hex_nbrs) do
        candidates[#candidates + 1] = { pq + nb[1], pr + nb[2] }
    end

    for _, hc in ipairs(candidates) do
        local fq, fr = hc[1], hc[2]
        if SOLID[world:get_tile(fq, fr, wall_layer)] then
            local hx, hy = Hex.hex_to_pixel(fq, fr)
            local rx = x - hx   -- player center relative to wall hex center
            local ry = y - hy

            -- 6-axis SAT: find the axis with maximum |sep| (= minimum penetration).
            -- Separating axis exists if |sep| > SAT_SUM on any axis.
            -- MTV = axis with largest |sep|; overlap = SAT_SUM - max_abs_sep.
            local max_abs_sep = -math.huge
            local best_nx, best_ny = 1, 0
            local best_sign = 1
            local colliding = true

            for _, n in ipairs(_hex_normals) do
                local sep     = rx * n[1] + ry * n[2]
                local abs_sep = math.abs(sep)
                if abs_sep > SAT_SUM then
                    colliding = false   -- separating axis found — no overlap
                    break
                end
                if abs_sep > max_abs_sep then
                    max_abs_sep = abs_sep
                    best_nx, best_ny = n[1], n[2]
                    best_sign = (sep >= 0) and 1 or -1
                end
            end

            if colliding then
                local overlap = SAT_SUM - max_abs_sep
                push_x = push_x + best_sign * best_nx * overlap
                push_y = push_y + best_sign * best_ny * overlap
            end
        end
    end

    return x + push_x, y + push_y
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
            if foot_grounded(world, self.x, self.y, fl_crossed) then
                self.z        = fl_crossed + 0.0
                self.falling  = false
                self.grounded = true
            end
        end

    else
        -- GROUNDED: z is always an exact integer here.
        -- Check floor every frame; if it disappears (walked off ledge), start falling.
        if foot_grounded(world, self.x, self.y, math.floor(self.z)) then
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
    self.x, self.y = wall_resolve(world, nx, ny, wall_layer)

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
    local quad = (self.jumping or self.falling) and air_quad or frame_quad
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(
        spritesheet, quad,
        math.floor(self.x - RENDER_W * 0.5),
        math.floor(self.y - self.z * LAYER_HEIGHT - RENDER_H),
        0, scale_x, scale_y)
end

return Player
