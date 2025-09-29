-- ===========================
-- AUTO FISH V3 - LIGHTWEIGHT RARE DETECTION
-- File: autofishv3_light.lua
-- ===========================

local AutoFishV3 = {}
AutoFishV3.__index = AutoFishV3

local logger = _G.Logger and _G.Logger.new("AutoFishV3") or {
    info=function(...) print(...) end,
    warn=function(...) print("WARN:", ...) end
}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Network remotes (user harus pastikan ini ada)
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, ReplicateTextEffect, CancelFishingInputs

-- Feature state
local isRunning = false
local fishingInProgress = false
local waitingForTextEffect = false
local spamActive = false
local fishCaughtFlag = false
local lastFishTime = 0
local connection, fishObtainedConnection, textEffectConnection

local currentPhase = "INITIAL"
local rareStreak = 0
local targetRareStreak = 3

local FAST_CONFIG = {
    chargeTime = 1.0,
    waitBetween = 0,
    spamDelay = 0.05,
    maxSpamTime = 30,
    textEffectTimeout = 10
}

local FISH_COLORS = {
    Uncommon = {r=0.7647,g=1,b=0.3333},
    Rare = {r=0.3333,g=0.6352,b=1},
    Legendary = {r=1,g=0.7215,b=0.1647},
    Mythic = {r=1,g=0.0941,b=0.0941}
}

-- ===== Initialize remotes =====
function AutoFishV3:Init(remotes)
    EquipTool = remotes.EquipTool
    ChargeFishingRod = remotes.ChargeFishingRod
    RequestFishing = remotes.RequestFishing
    FishingCompleted = remotes.FishingCompleted
    FishObtainedNotification = remotes.FishObtainedNotification
    ReplicateTextEffect = remotes.ReplicateTextEffect
    CancelFishingInputs = remotes.CancelFishingInputs

    logger:info("AutoFish V3 Lightweight Initialized")
end

-- ===== Start / Stop =====
function AutoFishV3:Start()
    if isRunning then return end
    isRunning = true
    fishingInProgress = false
    waitingForTextEffect = false
    spamActive = false
    fishCaughtFlag = false
    lastFishTime = 0
    currentPhase = "INITIAL"
    rareStreak = 0

    self:SetupTextEffectListener()
    self:SetupFishObtainedListener()

    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:FishingLoop()
    end)

    logger:info("AutoFish started")
end

function AutoFishV3:Stop()
    if not isRunning then return end
    isRunning = false
    fishingInProgress = false
    waitingForTextEffect = false
    spamActive = false
    fishCaughtFlag = false

    if connection then connection:Disconnect() connection=nil end
    if fishObtainedConnection then fishObtainedConnection:Disconnect() fishObtainedConnection=nil end
    if textEffectConnection then textEffectConnection:Disconnect() textEffectConnection=nil end

    logger:info("AutoFish stopped")
end

-- ===== Listeners =====
function AutoFishV3:SetupTextEffectListener()
    if not ReplicateTextEffect then return end
    if textEffectConnection then textEffectConnection:Disconnect() end

    textEffectConnection = ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not isRunning or not waitingForTextEffect then return end
        self:HandleTextEffect(data)
    end)
end

function AutoFishV3:SetupFishObtainedListener()
    if not FishObtainedNotification then return end
    if fishObtainedConnection then fishObtainedConnection:Disconnect() end

    fishObtainedConnection = FishObtainedNotification.OnClientEvent:Connect(function()
        if isRunning then
            fishCaughtFlag = true
            spamActive = false
            fishingInProgress = false
            waitingForTextEffect = false
            logger:info("Fish caught notification")
        end
    end)
end

-- ===== Handle text effect =====
function AutoFishV3:HandleTextEffect(data)
    if not data or not data.TextData then return end
    if not LocalPlayer.Character or not LocalPlayer.Character.Head then return end
    if data.TextData.AttachTo ~= LocalPlayer.Character.Head then return end

    local key = data.TextData.TextColor.Keypoints and data.TextData.TextColor.Keypoints[1]
    if not key then return end

    local rarity = self:GetFishRarity(key.Value)

    if currentPhase == "INITIAL" then
        self:HandleInitialPhase(rarity)
    elseif currentPhase == "WAITING_FOR_MYTHIC_SECRET" then
        self:HandleMythicSecretPhase(rarity)
    end

    waitingForTextEffect = false
end

-- ===== Phase handlers =====
function AutoFishV3:HandleInitialPhase(rarity)
    if rarity == "Rare" then
        rareStreak = rareStreak +1
        logger:info("Rare detected! Streak:", rareStreak, "/", targetRareStreak)
        self:CancelFishing()
        if rareStreak >= targetRareStreak then
            currentPhase = "WAITING_FOR_MYTHIC_SECRET"
            logger:info("Phase -> WAITING_FOR_MYTHIC_SECRET")
        end
    else
        rareStreak = 0
        self:StartCompletionSpam()
    end
end

function AutoFishV3:HandleMythicSecretPhase(rarity)
    if rarity=="Mythic" or rarity=="Secret" then
        logger:info(rarity, "detected -> spamming completion")
        self:StartCompletionSpam()
    else
        self:CancelFishing()
    end
end

-- ===== Utility =====
function AutoFishV3:GetFishRarity(color)
    local t = 0.01
    for rarity, c in pairs(FISH_COLORS) do
        if math.abs(color.R-c.r)<t and math.abs(color.G-c.g)<t and math.abs(color.B-c.b)<t then
            return rarity
        end
    end
    return nil
end

function AutoFishV3:CancelFishing()
    if CancelFishingInputs then pcall(CancelFishingInputs.InvokeServer, CancelFishingInputs) end
    fishingInProgress=false
    waitingForTextEffect=false
end

-- ===== Fishing loop =====
function AutoFishV3:FishingLoop()
    if fishingInProgress or waitingForTextEffect or spamActive then return end
    local now = tick()
    if now-lastFishTime < FAST_CONFIG.waitBetween then return end

    fishingInProgress=true
    lastFishTime=now

    spawn(function() self:ExecuteFishingSequence() end)
end

function AutoFishV3:ExecuteFishingSequence()
    if not (EquipTool and ChargeFishingRod and RequestFishing) then return false end
    pcall(EquipTool.FireServer, EquipTool, 1) -- slot 1 default
    task.wait(0.1)
    pcall(ChargeFishingRod.InvokeServer, ChargeFishingRod, tick()+FAST_CONFIG.chargeTime*1000)
    task.wait(0.1)
    pcall(RequestFishing.InvokeServer, RequestFishing, -1.233, 0.9999)

    waitingForTextEffect=true
    spawn(function()
        task.wait(FAST_CONFIG.textEffectTimeout)
        if waitingForTextEffect then
            waitingForTextEffect=false
            self:StartCompletionSpam()
        end
    end)

    return true
end

function AutoFishV3:StartCompletionSpam()
    if spamActive then return end
    spamActive=true
    fishCaughtFlag=false
    local startTime=tick()

    spawn(function()
        while spamActive and isRunning and (tick()-startTime)<FAST_CONFIG.maxSpamTime do
            if FishingCompleted then pcall(FishingCompleted.FireServer, FishingCompleted) end
            if fishCaughtFlag then break end
            task.wait(FAST_CONFIG.spamDelay)
        end
        spamActive=false
        fishingInProgress=false
    end)
end

function AutoFishV3:GetStatus()
    return {
        running=isRunning,
        inProgress=fishingInProgress,
        waiting=waitingForTextEffect,
        spamming=spamActive,
        lastCatch=lastFishTime,
        fishCaughtFlag=fishCaughtFlag,
        currentPhase=currentPhase,
        rareStreak=rareStreak,
        targetRareStreak=targetRareStreak
    }
end

return AutoFishV3