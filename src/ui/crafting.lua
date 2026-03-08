-- src/ui/crafting.lua
-- Hand-crafting panel. Appears to the right of the backpack when it is open.
--
-- Tab 1 "Can Craft" — only recipes the player knows AND has ingredients for.
-- Tab 2 "All Known" — all learned recipes, red ingredients if missing.
-- Clicking a recipe selects it. The green Craft button consumes ingredients
-- and places the output into inventory.

local ItemRegistry = require("src.world.item_registry")
local Recipes      = require("config.recipes")

local Crafting = {}

-- ── Panel state ────────────────────────────────────────────────────────────

local active_tab  = 1    -- 1 = "Can Craft", 2 = "All Known"
local selected_id = nil  -- recipe.id of the highlighted recipe, or nil

-- ── Layout ─────────────────────────────────────────────────────────────────
-- INV_* constants mirror inventory.lua so we can park beside it.

local INV_PANEL_W = 589
local INV_PANEL_H = 615   -- GRID_H(561) + PAD*2(28) + TITLE_H(26)
local CRAFT_GAP   = 10    -- px gap between the two panels

local PANEL_W     = 220
local PANEL_H     = INV_PANEL_H
local PAD         = 12
local TITLE_H     = 26    -- matches inventory title area
local ROW_H       = 30    -- height of one recipe row (name only)
local ROW_GAP     = 4
local INGR_H      = 72    -- ingredient detail area (fits up to 4 ingredient lines)
local TAB_H       = 26    -- tab height
local TAB_RAISE   = 5     -- px the active tab rises above the inactive tabs
local BTN_H       = 32    -- Craft button height
local TAB_R       = 4     -- tab corner radius

-- ── Colours (palette matches inventory.lua) ────────────────────────────────

local C_BG     = { 0.10, 0.10, 0.16, 0.97 }
local C_BORDER = { 0.32, 0.32, 0.42 }
local C_TITLE  = { 0.95, 0.90, 0.68 }
local C_SEP    = { 0.25, 0.25, 0.35 }
local C_ROW    = { 0.07, 0.07, 0.11, 0.90 }
local C_ROW_BR = { 0.26, 0.26, 0.36 }
local C_SEL    = { 0.18, 0.20, 0.32 }
local C_SEL_BR = { 0.46, 0.50, 0.80 }
local C_NAME   = { 1,    1,    1    }
local C_NAME_D = { 0.45, 0.45, 0.50 }   -- dimmed name: recipe not craftable
local C_HAVE   = { 0.28, 0.80, 0.32 }   -- ingredient: player has enough (green)
local C_LACK   = { 0.88, 0.28, 0.28 }   -- ingredient: not enough (red)
local C_TAB_I  = { 0.06, 0.06, 0.10 }   -- inactive tab (darker, recessed)
local C_TAB_T  = { 0.80, 0.80, 0.88 }   -- inactive tab text
local C_BTN    = { 0.18, 0.58, 0.22 }   -- craft button active (green)
local C_BTN_D  = { 0.14, 0.26, 0.14 }   -- craft button disabled

-- ── Private helpers ────────────────────────────────────────────────────────

local function panel_xy(W, H)
    local inv_px = math.floor((W - INV_PANEL_W) * 0.5)
    local inv_py = math.floor((H - INV_PANEL_H) * 0.5)
    return inv_px + INV_PANEL_W + CRAFT_GAP, inv_py
end

-- Bottom-anchored layout.
-- Order (bottom to top): tabs → craft button → sep → ingredient area → sep → list → title.
local function layout(cy)
    local lw       = PANEL_W - PAD * 2
    local tab_w    = math.floor((lw - 4) * 0.5)
    local tab_y    = cy + PANEL_H - PAD - TAB_H        -- tabs at very bottom
    local btn_y    = tab_y - 8 - BTN_H                 -- craft button above tabs
    local sep2_y   = btn_y - 6                         -- separator above button
    local ingr_y   = sep2_y - 6 - INGR_H               -- ingredient detail area
    local sep1_y   = ingr_y - 6                        -- separator above ingredient area
    local list_y   = cy + TITLE_H + 6
    local list_h   = sep1_y - list_y - 4
    return tab_y, btn_y, sep2_y, ingr_y, sep1_y, list_y, list_h, lw, tab_w
end

local function count_in_inv(player, item_id)
    local total = 0
    for _, slot in ipairs(player.inventory) do
        if slot.item_id == item_id then total = total + slot.count end
    end
    return total
end

-- Returns total inventory count for an input slot, respecting accept groups.
-- input.accept = { "oak_log", "palm_log", ... } means any of these count.
local function count_for_input(player, input)
    if input.accept then
        local total = 0
        for _, iname in ipairs(input.accept) do
            local id = ItemRegistry.id(iname)
            if id then total = total + count_in_inv(player, id) end
        end
        return total
    end
    local id = ItemRegistry.id(input.name)
    return id and count_in_inv(player, id) or 0
end

-- Returns the slot (live reference) with the highest current durability for
-- tools of the given class across the full inventory, or nil if none found.
local function best_tool_slot(player, class)
    local best_slot = nil
    local best_dur  = -1
    for _, slot in ipairs(player.inventory) do
        if slot.item_id ~= 0 and slot.durability
           and ItemRegistry.TOOL_CLASS[slot.item_id] == class
           and slot.durability > best_dur then
            best_slot = slot
            best_dur  = slot.durability
        end
    end
    return best_slot
end

local function can_craft(player, recipe)
    for _, input in ipairs(recipe.inputs) do
        if count_for_input(player, input) < input.count then
            return false
        end
    end
    if recipe.tool_costs then
        for _, cost in ipairs(recipe.tool_costs) do
            local slot = best_tool_slot(player, cost.class)
            if not slot or slot.durability < cost.durability_cost then
                return false
            end
        end
    end
    return true
end

local function visible_list(player)
    local list = {}
    for _, recipe in ipairs(Recipes) do
        if player.known_recipes[recipe.id] then
            if active_tab == 1 then
                if can_craft(player, recipe) then list[#list + 1] = recipe end
            else
                list[#list + 1] = recipe
            end
        end
    end
    return list
end

local function do_craft(player, recipe)
    -- Consume item inputs (respects accept groups: drains first available item type).
    for _, input in ipairs(recipe.inputs) do
        local need  = input.count
        local names = input.accept or { input.name }
        for _, iname in ipairs(names) do
            local id = ItemRegistry.id(iname)
            if id then
                for _, slot in ipairs(player.inventory) do
                    if slot.item_id == id and need > 0 then
                        local take = math.min(slot.count, need)
                        slot.count = slot.count - take
                        need       = need - take
                        if slot.count == 0 then slot.item_id = 0 end
                    end
                    if need == 0 then break end
                end
            end
            if need == 0 then break end
        end
    end
    -- Deduct tool durability costs (best tool of each required class).
    if recipe.tool_costs then
        for _, cost in ipairs(recipe.tool_costs) do
            local slot = best_tool_slot(player, cost.class)
            if slot then
                slot.durability = slot.durability - cost.durability_cost
                if slot.durability <= 0 then
                    slot.item_id    = 0
                    slot.count      = 0
                    slot.durability = nil
                end
            end
        end
    end
    -- Place output: stack into existing slots first, then empty slots.
    local out_id = ItemRegistry.id(recipe.output.name)
    local max_st = ItemRegistry.MAX_STACK[out_id] or 1
    local remain = recipe.output.count
    for _, slot in ipairs(player.inventory) do
        if slot.item_id == out_id and slot.count < max_st and remain > 0 then
            local add  = math.min(remain, max_st - slot.count)
            slot.count = slot.count + add
            remain     = remain - add
        end
        if remain == 0 then break end
    end
    for _, slot in ipairs(player.inventory) do
        if slot.item_id == 0 and remain > 0 then
            slot.item_id = out_id
            slot.count   = math.min(remain, max_st)
            remain       = remain - slot.count
        end
        if remain == 0 then break end
    end
end

-- ── Public API ─────────────────────────────────────────────────────────────

function Crafting.draw(player)
    if not player.backpack_open then return end

    local W, H   = love.graphics.getDimensions()
    local cx, cy = panel_xy(W, H)
    local font   = love.graphics.getFont()

    -- Panel background.
    love.graphics.setColor(C_BG[1], C_BG[2], C_BG[3], C_BG[4])
    love.graphics.rectangle("fill", cx, cy, PANEL_W, PANEL_H, 6, 6)

    -- Panel border.
    love.graphics.setColor(C_BORDER[1], C_BORDER[2], C_BORDER[3])
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", cx, cy, PANEL_W, PANEL_H, 6, 6)

    -- Title.
    local title = "Crafting"
    local tw    = font:getWidth(title)
    love.graphics.setColor(C_TITLE[1], C_TITLE[2], C_TITLE[3])
    love.graphics.print(title,
        math.floor(cx + (PANEL_W - tw) * 0.5),
        cy + math.floor((TITLE_H - font:getHeight()) * 0.5) + 2)

    -- Separator under title.
    love.graphics.setColor(C_SEP[1], C_SEP[2], C_SEP[3])
    love.graphics.line(cx + PAD, cy + TITLE_H, cx + PANEL_W - PAD, cy + TITLE_H)

    -- Layout.
    local tab_y, btn_y, sep2_y, ingr_y, sep1_y, list_y, list_h, lw, tab_w = layout(cy)
    local lx = cx + PAD

    -- ── Recipe list (name only) ───────────────────────────────────────────
    local list = visible_list(player)
    local ry   = list_y

    if #list == 0 then
        local msg = active_tab == 1 and "Nothing to craft." or "No recipes known."
        local mw  = font:getWidth(msg)
        love.graphics.setColor(C_SEP[1], C_SEP[2], C_SEP[3])
        love.graphics.print(msg,
            math.floor(cx + (PANEL_W - mw) * 0.5),
            list_y + 10)
    end

    for _, recipe in ipairs(list) do
        if ry + ROW_H > list_y + list_h then break end

        local is_sel = (selected_id == recipe.id)

        -- Row background.
        if is_sel then
            love.graphics.setColor(C_SEL[1], C_SEL[2], C_SEL[3])
        else
            love.graphics.setColor(C_ROW[1], C_ROW[2], C_ROW[3], C_ROW[4])
        end
        love.graphics.rectangle("fill", lx, ry, lw, ROW_H, 3, 3)

        -- Row border.
        if is_sel then
            love.graphics.setColor(C_SEL_BR[1], C_SEL_BR[2], C_SEL_BR[3])
            love.graphics.setLineWidth(1.5)
        else
            love.graphics.setColor(C_ROW_BR[1], C_ROW_BR[2], C_ROW_BR[3])
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", lx, ry, lw, ROW_H, 3, 3)
        love.graphics.setLineWidth(1)

        -- Recipe name — dimmed when not craftable (only relevant on "All Known" tab).
        local nc = can_craft(player, recipe) and C_NAME or C_NAME_D
        love.graphics.setColor(nc[1], nc[2], nc[3])
        love.graphics.print(recipe.display_name,
            lx + 8,
            math.floor(ry + (ROW_H - font:getHeight()) * 0.5))

        ry = ry + ROW_H + ROW_GAP
    end

    -- Separator above ingredient detail area.
    love.graphics.setColor(C_SEP[1], C_SEP[2], C_SEP[3])
    love.graphics.line(cx + PAD, sep1_y, cx + PANEL_W - PAD, sep1_y)

    -- ── Ingredient detail area ────────────────────────────────────────────
    -- Shows the cost of the selected recipe. Empty prompt when nothing selected.
    local sel_recipe = nil
    if selected_id then
        for _, r in ipairs(list) do
            if r.id == selected_id then sel_recipe = r; break end
        end
        -- Also search all known recipes in case we're on "All Known" tab.
        if not sel_recipe then
            for _, r in ipairs(Recipes) do
                if r.id == selected_id then sel_recipe = r; break end
            end
        end
    end

    local SPRITE_SZ = 48   -- source image size (px)
    local ICON_SZ   = math.min(INGR_H - 8, 56)   -- display size in the area
    local icon_x    = lx + 4
    local text_x    = icon_x + ICON_SZ + 8

    local iy = ingr_y + 8
    if sel_recipe then
        -- Draw the output item's sprite (or colour swatch) on the left.
        local out_id  = ItemRegistry.id(sel_recipe.output.name)
        local out_img = out_id and ItemRegistry.SPRITE[out_id]
        if out_img then
            local iw, ih  = out_img:getDimensions()
            local scale   = math.min(ICON_SZ / iw, ICON_SZ / ih)
            local dw, dh  = iw * scale, ih * scale
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(out_img,
                math.floor(icon_x + (ICON_SZ - dw) * 0.5),
                math.floor(ingr_y + (INGR_H - dh) * 0.5),
                0, scale, scale)
        elseif out_id then
            -- Colour swatch fallback.
            local def  = ItemRegistry.get(out_id)
            local col  = { 0.60, 0.60, 0.60 }
            if def then
                local CAT_COLOR = {
                    material  = { 0.72, 0.60, 0.38 },
                    organic   = { 0.30, 0.72, 0.26 },
                    block     = { 0.52, 0.52, 0.58 },
                    tool      = { 0.48, 0.68, 0.88 },
                    component = { 0.62, 0.52, 0.78 },
                }
                col = CAT_COLOR[def.category] or col
            end
            love.graphics.setColor(col[1], col[2], col[3])
            love.graphics.rectangle("fill",
                icon_x, ingr_y + (INGR_H - ICON_SZ) * 0.5,
                ICON_SZ, ICON_SZ, 3, 3)
        end

        -- Ingredient lines to the right of the icon.
        for _, input in ipairs(sel_recipe.inputs) do
            local have = count_for_input(player, input)
            local col  = (have >= input.count) and C_HAVE or C_LACK
            local iname
            if input.accept and have >= input.count then
                -- Satisfied: show the specific item that will be consumed.
                for _, aname in ipairs(input.accept) do
                    local aid = ItemRegistry.id(aname)
                    if aid and count_in_inv(player, aid) > 0 then
                        local def = ItemRegistry.get(aid)
                        iname = def and def.display_name or aname
                        break
                    end
                end
            end
            if not iname then
                -- Not satisfied (or no group): show the group label so player
                -- knows any variant counts, not just the base item.
                iname = input.display_name
                if not iname then
                    local id  = ItemRegistry.id(input.name)
                    local def = id and ItemRegistry.get(id)
                    iname = def and def.display_name or input.name
                end
            end
            love.graphics.setColor(col[1], col[2], col[3])
            love.graphics.print(input.count .. "x  " .. iname, text_x, iy)
            iy = iy + font:getHeight() + 3
        end
        -- Tool cost lines (durability consumed during crafting).
        if sel_recipe.tool_costs then
            for _, cost in ipairs(sel_recipe.tool_costs) do
                local slot     = best_tool_slot(player, cost.class)
                local have_dur = slot and slot.durability or 0
                local col      = (have_dur >= cost.durability_cost) and C_HAVE or C_LACK
                local class_lbl = cost.class:sub(1,1):upper() .. cost.class:sub(2)
                love.graphics.setColor(col[1], col[2], col[3])
                love.graphics.print(cost.durability_cost .. " HP  " .. class_lbl, text_x, iy)
                iy = iy + font:getHeight() + 3
            end
        end
    else
        local hint = "Select a recipe"
        local hw   = font:getWidth(hint)
        love.graphics.setColor(C_SEP[1], C_SEP[2], C_SEP[3])
        love.graphics.print(hint,
            math.floor(cx + (PANEL_W - hw) * 0.5),
            math.floor(ingr_y + (INGR_H - font:getHeight()) * 0.5))
    end

    -- Separator above craft button.
    love.graphics.setColor(C_SEP[1], C_SEP[2], C_SEP[3])
    love.graphics.line(cx + PAD, sep2_y, cx + PANEL_W - PAD, sep2_y)

    -- ── Craft button ─────────────────────────────────────────────────────
    local craft_active = sel_recipe ~= nil and can_craft(player, sel_recipe)
    local bcol = craft_active and C_BTN or C_BTN_D
    love.graphics.setColor(bcol[1], bcol[2], bcol[3])
    love.graphics.rectangle("fill", lx, btn_y, lw, BTN_H, 4, 4)
    love.graphics.setColor(C_BORDER[1], C_BORDER[2], C_BORDER[3])
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", lx, btn_y, lw, BTN_H, 4, 4)

    local blabel = "Craft"
    local bltw   = font:getWidth(blabel)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(blabel,
        math.floor(lx + (lw - bltw) * 0.5),
        math.floor(btn_y + (BTN_H - font:getHeight()) * 0.5))

    -- ── Tabs (physical folder-tab style, bottom of panel) ────────────────
    -- Recessed dark gutter that the tabs sit in.
    love.graphics.setColor(0.05, 0.05, 0.08)
    love.graphics.rectangle("fill",
        cx + 2, tab_y - 2,
        PANEL_W - 4, PANEL_H - (tab_y - cy) - 2,
        0, 0, 0, TAB_R)   -- round only bottom corners of gutter

    -- Draw inactive tabs first so the active tab paints on top.
    local tabs = { "Can Craft", "All Known" }
    for pass = 1, 2 do
        for i, label in ipairs(tabs) do
            local is_active = (i == active_tab)
            if (pass == 1) == (not is_active) then   -- pass 1 = inactive, pass 2 = active
                local tx = lx + (i - 1) * (tab_w + 4)
                local ty = is_active and (tab_y - TAB_RAISE) or tab_y
                local th = is_active and (TAB_H + TAB_RAISE) or TAB_H

                -- Fill.
                if is_active then
                    love.graphics.setColor(C_BG[1], C_BG[2], C_BG[3])
                else
                    love.graphics.setColor(C_TAB_I[1], C_TAB_I[2], C_TAB_I[3])
                end
                love.graphics.rectangle("fill", tx, ty, tab_w, th, TAB_R, TAB_R)

                -- Border.
                love.graphics.setColor(C_BORDER[1], C_BORDER[2], C_BORDER[3])
                love.graphics.setLineWidth(1)
                love.graphics.rectangle("line", tx, ty, tab_w, th, TAB_R, TAB_R)

                -- Active: blot out top border so the tab "opens" into the panel.
                if is_active then
                    love.graphics.setColor(C_BG[1], C_BG[2], C_BG[3])
                    love.graphics.setLineWidth(2)
                    love.graphics.line(tx + TAB_R + 1, ty, tx + tab_w - TAB_R - 1, ty)
                    love.graphics.setLineWidth(1)
                end

                -- Label.
                local ltw = font:getWidth(label)
                love.graphics.setColor(
                    is_active and C_TITLE[1] or C_TAB_T[1],
                    is_active and C_TITLE[2] or C_TAB_T[2],
                    is_active and C_TITLE[3] or C_TAB_T[3])
                love.graphics.print(label,
                    math.floor(tx + (tab_w - ltw) * 0.5),
                    math.floor(ty + (th - font:getHeight()) * 0.5))
            end
        end
    end

    love.graphics.setColor(1, 1, 1)
end

function Crafting.mousepressed(x, y, button, player)
    if not player.backpack_open or button ~= 1 then return false end

    local W, H   = love.graphics.getDimensions()
    local cx, cy = panel_xy(W, H)

    -- Outside the panel (including tab strip below) — not consumed.
    if x < cx or x >= cx + PANEL_W or y < cy or y >= cy + PANEL_H then
        return false
    end

    local tab_y, btn_y, sep2_y, ingr_y, sep1_y, list_y, list_h, lw, tab_w = layout(cy)
    local lx = cx + PAD

    -- Tab buttons.
    if y >= tab_y and y < tab_y + TAB_H then
        for i = 1, 2 do
            local tx = lx + (i - 1) * (tab_w + 4)
            if x >= tx and x < tx + tab_w then
                if active_tab ~= i then
                    active_tab  = i
                    selected_id = nil
                end
                return true
            end
        end
    end

    -- Craft button.
    if y >= btn_y and y < btn_y + BTN_H and x >= lx and x < lx + lw then
        if selected_id then
            local list = visible_list(player)
            for _, recipe in ipairs(list) do
                if recipe.id == selected_id and can_craft(player, recipe) then
                    do_craft(player, recipe)
                    if active_tab == 1 and not can_craft(player, recipe) then
                        selected_id = nil
                    end
                    break
                end
            end
        end
        return true
    end

    -- Recipe rows.
    local list = visible_list(player)
    local ry   = list_y
    for _, recipe in ipairs(list) do
        if ry + ROW_H > list_y + list_h then break end
        if y >= ry and y < ry + ROW_H and x >= lx and x < lx + lw then
            selected_id = (selected_id == recipe.id) and nil or recipe.id
            return true
        end
        ry = ry + ROW_H + ROW_GAP
    end

    return true  -- click inside panel; consume regardless
end

return Crafting
