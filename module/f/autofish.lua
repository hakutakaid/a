local AutoFishFeature = {}
AutoFishFeature.__index = AutoFishFeature

local logger = _G.Logger and _G.Logger.new("AutoFish") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local NetPath, EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted
local animations = {}
local loadedAnimations = {}

local function initializeRemotesAndAnimations()
    local success = pcall(function()
        NetPath = ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)
        
        EquipTool = NetPath:WaitForChild("RE/EquipToolFromHotbar", 5)
        ChargeFishingRod = NetPath:WaitForChild("RF/ChargeFishingRod", 5)
        RequestFishing = NetPath:WaitForChild("RF/RequestFishingMinigameStarted", 5)
        FishingCompleted = NetPath:WaitForChild("RE/FishingCompleted", 5)
        
        animations = {
            Cast = Instance.new("Animation"),
            Catch = Instance.new("Animation"),
            Waiting = Instance.new("Animation"),
            -- ReelIn telah dihapus dari tabel
            HoldIdle = Instance.new("Animation")
        }
        
        animations.Cast.AnimationId = "rbxassetid://92624107165273"
        animations.Catch.AnimationId = "rbxassetid://117319000848286"
        animations.Waiting.AnimationId = "rbxassetid://134965425664034"
        -- animations.ReelIn.AnimationId = "rbxassetid://114959536562596" <-- Dihapus
        animations.HoldIdle.AnimationId = "rbxassetid://96586569072385"
        
        return true
    end)
    
    return success
end

local function loadAnimations()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Humanoid") then return false end
    
    local humanoid = LocalPlayer.Character.Humanoid
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator", humanoid)
    end
    
    table.clear(loadedAnimations)
    for name, anim in pairs(animations) do
        loadedAnimations[name] = animator:LoadAnimation(anim)
    end
    logger:info("Animations loaded successfully.")
    return true
end

local isRunning = false
local currentMode = "Fast"
local connection = nil
local fishingInProgress = false
local lastFishTime = 0
local remotesAndAnimsInitialized = false
local perfectCast = false

local FISHING_CONFIGS = {
    ["Fast"] = { waitBetween = 0.5, rodSlot = 1 },
    ["Slow"] = { waitBetween = 1.5, rodSlot = 1 }
}

function AutoFishFeature:Init(guiControls)
    remotesAndAnimsInitialized = initializeRemotesAndAnimations()
    
    if not remotesAndAnimsInitialized then
        logger:warn("Failed to initialize remotes or animations.")
        return false
    end
    
    if guiControls and guiControls.perfectCastToggle then
        perfectCast = guiControls.perfectCastToggle.Value
        guiControls.perfectCastToggle.Changed:Connect(function(val)
            perfectCast = val
        end)
    end
    
    logger:info("Initialized with ANIMATION method - Fast & Slow modes")
    return true
end

function AutoFishFeature:Start(config)
    if isRunning then return end
    if not remotesAndAnimsInitialized then
        logger:warn("Cannot start - remotes/animations not initialized.")
        return
    end
    
    isRunning = true
    currentMode = config.mode or "Fast"
    fishingInProgress = false
    lastFishTime = 0
    
    if not loadAnimations() then
        logger:warn("Failed to load animations on start. Character might not be ready.")
        self:Stop()
        return
    end
    
    LocalPlayer.CharacterAdded:Connect(function()
        if isRunning then
            task.wait(1)
            loadAnimations()
        end
    end)
    
    logger:info("Started ANIMATION method - Mode:", currentMode)
    
    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:AnimationFishingLoop()
    end)
end

function AutoFishFeature:Stop()
    if not isRunning then return end
    
    isRunning = false
    fishingInProgress = false
    
    for _, animTrack in pairs(loadedAnimations) do
        if animTrack.IsPlaying then
            animTrack:Stop()
        end
    end
    
    if connection then
        connection:Disconnect()
        connection = nil
    end
    
    logger:info("Stopped ANIMATION method")
end

function AutoFishFeature:AnimationFishingLoop()
    if fishingInProgress then return end
    
    local currentTime = tick()
    local config = FISHING_CONFIGS[currentMode]
    
    if currentTime - lastFishTime < config.waitBetween then
        return
    end
    
    fishingInProgress = true
    lastFishTime = currentTime
    
    spawn(function()
        local success = self:ExecuteAnimatedFishingSequence()
        fishingInProgress = false
        
        if success then
            logger:info("Animation cycle completed!")
        end
    end)
end

function AutoFishFeature:ExecuteAnimatedFishingSequence()
    local config = FISHING_CONFIGS[currentMode]
    
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Humanoid") then
        logger:warn("Character not found. Skipping cycle.")
        return false
    end

    local success = pcall(function()
        EquipTool:FireServer(config.rodSlot)
        if loadedAnimations.HoldIdle then loadedAnimations.HoldIdle:Play() end
        task.wait(0.2)
        
        if loadedAnimations.HoldIdle then loadedAnimations.HoldIdle:Stop() end
        
        -- Mainkan animasi Cast
        if loadedAnimations.Cast then 
            loadedAnimations.Cast:Play() 
        end
        
        ChargeFishingRod:InvokeServer(perfectCast and 9e9 or tick())
        
        -- Tunggu event animasi selesai, bukan menjeda paksa
        if loadedAnimations.Cast then 
            loadedAnimations.Cast.Ended:Wait() 
        end
        
        -- Lanjutkan sisa logika setelah animasi selesai
        if loadedAnimations.Waiting then loadedAnimations.Waiting:Play() end
        
        local x = perfectCast and -1.238 or math.random()
        local z = perfectCast and 0.969 or math.random()
        RequestFishing:InvokeServer(x, z)
        
        task.wait(1.3)
        
        if loadedAnimations.Waiting and loadedAnimations.Waiting.IsPlaying then loadedAnimations.Waiting:Stop() end
        
        -- [[ BARIS UNTUK ReelIn TELAH DIHAPUS DI SINI ]]
        -- if loadedAnimations.ReelIn then loadedAnimations.ReelIn:Play() end
        -- task.wait(0.2)
        -- if loadedAnimations.ReelIn and loadedAnimations.ReelIn.IsPlaying then loadedAnimations.ReelIn:Stop() end

        if loadedAnimations.Catch then loadedAnimations.Catch:Play() end
        
        for i = 1, 3 do
            if not isRunning then break end
            FishingCompleted:FireServer()
            task.wait(0.1)
        end
        
        if loadedAnimations.Catch then loadedAnimations.Catch.Stopped:Wait() end
    end)

    if not success then
        logger:error("An error occurred during the animated fishing sequence.")
        for _, animTrack in pairs(loadedAnimations) do
            if animTrack.IsPlaying then animTrack:Stop() end
        end
        task.wait(1)
    end
    
    return success
end

function AutoFishFeature:GetStatus()
    return {
        running = isRunning,
        mode = currentMode,
        inProgress = fishingInProgress,
        lastCatch = lastFishTime,
        remotesReady = remotesAndAnimsInitialized,
        perfectCast = perfectCast
    }
end

function AutoFishFeature:SetMode(mode)
    if FISHING_CONFIGS[mode] then
        currentMode = mode
        logger:info("Mode changed to:", mode)
        return true
    end
    return false
end

function AutoFishFeature:Cleanup()
    logger:info("Cleaning up ANIMATION method...")
    self:Stop()
    remotesAndAnimsInitialized = false
    table.clear(animations)
    table.clear(loadedAnimations)
end

return AutoFishFeature
