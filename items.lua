--- "items.lua" begins here ---
local Settings = require('settings')
local Collision = require('collision')

local Items = {} --- this is the module itself
local Item = {} --- this is the item class
local DroppedItem = {} --- this is the dropped item class
Item.__index = Item
DroppedItem.__index = DroppedItem
-- List of dropped items in world
Items.droppedItems = {}

function Item:new(name, imagePath, stack)
    local self = setmetatable({}, Item)
    self.name = name or "Unnamed Item"
    self.imagePath = imagePath
    self.image = love.graphics.newImage(imagePath)
    self.width = self.image:getWidth()
    self.height = self.image:getHeight()
    self.stackSize = stack
    return self
end

function Item:draw(x, y, scale)
    scale = scale or 1
    love.graphics.draw(self.image, x, y, 0, scale, scale)
end

function Item:getName()
    return self.name
end

-- Define specific Items
Items.Fist = Item:new(
    "Fist",
    "images/fist.png",
    nil
)
Items.Pickaxe = Item:new(
    "Pickaxe",
    "images/pickaxe.png",
    nil
)
Items.Stone = Item:new(
    "Stone",
    "images/stone_item.png",
    999
)
Items.Hoe = Item:new(
    "Hoe",
    "images/hoe.png",
    nil
)
Items.Shovel = Item:new(
    "Shovel",
    "images/shovel.png",
    nil
)

function DroppedItem:new(item, worldX, worldY, zLayer)
    local self = setmetatable({}, DroppedItem)
    self.item = item
    -- position
    self.x = worldX - Settings.hexSize / 8
    self.y = worldY - Settings.hexSize / 8
    self.zLayer = zLayer
    -- visual properties
    self.size = Settings.hexSize / 2
    self.rotation = math.random() * math.pi * 2 -- starting rotation
    -- starting direction
    local angle = math.random() * math.pi * 2
    local speed = 100 + math.random() * 100 -- random speed between 100-200
    self.velocityX = math.cos(angle) * speed
    self.velocityY = math.sin(angle) * speed
    self.velocityZ = 150 + math.random() * 50
    -- gravity and friction
    self.gravity = 500
    self.friction = 0.95
    self.bounceDamping = 0.6
    self.groundHeight = 0
    self.currentZ = 0
    -- states
    self.isGrounded = false
    self.bounceCount = 0
    self.maxBounces = 5
    return self
end

function DroppedItem:update(dt, world)
    if self.isGrounded then
        return
    end
    
    --- apply gravity
    self.velocityZ = self.velocityZ - self.gravity * dt
    --- update height
    self.currentZ = self.currentZ + self.velocityZ * dt
    --- update horizontal
    self.x = self.x + self.velocityX * dt
    self.y = self.y + self.velocityY * dt
    --- apply friction (that's what she said)
    self.velocityX = self.velocityX * self.friction
    self.velocityY = self.velocityY * self.friction
    --- check if hit ground
    if self.currentZ <= self.groundHeight then
        --- Check if in water ---
        local _, _, waterTiles = Collision.checkCollision(self, world)
        if waterTiles and #waterTiles > 0 then
            -- Item sinks/despawns in water
            self.isGrounded = true
            self.velocityX = 0
            self.velocityY = 0
            self.velocityZ = 0
            self.shouldRemove = true
            return
        end
        self.currentZ = self.groundHeight
        self.bounceCount = self.bounceCount + 1
        if self.bounceCount >= self.maxBounces or math.abs(self.velocityZ) < 50 then
            --- stop bouncing
            self.isGrounded = true
            self.velocityX = 0
            self.velocityY = 0
            self.velocityZ = 0
        else
            --- bounce
            self.velocityZ = -self.velocityZ * self.bounceDamping
            self.velocityX = self.velocityX * self.bounceDamping
            self.velocityY = self.velocityY * self.bounceDamping
        end
    end
    --- collision with solid tiles
    local colliding, collisions = Collision.checkCollision(self, world)
    
    if colliding then
        -- store old position
        local oldX = self.x
        local oldY = self.y
        Collision.resolveCollision(self, collisions)
        -- Calculate the push direction (normal of collision)
        local pushX = self.x - oldX
        local pushY = self.y - oldY
        local pushDist = math.sqrt(pushX * pushX + pushY * pushY)
        if pushDist > 0 then
            -- normalize push direction
            pushX = pushX / pushDist
            pushY = pushY / pushDist
            -- Reflect velocity around the collision normal
            local dotProduct = self.velocityX * pushX + self.velocityY * pushY
            self.velocityX = self.velocityX - 2 * dotProduct * pushX
            self.velocityY = self.velocityY - 2 * dotProduct * pushY
            -- Dampen after bounce
            self.velocityX = self.velocityX * 0.7
            self.velocityY = self.velocityY * 0.7
        end
    end
end

function DroppedItem:draw()
    -- Calculate center from top-left position
    local centerX = self.x + self.size / 2
    local centerY = self.y + self.size / 2
    -- Draw shadow (gets smaller as item goes higher)
    if not self.isGrounded then
        local shadowScale = math.max(0.2, .65 - (self.currentZ / 100))
        love.graphics.setColor(0, 0, 0, 0.3 * shadowScale)
        love.graphics.circle("fill", centerX, centerY + 5, self.size / 2 * shadowScale)
        love.graphics.setColor(1, 1, 1, 1)
    end
    -- Draw item (offset by height)
    local drawY = centerY - self.currentZ
    local scale = self.size / self.item.image:getWidth()
    love.graphics.draw(
        self.item.image,
        centerX,
        drawY,
        self.rotation,
        scale,
        scale,
        self.item.image:getWidth() / 2,
        self.item.image:getHeight() / 2
    )
end

-- Spawn multiple dropped items at a location
function Items.spawnDroppedItems(item, count, worldX, worldY, zLayer)
    for i = 1, count do
        local droppedItem = DroppedItem:new(item, worldX, worldY, zLayer)
        table.insert(Items.droppedItems, droppedItem)
    end
end

-- Update all dropped items
function Items.updateDroppedItems(dt, World)
    -- Update in reverse order so we can safely remove items
    for i = #Items.droppedItems, 1, -1 do
        local droppedItem = Items.droppedItems[i]
        droppedItem:update(dt, World)
        
        -- Remove if marked for deletion
        if droppedItem.shouldRemove then
            table.remove(Items.droppedItems, i)
        end
    end
end

-- Draw all dropped items
function Items.drawDroppedItems()
    for i, droppedItem in ipairs(Items.droppedItems) do
        droppedItem:draw()
    end
end

return Items
--- "Items.lua" ends here ---