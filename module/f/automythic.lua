local AutoFishV3 = {}
AutoFishV3.__index = AutoFishV3

local logger = _G.Logger and _G.Logger.new("AutoFishV3") or {
    debug = function() end,
    info = function() end,
    warn = function() end,
    error = function() end
}

local InventoryWatcher = _G.InventoryWatcher or loadstring(game:HttpGet("https://raw.githubusercontent.com/hakutakaid/a/refs/heads/main/utils/fishit/inventdetect.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local Replion = require(ReplicatedStorage.Packages.Replion)
local PlayerStatsUtility = require(ReplicatedStorage.Shared.PlayerStatsUtility)
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)
local Data = nil

local NetPath = nil
local EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted, FishObtainedNotification, ReplicateTextEffect, CancelFishingInputs, EquipItem, EquipBait

local function initializeRemotes()
    local success = pcall(function()
        NetPath = ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)

        EquipTool = NetPath:WaitForChild("RE/EquipToolFromHotbar", 5)
        ChargeFishingRod = NetPath:WaitForChild("RF/ChargeFishingRod", 5)
        RequestFishing = NetPath:WaitForChild("RF/RequestFishingMinigameStarted", 5)
        FishingCompleted = NetPath:WaitForChild("RE/FishingCompleted", 5)
        FishObtainedNotification = NetPath:WaitForChild("RE/ObtainedNewFishNotification", 5)
        ReplicateTextEffect = NetPath:WaitForChild("RE/ReplicateTextEffect", 5)
        CancelFishingInputs = NetPath:WaitForChild("RF/CancelFishingInputs", 5)
        EquipItem = NetPath:WaitForChild("RE/EquipItem", 5)
        EquipBait = NetPath:WaitForChild("RE/EquipBait", 5)

        return true
    end)

    return success
end

local isRunning = false
local connection = nil
local fishObtainedConnection = nil
local textEffectConnection = nil
local spamConnection = nil
local controls = {}
local fishingInProgress = false
local waitingForTextEffect = false
local spamActive = false
local fishCaughtFlag = false
local lastFishTime = 0
local remotesInitialized = false
local inventoryWatcher = nil
local starterRodUUID = nil 
local switchingEquipment = false 

local rareStreak = 0
local targetRareStreak = 3
local currentPhase = "INITIAL"
local originalRod = nil
local HotbarCache = { slot1 = nil, equippedUuid = nil }
local dataConnection1 = nil
local dataConnection2 = nil

local FISH_COLORS = {
    Uncommon = {
        r = 0.76470589637756,
        g = 1,
        b = 0.33333334326744
    },
    Rare = {
        r = 0.33333334326744,
        g = 0.63529413938522,
        b = 1
    },
    Legendary = {
        r = 1,
        g = 0.72156864404678,
        b = 0.16470588743687
    },
    Mythic = {
        r = 1,
        g = 0.094117648899555,
        b = 0.094117648899555
    }
}

local FAST_CONFIG = {
    chargeTime = 1.0,
    waitBetween = 0,
    rodSlot = 1, 
    spamDelay = 0.05,
    maxSpamTime = 30,
    textEffectTimeout = 10
}

function AutoFishV3:Init(guiControls)
    controls = guiControls or {}
    remotesInitialized = initializeRemotes()

    if not remotesInitialized then
        return false
    end

    local success = pcall(function()
        Data = Replion.Client:WaitReplion("Data")
    end)

    if not success or not Data then
        return false
    end

    inventoryWatcher = InventoryWatcher.new()

    inventoryWatcher:onReady(function()
        self:SetupOriginalRodCache() 
    end)

    return true
end

-- Dihapus: FindStarterRod

function AutoFishV3:SetupOriginalRodCache()
    if not Data then
        return
    end

    local function resolveItem(uuid)
        if not uuid or uuid == "" then return nil end
        local invItem = PlayerStatsUtility:GetItemFromInventory(Data, function(it)
            return (it.UUID == uuid)
        end)
        if not invItem then return nil end
        local itemData = ItemUtility:GetItemData(invItem.Id)
        local kind = itemData and itemData.Data and itemData.Data.Type
        return { uuid = uuid, id = invItem.Id, type = kind }
    end

    local equipped = Data:GetExpect("EquippedItems") or {}
    local slot1Uuid = equipped[1]
    HotbarCache.slot1 = resolveItem(slot1Uuid)

    HotbarCache.equippedUuid = Data:GetExpect("EquippedId")

    if HotbarCache.slot1 and HotbarCache.slot1.type ~= "Fishing Rods" then
        HotbarCache.slot1 = nil
    end

    if HotbarCache.slot1 then
        originalRod = { 
            uuid = HotbarCache.slot1.uuid,
            category = "Fishing Rods"
        }
    end

    dataConnection1 = Data:OnChange("EquippedItems", function(newArr)
        local newUuid = (typeof(newArr)=="table" and newArr[1]) or nil
        HotbarCache.slot1 = resolveItem(newUuid)
        if HotbarCache.slot1 and HotbarCache.slot1.type ~= "Fishing Rods" then
            HotbarCache.slot1 = nil
        end

        if HotbarCache.slot1 and not originalRod then
            originalRod = {
                uuid = HotbarCache.slot1.uuid,
                category = "Fishing Rods"
            }
        end
    end)

    dataConnection2 = Data:OnChange("EquippedId", function(uuid)
        HotbarCache.equippedUuid = (uuid ~= "" and uuid) or nil
    end)
end

function AutoFishV3:CacheOriginalEquipment()
    if not originalRod then
        return false
    end
    
    return true
end

-- Dihapus: TeleportToFishingSpot

function AutoFishV3:EquipMidnightBait()
    if not EquipBait then
        return false
    end

    local success = pcall(function()
        EquipBait:FireServer(3)
    end)

    return success
end

-- Dihapus: EquipStarterRod, SwitchToStarterRodSetup, RestoreOriginalEquipment

function AutoFishV3:Start(config)
    if isRunning then return end

    if not remotesInitialized then
        return
    end

    if not self:CacheOriginalEquipment() then
        return
    end

    -- Dihapus: Teleportation check/execution

    self:EquipMidnightBait()
    task.wait(0.1)

    currentPhase = "INITIAL"
    rareStreak = 0
    switchingEquipment = false 

    isRunning = true
    fishingInProgress = false
    waitingForTextEffect = false
    spamActive = false
    fishCaughtFlag = false
    lastFishTime = 0

    self:SetupTextEffectListener()
    self:SetupFishObtainedListener()

    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:FishingLoop()
    end)
end

function AutoFishV3:Stop()
    if not isRunning then return end

    isRunning = false
    fishingInProgress = false
    waitingForTextEffect = false
    spamActive = false
    fishCaughtFlag = false
    switchingEquipment = false

    if connection then
        connection:Disconnect()
        connection = nil
    end

    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
        fishObtainedConnection = nil
    end

    if textEffectConnection then
        textEffectConnection:Disconnect()
        textEffectConnection = nil
    end

    if spamConnection then
        spamConnection:Disconnect()
        spamConnection = nil
    end
end

function AutoFishV3:SetupTextEffectListener()
    if not ReplicateTextEffect then
        return
    end

    if textEffectConnection then
        textEffectConnection:Disconnect()
    end

    textEffectConnection = ReplicateTextEffect.OnClientEvent:Connect(function(data)
        if not isRunning or not waitingForTextEffect then return end

        self:HandleTextEffect(data)
    end)
end

function AutoFishV3:SetupFishObtainedListener()
    if not FishObtainedNotification then
        return
    end

    if fishObtainedConnection then
        fishObtainedConnection:Disconnect()
    end

    fishObtainedConnection = FishObtainedNotification.OnClientEvent:Connect(function(...)
        if isRunning then
            fishCaughtFlag = true

            if spamActive then
                spamActive = false
            end

            -- Logika transisi fase dipertahankan, tapi tindakan 'restore equipment' dihapus/diganti
            if currentPhase == "WAITING_FOR_MYTHIC_SECRET" then
                spawn(function()
                    task.wait(1.0)
                    while fishingInProgress or waitingForTextEffect or spamActive do
                        task.wait(0.1)
                    end
                    -- Tidak ada restore equipment, langsung kembali ke fase awal
                    currentPhase = "INITIAL"
                    rareStreak = 0
                    switchingEquipment = false 
                end)
            end

            spawn(function()
                task.wait(0.1)
                fishingInProgress = false
                waitingForTextEffect = false
                fishCaughtFlag = false
            end)
        end
    end)
end

function AutoFishV3:HandleTextEffect(data)
    if not data or not data.TextData then return end

    if not LocalPlayer.Character or not LocalPlayer.Character.Head then return end
    if data.TextData.AttachTo ~= LocalPlayer.Character.Head then return end

    local textColor = data.TextData.TextColor
    if not textColor or not textColor.Keypoints then return end

    local keypoint = textColor.Keypoints[1]
    if not keypoint then return end

    local color = keypoint.Value
    local rarity = self:GetFishRarity(color)

    if currentPhase == "INITIAL" then
        self:HandleInitialPhase(rarity)
    elseif currentPhase == "WAITING_FOR_MYTHIC_SECRET" then
        self:HandleMythicSecretPhase(rarity)
    end

    waitingForTextEffect = false
end

function AutoFishV3:HandleInitialPhase(rarity)
    if rarity == "Rare" then
        rareStreak = rareStreak + 1
        self:CancelFishing()

        if rareStreak >= targetRareStreak then
            -- Alih-alih switch rod, langsung pindah fase
            currentPhase = "WAITING_FOR_MYTHIC_SECRET"
        end
    else
        if rareStreak > 0 then
            rareStreak = 0
        end
        self:StartCompletionSpam()
    end
end

function AutoFishV3:HandleMythicSecretPhase(rarity)
    if rarity == "Mythic" or rarity == "Secret" then
        self:StartCompletionSpam()
    elseif rarity == "Legendary" or rarity == "Rare" then
        self:CancelFishing()
    else
        self:StartCompletionSpam()
    end
end

function AutoFishV3:GetFishRarity(color)
    local threshold = 0.01

    for rarity, rarityColor in pairs(FISH_COLORS) do
        if math.abs(color.R - rarityColor.r) < threshold and
           math.abs(color.G - rarityColor.g) < threshold and
           math.abs(color.B - rarityColor.b) < threshold then
            return rarity
        end
    end

    return nil
end

function AutoFishV3:CancelFishing()
    if not CancelFishingInputs then
        return
    end

    local success = pcall(function()
        CancelFishingInputs:InvokeServer()
    end)

    spawn(function()
        task.wait(0.5)
        fishingInProgress = false
        waitingForTextEffect = false
    end)
end

function AutoFishV3:FishingLoop()
    if switchingEquipment or fishingInProgress or waitingForTextEffect or spamActive then
        return
    end

    local currentTime = tick()

    if currentTime - lastFishTime < FAST_CONFIG.waitBetween then
        return
    end

    fishingInProgress = true
    lastFishTime = currentTime

    spawn(function()
        local success = self:ExecuteFishingSequence()
        if not success then
            fishingInProgress = false
        end
    end)
end

function AutoFishV3:ExecuteFishingSequence()
    -- Dihapus: EquipRod, as rod is assumed to be equipped
    
    task.wait(0.1)

    if not self:ChargeRod(FAST_CONFIG.chargeTime) then
        return false
    end

    if not self:CastRod() then
        return false
    end

    waitingForTextEffect = true

    spawn(function()
        task.wait(FAST_CONFIG.textEffectTimeout)
        if waitingForTextEffect then
            waitingForTextEffect = false
            self:StartCompletionSpam()
        end
    end)

    return true
end

function AutoFishV3:StartCompletionSpam()
    if spamActive then return end

    spamActive = true
    fishCaughtFlag = false
    local spamStartTime = tick()

    spawn(function()
        while spamActive and isRunning and (tick() - spamStartTime) < FAST_CONFIG.maxSpamTime do
            self:FireCompletion()

            if fishCaughtFlag then
                break
            end

            task.wait(FAST_CONFIG.spamDelay)
        end

        spamActive = false

        if (tick() - spamStartTime) >= FAST_CONFIG.maxSpamTime then
            fishingInProgress = false
        end
    end)
end

-- Dihapus: EquipRod (fungsi)

function AutoFishV3:ChargeRod(chargeTime)
    if not ChargeFishingRod then return false end

    local success = pcall(function()
        local chargeValue = tick() + (chargeTime * 1000)
        return ChargeFishingRod:InvokeServer(chargeValue)
    end)

    return success
end

function AutoFishV3:CastRod()
    if not RequestFishing then return false end

    local success = pcall(function()
        local x = -1.233184814453125
        local z = 0.9999120558411321
        return RequestFishing:InvokeServer(x, z)
    end)

    return success
end

function AutoFishV3:FireCompletion()
    if not FishingCompleted then return false end

    local success = pcall(function()
        FishingCompleted:FireServer()
    end)

    return success
end

function AutoFishV3:GetStatus()
    return {
        running = isRunning,
        inProgress = fishingInProgress,
        waitingForEffect = waitingForTextEffect,
        spamming = spamActive,
        switchingEquipment = switchingEquipment,
        lastCatch = lastFishTime,
        fishCaughtFlag = fishCaughtFlag,
        remotesReady = remotesInitialized,
        textEffectListenerReady = textEffectConnection ~= nil,
        fishObtainedListenerReady = fishObtainedConnection ~= nil,
        inventoryReady = inventoryWatcher ~= nil,
        starterRodFound = starterRodUUID ~= nil, 
        currentPhase = currentPhase,
        rareStreak = rareStreak,
        targetRareStreak = targetRareStreak,
        originalEquipmentCached = originalRod ~= nil
    }
end

function AutoFishV3:Cleanup()
    self:Stop()

    if dataConnection1 then
        dataConnection1:Disconnect()
        dataConnection1 = nil
    end
    if dataConnection2 then
        dataConnection2:Disconnect()
        dataConnection2 = nil
    end

    if inventoryWatcher then
        inventoryWatcher:destroy()
        inventoryWatcher = nil
    end
    controls = {}
    remotesInitialized = false
    starterRodUUID = nil
    originalRod = nil
    rareStreak = 0
    currentPhase = "INITIAL"
    switchingEquipment = false
    HotbarCache = { slot1 = nil, equippedUuid = nil }
    Data = nil
end

return AutoFishV3
