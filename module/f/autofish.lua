local AutoFishFeature = {}
AutoFishFeature.__index = AutoFishFeature

-- Logger yang ditingkatkan untuk lebih ringkas dan tetap aman
local logger = _G.Logger and _G.Logger.new("AutoFish") or {
    debug = function(...) end,
    info = function(...) print("[AutoFish INFO]", ...) end, -- Mengganti print untuk debugging tanpa Logger
    warn = function(...) print("[AutoFish WARN]", ...) end,
    error = function(...) print("[AutoFish ERROR]", ...) end
}

-- Panggil GetService sekali untuk performa
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- Deklarasi variabel lokal untuk RemoteEvents/Functions dan animasi
local NetPath, EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted
local animations = {}
local loadedAnimations = {}

-- Status dan Konfigurasi
local isRunning = false
local currentMode = "Fast"
local connection = nil
local fishingInProgress = false
local lastFishTime = 0
local remotesAndAnimsInitialized = false
local perfectCast = false

-- Menggunakan konstanta untuk AnimationId agar lebih mudah dibaca/diperbarui
local ANIMATION_IDS = {
    Cast = "rbxassetid://92624107165273",
    Catch = "rbxassetid://117319000848286",
    Waiting = "rbxassetid://134965425664034",
    HoldIdle = "rbxassetid://96586569072385"
    -- ReelIn: "rbxassetid://114959536562596" <-- Dihapus
}

local FISHING_CONFIGS = {
    ["Fast"] = { waitBetween = 0.5, rodSlot = 1 },
    ["Slow"] = { waitBetween = 1.5, rodSlot = 1 }
}

--- PRIVATE FUNCTIONS
--------------------------------------------------------------------------------

-- Fungsi untuk menginisialisasi Remotes dan Animation Instances
local function initializeRemotesAndAnimations()
    local success = pcall(function()
        -- Tunggu folder NetPath
        NetPath = ReplicatedStorage:WaitForChild("Packages", 5)
            :WaitForChild("_Index", 5)
            :WaitForChild("sleitnick_net@0.2.0", 5)
            :WaitForChild("net", 5)

        -- Ambil Remotes
        EquipTool = NetPath:WaitForChild("RE/EquipToolFromHotbar", 5)
        ChargeFishingRod = NetPath:WaitForChild("RF/ChargeFishingRod", 5)
        RequestFishing = NetPath:WaitForChild("RF/RequestFishingMinigameStarted", 5)
        FishingCompleted = NetPath:WaitForChild("RE/FishingCompleted", 5)

        -- Buat Animation Instances dan set IDs (tanpa ReelIn)
        for name, id in pairs(ANIMATION_IDS) do
            local anim = Instance.new("Animation")
            anim.AnimationId = id
            animations[name] = anim
        end
        
        return true
    end)

    return success
end

-- Fungsi untuk memuat animasi ke Animator karakter
local function loadAnimations()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Humanoid") then 
        return false 
    end
    
    local humanoid = LocalPlayer.Character.Humanoid
    -- Pastikan Animator ada
    local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
    
    table.clear(loadedAnimations)
    for name, anim in pairs(animations) do
        -- Pastikan anim instance ada
        if anim and anim:IsA("Animation") then
             loadedAnimations[name] = animator:LoadAnimation(anim)
        end
    end

    -- Tambahkan pengecekan apakah animasi penting berhasil dimuat
    if not loadedAnimations.Cast then
        logger:warn("Failed to load essential animations.")
        return false
    end

    logger:info("Animations loaded successfully.")
    return true
end

--- PUBLIC METHODS
--------------------------------------------------------------------------------
--
function AutoFishFeature:Init(guiControls)
    remotesAndAnimsInitialized = initializeRemotesAndAnimations()

    if not remotesAndAnimsInitialized then
        logger:warn("Failed to initialize remotes or animations.")
        return false
    end

    -- Inisialisasi PerfectCast dari GUI jika tersedia
    if guiControls and guiControls.perfectCastToggle then
        perfectCast = guiControls.perfectCastToggle.Value
        guiControls.perfectCastToggle.Changed:Connect(function(val)
            perfectCast = val
            logger:info("Perfect Cast set to:", val)
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
    currentMode = config and config.mode or "Fast"
    fishingInProgress = false
    lastFishTime = 0

    -- Muat animasi dan sambungkan untuk memuat ulang saat karakter baru ditambahkan
    if not loadAnimations() then
        logger:warn("Failed to load animations on start. Character might not be ready. Will retry on CharacterAdded.")
    end

    -- Gunakan koneksi yang disimpan untuk CharacterAdded agar dapat diputus saat Cleanup
    self.charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
        if isRunning then
            -- Beri waktu karakter siap sebelum memuat animasi
            task.wait(1) 
            loadAnimations()
        end
    end)

    logger:info("Started ANIMATION method - Mode:", currentMode)

    -- Hubungkan ke Heartbeat untuk loop utama
    connection = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        self:AnimationFishingLoop()
    end)
end

function AutoFishFeature:Stop()
    if not isRunning then return end

    isRunning = false
    fishingInProgress = false

    -- Hentikan semua animasi yang dimuat
    for _, animTrack in pairs(loadedAnimations) do
        if animTrack.IsPlaying then
            animTrack:Stop()
        end
    end

    -- Putuskan koneksi Heartbeat
    if connection then
        connection:Disconnect()
        connection = nil
    end

    -- Putuskan koneksi CharacterAdded jika ada
    if self.charAddedConn then
        self.charAddedConn:Disconnect()
        self.charAddedConn = nil
    end

    logger:info("Stopped ANIMATION method")
end

-- Loop utama yang berjalan di Heartbeat
function AutoFishFeature:AnimationFishingLoop()
    if fishingInProgress then return end

    local currentTime = tick()
    local config = FISHING_CONFIGS[currentMode]

    -- Pengecekan waktu cooldown antar lemparan
    if currentTime - lastFishTime < config.waitBetween then
        return
    end

    fishingInProgress = true
    lastFishTime = currentTime

    -- Spawn untuk menghindari jeda Heartbeat
    task.spawn(function()
        local success = self:ExecuteAnimatedFishingSequence()
        fishingInProgress = false -- Setel ulang terlepas dari keberhasilan
        
        if success then
            logger:info("Animation cycle completed!")
        end
    end)
end

-- Urutan langkah mancing utama
function AutoFishFeature:ExecuteAnimatedFishingSequence()
    local config = FISHING_CONFIGS[currentMode]
    
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Humanoid") then
        logger:warn("Character not found. Skipping cycle.")
        return false
    end
    
    if not loadedAnimations.Cast then
        logger:warn("Animations not loaded. Skipping cycle.")
        return false
    end

    local success = pcall(function()
        -- 1. Equip Rod
        EquipTool:FireServer(config.rodSlot)
        if loadedAnimations.HoldIdle then loadedAnimations.HoldIdle:Play() end
        task.wait(0.2) -- Tunggu sebentar setelah equip
        
        if loadedAnimations.HoldIdle then loadedAnimations.HoldIdle:Stop() end
        
        -- 2. Cast
        if loadedAnimations.Cast then 
            loadedAnimations.Cast:Play() 
        end
        
        -- Anggap 'ChargeFishingRod' adalah RemoteFunction
        ChargeFishingRod:InvokeServer(perfectCast and 9e9 or tick())
        
        -- Tunggu animasi Cast selesai (atau beri batas waktu jika terjadi kesalahan)
        local castWaitSuccess = loadedAnimations.Cast.Ended:Wait(5) 
        if not castWaitSuccess then
            logger:warn("Cast animation did not end in time.")
            return
        end
        
        -- 3. Wait/Idle
        if loadedAnimations.Waiting then loadedAnimations.Waiting:Play() end
        
        -- 4. Request Fishing Minigame
        -- Gunakan koordinat statis/random untuk Perfect Cast/Regular
        local x = perfectCast and -1.238 or math.random() * 2 - 1 -- -1 hingga 1
        local z = perfectCast and 0.969 or math.random() * 2 - 1
        RequestFishing:InvokeServer(x, z)
        
        task.wait(1.3) -- Tunggu respons minigame
        
        -- Hentikan animasi Waiting
        if loadedAnimations.Waiting and loadedAnimations.Waiting.IsPlaying then 
            loadedAnimations.Waiting:Stop() 
        end
        
        -- [[ Dihapus: Logika untuk animasi ReelIn dihilangkan ]]
        -- if loadedAnimations.ReelIn then loadedAnimations.ReelIn:Play() end
        -- task.wait(0.2)
        -- if loadedAnimations.ReelIn and loadedAnimations.ReelIn.IsPlaying then loadedAnimations.ReelIn:Stop() end
        -- 
        
        -- 5. Catch
        if loadedAnimations.Catch then 
            loadedAnimations.Catch:Play() 
        end
        
        -- 6. Fire FishingCompleted (biasanya dilakukan beberapa kali untuk memastikan server menerima)
        for i = 1, 3 do
            if not isRunning then break end -- Keluar jika dihentikan saat loop
            FishingCompleted:FireServer()
            task.wait(0.1)
        end
        
        -- Tunggu animasi Catch selesai
        if loadedAnimations.Catch then 
            loadedAnimations.Catch.Stopped:Wait() 
        end
    end)

    if not success then
        logger:error("An error occurred during the animated fishing sequence.")
        -- Pastikan semua animasi dihentikan jika terjadi kesalahan
        for _, animTrack in pairs(loadedAnimations) do
            if animTrack.IsPlaying then animTrack:Stop() end
        end
        task.wait(1) -- Cool down singkat setelah error
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
    
    -- Reset status dan bersihkan tabel
    remotesAndAnimsInitialized = false
    table.clear(animations)
    table.clear(loadedAnimations)

    -- Reset remote variables ke nil (opsional, tapi praktik yang baik)
    NetPath, EquipTool, ChargeFishingRod, RequestFishing, FishingCompleted = nil
end

return AutoFishFeature
