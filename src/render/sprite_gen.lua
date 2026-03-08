-- src/render/sprite_gen.lua
-- Development utility: generates SE/SW parallelogram face sprites from square s_*.png sources.
--
-- PIPELINE
--   For each  assests/tiles/s_<name>.png  (must be a square):
--     1. Check whether  se_<name>.png  and  sw_<name>.png  already exist.
--     2. If SE is missing, shear the source into the SE parallelogram bounding box.
--     3. If SW is missing, shear the source into the SW parallelogram bounding box.
--     4. Write the missing file(s) to disk as PNG.
--
-- GEOMETRY (SIZE = 48, LAYER_HEIGHT = 48)
--   Both face bounding boxes  →  FACE_W × CANVAS_H  =  24 × 90 px
--
--   SE face (right parallelogram):   translate(0, S3) + shear(0, -S3/FACE_W)
--     top-right  (FACE_W,  0)        ← E vertex
--     top-left   (0,       S3 ≈ 42)  ← SE vertex
--     btm-left   (0,       S3 + LH)
--     btm-right  (FACE_W,  LH)
--
--   SW face (left parallelogram):    shear(0, +S3/FACE_W)
--     top-left   (0,       0)        ← W vertex
--     top-right  (FACE_W,  S3 ≈ 42)  ← SW vertex
--     btm-right  (FACE_W,  S3 + LH)
--     btm-left   (0,       LH)
--
-- CALLING CONVENTION
--   SpriteGen.run() once in GameLoop.load(), BEFORE TileRegistry.load().
--   Comment out the call once all sprites are settled.

local RenderCfg = require("config.render")

local SpriteGen = {}

local FACE_W   = RenderCfg.hex_size / 2                    -- 24 px  (= SIZE / 2)
local FACE_H   = RenderCfg.layer_height                    -- 48 px
local S3       = RenderCfg.hex_size * math.sqrt(3) * 0.5  -- ≈ 41.57 px  (hex inradius)
local CANVAS_H = math.ceil(S3 + FACE_H)                   -- 90 px

-- ── Internal helpers ──────────────────────────────────────────────────────────

-- Shear a square source sprite into the SE parallelogram bounding box.
-- Transform maps the source rectangle (FACE_W × FACE_H) to the parallelogram:
--   translate(0, S3) + shear(0, -S3/FACE_W)
-- This shifts the left column down by S3 while the right column stays at y=0.
local function make_se(src)
    local iw, ih = src:getDimensions()
    local canvas = love.graphics.newCanvas(FACE_W, CANVAS_H)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.push()
    love.graphics.origin()           -- ensure clean identity transform inside canvas
    love.graphics.translate(0, S3)   -- drop left edge down by S3
    love.graphics.shear(0, -S3 / FACE_W)  -- shear right edge back up to y=0
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(src, 0, 0, 0, FACE_W / iw, FACE_H / ih)
    love.graphics.pop()
    love.graphics.setCanvas()
    return canvas:newImageData()
end

-- Mirror the SE ImageData horizontally to produce SW.
local function make_sw(se_data)
    local w, h = se_data:getDimensions()
    local sw = love.image.newImageData(w, h)
    sw:mapPixel(function(x, y)
        return se_data:getPixel(w - 1 - x, y)
    end)
    return sw
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

local function save_png(imgdata, path)
    local fd = imgdata:encode("png")
    local f = io.open(path, "wb")
    if not f then
        print("[SpriteGen] ERROR: cannot write " .. path)
        return false
    end
    f:write(fd:getString())
    f:close()
    print("[SpriteGen] saved " .. path)
    return true
end

-- ── Public API ────────────────────────────────────────────────────────────────

function SpriteGen.run()
    if love.filesystem.isFused() then
        -- Running from a packaged .love — can't write back to source tree.
        return
    end

    local tile_vdir = "assests/tiles"                                   -- virtual (love.filesystem)
    local abs_dir   = love.filesystem.getSource() .. "/" .. tile_vdir .. "/"

    local items = love.filesystem.getDirectoryItems(tile_vdir)
    if not items then
        print("[SpriteGen] directory not found: " .. tile_vdir)
        return
    end

    for _, fname in ipairs(items) do
        -- Match s_<name>.png only (se_ and sw_ prefixes don't match ^s_ + underscore at pos 2)
        local stem = fname:match("^s_(.+)%.png$")
        if stem then
            local se_path = abs_dir .. "se_" .. stem .. ".png"
            local sw_path = abs_dir .. "sw_" .. stem .. ".png"

            local need_se = not file_exists(se_path)
            local need_sw = not file_exists(sw_path)

            if need_se or need_sw then
                print("[SpriteGen] processing " .. fname)
                local ok, src = pcall(love.graphics.newImage, tile_vdir .. "/" .. fname)
                if not ok then
                    print("[SpriteGen] ERROR: could not load " .. fname .. " — " .. tostring(src))
                else
                    src:setFilter("nearest", "nearest")
                    local se_data = make_se(src)
                    if need_se then save_png(se_data, se_path) end
                    if need_sw then save_png(make_sw(se_data), sw_path) end
                end
            end
        end
    end
end

return SpriteGen
