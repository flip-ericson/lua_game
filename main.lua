-- main.lua — Dwarf Island V4 entry point
-- LÖVE2D calls these callbacks automatically. This file stays thin —
-- all real logic lives in the GameLoop module.

-- Local Lua Debugger hook (VSCode). Only active when launched from the debugger.
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
    require("lldebugger").start()
end

local GameLoop = require("src.core.gameloop")

function love.load()
    GameLoop.load()
end

function love.update(dt)
    GameLoop.update(dt)
end

function love.draw()
    GameLoop.draw()
end

-- ── Input callbacks ────────────────────────────────────────────────────────

function love.keypressed(key, scancode, isrepeat)
    if key == "escape" then
        love.event.quit()
    end
    GameLoop.keypressed(key, scancode, isrepeat)
end

function love.keyreleased(key, scancode)
    GameLoop.keyreleased(key, scancode)
end

function love.mousepressed(x, y, button, istouch, presses)
    GameLoop.mousepressed(x, y, button, istouch, presses)
end

function love.mousereleased(x, y, button, istouch, presses)
    GameLoop.mousereleased(x, y, button, istouch, presses)
end

function love.mousemoved(x, y, dx, dy, istouch)
    GameLoop.mousemoved(x, y, dx, dy, istouch)
end

function love.wheelmoved(x, y)
    GameLoop.wheelmoved(x, y)
end

-- ── Window callbacks ───────────────────────────────────────────────────────

function love.resize(w, h)
    GameLoop.resize(w, h)
end
