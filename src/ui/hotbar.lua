-- src/ui/hotbar.lua
-- Draws the 10-slot hotbar (player.inventory[1..10]) bottom-center of screen.
-- Active slot highlighted with a gold border.
-- Active slot's item display_name shown above the bar.
-- Slots with sprites draw the PNG scaled to fit; slots without fall back to a
-- category-coloured placeholder square.
--
-- Keys 1–9 and 0 select slots 1–10 (handled in gameloop keypressed).
-- Mouse scroll cycles slots (handled in gameloop wheelmoved).

local ItemRegistry = require("src.world.item_registry")

local Hotbar = {}

-- ── Layout ────────────────────────────────────────────────────────────────

local SLOT_SIZE  = 44       -- px, square
local SLOT_GAP   = 3        -- px between slots
local BAR_BOTTOM = 10       -- px from screen bottom to bar bottom edge
local BAR_SLOTS  = 10
local SPRITE_PAD = 4        -- inset from slot edge for sprite drawing area

-- Total bar width (pre-computed).
local BAR_W = BAR_SLOTS * SLOT_SIZE + (BAR_SLOTS - 1) * SLOT_GAP

-- ── Category placeholder colours (fallback when no sprite) ────────────────

local CAT_COLOR = {
    material   = { 0.72, 0.60, 0.38 },
    organic    = { 0.30, 0.72, 0.26 },
    block      = { 0.52, 0.52, 0.58 },
    tool       = { 0.48, 0.68, 0.88 },
}
local CAT_COLOR_FALLBACK = { 0.60, 0.60, 0.60 }

-- ── Internal helpers ──────────────────────────────────────────────────────

-- Draw item content (sprite or colour swatch) centred inside a slot.
local function draw_item(id, slot_x, slot_y)
    local img = ItemRegistry.SPRITE[id]
    local inner = SLOT_SIZE - SPRITE_PAD * 2   -- 36 px drawing area

    if img then
        -- Scale sprite uniformly to fit inner area, preserving aspect ratio.
        local iw, ih = img:getDimensions()
        local scale  = math.min(inner / iw, inner / ih)
        local dw     = iw * scale
        local dh     = ih * scale
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(
            img,
            math.floor(slot_x + (SLOT_SIZE - dw) * 0.5),
            math.floor(slot_y + (SLOT_SIZE - dh) * 0.5),
            0, scale, scale)
    else
        -- Colour-swatch fallback for items without art yet.
        local def = ItemRegistry.get(id)
        local col = (def and CAT_COLOR[def.category]) or CAT_COLOR_FALLBACK
        love.graphics.setColor(col[1], col[2], col[3])
        love.graphics.rectangle("fill",
            slot_x + SPRITE_PAD, slot_y + SPRITE_PAD,
            inner, inner, 2, 2)
    end
end

-- ── Public API ────────────────────────────────────────────────────────────

-- Call from GameLoop.draw() AFTER camera has been reset to screen space.
function Hotbar.draw(player)
    local W, H = love.graphics.getDimensions()
    local ox   = math.floor((W - BAR_W) * 0.5)
    local oy   = H - SLOT_SIZE - BAR_BOTTOM

    for i = 1, BAR_SLOTS do
        local slot   = player.inventory[i]
        local sx     = ox + (i - 1) * (SLOT_SIZE + SLOT_GAP)
        local active = (i == player.hotbar_slot)

        -- Slot background.
        love.graphics.setColor(0.08, 0.08, 0.12, 0.88)
        love.graphics.rectangle("fill", sx, oy, SLOT_SIZE, SLOT_SIZE, 4, 4)

        -- Border — gold for active, dim for inactive.
        if active then
            love.graphics.setColor(0.95, 0.82, 0.28)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0.30, 0.30, 0.40)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", sx, oy, SLOT_SIZE, SLOT_SIZE, 4, 4)
        love.graphics.setLineWidth(1)

        -- Item sprite / placeholder + stack count badge.
        if slot.item_id ~= 0 then
            draw_item(slot.item_id, sx, oy)

            -- Count badge (only when > 1; tools are always 1).
            if slot.count > 1 then
                local font = love.graphics.getFont()
                local cnt  = tostring(slot.count)
                local tw   = font:getWidth(cnt)
                love.graphics.setColor(0, 0, 0, 0.7)
                love.graphics.rectangle("fill",
                    sx + SLOT_SIZE - tw - 4, oy + SLOT_SIZE - 14,
                    tw + 2, 12)
                love.graphics.setColor(1, 1, 1)
                love.graphics.print(cnt, sx + SLOT_SIZE - tw - 3, oy + SLOT_SIZE - 14)
            end
        end
    end

    -- Active slot item name — shown above the bar when occupied.
    local active_slot = player.inventory[player.hotbar_slot]
    if active_slot and active_slot.item_id ~= 0 then
        local def = ItemRegistry.get(active_slot.item_id)
        if def then
            local font = love.graphics.getFont()
            local tw   = font:getWidth(def.display_name)
            love.graphics.setColor(0.95, 0.90, 0.68)
            love.graphics.print(
                def.display_name,
                math.floor((W - tw) * 0.5),
                oy - 18)
        end
    end

    love.graphics.setColor(1, 1, 1)
end

-- Returns the hotbar slot index (1–10) under screen point (x, y), or nil.
function Hotbar.hit_test(x, y)
    local W, H = love.graphics.getDimensions()
    local ox   = math.floor((W - BAR_W) * 0.5)
    local oy   = H - SLOT_SIZE - BAR_BOTTOM
    if y < oy or y >= oy + SLOT_SIZE then return nil end
    for i = 1, BAR_SLOTS do
        local sx = ox + (i - 1) * (SLOT_SIZE + SLOT_GAP)
        if x >= sx and x < sx + SLOT_SIZE then
            return i
        end
    end
    return nil
end

return Hotbar
