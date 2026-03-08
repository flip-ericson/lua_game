-- src/ui/inventory.lua
-- Full backpack screen. Toggle with I; close with I or Escape.
-- Displays player.inventory[11..154] as a 12×12 grid.
-- Hotbar (slots 1–10) remains visible at the bottom while the backpack is open.

local ItemRegistry = require("src.world.item_registry")
local Hotbar       = require("src.ui.hotbar")

local Inventory = {}

-- ── Drag state (persists between frames) ──────────────────────────────────

local drag_item      = nil   -- { item_id, count } copy; nil when not dragging
local drag_src       = nil   -- inventory slot index the item was lifted from
local drop_target_bp = nil   -- backpack insert index (updated each draw frame)
local drop_target_hi = nil   -- hotbar slot index target (updated each draw frame)

-- ── Layout ────────────────────────────────────────────────────────────────

local SLOT_SIZE = 44
local SLOT_GAP  = 3
local COLS      = 12
local ROWS      = 12
local BACKPACK_START = 11   -- inventory[11] is backpack slot (1,1)

local GRID_W  = COLS * SLOT_SIZE + (COLS - 1) * SLOT_GAP   -- 561 px
local GRID_H  = ROWS * SLOT_SIZE + (ROWS - 1) * SLOT_GAP   -- 561 px

local PAD     = 14   -- panel edge padding
local TITLE_H = 26   -- height reserved for the panel title above the grid

local PANEL_W = GRID_W + PAD * 2         -- 589 px
local PANEL_H = GRID_H + PAD * 2 + TITLE_H

-- ── Category placeholder colours (mirrors hotbar.lua) ─────────────────────

local CAT_COLOR = {
    material   = { 0.72, 0.60, 0.38 },
    organic    = { 0.30, 0.72, 0.26 },
    block      = { 0.52, 0.52, 0.58 },
    tool       = { 0.48, 0.68, 0.88 },
    component  = { 0.62, 0.52, 0.78 },
}
local CAT_COLOR_FALLBACK = { 0.60, 0.60, 0.60 }

-- ── Internal helpers ──────────────────────────────────────────────────────

local SPRITE_PAD = 5   -- inset from slot edge for item drawing area

-- Returns (insert_col, row) for the insertion point nearest to (x, y) inside
-- the backpack grid, or nil if y is outside the grid's vertical bounds.
-- insert_col is in [0, COLS]: 0 = before first slot, COLS = after last slot.
-- The corresponding flat inventory index is BACKPACK_START + row*COLS + insert_col.
local function bp_insert_pos(x, y, gx, gy)
    if y < gy or y >= gy + GRID_H then return nil end
    if x < gx or x >= gx + GRID_W then return nil end
    local row = math.min(math.floor((y - gy) / (SLOT_SIZE + SLOT_GAP)), ROWS - 1)
    local rel_x      = x - gx
    local insert_col = 0
    for c = 0, COLS - 1 do
        if rel_x >= c * (SLOT_SIZE + SLOT_GAP) + SLOT_SIZE * 0.5 then
            insert_col = c + 1
        else
            break
        end
    end
    insert_col = math.min(insert_col, COLS)
    return insert_col, row
end

local function draw_durability_bar(slot, sx, sy)
    if not slot.durability then return end
    local max_dur = ItemRegistry.DURABILITY[slot.item_id]
    if not max_dur or max_dur == math.huge then return end
    local pct = math.max(0, slot.durability / max_dur)
    local r, g, b
    if     pct >= 0.75 then r, g, b = 0.20, 0.85, 0.20
    elseif pct >= 0.50 then r, g, b = 0.95, 0.88, 0.10
    elseif pct >= 0.25 then r, g, b = 0.95, 0.50, 0.10
    else                    r, g, b = 0.90, 0.15, 0.15
    end
    local bar_w = math.max(1, math.floor((SLOT_SIZE - 2) * pct))
    love.graphics.setColor(r, g, b)
    love.graphics.rectangle("fill", sx + 1, sy + SLOT_SIZE - 5, bar_w, 2)
end

local function draw_item(id, sx, sy)
    local img   = ItemRegistry.SPRITE[id]
    local inner = SLOT_SIZE - SPRITE_PAD * 2

    if img then
        local iw, ih = img:getDimensions()
        local scale  = math.min(inner / iw, inner / ih)
        local dw     = iw * scale
        local dh     = ih * scale
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(
            img,
            math.floor(sx + (SLOT_SIZE - dw) * 0.5),
            math.floor(sy + (SLOT_SIZE - dh) * 0.5),
            0, scale, scale)
    else
        local def = ItemRegistry.get(id)
        local col = (def and CAT_COLOR[def.category]) or CAT_COLOR_FALLBACK
        love.graphics.setColor(col[1], col[2], col[3])
        love.graphics.rectangle("fill",
            sx + SPRITE_PAD, sy + SPRITE_PAD, inner, inner, 2, 2)
    end
end

-- ── Public API ────────────────────────────────────────────────────────────

-- Ghost sprite/swatch centred on the mouse cursor while dragging.
-- Called both when backpack is open (with insertion bar) and when closed.
local function draw_drag_ghost(mx, my)
    if not drag_item then return end
    local img   = ItemRegistry.SPRITE[drag_item.item_id]
    local inner = SLOT_SIZE - SPRITE_PAD * 2
    local gox   = math.floor(mx - SLOT_SIZE * 0.5)
    local goy   = math.floor(my - SLOT_SIZE * 0.5)
    if img then
        local iw, ih = img:getDimensions()
        local scale  = math.min(inner / iw, inner / ih)
        local dw, dh = iw * scale, ih * scale
        love.graphics.setColor(1, 1, 1, 0.70)
        love.graphics.draw(img,
            math.floor(gox + (SLOT_SIZE - dw) * 0.5),
            math.floor(goy + (SLOT_SIZE - dh) * 0.5),
            0, scale, scale)
    else
        local def = ItemRegistry.get(drag_item.item_id)
        local col = (def and CAT_COLOR[def.category]) or CAT_COLOR_FALLBACK
        love.graphics.setColor(col[1], col[2], col[3], 0.70)
        love.graphics.rectangle("fill",
            gox + SPRITE_PAD, goy + SPRITE_PAD, inner, inner, 2, 2)
    end
    love.graphics.setColor(1, 1, 1)
end

function Inventory.draw(player)
    local W, H   = love.graphics.getDimensions()
    local mx, my = love.mouse.getPosition()

    -- When backpack is closed only render the drag ghost (hotbar drag in progress).
    if not player.backpack_open then
        draw_drag_ghost(mx, my)
        return
    end

    local px   = math.floor((W - PANEL_W) * 0.5)
    local py   = math.floor((H - PANEL_H) * 0.5)
    local font = love.graphics.getFont()
    local gx   = px + PAD
    local gy   = py + PAD + TITLE_H

    -- ── Hover detection (pre-pass) ────────────────────────────────────────
    local hovered_def  = nil
    local hovered_slot = nil
    for row = 0, ROWS - 1 do
        for col = 0, COLS - 1 do
            local sx = gx + col * (SLOT_SIZE + SLOT_GAP)
            local sy = gy + row * (SLOT_SIZE + SLOT_GAP)
            if mx >= sx and mx < sx + SLOT_SIZE and my >= sy and my < sy + SLOT_SIZE then
                local slot = player.inventory[BACKPACK_START + row * COLS + col]
                if slot and slot.item_id ~= 0 then
                    hovered_def  = ItemRegistry.get(slot.item_id)
                    hovered_slot = slot
                end
            end
        end
    end
    -- While dragging, always show the dragged item's name.
    if drag_item and not hovered_def then
        hovered_def  = ItemRegistry.get(drag_item.item_id)
        hovered_slot = drag_item
    end

    -- Dim world behind the panel.
    love.graphics.setColor(0, 0, 0, 0.50)
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- Panel background.
    love.graphics.setColor(0.10, 0.10, 0.16, 0.97)
    love.graphics.rectangle("fill", px, py, PANEL_W, PANEL_H, 6, 6)

    -- Panel border.
    love.graphics.setColor(0.32, 0.32, 0.42)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", px, py, PANEL_W, PANEL_H, 6, 6)

    -- Title area: hovered item name (with cur/max durability for tools), or empty.
    if hovered_def then
        local label = hovered_def.display_name
        if hovered_slot and hovered_slot.durability then
            local max_dur = ItemRegistry.DURABILITY[hovered_slot.item_id]
            if max_dur and max_dur ~= math.huge then
                label = label .. " - " .. hovered_slot.durability .. "/" .. max_dur
            end
        end
        local tw = font:getWidth(label)
        love.graphics.setColor(0.95, 0.90, 0.68)
        love.graphics.print(label,
            math.floor(px + (PANEL_W - tw) * 0.5),
            py + math.floor((TITLE_H - font:getHeight()) * 0.5) + 2)
    end

    -- Thin separator line under title area.
    love.graphics.setColor(0.25, 0.25, 0.35)
    love.graphics.line(px + PAD, py + TITLE_H, px + PANEL_W - PAD, py + TITLE_H)

    -- 12×12 slot grid (backpack slots 11–154).
    for row = 0, ROWS - 1 do
        for col = 0, COLS - 1 do
            local slot_idx = BACKPACK_START + row * COLS + col
            local slot     = player.inventory[slot_idx]
            local sx       = gx + col * (SLOT_SIZE + SLOT_GAP)
            local sy       = gy + row * (SLOT_SIZE + SLOT_GAP)

            -- Slot background.
            love.graphics.setColor(0.07, 0.07, 0.11, 0.90)
            love.graphics.rectangle("fill", sx, sy, SLOT_SIZE, SLOT_SIZE, 3, 3)

            -- Slot border.
            love.graphics.setColor(0.26, 0.26, 0.36)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", sx, sy, SLOT_SIZE, SLOT_SIZE, 3, 3)

            -- Item content.
            if slot and slot.item_id ~= 0 then
                draw_item(slot.item_id, sx, sy)

                -- Stack count badge.
                if slot.count > 1 then
                    local cnt = tostring(slot.count)
                    local ctw = font:getWidth(cnt)
                    love.graphics.setColor(0, 0, 0, 0.70)
                    love.graphics.rectangle("fill",
                        sx + SLOT_SIZE - ctw - 4, sy + SLOT_SIZE - 14,
                        ctw + 2, 12)
                    love.graphics.setColor(1, 1, 1)
                    love.graphics.print(cnt,
                        sx + SLOT_SIZE - ctw - 3,
                        sy + SLOT_SIZE - 14)
                end

                draw_durability_bar(slot, sx, sy)
            end
        end
    end

    -- ── Drag: insertion bar + ghost ───────────────────────────────────────
    if drag_item then
        -- Update drop targets for mousereleased to consume.
        local ins_col, ins_row = bp_insert_pos(mx, my, gx, gy)
        local merge_slot = nil   -- inventory index of merge target, or nil

        if ins_col then
            -- Count contiguous items from the front (items always collapse left).
            local BACKPACK_END = BACKPACK_START + ROWS * COLS - 1
            local item_count   = 0
            for i = BACKPACK_START, BACKPACK_END do
                if player.inventory[i] and player.inventory[i].item_id ~= 0 then
                    item_count = item_count + 1
                else
                    break
                end
            end

            -- Stack-merge check (hotbar → backpack only).
            if drag_src < BACKPACK_START then
                local max_st = ItemRegistry.MAX_STACK[drag_item.item_id] or 1
                for i = BACKPACK_START, BACKPACK_START + item_count - 1 do
                    local s = player.inventory[i]
                    if s and s.item_id == drag_item.item_id
                          and s.count + drag_item.count <= max_st then
                        merge_slot = i
                        break
                    end
                end
            end

            -- Clamp so the bar can only land at most one position past the last item.
            local flat = math.min(ins_row * COLS + ins_col, item_count)
            ins_row = math.floor(flat / COLS)
            ins_col = flat % COLS
            drop_target_bp = BACKPACK_START + flat
            drop_target_hi = nil
        else
            drop_target_bp = nil
            drop_target_hi = Hotbar.hit_test(mx, my)
        end

        -- Yellow box around the merge-target slot (replaces insertion bar).
        if merge_slot then
            local rel   = merge_slot - BACKPACK_START
            local mcol  = rel % COLS
            local mrow  = math.floor(rel / COLS)
            local msx   = gx + mcol * (SLOT_SIZE + SLOT_GAP)
            local msy   = gy + mrow * (SLOT_SIZE + SLOT_GAP)
            love.graphics.setColor(1, 0.88, 0, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", msx, msy, SLOT_SIZE, SLOT_SIZE, 3, 3)
            love.graphics.setLineWidth(1)
        end

        -- Insertion bar: hidden when a stack merge will happen.
        -- Red when dragging from the hotbar into a full backpack; yellow otherwise.
        if ins_col and not merge_slot then
            local bp_full = false
            if drag_src < BACKPACK_START then
                local n = 0
                for i = BACKPACK_START, BACKPACK_START + ROWS * COLS - 1 do
                    if player.inventory[i] and player.inventory[i].item_id ~= 0 then n = n + 1 else break end
                end
                bp_full = (n >= ROWS * COLS)
            end
            local bar_x = math.floor(gx + ins_col * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP * 0.5)
            local bar_y = gy + ins_row * (SLOT_SIZE + SLOT_GAP)
            if bp_full then
                love.graphics.setColor(1, 0.18, 0.10, 1)
            else
                love.graphics.setColor(1, 0.88, 0, 1)
            end
            love.graphics.setLineWidth(2)
            love.graphics.line(bar_x, bar_y, bar_x, bar_y + SLOT_SIZE)
            love.graphics.setLineWidth(1)
        end

        -- Ghost: item sprite centred on mouse (drawn last, on top of bar).
        draw_drag_ghost(mx, my)
    end

    love.graphics.setColor(1, 1, 1)
end

-- ── Mouse handlers ────────────────────────────────────────────────────────

-- Helper: returns the backpack inventory index under (x, y), or nil.
local function bp_hit_test(x, y, gx, gy)
    for row = 0, ROWS - 1 do
        for col = 0, COLS - 1 do
            local sx = gx + col * (SLOT_SIZE + SLOT_GAP)
            local sy = gy + row * (SLOT_SIZE + SLOT_GAP)
            if x >= sx and x < sx + SLOT_SIZE and y >= sy and y < sy + SLOT_SIZE then
                return BACKPACK_START + row * COLS + col
            end
        end
    end
    return nil
end

-- Lifts the item under the cursor out of its slot and into drag_item.
function Inventory.mousepressed(x, y, button, player)
    if button ~= 1 then return end

    local W, H = love.graphics.getDimensions()
    local px   = math.floor((W - PANEL_W) * 0.5)
    local py   = math.floor((H - PANEL_H) * 0.5)
    local gx   = px + PAD
    local gy   = py + PAD + TITLE_H

    -- Try backpack grid first (only when open).
    if player.backpack_open then
        local bp_idx = bp_hit_test(x, y, gx, gy)
        if bp_idx then
            local slot = player.inventory[bp_idx]
            if slot and slot.item_id ~= 0 then
                drag_item = { item_id = slot.item_id, count = slot.count, durability = slot.durability }
                drag_src  = bp_idx
                -- Collapse: shift everything after the lifted slot one step left.
                local BACKPACK_END = BACKPACK_START + ROWS * COLS - 1
                for i = bp_idx, BACKPACK_END - 1 do
                    player.inventory[i] = player.inventory[i + 1]
                end
                player.inventory[BACKPACK_END] = { item_id = 0, count = 0 }
            end
            return  -- consumed regardless (click was inside the grid)
        end
    end

    -- Try hotbar (always available, backpack open or closed).
    local hi = Hotbar.hit_test(x, y)
    if hi then
        local slot = player.inventory[hi]
        if slot and slot.item_id ~= 0 then
            drag_item = { item_id = slot.item_id, count = slot.count, durability = slot.durability }
            drag_src  = hi
            player.inventory[hi] = { item_id = 0, count = 0 }
        end
    end
end

function Inventory.mousereleased(x, y, button, player, toss_fn)
    if button ~= 1 or not drag_item then return end

    -- Recompute panel geometry (same as draw).
    local W, H = love.graphics.getDimensions()
    local px   = math.floor((W - PANEL_W) * 0.5)
    local py   = math.floor((H - PANEL_H) * 0.5)
    local gx   = px + PAD
    local gy   = py + PAD + TITLE_H

    -- Count contiguous backpack items from the front.
    local BACKPACK_END = BACKPACK_START + ROWS * COLS - 1
    local function count_bp()
        local n = 0
        for i = BACKPACK_START, BACKPACK_END do
            if player.inventory[i] and player.inventory[i].item_id ~= 0 then
                n = n + 1
            else
                break
            end
        end
        return n
    end

    -- Insert item into backpack at absolute slot index tgt, shifting right.
    local function insert_bp(item, tgt)
        local n = count_bp()
        tgt = math.max(BACKPACK_START, math.min(tgt, BACKPACK_START + n))
        for i = BACKPACK_START + n, tgt + 1, -1 do
            player.inventory[i] = player.inventory[i - 1]
        end
        player.inventory[tgt] = item
    end

    -- ── Determine drop zone ───────────────────────────────────────────────

    local ins_col, ins_row = nil, nil
    if player.backpack_open then
        ins_col, ins_row = bp_insert_pos(x, y, gx, gy)
    end

    if ins_col ~= nil and ins_row ~= nil then
        -- ── Backpack: merge or insert-and-shift ───────────────────────────
        local n = count_bp()
        if drag_src < BACKPACK_START and n >= ROWS * COLS then
            -- Hotbar → full backpack: discard (no item-entity system yet).
        else
            -- Stack-merge check (hotbar → backpack only).
            local merged = false
            if drag_src < BACKPACK_START then
                local max_st = ItemRegistry.MAX_STACK[drag_item.item_id] or 1
                for i = BACKPACK_START, BACKPACK_START + n - 1 do
                    local s = player.inventory[i]
                    if s and s.item_id == drag_item.item_id
                          and s.count + drag_item.count <= max_st then
                        s.count = s.count + drag_item.count
                        merged  = true
                        break
                    end
                end
            end
            if not merged then
                local flat = math.min(ins_row * COLS + ins_col, n)
                insert_bp(drag_item, BACKPACK_START + flat)
            end
        end

    else
        local hi = Hotbar.hit_test(x, y)
        if hi then
            local target  = player.inventory[hi]
            local max_st  = ItemRegistry.MAX_STACK[drag_item.item_id] or 1
            if target.item_id == drag_item.item_id
               and target.count + drag_item.count <= max_st then
                -- ── Hotbar: stack merge ───────────────────────────────────
                target.count = target.count + drag_item.count
            else
                -- ── Hotbar: swap ──────────────────────────────────────────
                local displaced = { item_id = target.item_id, count = target.count }
                player.inventory[hi] = drag_item
                -- Return displaced hotbar item to drag source.
                if displaced.item_id ~= 0 then
                    if drag_src >= BACKPACK_START then
                        -- Source was backpack: insert displaced there with shift.
                        insert_bp(displaced, drag_src)
                    else
                        -- Source was hotbar: simple slot assignment.
                        player.inventory[drag_src] = displaced
                    end
                end
            end
        else
            -- Outside both UI zones: toss item into the world.
            -- Item was already removed from inventory on mousepressed.
            if toss_fn then
                toss_fn(drag_item)
            end
        end
    end

    drag_item      = nil
    drag_src       = nil
    drop_target_bp = nil
    drop_target_hi = nil
end

-- Expose drag state so draw() can render the ghost in step 2.
function Inventory.get_drag() return drag_item end

return Inventory
