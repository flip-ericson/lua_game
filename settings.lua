--- "settings.lua" begins here ---
local Settings = {
    -- Window settings
    windowWidth = 1200,
    windowHeight = 700,
    -- Tile settings
    hexSize = 48,  -- Distance from center to corner
    gridWidth = 20,
    gridHeight = 20,
    zLayers = 3,
    -- Player settings
    playerSpeed = 200,
    jumpTime = .75, -- delta time is in second
    -- World Settings
    maxnightOverlayOpacity = 0.85, -- 0.0 fully transparent, 1.0 fully dark
    minnightOverlayOpacity = .5,
    tileHeightOffset = 30,
    -- Tick Settings
    tickSpeed = 1, --- once a second for now
    healthTick = 5,
    tillFailTick = 60,
    landDriesTick = 1,
    grassSpreadTick = 10,
    waterSpreadTick = 1,
    tillFailChance = 1440, -- number is denominator so chance is 1/1440
    grassSpreadChance = 30,
    waterSpreadChance = 30,
    landDriesChance = 4,
    -- Starting Time
    gameMinute = 1,     -- 0-59
    gameHour = 5,       -- 0-23 (starts at 5am)
    gameDay = 1,        -- 1-12(depends on month)
    gameMonth = 3,      -- 1-12
    gameYear = math.random(1, 1500),
    -- Real-time constants (in seconds)
    dayLength = 720,    -- 12 minutes in seconds
    nightLength = 480,  -- 8 minutes in seconds
    fullDayLength = 1200, -- 20 minutes total
    -- Audio Settings
    fadeInDuration = 5.0,
    fadeOutDuration = 60.0,
    musicVolume = 0,
    --- tools and items 
    tools = {
            ["Fist"] = true,
            ["Pickaxe"] = true,
            ["Hoe"] = true,
            ["Shovel"] = true
            },
    items = {
            ["stone_item"] = true
            }
}
-- 1. Helper Function: Greatest Common Divisor (GCD)
-- Uses the Euclidean algorithm, which is fast and standard.
local function gcd(a, b)
    -- Take absolute values to handle negative inputs
    a = math.abs(a)
    b = math.abs(b)
    while b ~= 0 do
        local t = b
        b = a % b
        a = t
    end
    return a
end
-- 2. Helper Function: Least Common Multiple (LCM) of TWO numbers
local function lcm_two(a, b)
    if a == 0 or b == 0 then
        return 0
    end
    -- Formula: (a * b) / GCD(a, b)
    -- Note: We use floor division (//) if available (Lua 5.3+) 
    -- or math.floor(a * b / gcd(a, b)) otherwise, to ensure an integer result.
    local result_gcd = gcd(a, b)
    -- Using the division first to prevent potential overflow (a*b) with large numbers
    return math.abs(a / result_gcd * b)
end
-- 3. Main Function: LCM of a TABLE of numbers
function find_lcm_of_table(numbers)
    if not numbers or #numbers == 0 then
        return nil -- Or raise an error
    end
    -- Start with the LCM of the first two numbers
    local result_lcm = numbers[1]
    -- Iterate from the second number onwards
    for i = 2, #numbers do
        local current_num = numbers[i]
        -- The LCM of a group is the LCM of the previous result and the next number.
        result_lcm = lcm_two(result_lcm, current_num)
    end
    return result_lcm
end

-- NOW reference the variables after Settings exists
Settings.allTicks = {Settings.healthTick, 
                    Settings.tillFailTick, 
                    Settings.landDriesTick, 
                    Settings.grassSpreadTick, 
                    Settings.waterSpreadTick}
Settings.tickFullCycle = find_lcm_of_table(Settings.allTicks)

return Settings
--- "settings.lua" ends here ---