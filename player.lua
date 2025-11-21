--- "player.lua" begins here ---
local Settings = require('settings')
local Items = require('items')
local Collision = require('collision')
local Selector = require('selector')
local Tiles = require('tiles')
local GameDebug = require('gamedebug')

local Player = {}

function Player:new(x, y)
    local obj = {
        x = x,
        y = y,
        zLayer = 2,
        speed = Settings.playerSpeed,
        size = ((math.sqrt(3) / 2) * Settings.hexSize),
        world = nil,
        -- Hotbar Inventory
        hotbar = {
            {item = Items.Pickaxe, count = nil},  -- slot 1 contains the Pickaxe object for now
            {item = Items.Stone, count = 1}, -- slot 2 contains the Stone object for now
            {item = Items.Hoe, count = nil}, -- slot 3 is hoe for now
            {item = Items.Shovel, count = nil}, -- slot 4 is shovel for now
            nil, nil, nil, nil, nil, nil  -- remaining 6 empty slots (10 total)
        },
        hotbarSelected = 1, -- which slot is selected (1..10)
        -- Item properties
        itemAnimationActive = false,
        itemAnimationTimer = 0,
        itemAnimationDuration = 0.5,
        itemAnimationHex = nil, --temporarily store selected tile
        itemAnimationSprite = nil,
        toolReach = Settings.hexSize,
        utilizedTile = nil,
        -- Swimming state
        isInWater = false,
        swimSpeedMultiplier = 0.5,  -- Swim at 50% speed
        swimVisiblePercent = 0.6, -- what percent of sprite is show while swimming
        -- jumping state
        goingUp = false,
        isJumping = false,
        jumpTimer = 0,
        viewLayer = 2,
        -- Animation properties
        spritesheet = nil,
        spriteWidth = 102,  -- 1024 / 10 columns
        spriteHeight = 111, -- 888 / 8 rows
        scale = (((math.sqrt(3) / 2) * Settings.hexSize)) / 102,  -- Scale sprite to match hitbox size
        direction = "down",  -- down, up, left, right
        state = "idle",      -- idle, walking
        animationTimer = 0,
        animationSpeed = 0.05,  -- Time between frames
        currentFrame = 1,
        -- Animation frame definitions
        animations = {
            idle = {
                down = {row = 1, frames = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 3, 2,
                                            1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1}},
                left = {row = 2, frames = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 ,1, 2, 3, 2,
                                            1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1}},
                up = {row = 3, frames = {1}},
                right = {row = 4, frames = {1, 1, 1, 1, 1, 1, 1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,1 ,1, 1, 2, 3, 2,
                                            1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1}}
            },
            walking = {
                down = {row = 5, frames = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}},
                left = {row = 6, frames = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}},
                up = {row = 7, frames = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}},
                right = {row = 8, frames = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}}
            }
        },     
        quads = {}
    }
    setmetatable(obj, self)
    self.__index = self 
    -- Load spritesheet
    obj:loadSpritesheet() 
    return obj
end

-- Add item to player's inventory
function Player:addItem(item, count)
    count = count or 1
    -- First, try to stack with existing items in hotbar
    for i = 1, #self.hotbar do
        local slot = self.hotbar[i]
        if slot and slot.item == item then
            -- Found matching item
            if item.stackSize then
                -- Item can stack
                local remaining = item.stackSize - slot.count
                if remaining > 0 then
                    local addAmount = math.min(remaining, count)
                    slot.count = slot.count + addAmount
                    count = count - addAmount
                    if count == 0 then
                        return true  -- All items added
                    end
                end
            end
        end
    end
    -- Still have items left, find empty slots
    while count > 0 do
        local emptySlot = nil
        for i = 1, #self.hotbar do
            if self.hotbar[i] == nil then
                emptySlot = i
                break
            end
        end     
        if emptySlot then
            -- Add to empty slot
            local addAmount = item.stackSize and math.min(item.stackSize, count) or count
            self.hotbar[emptySlot] = {item = item, count = addAmount}
            count = count - addAmount
        else
            -- Inventory full!
            return false
        end
    end
    return true
end

function Player:startItemAnimation()
    if not Selector.highlightedHex then
        return
    end
    -- pick correct sprite
    local sprite = nil
    local selectedItem = self.hotbar[self.hotbarSelected]
    if selectedItem.item and selectedItem.item.image then
        sprite = selectedItem.item.image
    else
    -- use fist if no tool
        sprite = Items.Fist.image
    end
    if sprite then
        self.itemAnimationActive = true
        self.itemAnimationTimer = 0
        self.itemAnimationHex = {
            x = Selector.highlightedHex.x,
            y = Selector.highlightedHex.y
        }
        self.itemAnimationSprite = sprite
    end
end

function Player:updateItemAnimation(dt)
    if self.itemAnimationActive then
        self.itemAnimationTimer = self.itemAnimationTimer + dt
        -- end and reset if animation is over
        if self.itemAnimationTimer >= self.itemAnimationDuration then
            self.itemAnimationActive = false
            self.itemAnimationTimer = 0
            self.itemAnimationHex = nil
            self.itemAnimationSprite = nil
        end
    end
end

function Player:drawItemAnimation()
    if not self.itemAnimationActive or not self.itemAnimationHex or not self.itemAnimationSprite then
        return
    end
    -- Calculate fade-out alpha (1.0 at start, 0.0 at end)
    local progress = self.itemAnimationTimer / self.itemAnimationDuration
    local alpha = 1.0 - progress
    -- Get sprite dimensions
    local spriteWidth = self.itemAnimationSprite:getWidth()
    local spriteHeight = self.itemAnimationSprite:getHeight()
    -- Scale to reasonable size (adjust this as needed)
    local targetSize = Settings.hexSize * 0.8
    local scale = targetSize / math.max(spriteWidth, spriteHeight)
    -- Calculate scaled dimensions
    local scaledWidth = spriteWidth * scale
    local scaledHeight = spriteHeight * scale
    -- Center on hex
    local drawX = self.itemAnimationHex.x - scaledWidth / 2
    local drawY = self.itemAnimationHex.y - scaledHeight / 2
    -- Draw with fade-out
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(self.itemAnimationSprite, drawX, drawY, 0, scale, scale)
    -- reset color
    love.graphics.setColor(1, 1, 1, 1)
end

function Player:drawHotbar(windowWidth, windowHeight)
    -- Hotbar geometry
    local hotbarWidth = 658
    local hotbarHeight = 69
    local hotbarX = (windowWidth - hotbarWidth) / 2
    local hotbarY = windowHeight - hotbarHeight - 8  -- 8 px buffer
    -- visual constants for slots
    local slots = 10
    local padding = 8
    local innerHeight = hotbarHeight - (padding * 2)
    local maxSlotSize = innerHeight -- fit inside the hotbar vertically
    local slotGap = 6
    -- compute slot size so all slots fit horizontally inside the hotbar
    local slotAreaWidth = hotbarWidth - (padding * 2)
    local slotSize = math.min(maxSlotSize, math.floor((slotAreaWidth - (slotGap * (slots - 1))) / slots))
    -- compute start x so slots are centered inside the hotbar area
    local totalSlotsWidth = slots * slotSize + (slots - 1) * slotGap
    local startX = hotbarX + (hotbarWidth - totalSlotsWidth) / 2
    local slotY = hotbarY + padding + (hotbarHeight - padding * 2 - slotSize) / 2
    -- draw slot outlines / backgrounds (simple)
    love.graphics.setColor(1, 1, 1, 0.08)
    for i = 1, slots do
        local sx = startX + (i - 1) * (slotSize + slotGap)
        love.graphics.rectangle("fill", sx, slotY, slotSize, slotSize, 6, 6)
    end
    -- reset color
    love.graphics.setColor(1, 1, 1, 1)
    -- draw slot borders
    for i = 1, slots do
        local sx = startX + (i - 1) * (slotSize + slotGap)
        love.graphics.rectangle("line", sx, slotY, slotSize, slotSize, 6, 6)
    end
    -- draw selected highlight
    if self.hotbarSelected and self.hotbarSelected >= 1 and self.hotbarSelected <= slots then
        local sx = startX + (self.hotbarSelected - 1) * (slotSize + slotGap)
        love.graphics.setLineWidth(2)
        love.graphics.setColor(1, 1, 0, 0.9) -- yellow-ish highlight
        love.graphics.rectangle("line", sx - 2, slotY - 2, slotSize + 4, slotSize + 4, 8, 8)
        love.graphics.setLineWidth(1)
        -- reset color
        love.graphics.setColor(1, 1, 1, 1)
    end
    -- draw items (scale them to fit slotSize)
    for i = 1, slots do
        local dict = self.hotbar[i]
        if dict then
            -- get scale so the largest dimension fits inside slot with a little padding
            local pad = 6
            local available = slotSize - pad * 2
            local iw = dict.item.width or (dict.item.image and dict.item.image:getWidth()) or available
            local ih = dict.item.height or (dict.item.image and dict.item.image:getHeight()) or available
            local scale = 1
            if iw > 0 and ih > 0 then
                scale = math.min(available / iw, available / ih)
            end
            -- center the item in the slot
            local sx = startX + (i - 1) * (slotSize + slotGap)
            local drawX = sx + (slotSize - (iw * scale)) / 2
            local drawY = slotY + (slotSize - (ih * scale)) / 2
            -- If the item has a :draw method that accepts (x,y,scale) use it; otherwise draw image directly
            if dict.item.draw then
                -- call the object's draw (Item:draw expects (x,y,scale) in earlier examples)
                dict.item:draw(drawX, drawY, scale)
            elseif dict.item.image then
                love.graphics.draw(dict.item.image, drawX, drawY, 0, scale, scale)
            end
            -- add the count to the hotbar
            if dict.count and dict.count > 1 then
                local text = tostring(dict.count)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.print(text, sx + slotSize - 4 - love.graphics.getFont():getWidth(text),
                                    slotY + slotSize - 4 - love.graphics.getFont():getHeight(), 0, 1, 1)
            end
        end
    end
end

function Player:loadSpritesheet()
    local success, result = pcall(function()
        return love.graphics.newImage("images/player_animations.png")
    end)
    if success then
        self.spritesheet = result
        self.spritesheet:setFilter("nearest", "nearest")
        -- Create quads for each sprite in the sheet (10 columns, 8 rows)
        for row = 1, 8 do
            self.quads[row] = {}
            for col = 1, 10 do
                self.quads[row][col] = love.graphics.newQuad(
                    (col - 1) * self.spriteWidth,
                    (row - 1) * self.spriteHeight,
                    self.spriteWidth,
                    self.spriteHeight,
                    self.spritesheet:getWidth(),
                    self.spritesheet:getHeight()
                )
            end
        end
    end
end

function Player:getCurrentQuad()
    local anim = self.animations[self.state][self.direction]
    if not anim then 
        return nil 
    end
    local frameIndex = anim.frames[self.currentFrame]
    return self.quads[anim.row][frameIndex]
end

function Player:updateJumpTimer(dt)
    if self.isJumping then
        -- increment timer by delta time
        self.jumpTimer = self.jumpTimer + dt
        -- find peak of jump (half the timer)
        if self.jumpTimer >= (Settings.jumpTime / 2) and self.goingUp then
            self.viewLayer = self.zLayer
            self.zLayer = self.zLayer + 1
            self.goingUp = false
        end
        if self.jumpTimer >= (Settings.jumpTime) and self.onGround then
            self.jumpTimer = 0
            self.isJumping = false
            self.viewLayer = self.zLayer
        end
    else
        self.viewLayer = self.zLayer
    end
end

function Player:keypressed(key)
    -- Handle Item Selection (this is a discrete event)
    if key >= '1' and key <= '9' then
        -- Convert key to number and set selection
        self.hotbarSelected = tonumber(key)
    elseif key == '0' then
        -- Key 0 selects slot 10
        self.hotbarSelected = 10
    end
    -- Handle tool use
    if key == 'return' then
        self.utilizedTile = Selector.highlightedHex
        self:startItemAnimation()
        self:utilize()
    end
    if key == 'space' then
        if not self.isJumping and self.onGround then
            self.isJumping = true
            self.jumpTimer = 0
            self.goingUp = true
        end
    end
end

function Player:mousepressed(key)
    if key == 1 then
        self.utilizedTile = Selector.highlightedHex
        self:startItemAnimation()
        self:utilize()
    end
end

function Player:update(dt)
    local moveX = 0
    local moveY = 0
    local isMoving = false
    local currentSpeed = self.speed
    -- check for items to pick up
    local playerCenterX = self.x + self.size / 2
    local playerCenterY = self.y + self.size / 2
    for i = #Items.droppedItems, 1, -1 do
        local item = Items.droppedItems[i]
        local itemCenterX = item.x + item.size / 2
        local itemCenterY = item.y + item.size / 2
        -- Check distance between player and item
        local dx = playerCenterX - itemCenterX
        local dy = playerCenterY - itemCenterY
        local distance = math.sqrt(dx * dx + dy * dy)
        -- Pickup radius
        local pickupRadius = self.size / 2 + item.size / 2
        if distance < pickupRadius and item.zLayer == self.zLayer then
            -- add to inv
            self:addItem(item.item, 1)
            -- Remove from world
            table.remove(Items.droppedItems, i)
        end
    end
    -- check if swimming before movement
    self.isInWater = false
    if self.world then
        local _, _, waterTiles = Collision.checkCollision(self, self.world)
        if waterTiles and #waterTiles > 0 then
            self.isInWater = true
            currentSpeed = currentSpeed * self.swimSpeedMultiplier
        end
    end
    -- Calculate intended movement and determine direction
    if love.keyboard.isDown('w') then
        moveY = moveY - 1
        self.direction = "up"
        isMoving = true
    end
    if love.keyboard.isDown('s') then
        moveY = moveY + 1
        self.direction = "down"
        isMoving = true
    end
    if love.keyboard.isDown('a') then
        moveX = moveX - 1
        self.direction = "left"
        isMoving = true
    end
    if love.keyboard.isDown('d') then
        moveX = moveX + 1
        self.direction = "right"
        isMoving = true
    end
    -- Normalize diagonal movement (multiply by 0.7071 when moving both X and Y)
    if moveX ~= 0 and moveY ~= 0 then
        moveX = moveX * 0.7071
        moveY = moveY * 0.7071
    end
    -- Apply speed and delta time
    moveX = moveX * currentSpeed * dt
    moveY = moveY * currentSpeed * dt
    -- Update state
    if isMoving and not self.isJumping then
        self.state = "walking"
    else
        self.state = "idle"
    end
    --- Apply movement with collision resolution
    if self.world and not GameDebug.noClip then
        -- Store old position
        local oldX = self.X
        local oldY = self.y
        -- Apply movement
        self.x = self.x + moveX
        self.y = self.y + moveY
        -- Check for collisions
        local colliding, collisions, onGround = Collision.checkCollision(self, self.world)
        self.onGround = onGround
        if colliding then
            -- Resolve collision (pushes player out of solid tiles)
            Collision.resolveCollision(self, collisions)
        end
        self:updateJumpTimer(dt)
    else
        -- No collision, just move freely
        self.x = self.x + moveX
        self.y = self.y + moveY
    end
    -- Update animation
    self:updateItemAnimation(dt)
    self:updateAnimation(dt)
end

function Player:updateAnimation(dt)
    local anim = self.animations[self.state][self.direction]
    if not anim then 
        return 
    end
    -- Update animation timer
    self.animationTimer = self.animationTimer + dt
    -- Change frame when timer exceeds animation speed
    if self.animationTimer >= self.animationSpeed then
        self.animationTimer = 0
        self.currentFrame = self.currentFrame + 1
        -- Loop back to first frame
        if self.currentFrame > #anim.frames then
            self.currentFrame = 1
        end
    end
    -- Reset to first frame if idle
    if self.state == "idle" and self.currentFrame > #anim.frames then
        self.currentFrame = 1
    end
end

function Player:draw()
    if self.spritesheet then
        local quad = self:getCurrentQuad()
        -- Calculate center from top-left position
        local centerX = self.x + self.size / 2
        local centerY = self.y + self.size / 2
        local spriteYOffset = 0
        if self.isJumping then
            -- Calculate jump progress (0 = start, 1 = peak, 0 = end)
            local jumpProgress = self.jumpTimer / Settings.jumpTime
             -- Make it arc: 0 -> 1 -> 0 (peak at 0.5)
            local jumpHeight = 1 - math.abs(jumpProgress * 2 - 1)
            -- Shadow shrinks as player goes higher
            local shadowScale = math.max(0.4, 1.0 - (jumpHeight * 0.4))

            love.graphics.setColor(0, 0, 0, 0.3)
            love.graphics.circle("fill", centerX, centerY + self.size * 0.4, self.size * 0.4 * shadowScale)
            love.graphics.setColor(1, 1, 1, 1)
            --make him move up and down
            spriteYOffset = jumpHeight * Settings.tileHeightOffset
        end
        if quad then
            -- Calculate scaled sprite dimensions
            local scaledWidth = self.spriteWidth * self.scale
            local scaledHeight = self.spriteHeight * self.scale
            -- Center the sprite on the player position
            local drawX = self.x - (scaledWidth - self.size) / 2
            local drawY = self.y - (scaledHeight - self.size) / 2
            -- when swimming only draw head
            if self.isInWater then
                local visiblePercent = self.swimVisiblePercent
                local qx, qy, qw, qh = quad:getViewport()
                local maskedQuad = love.graphics.newQuad(
                    qx,
                    qy,
                    qw,
                    qh * visiblePercent,
                    self.spritesheet:getWidth(),
                    self.spritesheet:getHeight()
                )
                love.graphics.draw(
                    self.spritesheet,
                    maskedQuad,
                    drawX,
                    drawY,
                    0,
                    self.scale,
                    self.scale
                )
            else
            -- Normal drawing
                love.graphics.draw(self.spritesheet, quad, drawX, drawY - spriteYOffset, 0, self.scale, self.scale)
            end
        end
    end
end

function Player:utilize()
    local utilizedHex = Selector.highlightedHex
    if not utilizedHex then
        return
    end
    -- look up the tile using the coordinates
    local World = require('world')
    local tile = World.getTile(utilizedHex.q, utilizedHex.r, utilizedHex.z)
    if not tile then
        return
    end
    -- figure out what tool is being used
    local currentTool = nil
    if self.hotbar[self.hotbarSelected] == nil then
        currentTool = 'Fist'
    else
        currentTool = self.hotbar[self.hotbarSelected].item:getName()
    end
----------------------------------------------------------------------------------
--  HANDLE STONE  ----------------------------------------------------------------
----------------------------------------------------------------------------------
    if tile.type.name == "stone" then -- if correct add correct tool bonus
        if tile.type.correctTool[currentTool] then
            tile.health = tile.health - 25
            World.addModifiedTile(tile)
        else
            if Settings.tools[currentTool] then -- any tool can damage stone (THIS IS LINE 495)
                tile.health = tile.health - 1
                World.addModifiedTile(tile)
            end
        end
        if tile.health <= 0 then
            local tileKey = string.format("%d,%d,%d", tile.q, tile.r, tile.z)
            World.removeModifiedTile(tile)
            -- get tile center for spawning resources
            local Collision = require('collision')
            local hexX, hexY = Collision.axialToPixel(tile.q, tile.r)
            --- spawn 1-5 stone
            local dropCount = math.random(1, 5)
            Items.spawnDroppedItems(Items.Stone, dropCount, hexX, hexY, tile.z)
            World.tiles[tileKey] = nil
            World.whereWalls()
        end
    end
----------------------------------------------------------------------------------
--  HANDLE GRASS  ----------------------------------------------------------------
----------------------------------------------------------------------------------
    if tile.type.name == "grass" then
        if tile.type.correctTool[currentTool] then
            if currentTool == "Hoe" then
                World.createTile(tile.q, tile.r, tile.z, Tiles.TileType.DIRT)
            end
            if currentTool == "Shovel" then
                tile.health = tile.health - 25
                World.addModifiedTile(tile)
            end
        else
            if Settings.tools[currentTool] then -- any tool can damage
                tile.health = tile.health - 1
                World.addModifiedTile(tile)
            end
        end
        if tile.health <= 0 then
            local tileKey = string.format("%d,%d,%d", tile.q, tile.r, tile.z)
            World.removeModifiedTile(tile)
            -- get tile center for spawning resources
            --local Collision = require('collision')
            --local hexX, hexY = Collision.axialToPixel(tile.q, tile.r)
            ----- spawn 1-5 dirt (NEEDS IMPLEMENTED)
            --local dropCount = math.random(1, 5)
            --Items.spawnDroppedItems(Items.Stone, dropCount, hexX, hexY, tile.z)
            World.tiles[tileKey] = nil
            World.whereWalls()
        end
    end
----------------------------------------------------------------------------------
--  HANDLE DIRT  ----------------------------------------------------------------
----------------------------------------------------------------------------------
    if tile.type.name == "dirt" then
        if tile.type.correctTool[currentTool] then
            if currentTool == "Hoe" then
                World.createTile(tile.q, tile.r, tile.z, Tiles.TileType.DRY_FARMLAND)
            end
        else
            if Settings.tools[currentTool] then -- any tool can damage except hoe
                tile.health = tile.health - 1
                World.addModifiedTile(tile)
            end
        end
        if tile.health <= 0 then
            local tileKey = string.format("%d,%d,%d", tile.q, tile.r, tile.z)
            World.removeModifiedTile(tile)
            -- get tile center for spawning resources
            --local Collision = require('collision')
            --local hexX, hexY = Collision.axialToPixel(tile.q, tile.r)
            ----- spawn 1-5 dirt (NEEDS IMPLEMENTED)
            --local dropCount = math.random(1, 5)
            --Items.spawnDroppedItems(Items.Stone, dropCount, hexX, hexY, tile.z)
            World.tiles[tileKey] = nil
            World.whereWalls()
        end
    end
----------------------------------------------------------------------------------
--  HANDLE FARMLAND  ----------------------------------------------------------------
----------------------------------------------------------------------------------
    if tile.type.name == "dry_farmland" or tile.type.name == "wet_farmland" then
        if tile.type.correctTool[currentTool] then
            if currentTool == "Hoe" then
            end
        else
            if Settings.tools[currentTool] then -- any tool can damage except hoe
                tile.health = tile.health - 1
                World.addModifiedTile(tile)
            end
        end
        if tile.health <= (tile.type.maxHealth * .75) then
            local tileKey = string.format("%d,%d,%d", tile.q, tile.r, tile.z)
            World.removeModifiedTile(tile)
            World.createTile(tile.q, tile.r, tile.z, Tiles.TileType.DIRT)
        end
    end
end

return Player
--- "player.lua" ends here ---