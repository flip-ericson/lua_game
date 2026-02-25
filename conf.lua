-- conf.lua — LÖVE2D window & module configuration
-- Loaded by LÖVE before main.lua. Anything here overrides defaults.

function love.conf(t)
    t.identity  = "dwarf_island_v4"   -- save directory name
    t.version   = "11.5"              -- minimum LÖVE version required
    t.console   = false               -- set true on Windows if you want a debug console

    t.window.title          = "Dwarf Island"
    t.window.fullscreen     = true
    t.window.fullscreentype = "desktop"   -- uses your current desktop res, no mode switch
    t.window.vsync          = 1           -- 0 = off, 1 = on, -1 = adaptive

    -- Disable modules we won't use (saves startup time)
    t.modules.joystick = false
    t.modules.touch    = false
    t.modules.video    = false
end
