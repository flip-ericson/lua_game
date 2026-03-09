-- src/world/mob_manager.lua
-- Owns the list of all live mobs.
-- Handles painter-order depth injection (same pattern as player / item drops).
--
-- Step 1 — spawn + draw only.
-- Step 2 — update loop: A* wander, time-sliced pathfinding budget.
-- Step 7 — day/night spawn rules.

local Mob        = require("src.entities.mob")
local Pathfinder = require("src.core.pathfinder")

local MobManager = {}
MobManager.__index = MobManager

function MobManager.new()
    return setmetatable({ mobs = {} }, MobManager)
end

-- Spawn a mob of the given definition at (q, r, layer).
-- def   : table from config/mobs.lua  (e.g. MobDefs.turkey)
-- Returns the new Mob instance (caller may store it for later removal).
function MobManager:spawn(def, q, r, layer)
    local mob = Mob.new(def, q, r, layer)
    self.mobs[#self.mobs + 1] = mob
    return mob
end

-- Remove a specific mob instance from the active list.
function MobManager:remove(mob)
    for i, m in ipairs(self.mobs) do
        if m == mob then
            table.remove(self.mobs, i)
            return
        end
    end
end

-- Called from GameLoop.update(dt).
-- Drives the FSM + movement for every live mob.
-- Note: pathfinding is capped inside Mob:_start_wander (PATH_BUDGET nodes).
-- Full time-slicing (staggered updates across frames) added when mob counts grow.
function MobManager:update(dt, world, player)
    for _, mob in ipairs(self.mobs) do
        mob:update(dt, world, player)
    end
end

-- Called from the renderer's painter loop at each row r.
-- Draws all mobs whose .r matches this painter row (depth-correct injection).
function MobManager:draw_row(r)
    for _, mob in ipairs(self.mobs) do
        if mob.r == r then
            mob:draw_world()
        end
    end
end

-- Debug: redirect the first mob to the walkable surface near (q, r, layer).
-- Called from the mob path debug mode (P key + LMB).
function MobManager:debug_redirect(world, q, r, layer)
    local mob = self.mobs[1]
    if not mob then return end
    local tl = Pathfinder.surface_layer(world, q, r, layer)
    if tl then mob:force_wander_to(world, q, r, tl) end
end

-- Debug: draw the A* path for every live mob.
-- Call only while cam:apply() is active.
function MobManager:draw_paths()
    for _, mob in ipairs(self.mobs) do
        mob:draw_path()
    end
end

return MobManager
