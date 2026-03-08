-- src/core/gameloop.lua — Core game loop

local Debug         = require("src.core.debug")
local Hex           = require("src.core.hex")
local LoadingScreen = require("src.core.loading_screen")
local SpriteGen     = require("src.render.sprite_gen")
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
local Time          = require("src.core.time")

local GameLoop = {}

local W, H
local world       -- the active World instance
local player      -- the player entity
local camera      -- Camera instance
local cam_layer   -- world layer the camera is focused on
local cam_q, cam_r
local _saved_zoom   -- zoom level saved when entering overview (M key)

local CAM_LERP = 8  -- camera follow speed (higher = snappier; 8 = smooth but responsive)

local swing_cooldown  = 0   -- seconds remaining until next swing is allowed
local FISTS_ID              -- set in GameLoop.load() after ItemRegistry is ready
local id_rye_planted        -- set in GameLoop.load(); needed in mousepressed

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

    -- SpriteGen.run()   -- uncomment to regenerate se_/sw_ sprites from s_*.png sources
    TileRegistry.load()
    ItemRegistry.load()
    FISTS_ID = ItemRegistry.id("fists")

    -- ── Tile tick handlers ────────────────────────────────────────────────
    -- Registered here after both registries are loaded so IDs are valid.
    local id_wet  = TileRegistry.id("wet_tilled_soil")
    local id_dry  = TileRegistry.id("dry_tilled_soil")
    World.register_tick_handler(id_wet, function(w, q, r, layer)
        -- Dry out after one game day if still wet (defensive: tile may have been mined).
        if w:get_tile(q, r, layer) == id_wet then
            w:set_tile(q, r, layer, id_dry)
            -- If there's a crop above, double its remaining growth time (drying penalty).
            local above_tid = w:get_tile(q, r, layer + 1)
            if above_tid and TileRegistry.IS_CROP[above_tid] then
                local crop_tick = w:get_tile_tick(q, r, layer + 1)
                if crop_tick then
                    local remaining = crop_tick - w.game_time
                    if remaining > 0 then
                        w:deregister_tile_tick(q, r, layer + 1)
                        w:register_tile_tick(q, r, layer + 1, w.game_time + remaining * 2)
                    end
                end
            end
        end
    end)

    -- ── Rye crop tick handlers ─────────────────────────────────────────────
    -- 1 game day = 1440 game-minutes (1 real second = 1 game minute).
    id_rye_planted            = TileRegistry.id("rye_planted")
    local id_rye_seedling     = TileRegistry.id("rye_seedling")
    local id_rye_immature     = TileRegistry.id("rye_immature")
    local id_rye_mature       = TileRegistry.id("rye_mature")

    local RYE_DELAY = {              -- base grow time (minutes) for each phase
        [id_rye_planted]  = 30,     -- DEBUG: 30 min (was 2880)
        [id_rye_seedling] = 30,     -- DEBUG: 30 min (was 7200)
        [id_rye_immature] = 30,     -- DEBUG: 30 min (was 10080)
    }
    local RYE_NEXT = {
        [id_rye_planted]  = id_rye_seedling,
        [id_rye_seedling] = id_rye_immature,
        [id_rye_immature] = id_rye_mature,
    }

    local function rye_tick(w, q, r, layer)
        local tid = w:get_tile(q, r, layer)
        if not TileRegistry.IS_CROP[tid] then return end  -- tile removed/replaced

        local season = Time.season(w.game_time)
        -- Winter dormancy: revert all phases to planted; re-check in 1–3 days.
        if season == "Stoneviel" then
            w:set_tile(q, r, layer, id_rye_planted)
            w:register_tile_tick(q, r, layer, w.game_time + 30)  -- DEBUG (was 1440–4320)
            return
        end

        -- Advance to next phase.
        local next_id = RYE_NEXT[tid]
        if not next_id then return end  -- rye_mature: harvest manually, no further tick

        w:set_tile(q, r, layer, next_id)

        -- Schedule next growth tick unless we just reached mature.
        -- Check farmland NOW (start of new phase) to set the initial delay.
        -- Mid-phase changes are handled by events: wet→dry doubles, dry→wet halves.
        local base = RYE_DELAY[next_id]
        if base then
            local delay    = base  -- DEBUG: no variance (was base ± 1440)
            local farmland = w:get_tile(q, r, layer - 1)
            if farmland == id_dry then delay = delay * 2 end
            w:register_tile_tick(q, r, layer, w.game_time + delay)
        end
    end

    World.register_tick_handler(id_rye_planted,  rye_tick)
    World.register_tick_handler(id_rye_seedling, rye_tick)
    World.register_tick_handler(id_rye_immature, rye_tick)

    Time.load()
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
    local function tool_slot(name)
        local id  = ItemRegistry.id(name)
        local dur = ItemRegistry.DURABILITY[id]
        local mw  = ItemRegistry.MAX_WATER[id]
        return {
            item_id    = id,
            count      = 1,
            durability = (dur and dur > 0) and dur or nil,
            water      = (mw  and mw  > 0) and mw  or nil,
        }
    end
    player.inventory[1] = tool_slot("diamond_pickaxe")
    player.inventory[2] = tool_slot("diamond_shovel")
    player.inventory[3] = tool_slot("diamond_axe")
    player.inventory[4] = tool_slot("crude_chisel")
    player.inventory[5] = tool_slot("diamond_hoe")
    player.inventory[6] = tool_slot("watering_can")
    player.inventory[7] = { item_id = ItemRegistry.id("rye_seed"),  count = 10 }
    player.inventory[8] = { item_id = ItemRegistry.id("rye_grain"), count = 10 }

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
    Time.draw(Time.get(world), W, H)

    Debug.draw(world, camera, cam_layer, WorldgenCfg.sea_level)
end

-- ── Debug: instamine tile break ───────────────────────────────────────────
-- Rolls the tile's drop table and spawns item drops at the tile center.
local function break_tile(q, r, layer)
    local tile_id = world:get_tile(q, r, layer)
    if not tile_id or tile_id == 0 then return end
    local def = TileRegistry.get(tile_id)
    world:deregister_tile_tick(q, r, layer)   -- clean up any pending tick
    world:set_tile(q, r, layer, 0)
    if def and def.drops then
        local bx, by = Hex.hex_to_pixel(q, r)
        for _, entry in ipairs(def.drops) do
            local item_name, min_c, max_c, chance = entry[1], entry[2], entry[3], entry[4]
            -- Optional 4th field: chance (0..1). Absent = 1.0 (always drops).
            if not chance or math.random() < chance then
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

            -- Decrement tool durability; destroy at 0.
            if slot and slot.item_id ~= 0 and slot.durability then
                slot.durability = slot.durability - 1
                if slot.durability <= 0 then
                    slot.item_id    = 0
                    slot.count      = 0
                    slot.durability = nil
                end
            end
        end
    end

    if button == 2 and not player.backpack_open and not Hotbar.hit_test(x, y) then
        local slot      = player.inventory[player.hotbar_slot]
        local held_id   = slot and slot.item_id ~= 0 and slot.item_id or nil
        local place_tid = held_id and ItemRegistry.PLACES_TILE[held_id] or 0

        if place_tid ~= 0 then
            local hq, hr, hl = Renderer.get_hover()
            local face = Renderer.get_hover_face()
            if hq and face ~= nil and Renderer.get_hover_in_reach() then
                local FACE_NBR = {
                    [0] = { 0,  0,  1 },   -- top → layer above
                    [1] = { 1,  0,  0 },   -- SE  → east axial neighbor
                    [2] = { 0,  1,  0 },   -- S   → southeast axial neighbor
                    [3] = {-1,  1,  0 },   -- SW  → southwest axial neighbor
                }
                local off = FACE_NBR[face]
                if off then
                    local tq, tr, tl = hq + off[1], hr + off[2], hl + off[3]
                    local existing   = world:get_tile(tq, tr, tl)
                    -- Block if target overlaps the player's body (same hex, layer or layer+1).
                    local blocks_player = (tq == player.q and tr == player.r
                                          and tl >= player.layer and tl <= player.layer + 1)
                    -- Only place if target is not solid and not inside the player.
                    if not TileRegistry.SOLID[existing] and not blocks_player then
                        world:set_tile(tq, tr, tl, place_tid)
                        slot.count = slot.count - 1
                        if slot.count <= 0 then
                            slot.item_id = 0
                            slot.count   = 0
                        end
                    end
                end
            end
        elseif held_id and ItemRegistry.TOOL_CLASS[held_id] == "hoe" then
            -- Hoe tilling: RMB on the top face (face=0) only.
            --   grass → dirt
            --   dirt  → dry_tilled_soil
            local hq, hr, hl, htid = Renderer.get_hover()
            local face = Renderer.get_hover_face()
            if hq and face == 0 and htid and Renderer.get_hover_in_reach() then
                local result_id
                if htid == TileRegistry.id("grass") then
                    result_id = TileRegistry.id("dirt")
                elseif htid == TileRegistry.id("dirt") then
                    result_id = TileRegistry.id("dry_tilled_soil")
                end
                if result_id then
                    world:set_tile(hq, hr, hl, result_id)
                    slot.durability = slot.durability - 1
                    if slot.durability <= 0 then
                        slot.item_id    = 0
                        slot.count      = 0
                        slot.durability = nil
                    end
                end
            end
        elseif held_id and held_id == ItemRegistry.id("rye_seed") then
            -- Rye planting: RMB top face of any farmland → place rye_planted above it.
            local hq, hr, hl, htid = Renderer.get_hover()
            local face = Renderer.get_hover_face()
            if hq and face == 0 and htid and Renderer.get_hover_in_reach() then
                local is_farmland = (htid == TileRegistry.id("wet_tilled_soil")
                                  or htid == TileRegistry.id("dry_tilled_soil"))
                if is_farmland and world:get_tile(hq, hr, hl + 1) == 0 then
                    world:set_tile(hq, hr, hl + 1, id_rye_planted)
                    -- Schedule first tick.
                    -- Stoneviel (winter): skip straight to a spring-check timer.
                    -- Growing season: normal 2-day base ±1; 2× if dry farmland.
                    local delay
                    if Time.season(world.game_time) == "Stoneviel" then
                        delay = 30   -- DEBUG (was 1440–4320)
                    else
                        delay = 30   -- DEBUG (was 2880 ± 1440)
                        if htid == TileRegistry.id("dry_tilled_soil") then
                            delay = delay * 2
                        end
                    end
                    world:register_tile_tick(hq, hr, hl + 1, world.game_time + delay)
                    slot.count = slot.count - 1
                    if slot.count <= 0 then
                        slot.item_id = 0
                        slot.count   = 0
                    end
                end
            end
        elseif held_id and ItemRegistry.TOOL_CLASS[held_id] == "watering_can" then
            -- Watering can:
            --   RMB on liquid tile  → refill to max water.
            --   RMB on crop tile    → water farmland below + halve remaining crop tick.
            --   RMB on dry farmland → wet it; schedule drying after 1 game day.
            --   RMB elsewhere       → cosmetic splash only.
            local hq, hr, hl, htid = Renderer.get_hover()
            if hq and htid and Renderer.get_hover_in_reach() then
                if htid == TileRegistry.id("salt_water") then
                    slot.water = ItemRegistry.MAX_WATER[held_id]
                elseif slot.water and slot.water > 0 then
                    Effects.splash(hq, hr, hl)
                    if TileRegistry.IS_CROP[htid] then
                        -- Water the farmland one layer below the crop.
                        local fl  = hl - 1
                        local ftid = world:get_tile(hq, hr, fl)
                        if ftid == TileRegistry.id("dry_tilled_soil") then
                            world:set_tile(hq, hr, fl, TileRegistry.id("wet_tilled_soil"))
                            world:deregister_tile_tick(hq, hr, fl)
                            world:register_tile_tick(hq, hr, fl, world.game_time + math.random(1080, 1800))
                            -- Halve the crop's remaining growth time.
                            local crop_tick = world:get_tile_tick(hq, hr, hl)
                            if crop_tick then
                                local remaining = crop_tick - world.game_time
                                if remaining > 0 then
                                    world:deregister_tile_tick(hq, hr, hl)
                                    world:register_tile_tick(hq, hr, hl, world.game_time + remaining * 0.5)
                                end
                            end
                        end
                    elseif htid == TileRegistry.id("dry_tilled_soil") then
                        -- Water dry farmland → wet farmland; schedule drying after 1 game day.
                        world:set_tile(hq, hr, hl, TileRegistry.id("wet_tilled_soil"))
                        world:deregister_tile_tick(hq, hr, hl)
                        world:register_tile_tick(hq, hr, hl, world.game_time + math.random(1080, 1800))
                    end
                    slot.water = slot.water - 1
                    if slot.water <= 0 then
                        slot.item_id = 0
                        slot.count   = 0
                        slot.water   = nil
                    end
                end
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
