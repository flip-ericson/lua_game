-- src/core/gameloop.lua — Core game loop

local Debug         = require("src.core.debug")
local Hex           = require("src.core.hex")
local LoadingScreen = require("src.core.loading_screen")
local TileRegistry  = require("src.world.tile_registry")
local ItemRegistry  = require("src.world.item_registry")
local World         = require("src.world.world")
local Worldgen      = require("src.world.worldgen")
local WorldgenCfg   = require("config.worldgen")
local RenderCfg     = require("config.render")
local Camera        = require("src.render.camera")
local Renderer      = require("src.render.renderer")
local Player        = require("src.entities.player")
local ItemDrops     = require("src.entities.item_drops")
local Effects       = require("src.render.effects")
local Hotbar        = require("src.ui.hotbar")
local Inventory     = require("src.ui.inventory")
local Crafting      = require("src.ui.crafting")
local Recipes       = require("config.recipes")

local GameLoop = {}

local W, H
local world       -- the active World instance
local player      -- the player entity
local camera      -- Camera instance
local cam_layer   -- world layer the camera is focused on
local cam_q, cam_r
local _saved_zoom   -- zoom level saved when entering overview (M key)

local CAM_LERP = 8  -- camera follow speed (higher = snappier; 8 = smooth but responsive)

local swing_cooldown = 0   -- seconds remaining until next swing is allowed
local FISTS_ID              -- set in GameLoop.load() after ItemRegistry is ready

-- Search for a valid spawn point: a grass tile with air directly above.
-- Picks random hexes within the world boundary and retries up to max_attempts.
-- Returns (q, r, layer) of the spawn tile itself (player z = that layer).
local function find_spawn(world)
    local R     = WorldgenCfg.world_radius
    local sea   = WorldgenCfg.sea_level
    local grass = TileRegistry.id("grass")

    for _ = 1, 200 do
        -- Uniform random hex inside the hexagonal world boundary.
        local q, r
        repeat
            q = math.random(-R, R)
            r = math.random(-R, R)
        until math.max(math.abs(q), math.abs(q + r), math.abs(r)) <= R

        local sl = Worldgen.surface_layer(q, r)

        -- Surface must be above sea, a grass tile, with nothing on top of it.
        if sl >= sea
            and world:get_tile(q, r, sl)     == grass   -- solid grass, not sand/stone
            and world:get_tile(q, r, sl + 1) == 0       -- air above (no tree trunk etc.)
        then
            return q, r, sl
        end
    end

    -- Fallback: world origin at sea level. Logs a warning so it's visible.
    print("[Spawn] WARNING: no valid spawn found in 200 attempts — falling back to origin")
    return 0, 0, sea
end

function GameLoop.load()
    W, H = love.graphics.getDimensions()
    love.graphics.setDefaultFilter("nearest", "nearest")
    math.randomseed(os.time())

    Hex.SIZE = RenderCfg.hex_size

    TileRegistry.load()
    ItemRegistry.load()
    FISTS_ID = ItemRegistry.id("fists")
    Player.load()

    -- Show loading screen before blocking worldgen.
    LoadingScreen.show()

    local t0  = love.timer.getTime()
    world     = World.new()

    -- Debug preset: generate every chunk now so find_spawn can query any tile freely.
    if WorldgenCfg.preload_all then
        world:preload_all()
    end

    -- Find a valid spawn: random grass tile, air above, above sea level.
    local sq, sr, sl = find_spawn(world)
    cam_q, cam_r     = sq, sr
    cam_layer        = sl

    local px, py = Hex.hex_to_pixel(sq, sr)
    camera = Camera.new(px, py - sl * RenderCfg.layer_height)
    player = Player.new(px, py, sl)

    -- Starting gear: diamond tools in hotbar slots 1–3.
    player.inventory[1] = { item_id = ItemRegistry.id("diamond_pickaxe"), count = 1 }
    player.inventory[2] = { item_id = ItemRegistry.id("diamond_shovel"),  count = 1 }
    player.inventory[3] = { item_id = ItemRegistry.id("diamond_axe"),     count = 1 }

    -- Test materials so crafting can be exercised immediately.
    player.inventory[4] = { item_id = ItemRegistry.id("stone_chunk"), count = 5 }
    player.inventory[5] = { item_id = ItemRegistry.id("stick"),       count = 5 }

    -- Unlock default recipes.
    for _, recipe in ipairs(Recipes) do
        if recipe.learned_by_default then
            player.known_recipes[recipe.id] = true
        end
    end

    -- Lazy presets: prime the neighbourhood around the chosen spawn point.
    if not WorldgenCfg.preload_all then
        world:preload_near(cam_q, cam_r, cam_layer)
    end

    print(string.format("[Startup] worldgen + spawn + preload: %.2f s", love.timer.getTime() - t0))
end

function GameLoop.update(dt)
    world:update(dt)

    -- ── Player movement (WASD) + physics (gravity / floor) ───────────────
    player:update(dt, world)

    -- ── Item drop physics ─────────────────────────────────────────────────
    ItemDrops.update(dt, world, player)

    -- ── Hit effects (shake, particles) ────────────────────────────────────
    Effects.update(dt)

    -- ── Swing cooldown ─────────────────────────────────────────────────────
    if swing_cooldown > 0 then
        swing_cooldown = math.max(0, swing_cooldown - dt)
    end

    -- ── Camera lerp-follow ────────────────────────────────────────────────
    -- Framerate-independent lerp: moves CAM_LERP × remaining distance per second.
    -- Skip in overview so the M-key flyout isn't overridden every frame.
    if not Renderer.get_overview() then
        local tx = player.x
        local ty = player.y - player.layer * RenderCfg.layer_height
        local t  = math.min(CAM_LERP * dt, 1)
        camera.x = camera.x + (tx - camera.x) * t
        camera.y = camera.y + (ty - camera.y) * t
    end

    cam_q, cam_r = player.q, player.r
    cam_layer    = player.layer + 1  -- wall layer: floor is layer, body/walls are layer+1

    world:preload_near(cam_q, cam_r, cam_layer)
end

function GameLoop.draw()
    love.graphics.clear(0.06, 0.06, 0.10)

    Renderer.draw(world, camera, cam_layer, player)

    Hotbar.draw(player)
    Inventory.draw(player)
    Crafting.draw(player)

    Debug.draw(world, camera, cam_layer, WorldgenCfg.sea_level)
end

-- ── Debug: instamine tile break ───────────────────────────────────────────
-- Rolls the tile's drop table and spawns item drops at the tile center.
local function break_tile(q, r, layer)
    local tile_id = world:get_tile(q, r, layer)
    if not tile_id or tile_id == 0 then return end
    local def = TileRegistry.get(tile_id)
    world:set_tile(q, r, layer, 0)
    if def and def.drops then
        local bx, by = Hex.hex_to_pixel(q, r)
        for _, entry in ipairs(def.drops) do
            local item_name, min_c, max_c = entry[1], entry[2], entry[3]
            local count = (min_c == max_c) and min_c or math.random(min_c, max_c)
            if count > 0 then
                local item_id = ItemRegistry.id(item_name)
                if item_id then
                    ItemDrops.spawn(item_id, count, bx, by, layer)
                end
            end
        end
    end
end

function GameLoop.keypressed(key, scancode, isrepeat)
    -- Render mode
    if key == "tab" then Renderer.toggle_mode()      end
    if key == "o"   then Renderer.toggle_occlusion() end

    -- Debug overlays
    if key == "f3" then Debug.toggle()           end
    if key == "h"  then Debug.toggle_hud()       end
    if key == "j"  then Debug.toggle_jade()      end
    if key == "x"  then Debug.toggle_instamine() end

    -- Backpack
    if key == "i" then
        player.backpack_open = not player.backpack_open
    end

    -- Hotbar slot selection: keys 1–9 → slots 1–9, 0 → slot 10.
    local slot_keys = {
        ["1"]=1, ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5,
        ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["0"]=10,
    }
    if slot_keys[key] then
        player.hotbar_slot = slot_keys[key]
    end

    -- World overview (M): zoom to fit entire world, blue ocean plane, sampled land.
    -- Only works in overworld mode. Press M again to restore camera position.
    if key == "m" and Renderer.get_mode() == "overworld" then
        if not Renderer.get_overview() then
            _saved_zoom = camera.zoom
            local R  = WorldgenCfg.world_radius
            local pw = 3 * Hex.SIZE * R
            local ph = 2 * math.sqrt(3) * Hex.SIZE * R
            camera.zoom = math.min(W / pw, H / ph) * 0.85
            camera.x    = 0
            camera.y    = -WorldgenCfg.sea_level * RenderCfg.layer_height
        else
            camera.zoom = _saved_zoom
            -- camera.x/y snaps back to player on the next update tick
        end
        Renderer.toggle_overview()
    end

    -- Zoom  (= / + zooms in,  - zooms out)
    if key == "=" or key == "+" then
        camera.zoom = math.min(camera.zoom * 1.25, 4.0)
    end
    if key == "-" then
        camera.zoom = math.max(camera.zoom / 1.25, 0.25)
    end

    -- Layer shift  ([ = deeper,  ] = higher;  PageUp/PageDown = same;  Home = reset)
    -- Moves player.layer; cam_layer + camera.y follow via update() snap.
    -- Hold Shift for ×20 jump.
    local shift      = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
    local layer_step = shift and 20 or 1
    if key == "]" or key == "pageup" then
        player.layer = math.min(player.layer + layer_step, WorldgenCfg.world_depth - 1)
    end
    if key == "[" or key == "pagedown" then
        player.layer = math.max(player.layer - layer_step, 0)
    end
    if key == "home" then
        player.layer = WorldgenCfg.sea_level
    end
end

function GameLoop.keyreleased(key, scancode)  end
function GameLoop.mousepressed(x, y, button, istouch, presses)
    Inventory.mousepressed(x, y, button, player)
    Crafting.mousepressed(x, y, button, player)

    if button == 1 and not player.backpack_open and not Hotbar.hit_test(x, y) then
        local hq, hr, hl, htid = Renderer.get_hover()

        if Debug.instamine_on() then
            -- Instamine: break immediately, no cooldown, no reach check.
            if hq and htid and htid ~= 0 then
                Effects.hit(hq, hr, hl, htid)
                break_tile(hq, hr, hl)
            end
        elseif hq and htid and htid ~= 0 and Renderer.get_hover_in_reach()
               and swing_cooldown <= 0 then
            -- Normal mining swing.
            local slot    = player.inventory[player.hotbar_slot]
            local tool_id = (slot and slot.item_id ~= 0
                             and ItemRegistry.IS_TOOL[slot.item_id])
                             and slot.item_id or FISTS_ID
            local dmg     = ItemRegistry.BASE_DAMAGE[tool_id]    or 0
            local cd      = ItemRegistry.SWING_COOLDOWN[tool_id] or 0.5

            -- Apply penalty when tile category isn't in the tool's preferred list.
            local tool_def = ItemRegistry.get(tool_id)
            local tile_cat = TileRegistry.CATEGORY[htid]
            local preferred = false
            if tool_def and tool_def.preferred then
                for _, cat in ipairs(tool_def.preferred) do
                    if cat == tile_cat then preferred = true; break end
                end
            end
            if not preferred and tool_def and tool_def.penalty_mul then
                dmg = dmg * tool_def.penalty_mul
            end

            Effects.hit(hq, hr, hl, htid)
            swing_cooldown = cd

            local hp = world:damage_tile(hq, hr, hl, dmg)
            if hp <= 0 then
                break_tile(hq, hr, hl)
            end
        end
    end
end
function GameLoop.mousereleased(x, y, button, istouch, presses)
    local function toss_fn(item)
        local mx, my = love.mouse.getPosition()
        local wx, wy = camera:screen_to_world(mx, my)
        local dx     = wx - player.x
        local dy     = wy - player.y
        local len    = math.sqrt(dx * dx + dy * dy)
        local TOSS_VEL = 200   -- px/s
        local TOSS_VZ  = 1.5   -- layers/s upward
        if len > 0 then
            dx = dx / len * TOSS_VEL
            dy = dy / len * TOSS_VEL
        else
            dx, dy = TOSS_VEL, 0
        end
        for _ = 1, item.count do
            ItemDrops.spawn(item.item_id, 1, player.x, player.y, player.layer, dx, dy, TOSS_VZ)
        end
    end
    Inventory.mousereleased(x, y, button, player, toss_fn)
end
function GameLoop.mousemoved(x, y, dx, dy, istouch)             end

function GameLoop.wheelmoved(x, y)
    -- Scroll = cycle hotbar (up → left / smaller index, down → right / larger).
    -- Use = / - keys to zoom instead.
    if y ~= 0 then
        local s = player.hotbar_slot - y   -- scroll up (y>0) → decrement
        player.hotbar_slot = ((s - 1) % 10) + 1  -- wrap 1–10
    end
end

function GameLoop.resize(w, h)
    W, H = w, h
end

return GameLoop
