--- "time.lua" begins here ---
local Settings = require('settings')

local Time = {}

function Time:new()
    local obj = {
        -- Real-time constants (in seconds)
        dayLength = Settings.dayLength,
        nightLength = Settings.nightLength,
        fullDayLength = Settings.fullDayLength,
        -- Game time tracking
        gameMinute = Settings.gameMinute,-- 0-59
        gameHour = Settings.gameHour,-- 0-23
        gameDay = Settings.gameDay,-- 1-12(depends on month)
        gameMonth = Settings.gameMonth,-- 1-12
        gameYear = Settings.gameYear,
        -- Internal timer
        timer = 0,
        -- Lunar cycle tracking
        moonPhase = 0,      -- 1-8
        moonPhases = {
            "moon_01_full",
            "moon_02_waning_full",
            "moon_03_half_full",
            "moon_04_waning_new",
            "moon_05_new",
            "moon_06_waxing_new",
            "moon_07_half_new",
            "moon_08_waxing_full"
        },
        lastMoonAdvanced = false,  -- Track if we've advanced moon phase today
        -- Month definitions
        months = {
            {name = "Sapphire", days = 8, season = "Stoneviel"},
            {name = "Silver", days = 9, season = "Stoneviel"},
            {name = "Mithril", days = 11, season = "Ironsong"},
            {name = "Jade", days = 9, season = "Ironsong"},
            {name = "Emerald", days = 10, season = "Ironsong"},
            {name = "Sunstone", days = 11, season = "Hammerheight"},
            {name = "Ruby", days = 12, season = "Hammerheight"},
            {name = "Iron", days = 10, season = "Hammerheight"},
            {name = "Copper", days = 10, season = "Brightforge"},
            {name = "Gold", days = 11, season = "Brightforge"},
            {name = "Sandstone", days = 9, season = "Brightforge"},
            {name = "Diamond", days = 9, season = "Stoneviel"}
        },
        -- Day/night/twilight state
        isDay = true,
        isTwilight = false,
        -- Night overlay settings
        targetNightOpacity = Settings.maxnightOverlayOpacity,
        currentNightOpacity = 0.0,
        -- Image loading
        moonImages = {},
        sunImage = nil,
        guiBackground = nil,
        imageSize = 40,  -- Desired size for the celestial body images
        -- Audio tracking
        currentMusic = nil,  -- 'day' or 'night'
        musicFadingIn = false,
        musicFadingOut = false,
        fadeInStartTime = 0,
        fadeOutStartTime = 0,
        fadeInDuration = Settings.fadeInDuration,
        fadeOutDuration = Settings.fadeOutDuration,
        targetMusicVolume = Settings.musicVolume,
        -- Audio sources
        dayMusic = nil,
        nightMusic = nil,
        crowSound = nil,
        howlSound = nil
    }
    setmetatable(obj, self)
    self.__index = self
    -- Calculate initial night overlay opacity based on moon phase
    obj:calculateTargetNightOpacity()
    -- Set initial opacity based on current time
    obj:updateNightOpacity()
    -- Load images
    obj:loadImages()
    -- Load audio
    obj:loadAudio()
    return obj
end

function Time:calculateTargetNightOpacity()
    local minOpacity = Settings.minnightOverlayOpacity
    local maxOpacity = Settings.maxnightOverlayOpacity
    
    if self.moonPhase == 1 then
        self.targetNightOpacity = minOpacity
    elseif self.moonPhase == 2 or self.moonPhase == 8 then
        self.targetNightOpacity = minOpacity + (maxOpacity - minOpacity) * 0.25
    elseif self.moonPhase == 3 or self.moonPhase == 7 then
        self.targetNightOpacity = minOpacity + (maxOpacity - minOpacity) * 0.5
    elseif self.moonPhase == 4 or self.moonPhase == 6 then
        self.targetNightOpacity = minOpacity + (maxOpacity - minOpacity) * 0.75
    else
        self.targetNightOpacity = maxOpacity
    end
end

function Time:getTwilightProgress()
    -- Morning twilight: 4am (hour 4) - transitions from night to day
    -- Evening twilight: 8pm (hour 20) - transitions from day to night
    if self.gameHour == 4 then
        -- Morning twilight: 0.0 (full night) to 1.0 (full day)
        return self.gameMinute / 60.0
    elseif self.gameHour == 20 then
        -- Evening twilight: 0.0 (full day) to 1.0 (full night)
        return self.gameMinute / 60.0
    end
    return nil  -- Not twilight
end

function Time:updateNightOpacity()
    local twilightProgress = self:getTwilightProgress()
    if twilightProgress then
        -- We're in twilight
        self.isTwilight = true
        if self.gameHour == 4 then
            -- Morning: fade from night to day (targetNightOpacity -> 0)
            self.currentNightOpacity = self.targetNightOpacity * (1.0 - twilightProgress)
        else -- gameHour == 20
            -- Evening: fade from day to night (0 -> targetNightOpacity)
            self.currentNightOpacity = self.targetNightOpacity * twilightProgress
        end
    else
        self.isTwilight = false 
        -- Full day (5am-7pm): no overlay
        if self.gameHour >= 5 and self.gameHour < 20 then
            self.currentNightOpacity = 0.0
            self.isDay = true
        -- Full night (9pm-3am): full night overlay
        elseif self.gameHour >= 21 or self.gameHour < 4 then
            self.currentNightOpacity = self.targetNightOpacity
            self.isDay = false
        end
    end
end

function Time:loadImages()
    local imagePath = "images/"
    -- Load moon phase images
    for i, phaseName in ipairs(self.moonPhases) do
        local fullPath = imagePath .. phaseName .. ".png"
        local success, image = pcall(love.graphics.newImage, fullPath)
        if success then
            self.moonImages[i] = image
        end
    end
    -- Load sun image
    local sunPath = imagePath .. "sun.png"
    local success, image = pcall(love.graphics.newImage, sunPath)
    if success then
        self.sunImage = image
    end
    -- Load GUI background
    local guiPath = imagePath .. "gui.png"
    local success, image = pcall(love.graphics.newImage, guiPath)
    if success then
        self.guiBackground = image
    end
end

function Time:loadAudio()
    local soundPath = "sounds/"
    -- Load day music (looping)
    local dayMusicPath = soundPath .. "day_soundtrack.wav"
    local success, source = pcall(love.audio.newSource, dayMusicPath, "stream")
    if success then
        source:setLooping(true)
        self.dayMusic = source
    end
    -- Load night music (looping)
    local nightMusicPath = soundPath .. "night_soundtrack.wav"
    success, source = pcall(love.audio.newSource, nightMusicPath, "stream")
    if success then
        source:setLooping(true)
        self.nightMusic = source
    end
    -- Load crow sound effect
    local crowPath = soundPath .. "day_start_crow.wav"
    success, source = pcall(love.audio.newSource, crowPath, "static")
    if success then
        self.crowSound = source
    end
    -- Load howl sound effect
    local howlPath = soundPath .. "night_start_howl.wav"
    success, source = pcall(love.audio.newSource, howlPath, "static")
    if success then
        self.howlSound = source
    end
end

function Time:update(dt)
    self.timer = self.timer + dt
    -- Calculate how many real seconds = 1 game hour
    local secondsPerGameHour = self.fullDayLength / 24
    -- Calculate how many real seconds = 1 game minute
    local secondsPerGameMinute = secondsPerGameHour / 60
    -- Update game time
    if self.timer >= secondsPerGameMinute then
        self.timer = self.timer - secondsPerGameMinute
        self.gameMinute = self.gameMinute + 1   
        if self.gameMinute >= 60 then
            self.gameMinute = 0
            self.gameHour = self.gameHour + 1        
            if self.gameHour >= 24 then
                self.gameHour = 0
                self.gameDay = self.gameDay + 1            
                -- Check if we need to advance to next month
                local currentMonth = self.months[self.gameMonth]
                if self.gameDay > currentMonth.days then
                    self.gameDay = 1
                    self.gameMonth = self.gameMonth + 1                
                    if self.gameMonth > 12 then
                        self.gameMonth = 1
                        self.gameYear = self.gameYear + 1
                    end
                end
            end
        end    
        -- Update night overlay opacity every minute
        self:updateNightOpacity()   
        -- Handle music transitions and sound effects
        self:updateAudio()
    end 
    -- Update audio fading
    self:updateAudioFading(dt) 
    -- Advance moon phase at 7pm (before evening twilight starts at 8pm)
    if self.gameHour == 19 and not self.lastMoonAdvanced then
        self.moonPhase = self.moonPhase + 1
        if self.moonPhase > 8 then
            self.moonPhase = 1
        end
        self.lastMoonAdvanced = true     
        -- Recalculate target opacity for the new moon phase
        self:calculateTargetNightOpacity()
    end 
    -- Reset moon advancement flag during the day
    if self.gameHour >= 5 and self.gameHour < 19 then
        self.lastMoonAdvanced = false
    end
end

function Time:updateAudio()
    -- Initialize music if nothing is playing
    if self.currentMusic == nil then
        if self.isDay and self.dayMusic then
            self.dayMusic:setVolume(self.targetMusicVolume)
            self.dayMusic:play()
            self.currentMusic = 'day'
            self.fadeInStartTime = love.timer.getTime()
            self.musicFadingIn = true
        elseif not self.isDay and self.nightMusic then
            self.nightMusic:setVolume(self.targetMusicVolume)
            self.nightMusic:play()
            self.currentMusic = 'night'
            self.fadeInStartTime = love.timer.getTime()
            self.musicFadingIn = true
        end
    end  
    -- Start day at 5am - play crow and transition to day music
    if self.gameHour == 5 and self.gameMinute == 0 then
        if self.currentMusic ~= 'day' then
            -- Play crow sound
            if self.crowSound then
                self.crowSound:play()
            end           
            -- Start fading in day music
            if self.dayMusic then
                self.dayMusic:setVolume(0)
                self.dayMusic:play()
                self.fadeInStartTime = love.timer.getTime()
                self.musicFadingIn = true
                self.currentMusic = 'day'
            end
        end
    end   
    -- Start fade out of day music at 8pm (during evening twilight)
    if self.gameHour == 20 and self.gameMinute == 0 then
        if self.currentMusic == 'day' and self.dayMusic then
            self.fadeOutStartTime = love.timer.getTime()
            self.musicFadingOut = true
        end
    end   
    -- Start night at 9pm - play howl and transition to night music
    if self.gameHour == 21 and self.gameMinute == 0 then
        if self.currentMusic ~= 'night' then
            -- Play howl sound
            if self.howlSound then
                self.howlSound:play()
            end         
            -- Start fading in night music
            if self.nightMusic then
                self.nightMusic:setVolume(0)
                self.nightMusic:play()
                self.fadeInStartTime = love.timer.getTime()
                self.musicFadingIn = true
                self.currentMusic = 'night'
            end
        end
    end 
    -- Start fade out of night music at 4am (before morning twilight)
    if self.gameHour == 4 and self.gameMinute == 0 then
        if self.currentMusic == 'night' and self.nightMusic then
            self.fadeOutStartTime = love.timer.getTime()
            self.musicFadingOut = true
        end
    end
end

function Time:updateAudioFading(dt)
    local currentTime = love.timer.getTime() 
    -- Handle fade in
    if self.musicFadingIn then
        local elapsed = currentTime - self.fadeInStartTime     
        if elapsed >= self.fadeInDuration then
            -- Fade-in complete
            if self.currentMusic == 'day' and self.dayMusic then
                self.dayMusic:setVolume(self.targetMusicVolume)
            elseif self.currentMusic == 'night' and self.nightMusic then
                self.nightMusic:setVolume(self.targetMusicVolume)
            end
            self.musicFadingIn = false
        else
            -- Calculate progress (0.0 to 1.0)
            local progress = elapsed / self.fadeInDuration
            local volume = self.targetMusicVolume * progress
            
            if self.currentMusic == 'day' and self.dayMusic then
                self.dayMusic:setVolume(volume)
            elseif self.currentMusic == 'night' and self.nightMusic then
                self.nightMusic:setVolume(volume)
            end
        end
    end  
    -- Handle fade out
    if self.musicFadingOut then
        local elapsed = currentTime - self.fadeOutStartTime      
        if elapsed >= self.fadeOutDuration then
            -- Fade-out complete - stop the music
            if self.currentMusic == 'day' and self.dayMusic then
                self.dayMusic:stop()
            elseif self.currentMusic == 'night' and self.nightMusic then
                self.nightMusic:stop()
            end
            self.musicFadingOut = false
        else
            -- Calculate progress (1.0 to 0.0)
            local progress = 1.0 - (elapsed / self.fadeOutDuration)
            local volume = self.targetMusicVolume * progress
            
            if self.currentMusic == 'day' and self.dayMusic then
                self.dayMusic:setVolume(volume)
            elseif self.currentMusic == 'night' and self.nightMusic then
                self.nightMusic:setVolume(volume)
            end
        end
    end
end

function Time:getCurrentMonth()
    return self.months[self.gameMonth]
end

function Time:getCurrentSeason()
    return self.months[self.gameMonth].season
end

function Time:getCurrentMoonPhase()
    return self.moonPhases[self.moonPhase]
end

function Time:getOrdinalSuffix(day)
    -- Handle special cases for 11th, 12th, 13th
    if day >= 11 and day <= 13 then
        return "th"
    end  
    -- Get last digit
    local lastDigit = day % 10
    if lastDigit == 1 then
        return "st"
    elseif lastDigit == 2 then
        return "nd"
    elseif lastDigit == 3 then
        return "rd"
    else
        return "th"
    end
end

function Time:getTimeString()
    -- Format: HH:MM (24-hour format)
    return string.format("%02d:%02d", self.gameHour, self.gameMinute)
end

function Time:getDateString()
    local month = self.months[self.gameMonth]
    local suffix = self:getOrdinalSuffix(self.gameDay)
    return string.format("%d%s of %s, Year %d", self.gameDay, suffix, month.name, self.gameYear)
end

function Time:getDayPeriod()
    if self.isTwilight then
        if self.gameHour == 4 then
            return "Dawn"
        else
            return "Dusk"
        end
    elseif self.isDay then
        return "Day"
    else
        return "Night"
    end
end

function Time:drawNightOverlay(windowWidth, windowHeight)
    if self.currentNightOpacity > 0 then
        love.graphics.setColor(0, 0, 0, self.currentNightOpacity)
        love.graphics.rectangle("fill", 0, 0, windowWidth, windowHeight)
        love.graphics.setColor(1, 1, 1, 1)  -- Reset color
    end
end

function Time:draw(windowWidth, windowHeight)
    -- Ensure color is set to white before drawing text
    love.graphics.setColor(1, 1, 1, 1)  
    -- Create time display text
    local timeText = self:getTimeString()
    local dateText = self:getDateString()
    local seasonText = self:getCurrentSeason()  
    -- Font size
    local font = love.graphics.getFont()
    -- Position in top right corner with padding
    local padding = 10
    local lineHeight = font:getHeight()
    local textWidth = 150
    local x = windowWidth - padding - textWidth - self.imageSize - 10
    -- Calculate background dimensions
    local bgPadding = 8
    local bgWidth = textWidth + self.imageSize + 10 + (bgPadding * 2)
    local bgHeight = (lineHeight * 3) + (bgPadding * 2)
    local bgX = windowWidth - padding - bgWidth
    local bgY = padding - bgPadding
    -- Draw GUI background
    if self.guiBackground then
        local scaleX = bgWidth / self.guiBackground:getWidth()
        local scaleY = bgHeight / self.guiBackground:getHeight()
        love.graphics.draw(self.guiBackground, bgX, bgY, 0, scaleX, scaleY)
    end
-- Draw Hotbar background (bottom center)
    if self.guiBackground then
        local hotbarWidth = 600
        local hotbarHeight = 69
        local hotbarX = (windowWidth - hotbarWidth) / 2
        local hotbarY = windowHeight - hotbarHeight - 8  -- 8px buffer from bottom
        local scaleX = hotbarWidth / self.guiBackground:getWidth()
        local scaleY = hotbarHeight / self.guiBackground:getHeight()
        love.graphics.draw(self.guiBackground, hotbarX, hotbarY, 0, scaleX, scaleY)
    end
    -- Draw text with right alignment
    love.graphics.printf(timeText, x, padding, textWidth, "right")
    love.graphics.printf(dateText, x, padding + lineHeight, textWidth, "right")
    love.graphics.printf(seasonText, x, padding + lineHeight * 2, textWidth, "right")
    
    -- Draw celestial body (sun or moon) to the right of text
    local imageX = windowWidth - padding - self.imageSize - 5
    local imageY = padding
    
    if self.isDay then
        -- Draw sun during day
        if self.sunImage then
            local scaleX = self.imageSize / self.sunImage:getWidth()
            local scaleY = self.imageSize / self.sunImage:getHeight()
            love.graphics.draw(self.sunImage, imageX, imageY, 0, scaleX, scaleY)
        end
    else
        -- Draw current moon phase at night (and during twilight)
        local moonImage = self.moonImages[self.moonPhase]
        if moonImage then
            local scaleX = self.imageSize / moonImage:getWidth()
            local scaleY = self.imageSize / moonImage:getHeight()
            love.graphics.draw(moonImage, imageX, imageY, 0, scaleX, scaleY)
        end
    end
end

return Time
--- "time.lua" ends here ---