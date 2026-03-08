-- src/core/time.lua
-- Stateless calendar module. All game state lives in world.game_time.
-- 1 real second = 1 game minute → 1 game day = 1440 real seconds.
--
-- PUBLIC API
--   Time.load()              → pre-load sun/moon sprites (call once at startup)
--   Time.get(world)          → snapshot table with all derived calendar fields
--   Time.draw(snap, sw, sh)  → draw corner widget (top-right)
--
-- CALENDAR
--   12 months (variable length), 119 days/year, 4 seasons, 8 moon phases.
--   Moon phase = (total_days % 8) + 1  (1=Full … 8=Waxing Gibbous)

local Time = {}

-- ── Calendar data ─────────────────────────────────────────────────────────

local MONTHS = {
    { name = "Sapphire",  days = 8,  season = "Stoneviel"    },
    { name = "Silver",    days = 9,  season = "Stoneviel"    },
    { name = "Mithril",   days = 11, season = "Ironsong"     },
    { name = "Jade",      days = 9,  season = "Ironsong"     },
    { name = "Emerald",   days = 10, season = "Ironsong"     },
    { name = "Sunstone",  days = 11, season = "Hammerheight" },
    { name = "Ruby",      days = 12, season = "Hammerheight" },
    { name = "Iron",      days = 10, season = "Hammerheight" },
    { name = "Copper",    days = 10, season = "Brightforge"  },
    { name = "Gold",      days = 11, season = "Brightforge"  },
    { name = "Sandstone", days = 9,  season = "Brightforge"  },
    { name = "Diamond",   days = 9,  season = "Stoneviel"    },
}

local MOON_NAMES = {
    "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent",
    "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
}

-- Pre-compute cumulative day offsets for O(1) month lookup.
local MONTH_OFFSETS = {}
local YEAR_DAYS = 0
do
    local acc = 0
    for i, m in ipairs(MONTHS) do
        MONTH_OFFSETS[i] = acc
        acc = acc + m.days
    end
    YEAR_DAYS = acc  -- 119
end

-- ── Sprite storage ────────────────────────────────────────────────────────

local _moon_sprites = {}   -- [1..8] → loaded Image, or nil
local _sun_sprite   = nil
local ICON_SIZE     = 36   -- matches hotbar inner drawing area (SLOT_SIZE=44, PAD=4*2)

local MOON_PATHS = {
    "assests/ui/moon_01_full.png",
    "assests/ui/moon_02_waning_full.png",
    "assests/ui/moon_03_half_full.png",
    "assests/ui/moon_04_waning_new.png",
    "assests/ui/moon_05_new.png",
    "assests/ui/moon_06_waxing_new.png",
    "assests/ui/moon_07_half_new.png",
    "assests/ui/moon_08_waxing_full.png",
}

function Time.load()
    for i, path in ipairs(MOON_PATHS) do
        if love.filesystem.getInfo(path) then
            local img = love.graphics.newImage(path)
            img:setFilter("nearest", "nearest")
            _moon_sprites[i] = img
        end
    end
    local sun_path = "assests/ui/sun.png"
    if love.filesystem.getInfo(sun_path) then
        local img = love.graphics.newImage(sun_path)
        img:setFilter("nearest", "nearest")
        _sun_sprite = img
    end
end

-- ── Snapshot derivation ───────────────────────────────────────────────────

local MINS_PER_DAY = 24 * 60   -- 1440

function Time.get(world)
    local total_mins  = math.floor(world.game_time)
    local hour        = math.floor(total_mins / 60) % 24
    local minute      = total_mins % 60
    local total_days  = math.floor(total_mins / MINS_PER_DAY)
    local day_of_year = total_days % YEAR_DAYS   -- 0..118

    -- Find month index: scan from the end for the first offset ≤ day_of_year.
    local month_idx = 1
    for i = #MONTHS, 1, -1 do
        if day_of_year >= MONTH_OFFSETS[i] then
            month_idx = i
            break
        end
    end

    local day_of_month = day_of_year - MONTH_OFFSETS[month_idx] + 1  -- 1-indexed
    local year         = math.floor(total_days / YEAR_DAYS) + 1       -- 1-indexed

    local moon_phase   = (total_days % 8) + 1   -- 1..8

    local is_day   = (hour >= 6 and hour < 20)
    local is_dawn  = (hour >= 4 and hour < 6)
    local is_dusk  = (hour >= 20 and hour < 22)
    local is_night = not is_day and not is_dawn and not is_dusk

    return {
        hour         = hour,
        minute       = minute,
        total_days   = total_days,
        day_of_year  = day_of_year,
        year         = year,
        month_idx    = month_idx,
        month_name   = MONTHS[month_idx].name,
        day_of_month = day_of_month,
        season       = MONTHS[month_idx].season,
        moon_phase   = moon_phase,
        moon_name    = MOON_NAMES[moon_phase],
        is_day       = is_day,
        is_dawn      = is_dawn,
        is_dusk      = is_dusk,
        is_night     = is_night,
    }
end

-- ── Helpers ───────────────────────────────────────────────────────────────

-- ordinal(n) → "1st", "2nd", "3rd", "4th", "11th", "21st", etc.
local function ordinal(n)
    local abs_n = math.abs(n)
    local last2 = abs_n % 100
    -- 11, 12, 13 are always "th" (English irregulars).
    if last2 >= 11 and last2 <= 13 then
        return n .. "th"
    end
    local last1 = abs_n % 10
    if last1 == 1 then return n .. "st" end
    if last1 == 2 then return n .. "nd" end
    if last1 == 3 then return n .. "rd" end
    return n .. "th"
end

-- ── Widget draw ───────────────────────────────────────────────────────────

local C_BG     = { 0.08, 0.08, 0.12, 0.85 }   -- dark panel
local C_TEXT   = { 0.92, 0.75, 0.35, 1.00 }   -- amber
local C_DIM    = { 0.60, 0.50, 0.25, 1.00 }   -- secondary amber
local PAD      = 8   -- inner padding
local ICON_GAP = 6   -- gap between icon and text column
local MARGIN   = 8   -- gap from screen edge

-- draw(snap, sw, sh)
--   snap → result of Time.get(world); nil = skip draw
--   sw, sh → screen width / height
function Time.draw(snap, sw, sh)
    if not snap then return end

    local fnt = love.graphics.getFont()
    local lh  = fnt:getHeight() + 3   -- line height with a little breathing room

    -- Build display strings.
    local h12 = snap.hour % 12
    if h12 == 0 then h12 = 12 end
    local ampm       = snap.hour < 12 and "AM" or "PM"
    local time_str   = string.format("%d:%02d %s", h12, snap.minute, ampm)
    local date_str   = string.format("%s of %s, Year %d",
                           ordinal(snap.day_of_month), snap.month_name, snap.year)
    local season_str = snap.season

    -- Panel sizing.
    local text_w  = math.max(fnt:getWidth(time_str),
                             fnt:getWidth(date_str),
                             fnt:getWidth(season_str))
    local rows_h  = lh * 3
    local inner_h = math.max(ICON_SIZE, rows_h)
    local panel_w = PAD + ICON_SIZE + ICON_GAP + text_w + PAD
    local panel_h = PAD + inner_h + PAD

    local px = sw - MARGIN - panel_w
    local py = MARGIN

    -- Background panel.
    love.graphics.setColor(C_BG)
    love.graphics.rectangle("fill", px, py, panel_w, panel_h, 4, 4)

    -- Icon: sun during day, moon at night.
    local icon_x = px + PAD
    local icon_y = py + PAD
    -- Vertically center icon in inner_h.
    local icon_top = icon_y + math.floor((inner_h - ICON_SIZE) * 0.5)

    -- Sun during day and dawn; moon during dusk and night.
    local show_sun = snap.is_day or snap.is_dawn
    local icon_img = show_sun and _sun_sprite or _moon_sprites[snap.moon_phase]
    if icon_img then
        local iw, ih = icon_img:getDimensions()
        local scale  = math.min(ICON_SIZE / iw, ICON_SIZE / ih)
        local dw, dh = iw * scale, ih * scale
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(icon_img,
            math.floor(icon_x + (ICON_SIZE - dw) * 0.5),
            math.floor(icon_top + (ICON_SIZE - dh) * 0.5),
            0, scale, scale)
    else
        -- Fallback colored dot when sprites are missing.
        love.graphics.setColor(show_sun and {1.0, 0.85, 0.2, 1} or {0.7, 0.7, 0.9, 1})
        love.graphics.circle("fill",
            icon_x + ICON_SIZE * 0.5,
            icon_top + ICON_SIZE * 0.5,
            ICON_SIZE * 0.4)
    end

    -- Text column.
    local tx      = icon_x + ICON_SIZE + ICON_GAP
    local ty      = py + PAD + math.floor((inner_h - rows_h) * 0.5)

    love.graphics.setColor(C_TEXT)
    love.graphics.print(time_str,   tx, ty)
    love.graphics.print(date_str,   tx, ty + lh)
    love.graphics.setColor(C_DIM)
    love.graphics.print(season_str, tx, ty + lh * 2)

    love.graphics.setColor(1, 1, 1, 1)
end

return Time
