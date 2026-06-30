--[[
    Base UI | v1.0
    LinoriaLib Comprehensive Script Framework (Optimized Features Edition)
--]]

-- =====================================================================
-- SERVICES
-- =====================================================================
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local Lighting          = game:GetService("Lighting")
local VirtualUser       = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIM               = game:GetService("VirtualInputManager")

local LocalPlayer       = Players.LocalPlayer
local Camera            = Workspace.CurrentCamera
local Mouse             = LocalPlayer:GetMouse()

-- =====================================================================
-- STATE & CLEANUP MANAGER
-- =====================================================================
local Connections = {}
local Threads     = {}
local OriginalLighting = {
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    ColorShift_Bottom = Lighting.ColorShift_Bottom,
    ColorShift_Top = Lighting.ColorShift_Top,
    ClockTime = Lighting.ClockTime
}

local function AddConnection(conn)
    table.insert(Connections, conn)
    return conn
end

local function AddThread(thread)
    table.insert(Threads, thread)
    return thread
end

-- =====================================================================
-- ENTITY SOURCE (universal) -- the ONE place every mob feature reads from.
-- Per game, set the container path in Settings > Entity Source (default
-- "World.Entities"). Path is dot-separated under Workspace, e.g. "Living",
-- "World.Entities", or "Game.Mobs". All farm / ESP / network / safe-area
-- mob logic resolves through here, so retargeting a new game = one field.
-- =====================================================================
local DEFAULT_ENTITY_PATH = "World.Entities"
local function resolveContainer()
    local path = (Options and Options.EntityPath and Options.EntityPath.Value) or DEFAULT_ENTITY_PATH
    if path == nil or path == "" then return nil end
    local node = Workspace
    for seg in string.gmatch(path, "[^%.]+") do
        if not node then return nil end
        node = node:FindFirstChild(seg)
    end
    return node
end
local function getMobHRP(model)
    return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
end
local function isMobModel(model)
    if not (model and model:IsA("Model")) or model == LocalPlayer.Character then return false end
    if Players:GetPlayerFromCharacter(model) then return false end
    if model.Name == LocalPlayer.Name then return false end
    return model:FindFirstChildOfClass("Humanoid") ~= nil and getMobHRP(model) ~= nil
end
-- Returns every live mob (Humanoid.Health > 0) under the configured container.
local function getEntities()
    local out, c = {}, resolveContainer()
    if not c then return out end
    for _, v in ipairs(c:GetDescendants()) do
        if isMobModel(v) then
            local hum = v:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then table.insert(out, v) end
        end
    end
    return out
end

-- Network-ownership helpers (executor-gated -- degrade gracefully on weak executors).
local isnetworkowner = isnetworkowner or function() return false end
local function forceSimRadius()
    if not sethiddenproperty then return end
    pcall(function()
        sethiddenproperty(LocalPlayer, "MaxSimulationRadius", 9e9)
        sethiddenproperty(LocalPlayer, "SimulationRadius", 9e9)
    end)
end

-- Generic Discord webhook sender (game-specific TRIGGERS are fill-in; this is the
-- transport). Call sendWebhook("Title", "Description") from any event you wire up.
local function sendWebhook(title, description, color)
    if not (Toggles and Toggles.WebhookEnabled and Toggles.WebhookEnabled.Value) then return end
    local url = Options and Options.WebhookURL and Options.WebhookURL.Value
    if type(url) ~= "string" or url == "" or not string.find(url, "discord") then return end
    local req = http_request or request or (syn and syn.request)
    if not req then return end
    task.spawn(function()
        local payload = {
            embeds = { {
                title = tostring(title or "Event"),
                description = tostring(description or ""),
                color = color or 0x8a2be2,
                footer = { text = "Base UI" },
            } },
        }
        local ok, body = pcall(function() return HttpService:JSONEncode(payload) end)
        if not ok then return end
        pcall(function()
            req({ Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
        end)
    end)
end

-- =====================================================================
-- SHIM IMPORT
-- =====================================================================
local Shim = loadstring(game:HttpGet("https://raw.githubusercontent.com/LogicalGoy/samet-modified-lib-v2/refs/heads/main/SametLinoriaShim.lua"))()
local Library, Toggles, Options, ThemeManager, SaveManager = Shim:Init({
    Name = "Citra Hub",
    SubName = "Placeholder",
    Logo = "91942884565368",
    Accent = Color3.fromRGB(255, 165, 0),
    ShowTabIcons = false
})

-- =====================================================================
-- WINDOW
-- =====================================================================
local Window = Library:CreateWindow({
    Title    = "Citra Hub ",
    Center   = true,
    AutoShow = true,
    TabPaddingX = 8,
    MenuFadeTime = 0.2,
})

-- Menu toggle keybind
Library.ToggleKeybind = Enum.KeyCode.RightShift

-- =====================================================================
-- TAB 1 : MAIN
-- =====================================================================
local TabMain       = Window:AddTab("Main")

-- Separate Groupboxes
local MobGroup      = TabMain:AddLeftGroupbox("Mob Farm")
local PlayerGroup   = TabMain:AddLeftGroupbox("Player Farm")
local CombatGroup   = TabMain:AddRightGroupbox("Combat")
local PosGroup      = TabMain:AddRightGroupbox("Farm Position")

MobGroup:AddToggle("MobFarm", { Text = "Enable Mob Farm", Default = false })
MobGroup:AddDropdown("SelectMob", {
    Values  = { "Closest" },
    Default = 1,
    Multi   = false,
    Text    = "Select Mob",
})

PlayerGroup:AddToggle("PlayerFarm", { Text = "Enable Player Farm", Default = false })
PlayerGroup:AddDropdown("TargetPlayerDropdown", {
    Values  = { "Closest" },
    Default = 1,
    Multi   = false,
    Text    = "Target Player",
})

CombatGroup:AddToggle("AutoM1", { Text = "Auto M1", Default = false })
CombatGroup:AddToggle("AutoHeavy", { Text = "Auto Heavy", Default = false })
CombatGroup:AddToggle("AutoEquip", { Text = "Auto Equip Tool", Default = false,
    Tooltip = "Re-equips your first backpack tool whenever it becomes unequipped." })

PosGroup:AddDropdown("FarmMethod", {
    Values = { "Behind", "Above", "Below", "Custom" },
    Default = 1,
    Multi = false,
    Text = "Farm Method",
})
PosGroup:AddSlider("FarmOffsetX", { Text = "Offset X", Default = 0, Min = -30, Max = 30, Rounding = 1 })
PosGroup:AddSlider("FarmOffsetY", { Text = "Offset Y", Default = 5, Min = -30, Max = 30, Rounding = 1 })
PosGroup:AddSlider("FarmOffsetZ", { Text = "Offset Z", Default = 0, Min = -30, Max = 30, Rounding = 1 })
PosGroup:AddSlider("FarmSmoothness", { Text = "Tween Smoothness", Default = 0.5, Min = 0.1, Max = 1.0, Rounding = 2 })

-- Automation Loops
AddThread(task.spawn(function()
    local m1Remote = nil
    local heavyRemote = nil
    pcall(function()
        m1Remote = game:GetService("ReplicatedStorage").Files.Framework.Network.UnreliableRemoteEvent
        heavyRemote = game:GetService("ReplicatedStorage").Files.Modules.Shared.Packet.RemoteEvent
    end)
    while task.wait(0.1) do
        if Toggles.AutoM1 and Toggles.AutoM1.Value and m1Remote then
            pcall(function() m1Remote:FireServer("M1") end)
        end
        if Toggles.AutoHeavy and Toggles.AutoHeavy.Value and heavyRemote then
            pcall(function()
                heavyRemote:FireServer(buffer.fromstring("\x03\x05Event\x1C\v\x04Name\v\bCritical\v\x04Args\x16\xEB2\xE2\xBC\x02\xE7?=\x04\x9F\x7F\xBF\x00"))
            end)
        end
    end
end))

-- Auto Equip Tool loop (re-equips the first backpack tool when nothing is held)
AddThread(task.spawn(function()
    while task.wait(0.4) do
        if Toggles.AutoEquip and Toggles.AutoEquip.Value then
            pcall(function()
                local char = LocalPlayer.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if char and hum and not char:FindFirstChildOfClass("Tool") then
                    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
                    local tool = bp and bp:FindFirstChildOfClass("Tool")
                    if tool then hum:EquipTool(tool) end
                end
            end)
        end
    end
end))

-- Dynamic Dropdown Updaters
AddThread(task.spawn(function()
    while task.wait(2) do
        -- Update Mob List
        local entities = resolveContainer()
        if entities and Options.SelectMob then
            local mobNames = { "Closest" }
            local seen = {}
            for _, v in ipairs(entities:GetDescendants()) do
                if v:IsA("Model") and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Name ~= LocalPlayer.Name then
                    if not Players:GetPlayerFromCharacter(v) then
                        local n = string.gsub(v.Name, "%d+$", "")
                        if not seen[n] then
                            seen[n] = true
                            table.insert(mobNames, n)
                        end
                    end
                end
            end
            table.sort(mobNames)
            Options.SelectMob:SetValues(mobNames)
        end
        
        -- Update Player List
        if Options.TargetPlayerDropdown then
            local playerNames = { "Closest" }
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    table.insert(playerNames, p.Name)
                end
            end
            Options.TargetPlayerDropdown:SetValues(playerNames)
        end
    end
end))

local function GetMobTarget()
    local entities = resolveContainer()
    if not entities then return nil end
    local closest, shortestDist = nil, math.huge
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    for _, v in ipairs(entities:GetDescendants()) do
        if v:IsA("Model") and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 then
            if not Players:GetPlayerFromCharacter(v) and v.Name ~= LocalPlayer.Name then
                local selected = Options.SelectMob and Options.SelectMob.Value or "Closest"
                local n = string.gsub(v.Name, "%d+$", "")
                if selected == "Closest" or string.find(string.lower(n), string.lower(selected)) then
                    local dist = (hrp.Position - v.HumanoidRootPart.Position).Magnitude
                    if dist < shortestDist then
                        shortestDist, closest = dist, v
                    end
                end
            end
        end
    end
    return closest
end

local function GetPlayerTarget()
    local closest, shortestDist = nil, math.huge
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            local hum = p.Character:FindFirstChild("Humanoid")
            if hum and hum.Health > 0 then
                local selected = Options.TargetPlayerDropdown and Options.TargetPlayerDropdown.Value or "Closest"
                if selected == "Closest" or string.find(string.lower(p.Name), string.lower(selected)) then
                    local dist = (hrp.Position - p.Character.HumanoidRootPart.Position).Magnitude
                    if dist < shortestDist then
                        shortestDist, closest = dist, p.Character
                    end
                end
            end
        end
    end
    return closest
end

local farmTargetCFrame = nil

AddThread(task.spawn(function()
    while task.wait() do
        local doMob = Toggles.MobFarm and Toggles.MobFarm.Value
        local doPlayer = Toggles.PlayerFarm and Toggles.PlayerFarm.Value
        if doMob or doPlayer then
            local target = doMob and GetMobTarget() or GetPlayerTarget()
            if target then
                local tgtHrp = target:FindFirstChild("HumanoidRootPart")
                if tgtHrp then
                    local mode = Options.FarmMethod and Options.FarmMethod.Value or "Behind"
                    local ox = Options.FarmOffsetX and Options.FarmOffsetX.Value or 0
                    local oy = Options.FarmOffsetY and Options.FarmOffsetY.Value or 5
                    local oz = Options.FarmOffsetZ and Options.FarmOffsetZ.Value or 0
                    
                    local cf = tgtHrp.CFrame
                    local pos = cf.Position
                    
                    if mode == "Above" or mode == "Below" then
                        local height = math.abs(oy)
                        if height < 1 then height = 5 end
                        if mode == "Below" then height = -height end
                        local eyePos = Vector3.new(pos.X + ox, pos.Y + height, pos.Z)
                        local lookDir = (pos - eyePos).Unit
                        local pitch = math.asin(lookDir.Y)
                        local yaw = math.atan2(-cf.LookVector.X, -cf.LookVector.Z)
                        farmTargetCFrame = CFrame.new(eyePos) * CFrame.fromOrientation(pitch, yaw, 0)
                    elseif mode == "Custom" then
                        farmTargetCFrame = CFrame.lookAt(pos + Vector3.new(ox, oy, oz), pos)
                    else -- Behind
                        local seat = (cf * CFrame.new(ox, oy, oz)).Position
                        farmTargetCFrame = CFrame.lookAt(seat, Vector3.new(pos.X, seat.Y, pos.Z))
                    end
                else
                    farmTargetCFrame = nil
                end
            else
                farmTargetCFrame = nil
            end
        else
            farmTargetCFrame = nil
        end
    end
end))

-- Smooth Farm Tweening Loop
AddConnection(RunService.Heartbeat:Connect(function(dt)
    if farmTargetCFrame then
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local alpha = Options.FarmSmoothness and Options.FarmSmoothness.Value or 0.5
            hrp.CFrame = hrp.CFrame:Lerp(farmTargetCFrame, alpha)
            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = true end
        end
    else
        -- Only disable platform stand if we were farming and just stopped, 
        -- but leave it alone if Fly is active.
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum and not (Toggles.FlyToggle and Toggles.FlyToggle.Value) then
            if hum.PlatformStand and (Toggles.MobFarm and not Toggles.MobFarm.Value) and (Toggles.PlayerFarm and not Toggles.PlayerFarm.Value) then
                hum.PlatformStand = false
            end
        end
    end
end))

-- =====================================================================
-- SAFE AREA (Auto-Retreat) -- universal, pure client.
-- Set a safezone platform; when HP% drops below the trigger, pause farms, TP
-- onto the platform and hold until HP recovers, then return. Saved per-PlaceId
-- so it survives rejoins into the same world.
-- =====================================================================
do
    local SafeBox = TabMain:AddRightGroupbox("Safe Area")
    local SAFE_FILE = "BaseUI/SafeArea.json"
    local FARM_TOGGLE_KEYS = { "MobFarm", "PlayerFarm" }

    local safePlatform, safeCF, safeActive = nil, nil, false
    local savedToggles, returnPos = {}, nil

    local function saRoot() local c = LocalPlayer.Character; return c and c:FindFirstChild("HumanoidRootPart") end
    local function saHum()  local c = LocalPlayer.Character; return c and c:FindFirstChildOfClass("Humanoid") end

    local function makePlatform(cf)
        if safePlatform then pcall(function() safePlatform:Destroy() end) end
        local p = Instance.new("Part")
        p.Name = "BaseUISafeZone"; p.Size = Vector3.new(12, 1, 12)
        p.Anchored = true; p.CanCollide = true
        p.Material = Enum.Material.Neon; p.Color = Color3.fromRGB(0, 255, 127); p.Transparency = 0.4
        p.CFrame = CFrame.new(cf.Position - Vector3.new(0, 3, 0))
        p.Parent = Workspace
        safePlatform = p
    end

    local function saSave()
        if not writefile then return end
        pcall(function()
            if makefolder and isfolder and not isfolder("BaseUI") then makefolder("BaseUI") end
            local data = { placeId = game.PlaceId }
            if safeCF then data.cf = { safeCF:GetComponents() } end
            writefile(SAFE_FILE, HttpService:JSONEncode(data))
        end)
    end
    local function saLoad()
        if not (isfile and readfile) then return end
        pcall(function()
            if not isfile(SAFE_FILE) then return end
            local data = HttpService:JSONDecode(readfile(SAFE_FILE))
            if type(data) ~= "table" or not data.cf or data.placeId ~= game.PlaceId then return end
            if type(data.cf) == "table" and #data.cf >= 12 then
                safeCF = CFrame.new(table.unpack(data.cf))
                makePlatform(safeCF)
            end
        end)
    end

    local SafeStatus = SafeBox:AddLabel("Status: Idle")

    SafeBox:AddButton({ Text = "Set Safezone (here)", Func = function()
        local hrp = saRoot(); if not hrp then Library:Notify("Safe Area: No character!", 3); return end
        safeCF = hrp.CFrame; makePlatform(safeCF); saSave()
        SafeStatus:SetText("Status: Set"); Library:Notify("Safezone set (saved across rejoins).", 3)
    end })
    SafeBox:AddButton({ Text = "Clear Safezone", Func = function()
        if safePlatform then pcall(function() safePlatform:Destroy() end) end
        safePlatform, safeCF = nil, nil; saSave()
        SafeStatus:SetText("Status: Idle"); Library:Notify("Safezone cleared.", 3)
    end })

    SafeBox:AddSlider("SafeHpTrigger", { Text = "Retreat at HP %", Default = 30, Min = 5, Max = 95, Rounding = 0 })
    SafeBox:AddSlider("SafeHpResume", { Text = "Resume at HP %", Default = 90, Min = 10, Max = 100, Rounding = 0 })
    SafeBox:AddToggle("SafeAreaEnabled", { Text = "Enable Safe Area", Default = false,
        Tooltip = "Set a safezone first. Auto-retreats at low HP, holds until recovered, returns." })

    local function retreat()
        safeActive = true
        local hrp = saRoot(); returnPos = hrp and hrp.Position
        savedToggles = {}
        for _, name in ipairs(FARM_TOGGLE_KEYS) do
            local t = Toggles[name]
            if t and t.Value then savedToggles[name] = true; pcall(function() t:SetValue(false) end) end
        end
        if safeCF and (not safePlatform or not safePlatform.Parent) then makePlatform(safeCF) end
        hrp = saRoot()
        if hrp and safeCF then hrp.CFrame = safeCF; hrp.AssemblyLinearVelocity = Vector3.zero end
        SafeStatus:SetText("Status: Recovering")

        pcall(function()
            RunService:BindToRenderStep("BaseUISafeFreeze", Enum.RenderPriority.Character.Value + 1, function()
                local h = saRoot()
                if h and safeCF then
                    h.CFrame = safeCF
                    h.AssemblyLinearVelocity = Vector3.zero
                    h.AssemblyAngularVelocity = Vector3.zero
                end
            end)
        end)

        local died = false
        while Toggles.SafeAreaEnabled and Toggles.SafeAreaEnabled.Value do
            local hum = saHum()
            if not hum or hum.Health <= 0 then died = true break end
            local resume = (Options.SafeHpResume and Options.SafeHpResume.Value) or 90
            if (hum.Health / hum.MaxHealth) * 100 >= resume then break end
            task.wait(0.3)
        end
        pcall(function() RunService:UnbindFromRenderStep("BaseUISafeFreeze") end)

        local stillOn = Toggles.SafeAreaEnabled and Toggles.SafeAreaEnabled.Value
        local hum = saHum()
        if not died and stillOn and hum and hum.Health > 0 and returnPos then
            SafeStatus:SetText("Status: Returning")
            local hrp2 = saRoot()
            local t0 = os.clock()
            while hrp2 and hrp2.Parent and (os.clock() - t0) < 5 do
                local dist = (hrp2.Position - returnPos).Magnitude
                if dist <= 3 then break end
                local dt = RunService.RenderStepped:Wait()
                local step = math.min(dist, 40 * dt)
                hrp2.CFrame = CFrame.new(hrp2.Position + (returnPos - hrp2.Position).Unit * step)
                hrp2.AssemblyLinearVelocity = Vector3.zero
                local h2 = saHum(); if h2 then h2.PlatformStand = true end
            end
            local h2 = saHum(); if h2 then h2.PlatformStand = false end
        end

        for name in pairs(savedToggles) do
            local t = Toggles[name]; if t then pcall(function() t:SetValue(true) end) end
        end
        savedToggles = {}
        SafeStatus:SetText(safeCF and "Status: Set" or "Status: Idle")
        safeActive = false
    end

    AddThread(task.spawn(function()
        while not Library.Unloaded do
            task.wait(0.3)
            if Toggles.SafeAreaEnabled and Toggles.SafeAreaEnabled.Value and safeCF and not safeActive then
                local hum = saHum()
                if hum and hum.Health > 0 then
                    local trig = (Options.SafeHpTrigger and Options.SafeHpTrigger.Value) or 30
                    if (hum.Health / hum.MaxHealth) * 100 <= trig then pcall(retreat) end
                end
            end
        end
    end))

    saLoad()
    SafeStatus:SetText(safeCF and "Status: Set (restored)" or "Status: Idle")
end

-- =====================================================================
-- TAB 2 : AUTO PARRY
-- =====================================================================
local TabParry      = Window:AddTab("Auto Parry")

-- =====================================================================
-- TAB 3 : CHARACTER
-- =====================================================================
local TabChar       = Window:AddTab("Character")
local CharLeft      = TabChar:AddLeftGroupbox("Movement")

-- WalkSpeed
local WalkSpeedToggle = CharLeft:AddToggle("WalkSpeedEnabled", {
    Text    = "WalkSpeed",
    Default = false,
})

CharLeft:AddSlider("WalkSpeedValue", {
    Text     = "Speed",
    Default  = 16,
    Min      = 16,
    Max      = 500,
    Rounding = 0,
})

WalkSpeedToggle:AddKeyPicker("WalkSpeedKey", { Default = "None", SyncToggleState = true, Mode = "Toggle", Text = "WalkSpeed" })

-- JumpHeight
local JumpHeightToggle = CharLeft:AddToggle("JumpHeightEnabled", {
    Text    = "JumpHeight",
    Default = false,
})

CharLeft:AddSlider("JumpHeightValue", {
    Text     = "Height",
    Default  = 7.2,
    Min      = 0,
    Max      = 500,
    Rounding = 1,
})

JumpHeightToggle:AddKeyPicker("JumpHeightKey", { Default = "None", SyncToggleState = true, Mode = "Toggle", Text = "JumpHeight" })

-- Infinite Jump
local InfiniteJumpToggle = CharLeft:AddToggle("InfiniteJump", {
    Text    = "Infinite Jump",
    Default = false,
})

InfiniteJumpToggle:AddKeyPicker("InfiniteJumpKey", { Default = "None", SyncToggleState = true, Mode = "Toggle", Text = "Infinite Jump" })

-- Noclip
local NoclipToggle = CharLeft:AddToggle("Noclip", {
    Text    = "Noclip",
    Default = false,
})

NoclipToggle:AddKeyPicker("NoclipKey", { Default = "None", SyncToggleState = true, Mode = "Toggle", Text = "Noclip" })

-- Fly Setup
local FlyToggle = CharLeft:AddToggle("FlyToggle", {
    Text    = "Fly",
    Default = false,
})

CharLeft:AddSlider("FlySpeed", {
    Text     = "Speed",
    Default  = 50,
    Min      = 16,
    Max      = 300,
    Rounding = 0,
})

FlyToggle:AddKeyPicker("FlyKey", { Default = "None", SyncToggleState = true, Mode = "Toggle", Text = "Fly" })

-- Default stats caching
local DefaultWalkSpeed = 16
local DefaultJumpHeight = 7.2
local DefaultUseJumpPower = true
do
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        DefaultWalkSpeed = hum.WalkSpeed
        DefaultJumpHeight = hum.JumpHeight
        DefaultUseJumpPower = hum.UseJumpPower
    end
end

-- Reset handlers
Toggles.WalkSpeedEnabled:OnChanged(function()
    if not Toggles.WalkSpeedEnabled.Value then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = DefaultWalkSpeed end
    end
end)

Toggles.JumpHeightEnabled:OnChanged(function()
    if not Toggles.JumpHeightEnabled.Value then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then 
            hum.JumpHeight = DefaultJumpHeight 
            hum.UseJumpPower = DefaultUseJumpPower
        end
    end
end)

-- part -> its CanCollide value BEFORE noclip turned it off (weak so despawned
-- parts drop out). We restore ONLY these on disable -- never blanket-force every
-- part collidable, which used to leave the HumanoidRootPart CanCollide = true and
-- caused the leftover jitter after noclip was turned off.
local noclipOriginal = setmetatable({}, { __mode = "k" })
Toggles.Noclip:OnChanged(function()
    if not Toggles.Noclip.Value then
        for part, original in pairs(noclipOriginal) do
            if part and part.Parent then
                pcall(function() part.CanCollide = original end)
            end
        end
        table.clear(noclipOriginal)
    end
end)

local flyKeys = {W = false, A = false, S = false, D = false, Space = false, LeftShift = false}

Toggles.FlyToggle:OnChanged(function()
    local char = LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local root = char.HumanoidRootPart
        local hum = char:FindFirstChildOfClass("Humanoid")
        if Toggles.FlyToggle.Value then
            if hum then hum.PlatformStand = true end
            local bv = Instance.new("BodyVelocity")
            local bg = Instance.new("BodyGyro")
            bv.Name = "MaliciousFlyBV"
            bg.Name = "MaliciousFlyBG"
            bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            bv.Velocity = Vector3.new(0, 0, 0)
            bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            bg.P = 9e4
            bg.CFrame = Camera.CFrame
            bv.Parent = root
            bg.Parent = root
        else
            if hum then hum.PlatformStand = false end
            if root:FindFirstChild("MaliciousFlyBV") then root.MaliciousFlyBV:Destroy() end
            if root:FindFirstChild("MaliciousFlyBG") then root.MaliciousFlyBG:Destroy() end
        end
    end
end)

-- Keybinds (Restructured inline under each feature toggle above)

-- Connections
AddConnection(UserInputService.JumpRequest:Connect(function()
    if Toggles.InfiniteJump and Toggles.InfiniteJump.Value then
        local char = LocalPlayer.Character
        if char and char:FindFirstChildOfClass("Humanoid") then
            char:FindFirstChildOfClass("Humanoid"):ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end))

AddConnection(UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.W then flyKeys.W = true end
    if input.KeyCode == Enum.KeyCode.A then flyKeys.A = true end
    if input.KeyCode == Enum.KeyCode.S then flyKeys.S = true end
    if input.KeyCode == Enum.KeyCode.D then flyKeys.D = true end
    if input.KeyCode == Enum.KeyCode.Space then flyKeys.Space = true end
    if input.KeyCode == Enum.KeyCode.LeftShift then flyKeys.LeftShift = true end
end))

AddConnection(UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.W then flyKeys.W = false end
    if input.KeyCode == Enum.KeyCode.A then flyKeys.A = false end
    if input.KeyCode == Enum.KeyCode.S then flyKeys.S = false end
    if input.KeyCode == Enum.KeyCode.D then flyKeys.D = false end
    if input.KeyCode == Enum.KeyCode.Space then flyKeys.Space = false end
    if input.KeyCode == Enum.KeyCode.LeftShift then flyKeys.LeftShift = false end
end))

AddConnection(RunService.Heartbeat:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    -- Apply WalkSpeed Override
    if Toggles.WalkSpeedEnabled and Toggles.WalkSpeedEnabled.Value then
        hum.WalkSpeed = Options.WalkSpeedValue.Value
    end

    -- Apply JumpHeight Override
    if Toggles.JumpHeightEnabled and Toggles.JumpHeightEnabled.Value then
        hum.UseJumpPower = false
        hum.JumpHeight = Options.JumpHeightValue.Value
    end

    -- Flight Logic
    if Toggles.FlyToggle and Toggles.FlyToggle.Value then
        if hum then hum.PlatformStand = true end
        local bv = root:FindFirstChild("MaliciousFlyBV")
        local bg = root:FindFirstChild("MaliciousFlyBG")
        if bv and bg then
            local moveDir = Vector3.new(0, 0, 0)
            local cameraCFrame = Camera.CFrame
            
            if flyKeys.W then moveDir = moveDir + cameraCFrame.LookVector end
            if flyKeys.S then moveDir = moveDir - cameraCFrame.LookVector end
            if flyKeys.D then moveDir = moveDir + cameraCFrame.RightVector end
            if flyKeys.A then moveDir = moveDir - cameraCFrame.RightVector end
            if flyKeys.Space then moveDir = moveDir + Vector3.new(0, 1, 0) end
            if flyKeys.LeftShift then moveDir = moveDir - Vector3.new(0, 1, 0) end

            bg.CFrame = cameraCFrame
            if moveDir.Magnitude > 0 then
                bv.Velocity = moveDir.Unit * Options.FlySpeed.Value
            else
                bv.Velocity = Vector3.new(0, 0, 0)
            end
        end
    end
end))

-- Dedicated Noclip Stepped Loop (Runs BEFORE physics so the collision is cleared before
-- the engine resolves contacts that frame). Noclip is JUST CanCollide=false, re-asserted
-- every frame because the game re-enables it. The old version ALSO zeroed the X/Z velocity
-- and set Massless every frame -- zeroing horizontal velocity each Stepped killed all walking
-- momentum, which is why it "slowed you down immensely" and you couldn't move through
-- anything. We don't touch velocity or mass at all now -- you walk/fly normally, just clip-free.
AddConnection(RunService.Stepped:Connect(function()
    local char = LocalPlayer.Character
    if Toggles.Noclip and Toggles.Noclip.Value and char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                -- Remember the original (only parts that were actually collidable get here,
                -- so the HumanoidRootPart -- normally CanCollide=false -- is never touched).
                if noclipOriginal[part] == nil then noclipOriginal[part] = part.CanCollide end
                part.CanCollide = false
            end
        end
    end
end))

-- =====================================================================
-- NETWORK EXPLOITS (Character tab) -- universal, via network ownership.
-- Forces a huge simulation radius so the server hands us nearby mobs, then:
--   Network ESP  : highlight mobs we currently own (killable instantly)
--   Instant Kill : set Health=0 the instant ownership is granted
--   Freeze Mobs  : pin a mob's CFrame while we own it
--   Bring Mobs   : pull owned mobs to us
-- Needs executor sethiddenproperty + isnetworkowner; no-ops without them.
-- =====================================================================
do
    local NetBox = TabChar:AddRightGroupbox("Network Exploits")

    NetBox:AddToggle("NetESP", { Text = "Network ESP (Owned)", Default = false,
        Tooltip = "Highlights mobs you currently have network ownership of (instant-killable)." })
    NetBox:AddToggle("InstaKill", { Text = "Instant Kill", Default = false,
        Tooltip = "Kills mobs the instant the server grants you ownership." })
    NetBox:AddSlider("NetRange", { Text = "Range", Default = 60, Min = 10, Max = 300, Rounding = 0, Suffix = " studs" })
    NetBox:AddToggle("FreezeMobs", { Text = "Freeze Mobs", Default = false,
        Tooltip = "Pins owned mobs in place so they can't move or attack." })
    NetBox:AddToggle("BringMobs", { Text = "Bring Mobs", Default = false,
        Tooltip = "Pulls owned mobs to you." })

    -- mob -> pinned CFrame (weak so despawned mobs drop out).
    local frozen = setmetatable({}, { __mode = "k" })
    local instaActive = {}

    AddConnection(RunService.Heartbeat:Connect(function()
        local netESP = Toggles.NetESP and Toggles.NetESP.Value
        local insta  = Toggles.InstaKill and Toggles.InstaKill.Value
        local freeze = Toggles.FreezeMobs and Toggles.FreezeMobs.Value
        local bring  = Toggles.BringMobs and Toggles.BringMobs.Value
        if not (netESP or insta or freeze or bring) then return end

        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if (insta or freeze or bring) then forceSimRadius() end

        local range = (Options.NetRange and Options.NetRange.Value) or 60

        for _, mob in ipairs(getEntities()) do
            local mobHrp = getMobHRP(mob)
            local hum = mob:FindFirstChildOfClass("Humanoid")
            if mobHrp and hum and hum.Health > 0 then
                local owned = isnetworkowner(mobHrp)
                local dist = hrp and (hrp.Position - mobHrp.Position).Magnitude or math.huge

                -- Network ESP highlight
                if netESP and owned then
                    if not mob:FindFirstChild("NetOwnHighlight") then
                        local h = Instance.new("Highlight")
                        h.Name = "NetOwnHighlight"
                        h.FillColor = Color3.fromRGB(0, 255, 0)
                        h.OutlineColor = Color3.fromRGB(0, 200, 0)
                        h.FillTransparency = 0.5
                        h.Parent = mob
                    end
                else
                    local h = mob:FindFirstChild("NetOwnHighlight")
                    if h then h:Destroy() end
                end

                -- Instant Kill (fire-on-grant, within range)
                if insta and owned and hrp and dist <= range and not instaActive[mob] then
                    instaActive[mob] = true
                    local deadHum = hum
                    task.spawn(function()
                        for _ = 1, 3 do
                            if not deadHum.Parent or deadHum.Health <= 0 then break end
                            pcall(function() deadHum.Health = 0 end)
                            task.wait()
                        end
                        task.wait(0.4)
                        instaActive[mob] = nil
                    end)
                end

                -- Freeze (pin while owned + in range)
                if freeze and hrp and dist <= range then
                    if owned then
                        local lock = frozen[mob]
                        if not lock then lock = mobHrp.CFrame; frozen[mob] = lock end
                        pcall(function()
                            mobHrp.CFrame = lock
                            mobHrp.AssemblyLinearVelocity = Vector3.zero
                            mobHrp.AssemblyAngularVelocity = Vector3.zero
                        end)
                    end
                elseif frozen[mob] then
                    frozen[mob] = nil
                end

                -- Bring (pull owned mobs to us)
                if bring and owned and hrp and dist <= range and dist > 6 then
                    pcall(function()
                        mobHrp.CFrame = hrp.CFrame * CFrame.new(0, 0, -4)
                        mobHrp.AssemblyLinearVelocity = Vector3.zero
                    end)
                end
            else
                local h = mob:FindFirstChild("NetOwnHighlight")
                if h then h:Destroy() end
            end
        end
    end))
end

-- =====================================================================
-- TAB 3 : AIMBOT
-- =====================================================================
local TabAim        = Window:AddTab("Aimbot")
local AimLeft       = TabAim:AddLeftGroupbox("Aimbot")
local AimRight      = TabAim:AddRightGroupbox("FOV")
local AimBottom     = TabAim:AddLeftGroupbox("Hitbox Expander")
local TargetActions = TabAim:AddRightGroupbox("Target")

-- Aimbot controls
local AimMaster = AimLeft:AddToggle("AimMaster", {
    Text    = "Aimbot",
    Default = false,
})

-- Personalised aim key: toggle to lock on
AimMaster:AddKeyPicker("AimKey", { Default = "None", SyncToggleState = true, Mode = "Toggle", Text = "Aim Key" })


AimLeft:AddDropdown("AimPartTarget", {
    Values  = { "Head", "HumanoidRootPart", "Torso" },
    Default = 3,
    Multi   = false,
    Text    = "Target Part",
})

AimLeft:AddSlider("AimSmoothness", {
    Text     = "Smoothness",
    Default  = 0,
    Min      = 0,
    Max      = 5,
    Rounding = 0,
})

-- FOV Circle setup
AimRight:AddToggle("ShowFOVCircle", {
    Text    = "Show FOV",
    Default = false,
})

AimRight:AddSlider("FOVRadius", {
    Text     = "Radius",
    Default  = 100,
    Min      = 10,
    Max      = 800,
    Rounding = 0,
})

local FOVCircle = nil
local drawSuccess, drawErr = pcall(function()
    FOVCircle = Drawing.new("Circle")
    FOVCircle.Thickness = 1.5
    FOVCircle.Color = Color3.fromRGB(255, 255, 255)
    FOVCircle.Filled = false
    FOVCircle.Transparency = 1
    FOVCircle.Visible = false
    return FOVCircle
end)

local function GetClosestPlayerInFOV()
    local closestPlayer = nil
    local shortestDistance = math.huge
    local maxFOV = Options.FOVRadius and Options.FOVRadius.Value or 100
    local aimPart = Options.AimPartTarget and Options.AimPartTarget.Value or "Torso"

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local targetPart = player.Character:FindFirstChild(aimPart)
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if targetPart and humanoid and humanoid.Health > 0 then
                local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                if onScreen then
                    local mousePos = UserInputService:GetMouseLocation()
                    local distance = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if distance < shortestDistance and distance <= maxFOV then
                        shortestDistance = distance
                        closestPlayer = player
                    end
                end
            end
        end
    end
    return closestPlayer
end

local CurrentAimTarget = nil

-- Aimbot RenderStepped Loop
AddConnection(RunService.RenderStepped:Connect(function()
    -- Dynamic FOV circle updates
    if FOVCircle then
        FOVCircle.Visible = Toggles.ShowFOVCircle and Toggles.ShowFOVCircle.Value or false
        FOVCircle.Radius = Options.FOVRadius and Options.FOVRadius.Value or 100
        FOVCircle.Position = UserInputService:GetMouseLocation()
    end

    -- Camera Lerp Aimbot (active when toggled)
    if Toggles.AimMaster and Toggles.AimMaster.Value then
        local isAimKeyDown = Options.AimKey and Options.AimKey:GetState()
        if isAimKeyDown then
            -- Re-evaluate target if needed
            if not CurrentAimTarget or not CurrentAimTarget.Character or not CurrentAimTarget.Character:FindFirstChild("Humanoid") or CurrentAimTarget.Character.Humanoid.Health <= 0 then
                CurrentAimTarget = GetClosestPlayerInFOV()
            end
            
            if CurrentAimTarget and CurrentAimTarget.Character then
                local aimPart = Options.AimPartTarget and Options.AimPartTarget.Value or "Torso"
                local part = CurrentAimTarget.Character:FindFirstChild(aimPart)
                if part then
                    local targetPos = part.Position
                    local smoothness = Options.AimSmoothness and Options.AimSmoothness.Value or 0
                    local targetCFrame = CFrame.new(Camera.CFrame.Position, targetPos)
                    if smoothness <= 0 then
                        Camera.CFrame = targetCFrame
                    else
                        Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, 1 / smoothness)
                    end
                end
            else
                CurrentAimTarget = GetClosestPlayerInFOV()
            end
        else
            CurrentAimTarget = nil
        end
    else
        CurrentAimTarget = nil
    end
end))

-- Hitbox Extender Groupbox
AimBottom:AddToggle("ExtendHitboxes", {
    Text    = "Hitbox Expander",
    Default = false,
})

AimBottom:AddSlider("HitboxSize", {
    Text     = "Size",
    Default  = 2,
    Min      = 2,
    Max      = 50,
    Rounding = 1,
})

local OriginalHitboxes = {} -- HumanoidRootPart -> {Size, CanCollide, Transparency}

AddConnection(RunService.Heartbeat:Connect(function()
    if Toggles.ExtendHitboxes and Toggles.ExtendHitboxes.Value then
        local targetSize = Options.HitboxSize and Options.HitboxSize.Value or 2
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local root = player.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    if not OriginalHitboxes[root] then
                        OriginalHitboxes[root] = {
                            Size = root.Size,
                            CanCollide = root.CanCollide,
                            Transparency = root.Transparency
                        }
                    end
                    root.Size = Vector3.new(targetSize, targetSize, targetSize)
                    root.CanCollide = false
                    root.Transparency = 0.7
                end
            end
        end
    else
        -- Restore original hitboxes
        for root, data in pairs(OriginalHitboxes) do
            pcall(function()
                if root and root.Parent then
                    root.Size = data.Size
                    root.CanCollide = data.CanCollide
                    root.Transparency = data.Transparency
                end
            end)
        end
        table.clear(OriginalHitboxes)
    end
end))

-- Target selection and dynamic player listings
local playerList = {}
local selectedPlayer = nil

local function updatePlayerDropdown()
    table.clear(playerList)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(playerList, player.Name)
        end
    end
    if Options.AimTargetPlayer then
        Options.AimTargetPlayer:SetValues(playerList)
    end
end

TargetActions:AddDropdown("AimTargetPlayer", {
    Values    = playerList,
    Default   = 1,
    AllowNull = true,
    Multi     = false,
    Text      = "Player",
})

Options.AimTargetPlayer:OnChanged(function()
    selectedPlayer = Players:FindFirstChild(Options.AimTargetPlayer.Value)
end)

AddConnection(Players.PlayerAdded:Connect(updatePlayerDropdown))
AddConnection(Players.PlayerRemoving:Connect(updatePlayerDropdown))
updatePlayerDropdown()

-- Target Actions Buttons
TargetActions:AddButton({
    Text = "Teleport",
    Func = function()
        if selectedPlayer and selectedPlayer.Character then
            local targetRoot = selectedPlayer.Character:FindFirstChild("HumanoidRootPart")
            local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot and localRoot then
                localRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, -3)
            end
        else
            Library:Notify("Target character not found.", 2)
        end
    end
})

TargetActions:AddButton({
    Text = "Spectate",
    Func = function()
        if selectedPlayer and selectedPlayer.Character then
            local hum = selectedPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                Camera.CameraSubject = hum
                Library:Notify("Now spectating: " .. selectedPlayer.Name, 2)
            end
        else
            Camera.CameraSubject = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            Library:Notify("Reset camera to local player.", 2)
        end
    end
})

TargetActions:AddButton({
    Text = "Stop Spectating",
    Func = function()
        Camera.CameraSubject = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        Library:Notify("Reset camera to local player.", 2)
    end
})

-- =====================================================================
-- TAB 5 : ESP
-- =====================================================================
local TabESP        = Window:AddTab("ESP")
local PlayerESPBox  = TabESP:AddLeftGroupbox("Player ESP")
local MobESPBox     = TabESP:AddRightGroupbox("Mob ESP")
local VisBox        = TabESP:AddLeftGroupbox("Visuals")

-- Build an identical control set into a box under a key prefix (PlayerESP / MobESP),
-- so Players and Mobs each get their own independent ESP instead of one shared block.
local function buildESPControls(box, prefix, defColor, keyText)
    box:AddToggle(prefix .. "_Enable", { Text = "Enable", Default = false })
        :AddKeyPicker(prefix .. "_Key", { Default = "None", SyncToggleState = true, Mode = "Toggle", Text = keyText })
    box:AddToggle(prefix .. "_Rainbow", { Text = "Rainbow", Default = false })
    box:AddToggle(prefix .. "_Box", { Text = "Box", Default = true })
    box:AddToggle(prefix .. "_Name", { Text = "Name", Default = true })
    box:AddToggle(prefix .. "_Health", { Text = "Health", Default = false })
    box:AddToggle(prefix .. "_Distance", { Text = "Distance", Default = false })
    box:AddToggle(prefix .. "_Tracer", { Text = "Tracer", Default = false })
    box:AddToggle(prefix .. "_Highlight", { Text = "Highlight (Chams)", Default = false })
        :AddColorPicker(prefix .. "_Color", { Default = defColor, Title = keyText .. " Color" })
end
buildESPControls(PlayerESPBox, "PlayerESP", Color3.fromRGB(0, 150, 255), "Player ESP")
buildESPControls(MobESPBox, "MobESP", Color3.fromRGB(255, 80, 80), "Mob ESP")

VisBox:AddSlider("MaxESPDistance", { Text = "Max Distance", Default = 1000, Min = 100, Max = 5000, Rounding = 0 })
VisBox:AddDropdown("TracerOrigin", {
    Values  = { "Bottom", "Center", "Mouse" },
    Default = "Bottom",
    Multi   = false,
    Text    = "Tracer Origin",
    Tooltip = "Where tracers start: screen bottom, screen centre, or your mouse.",
})

-- =============================================================================
-- UNIFIED ESP RENDERER (Players + Mobs, each with its own per-element toggles)
-- =============================================================================
local ESPCache = {}    -- model -> { Box, Tracer, Name, Distance, HealthBg, HealthBar, Highlight }
local chamsCache = {}  -- legacy: kept only so the Unload routine's chams loop is a no-op

local function makeESP(model)
    if ESPCache[model] then return ESPCache[model] end
    local ok, d = pcall(function()
        local t = {
            Box       = Drawing.new("Square"),
            Tracer    = Drawing.new("Line"),
            Name      = Drawing.new("Text"),
            Distance  = Drawing.new("Text"),
            HealthBg  = Drawing.new("Line"),
            HealthBar = Drawing.new("Line"),
        }
        t.Box.Thickness = 1.5; t.Box.Filled = false; t.Box.Visible = false
        t.Tracer.Thickness = 1; t.Tracer.Visible = false
        t.Name.Size = 13; t.Name.Center = true; t.Name.Outline = true; t.Name.Visible = false
        t.Distance.Size = 13; t.Distance.Center = true; t.Distance.Outline = true; t.Distance.Visible = false
        t.HealthBg.Thickness = 3; t.HealthBg.Color = Color3.fromRGB(40, 0, 0); t.HealthBg.Visible = false
        t.HealthBar.Thickness = 3; t.HealthBar.Visible = false
        return t
    end)
    if ok and d then ESPCache[model] = d; return d end
    return nil
end
local function hideESP(d)
    if not d then return end
    d.Box.Visible = false; d.Tracer.Visible = false; d.Name.Visible = false
    d.Distance.Visible = false; d.HealthBg.Visible = false; d.HealthBar.Visible = false
end
local function destroyESP(model)
    local d = ESPCache[model]
    if not d then return end
    for _, v in pairs(d) do pcall(function() v:Destroy() end) end
    ESPCache[model] = nil
end

-- ESP RenderStepped Loop (unified Player + Mob)
AddConnection(RunService.RenderStepped:Connect(function()
    local maxDist = Options.MaxESPDistance and Options.MaxESPDistance.Value or 1000
    local tracerOrigin = (Options.TracerOrigin and Options.TracerOrigin.Value) or "Bottom"
    local function tracerFrom()
        if tracerOrigin == "Mouse" then return UserInputService:GetMouseLocation()
        elseif tracerOrigin == "Center" then return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        else return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y) end
    end

    local seen = {}
    local function on(key) return Toggles[key] and Toggles[key].Value end

    local function renderOne(model, root, hum, name, prefix)
        if not on(prefix .. "_Enable") then return end
        if not (root and hum and hum.Health > 0) then return end
        local dist = (Camera.CFrame.Position - root.Position).Magnitude
        if dist > maxDist then return end

        local d = makeESP(model)
        if not d then return end
        seen[model] = true

        local rainbow = on(prefix .. "_Rainbow") and Color3.fromHSV((tick() % 5) / 5, 1, 1) or nil
        local col = rainbow or (Options[prefix .. "_Color"] and Options[prefix .. "_Color"].Value) or Color3.fromRGB(255, 255, 255)

        -- Highlight (chams) -- works regardless of on-screen / 2D visibility.
        if on(prefix .. "_Highlight") then
            if not d.Highlight then
                local h = Instance.new("Highlight")
                h.FillTransparency = 0.5; h.OutlineTransparency = 0
                h.Adornee = model; h.Parent = model
                d.Highlight = h
            end
            d.Highlight.FillColor = col; d.Highlight.OutlineColor = col
        elseif d.Highlight then
            d.Highlight:Destroy(); d.Highlight = nil
        end

        local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
        if not onScreen then hideESP(d); return end
        local sizeX, sizeY = 2000 / screenPos.Z, 3000 / screenPos.Z

        d.Box.Visible = on(prefix .. "_Box")
        if d.Box.Visible then
            d.Box.Size = Vector2.new(sizeX, sizeY)
            d.Box.Position = Vector2.new(screenPos.X - sizeX / 2, screenPos.Y - sizeY / 2)
            d.Box.Color = col
        end

        if on(prefix .. "_Health") then
            local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            local barPos = Vector2.new(screenPos.X - sizeX / 2 - 6, screenPos.Y - sizeY / 2)
            d.HealthBg.From = barPos; d.HealthBg.To = Vector2.new(barPos.X, barPos.Y + sizeY); d.HealthBg.Visible = true
            d.HealthBar.From = Vector2.new(barPos.X, barPos.Y + sizeY)
            d.HealthBar.To = Vector2.new(barPos.X, barPos.Y + sizeY - (sizeY * pct))
            d.HealthBar.Color = Color3.fromHSV(pct * 0.33, 1, 1); d.HealthBar.Visible = true
        else
            d.HealthBg.Visible = false; d.HealthBar.Visible = false
        end

        local nameOn = on(prefix .. "_Name")
        d.Name.Visible = nameOn
        if nameOn then
            d.Name.Text = name
            d.Name.Position = Vector2.new(screenPos.X, screenPos.Y - (1500 / screenPos.Z) - 15)
            d.Name.Color = col
        end

        d.Distance.Visible = on(prefix .. "_Distance")
        if d.Distance.Visible then
            d.Distance.Text = string.format("%dm", math.floor(dist))
            d.Distance.Position = Vector2.new(screenPos.X, screenPos.Y - (1500 / screenPos.Z) - (nameOn and 27 or 15))
            d.Distance.Color = col
        end

        d.Tracer.Visible = on(prefix .. "_Tracer")
        if d.Tracer.Visible then
            d.Tracer.From = tracerFrom(); d.Tracer.To = Vector2.new(screenPos.X, screenPos.Y); d.Tracer.Color = col
        end
    end

    -- Players
    if on("PlayerESP_Enable") then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                renderOne(p.Character, p.Character:FindFirstChild("HumanoidRootPart"),
                    p.Character:FindFirstChildOfClass("Humanoid"), p.DisplayName or p.Name, "PlayerESP")
            end
        end
    end

    -- Mobs (from the universal Entity Source)
    if on("MobESP_Enable") then
        for _, m in ipairs(getEntities()) do
            renderOne(m, getMobHRP(m), m:FindFirstChildOfClass("Humanoid"),
                (string.gsub(m.Name, "%d+$", "")), "MobESP")
        end
    end

    -- Cleanup: hide/destroy ESP for anything not rendered this frame.
    for model, d in pairs(ESPCache) do
        if not model.Parent then
            destroyESP(model)
        elseif not seen[model] then
            hideESP(d)
            if d.Highlight then d.Highlight:Destroy(); d.Highlight = nil end
        end
    end
end))

-- Chams are now handled per-type via the "Highlight (Chams)" toggle in each ESP box,
-- driven by the unified renderer above.

-- FullBright (in the ESP > Visuals box)
VisBox:AddToggle("FullBrightActive", {
    Text    = "FullBright",
    Default = false,
})
Toggles.FullBrightActive:AddKeyPicker("FullBrightKey", { Default = "None", SyncToggleState = true, Mode = "Toggle", Text = "FullBright" })

Toggles.FullBrightActive:OnChanged(function()
    if Toggles.FullBrightActive.Value then
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.ClockTime = 14
    else
        Lighting.Ambient = OriginalLighting.Ambient
        Lighting.OutdoorAmbient = OriginalLighting.OutdoorAmbient
        Lighting.ClockTime = OriginalLighting.ClockTime or 12
    end
end)

-- =====================================================================
-- TAB 6 : UTILITIES (Server & Client)
-- =====================================================================
local TabUtils      = Window:AddTab("Utilities")
local UtilLeft      = TabUtils:AddLeftGroupbox("Performance")
local UtilRight     = TabUtils:AddRightGroupbox("Connections")

-- FPS Booster Control
UtilLeft:AddToggle("FPSBoosterActive", {
    Text    = "FPS Booster",
    Default = false,
})

local FPSBoosterCache = {}

local function toggleFPSBooster(enable)
    if enable then
        task.spawn(function()
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if not FPSBoosterCache[obj] then
                    if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke") or obj:IsA("Sparkles") or obj:IsA("Fire") then
                        FPSBoosterCache[obj] = { Enabled = obj.Enabled }
                        obj.Enabled = false
                    elseif obj:IsA("Decal") or obj:IsA("Texture") then
                        FPSBoosterCache[obj] = { Texture = obj.Texture }
                        obj.Texture = ""
                    elseif obj:IsA("PostEffect") then
                        FPSBoosterCache[obj] = { Enabled = obj.Enabled }
                        obj.Enabled = false
                    end
                end
            end
        end)
    else
        for obj, data in pairs(FPSBoosterCache) do
            pcall(function()
                if data.Enabled ~= nil then
                    obj.Enabled = data.Enabled
                elseif data.Texture ~= nil then
                    obj.Texture = data.Texture
                end
            end)
        end
        table.clear(FPSBoosterCache)
    end
end

Toggles.FPSBoosterActive:OnChanged(function()
    toggleFPSBooster(Toggles.FPSBoosterActive.Value)
end)

AddConnection(Workspace.DescendantAdded:Connect(function(obj)
    if Toggles.FPSBoosterActive and Toggles.FPSBoosterActive.Value then
        if not FPSBoosterCache[obj] then
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke") or obj:IsA("Sparkles") or obj:IsA("Fire") then
                FPSBoosterCache[obj] = { Enabled = obj.Enabled }
                obj.Enabled = false
            elseif obj:IsA("Decal") or obj:IsA("Texture") then
                FPSBoosterCache[obj] = { Texture = obj.Texture }
                obj.Texture = ""
            elseif obj:IsA("PostEffect") then
                FPSBoosterCache[obj] = { Enabled = obj.Enabled }
                obj.Enabled = false
            end
        end
    end
end))

-- Anti-AFK
UtilLeft:AddToggle("AntiAFK", {
    Text    = "Anti-AFK",
    Default = false,
    Tooltip = "Bypasses idle kick using VirtualUser interactions",
})

local idleConnection
Toggles.AntiAFK:OnChanged(function()
    if Toggles.AntiAFK.Value then
        idleConnection = LocalPlayer.Idled:Connect(function()
            VirtualUser:Button2Down(Vector2.new(0,0), Camera.CFrame)
            task.wait(1)
            VirtualUser:Button2Up(Vector2.new(0,0), Camera.CFrame)
        end)
    else
        if idleConnection then
            idleConnection:Disconnect()
            idleConnection = nil
        end
    end
end)

-- FPS Cap (executor-gated; 0 = unlimited)
UtilLeft:AddSlider("FPSCap", { Text = "FPS Cap (0 = Unlimited)", Default = 0, Min = 0, Max = 360, Rounding = 0 })
Options.FPSCap:OnChanged(function()
    if setfpscap then
        pcall(setfpscap, (Options.FPSCap.Value <= 0) and 9999 or Options.FPSCap.Value)
    end
end)

-- No Shadows
UtilLeft:AddToggle("NoShadows", { Text = "No Shadows", Default = false,
    Tooltip = "Disables global shadows for extra FPS." })
Toggles.NoShadows:OnChanged(function()
    pcall(function() Lighting.GlobalShadows = not Toggles.NoShadows.Value end)
end)

-- Low Detail Terrain (flatten water for FPS)
UtilLeft:AddToggle("LowDetail", { Text = "Low Detail Terrain", Default = false,
    Tooltip = "Removes water waves/reflection for extra FPS." })
Toggles.LowDetail:OnChanged(function()
    pcall(function()
        local t = Workspace:FindFirstChildOfClass("Terrain")
        if not t then return end
        if Toggles.LowDetail.Value then
            t.WaterWaveSize = 0; t.WaterWaveSpeed = 0; t.WaterReflectance = 0; t.WaterTransparency = 1
        else
            t.WaterWaveSize = 0.15; t.WaterWaveSpeed = 10; t.WaterReflectance = 1; t.WaterTransparency = 0.3
        end
    end)
end)

-- Disable Character Effects (clears particles/trails on every character for FPS in fights)
UtilLeft:AddToggle("NoCharEffects", { Text = "No Character Effects", Default = false,
    Tooltip = "Disables particle/trail effects on all characters (re-checks as they spawn)." })
AddThread(task.spawn(function()
    while task.wait(0.5) do
        if Toggles.NoCharEffects and Toggles.NoCharEffects.Value then
            pcall(function()
                local living = resolveContainer()
                local roots = { Players.LocalPlayer.Character }
                for _, p in ipairs(Players:GetPlayers()) do table.insert(roots, p.Character) end
                if living then table.insert(roots, living) end
                for _, container in ipairs(roots) do
                    if container then
                        for _, e in ipairs(container:GetDescendants()) do
                            if (e:IsA("ParticleEmitter") or e:IsA("Trail") or e:IsA("Smoke") or e:IsA("Fire") or e:IsA("Sparkles")) and e.Enabled then
                                e.Enabled = false
                            end
                        end
                    end
                end
            end)
        end
    end
end))

-- Server Hopper
UtilRight:AddButton({
    Text = "Server Hopper",
    Func = function()
        Library:Notify("Searching for a new server...", 3)
        task.spawn(function()
            local servers = {}
            local success, list = pcall(function()
                return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"))
            end)
            
            if success and list and list.data then
                for _, server in ipairs(list.data) do
                    if server.playing < server.maxPlayers and server.id ~= game.JobId then
                        table.insert(servers, server.id)
                    end
                end
            end
            
            if #servers > 0 then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[math.random(1, #servers)], LocalPlayer)
            else
                Library:Notify("No suitable servers found.", 3)
            end
        end)
    end
})

-- Rejoin Server
UtilRight:AddButton({
    Text = "Rejoin Server",
    Func = function()
        Library:Notify("Reconnecting to server...", 3)
        if #Players:GetPlayers() <= 1 then
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end
    end
})

-- Webhook (generic Discord logger). The transport is universal; wire the
-- game-specific TRIGGERS by calling sendWebhook("Title", "Description") from
-- your own events (boss kill, rare drop, etc.).
local WebhookBox = TabUtils:AddRightGroupbox("Webhook")
WebhookBox:AddToggle("WebhookEnabled", { Text = "Enable Webhook", Default = false })
WebhookBox:AddInput("WebhookURL", { Text = "Webhook URL", Placeholder = "https://discord.com/api/webhooks/..." })
WebhookBox:AddButton({
    Text = "Test Webhook",
    Func = function()
        if not (Toggles.WebhookEnabled and Toggles.WebhookEnabled.Value) then
            Library:Notify("Enable the webhook first.", 3); return
        end
        local url = Options.WebhookURL and Options.WebhookURL.Value
        if type(url) ~= "string" or url == "" or not string.find(url, "discord") then
            Library:Notify("Enter a valid Discord webhook URL.", 3); return
        end
        sendWebhook("Base UI", "Webhook test -- if you see this, it works!")
        Library:Notify("Test sent.", 2)
    end,
})

-- =====================================================================
-- TAB 7 : SETTINGS & CONFIGS
-- =====================================================================
local TabSettings   = Window:AddTab("Settings")
-- The real Theme controls live in the "Theme" box (ThemeManager) and the real config UI in
-- "Save Profiles" (SaveManager), both built below -- so the old empty/duplicate boxes are gone.
-- SetLeft is kept (renamed "Menu") to host Menu Keybinds and Unload settings.
local SetLeft       = TabSettings:AddLeftGroupbox("Menu")

SetLeft:AddLabel("Menu Toggle"):AddKeyPicker("UAP_Menu", { Default = "RightShift", NoUI = true, Text = "Menu Toggle" })
Library.ToggleKeybind = Options.UAP_Menu

SetLeft:AddToggle("ShowKeybindsList", {
    Text = "Show Keybinds List",
    Default = true,
    Callback = function(v)
        if Library.KeyList and Library.KeyList.SetVisibility then
            Library.KeyList:SetVisibility(v)
        end
    end
})

-- Theme Manager Initialization
ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("UAPAutomation")
ThemeManager:ApplyToTab(TabSettings)

-- Config Manager Initialization
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
SaveManager:SetFolder("UAPAutomation/configs")
SaveManager:BuildConfigSection(TabSettings)

-- Entity Source (fill in per game). All mob features (Farm, ESP, Network, Safe
-- Area triggers) resolve through this dot-path under Workspace.
local EntityBox = TabSettings:AddRightGroupbox("Entity Source")
EntityBox:AddInput("EntityPath", {
    Text = "Mob Container Path",
    Default = DEFAULT_ENTITY_PATH,
    Placeholder = "World.Entities",
    Tooltip = "Dot-path under Workspace where mobs live. e.g. Living, World.Entities, Game.Mobs",
})
EntityBox:AddLabel("Every mob feature reads from this path.", true)

-- Teardown and Unload Button
SetLeft:AddButton({
    Text = "Unload Menu",
    Func = function()
        -- Disconnect connections
        for _, conn in ipairs(Connections) do
            if typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
        end
        table.clear(Connections)

        if idleConnection then
            idleConnection:Disconnect()
            idleConnection = nil
        end

        -- Kill coroutines
        for _, t in ipairs(Threads) do
            pcall(task.cancel, t)
        end
        table.clear(Threads)

        -- Clean up Highlight visualizers
        for player, cham in pairs(chamsCache) do
            if cham then cham:Destroy() end
        end
        table.clear(chamsCache)

        -- Clean up ESP drawings
        if FOVCircle then FOVCircle:Destroy() end
        for player, drawings in pairs(ESPCache) do
            for _, drawing in pairs(drawings) do
                drawing:Destroy()
            end
        end
        table.clear(ESPCache)

        -- Disable FPS booster and clear cache
        toggleFPSBooster(false)

        -- Restore original hitboxes
        for root, data in pairs(OriginalHitboxes) do
            pcall(function()
                if root and root.Parent then
                    root.Size = data.Size
                    root.CanCollide = data.CanCollide
                    root.Transparency = data.Transparency
                end
            end)
        end
        table.clear(OriginalHitboxes)

        -- Restore original lighting configurations
        Lighting.Ambient = OriginalLighting.Ambient
        Lighting.OutdoorAmbient = OriginalLighting.OutdoorAmbient
        Lighting.ClockTime = OriginalLighting.ClockTime or 12

        -- Restore WalkSpeed/JumpPower defaults if humanoid exists
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end

        -- Destroy Linoria UI
        Library:Unload()
    end,
    DoubleClick = true,
    Tooltip = "Double-click to completely clean and unload the script.",
})

-- =====================================================================
-- HUB INITIALIZATION
-- =====================================================================
Library:Notify("Base Framework Loaded Successfully.", 3)

-- =====================================================================
-- TAB: AUTO PARRY
-- =====================================================================
do

local TabParryCombat = TabParry
local TabParryBuilder = TabParry
local TabParrySettings = TabSettings

local AddConn = AddConnection
local Adapter = {}
local ENEMY_CONTAINERS = { "Living", "Enemies", "Characters", "NPCs", "Mobs", "Entities" }

function Adapter.getEnemies()
    local out, seen = {}, {}
    local function consider(inst)
        if not inst or seen[inst] or not inst:IsA("Model") then return end
        if inst == LocalPlayer.Character then return end
        local hum = inst:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then seen[inst] = true; table.insert(out, inst) end
    end
    for _, name in ipairs(ENEMY_CONTAINERS) do
        local folder = Workspace:FindFirstChild(name)
        if folder then for _, c in ipairs(folder:GetChildren()) do consider(c) end end
    end
    for _, c in ipairs(Workspace:GetChildren()) do consider(c) end
    return out
end

function Adapter.getAnimator(model)
    local hum = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
    return hum and hum:FindFirstChildOfClass("Animator")
end

function Adapter.isPlayer(model)
    return Players:GetPlayerFromCharacter(model) ~= nil
        or (model.Name ~= "" and Players:FindFirstChild(model.Name) ~= nil)
end

local _blockRemote, _blockResolved
local function resolveBlockRemote()
    if _blockResolved then return _blockRemote end
    _blockResolved = true
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local combat = remotes and remotes:FindFirstChild("Combat")
        local block = combat and combat:FindFirstChild("Block")
        if block and block:IsA("RemoteEvent") then _blockRemote = block end
    end)
    return _blockRemote
end

local _keyHeld = false
function Adapter.setBlock(state, opts)
    opts = opts or {}
    local mode = opts.action or "Auto"
    local keyStr = opts.key or "F"
    local remote = (mode ~= "Key") and resolveBlockRemote() or nil
    if remote and mode ~= "Key" then
        pcall(function() remote:FireServer(state and "Start" or "Stop") end)
        return true
    end
    if keyStr == "MouseButton2" or keyStr == "M2" then
        if state and not _keyHeld then
            _keyHeld = true
            pcall(function()
                local loc = UserInputService:GetMouseLocation()
                VIM:SendMouseButtonEvent(loc.X, loc.Y, 1, true, game, 1)
            end)
        elseif (not state) and _keyHeld then
            _keyHeld = false
            pcall(function()
                local loc = UserInputService:GetMouseLocation()
                VIM:SendMouseButtonEvent(loc.X, loc.Y, 1, false, game, 1)
            end)
        end
        return true
    end
    local key = pcall(function() return Enum.KeyCode[keyStr] end) and Enum.KeyCode[keyStr] or Enum.KeyCode.F
    if state and not _keyHeld then
        _keyHeld = true
        pcall(function() VIM:SendKeyEvent(true, key, false, game) end)
    elseif (not state) and _keyHeld then
        _keyHeld = false
        pcall(function() VIM:SendKeyEvent(false, key, false, game) end)
    end
    return true
end

function Adapter.dodge(direction)
    local keyMap = { Left = Enum.KeyCode.A, Right = Enum.KeyCode.D, Back = Enum.KeyCode.S }
    local key = keyMap[direction]
    if not key then return end
    task.spawn(function()
        pcall(function() VIM:SendKeyEvent(true, key, false, game) end)
        task.wait(0.15)
        pcall(function() VIM:SendKeyEvent(false, key, false, game) end)
    end)
end

-- =============================================================================
-- STATE + TIMING DATABASE
-- learnedAttacks[id] = { frac, delayMs, name, enabled, minDist, maxDist,
--                         samples, dodge, repeatCount, repeatDelay }
-- =============================================================================
local learnedAttacks  = {}
local blacklist       = {}
local playerWhitelist = {}
local pendingAttacks  = {}
local captureArmed    = false
local DB_FILE         = "UAP/timings.json"
local priorityTarget  = nil
local lastAttacker    = nil

local function saveDB()
    if not (writefile and isfolder) then return end
    pcall(function()
        if makefolder and not isfolder("UAP") then makefolder("UAP") end
        writefile(DB_FILE, HttpService:JSONEncode({
            attacks   = learnedAttacks,
            blacklist = blacklist,
            whitelist = playerWhitelist,
        }))
    end)
end
local function loadDB()
    if not (isfile and readfile) then return end
    pcall(function()
        if isfile(DB_FILE) then
            local data = HttpService:JSONDecode(readfile(DB_FILE))
            if type(data) == "table" then
                if data.attacks then
                    learnedAttacks  = data.attacks
                    blacklist       = (type(data.blacklist) == "table") and data.blacklist or {}
                    playerWhitelist = (type(data.whitelist) == "table") and data.whitelist or {}
                else
                    learnedAttacks = data
                end
            end
        end
    end)
end
loadDB()

local function dbCount()
    local n = 0; for _ in pairs(learnedAttacks) do n = n + 1 end; return n
end

local function b64encode(data)
    if crypt and crypt.base64encode then return crypt.base64encode(data) end
    if crypt and crypt.base64 and crypt.base64.encode then return crypt.base64.encode(data) end
    local B = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x)
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
        return B:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end
local function b64decode(data)
    if crypt and crypt.base64decode then return crypt.base64decode(data) end
    if crypt and crypt.base64 and crypt.base64.decode then return crypt.base64.decode(data) end
    local B = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^' .. B .. '=]', '')
    return (data:gsub('=', ''):gsub('.', function(x)
        local r, f = '', (B:find(x, 1, true) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if #x ~= 8 then return '' end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0) end
        return string.char(c)
    end))
end

-- =============================================================================
-- LIVE LOG BUFFER (rendered by the Logger panel)
-- =============================================================================
local logRows  = {}
local LOG_MAX  = 120
local logDedup = {} -- [key] = tick()

local function pushLog(id, enemyName, animName, dist, status, enemyModel)
    local dedupKey = (enemyName or "") .. "_" .. tostring(id)
    local dedupSec = (Options and Options.UAP_LogDedup and Options.UAP_LogDedup.Value) or 2
    local now = tick()
    if dedupSec > 0 and logDedup[dedupKey] and (now - logDedup[dedupKey]) < dedupSec then
        return
    end
    logDedup[dedupKey] = now
    local foundIdx = nil
    for idx, r in ipairs(logRows) do
        if r.id == tostring(id) and r.enemy == (enemyName or "?") then
            foundIdx = idx
            break
        end
    end
    if foundIdx then
        local existing = table.remove(logRows, foundIdx)
        existing.t = os.date("%X")
        existing.dist = math.floor(dist or 0)
        existing.status = status or "?"
        existing.count = (existing.count or 1) + 1
        existing.model = enemyModel or existing.model
        table.insert(logRows, 1, existing)
    else
        table.insert(logRows, 1, {
            t = os.date("%X"), id = tostring(id),
            enemy = enemyName or "?",
            anim  = animName or "?",
            dist  = math.floor(dist or 0),
            status = status or "?",
            count = 1,
            model = enemyModel,
        })
    end
    while #logRows > LOG_MAX do table.remove(logRows) end
end

-- =============================================================================
-- DETECTION CORE
-- =============================================================================
local lastParry, blockHeld = 0, false

local function setBlock(state)
    if state == blockHeld then return end
    blockHeld = state
    Adapter.setBlock(state, {
        action = (Options.UAP_Action and Options.UAP_Action.Value) or "Auto",
        key    = (Options.UAP_Key and Options.UAP_Key.Value) or "F",
    })
end

local function isAttackTrack(track)
    local p = track.Priority
    return p == Enum.AnimationPriority.Action  or p == Enum.AnimationPriority.Action2
        or p == Enum.AnimationPriority.Action3 or p == Enum.AnimationPriority.Action4
end

local function myHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function enemyDist(model)
    local hrp, theirs = myHRP(), (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
    if not hrp or not theirs then return math.huge end
    return (hrp.Position - theirs.Position).Magnitude
end

local function inFOV(model)
    local limit = Options.UAP_FOV and Options.UAP_FOV.Value or 180
    if limit >= 180 then return true end
    local hrp, theirs = myHRP(), (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
    if not hrp or not theirs then return false end
    local dir = (theirs.Position - hrp.Position)
    if dir.Magnitude < 0.1 then return true end
    local ang = math.deg(math.acos(math.clamp(hrp.CFrame.LookVector:Dot(dir.Unit), -1, 1)))
    return ang <= limit
end

local function defaultFrac() return (Options.UAP_DefaultFrac and Options.UAP_DefaultFrac.Value or 45) / 100 end

local function triggerParry(track, frac, info, model)
    local lead   = (Options.UAP_Offset and Options.UAP_Offset.Value or 0) + 60
    local hold   = (Options.UAP_BlockHold and Options.UAP_BlockHold.Value) or 220
    local cooldn = 0.35
    local pingMs = LocalPlayer:GetNetworkPing() * 1000
    frac = math.clamp(frac or 0.45, 0.02, 0.98)

    local feintOn    = Toggles.UAP_Feint and Toggles.UAP_Feint.Value
    local feintPct   = ((Options.UAP_FeintThresh and Options.UAP_FeintThresh.Value) or 40) / 100
    local notifyOn   = Toggles.UAP_Notify and Toggles.UAP_Notify.Value
    local notifyMode = (Options.UAP_NotifyStyle and Options.UAP_NotifyStyle.Value) or "Library"
    local faceOn     = Toggles.UAP_FaceAttacker and Toggles.UAP_FaceAttacker.Value
    local dodge      = info and info.dodge or "None"
    local repCount   = (info and info.repeatCount and info.repeatCount > 1) and info.repeatCount or 1
    local repDelay   = (info and info.repeatDelay) or 0.35
    local useDelay   = info and info.delayMs and info.delayMs > 0

    task.spawn(function()
        local length = track.Length
        -- ---- wait for hit timing ------------------------------------------------
        if useDelay then
            local waitSec = math.max(0, (info.delayMs - pingMs * 0.5)) / 1000
            if waitSec > 0 then
                local t0 = os.clock()
                while track.IsPlaying and (os.clock() - t0) < waitSec do
                    task.wait()
                    if Library.Unloaded then return end
                end
            end
            if feintOn and not track.IsPlaying then
                if length and length > 0 and track.TimePosition < feintPct * length then return end
            end
        elseif length and length > 0 then
            local hitTime = frac * length
            local speed = (track.Speed and track.Speed > 0) and track.Speed or 1
            local preempt = ((lead + pingMs * 0.5) / 1000) * speed
            local target = math.max(0, hitTime - preempt)
            while track.IsPlaying and track.TimePosition < target do
                task.wait()
                if Library.Unloaded then return end
            end
            if feintOn and not track.IsPlaying and track.TimePosition < feintPct * length then return end
            if not track.IsPlaying and track.TimePosition < hitTime * 0.5 then return end
        else
            local d = math.max(0, 90 - pingMs) / 1000
            if d > 0 then task.wait(d) end
        end

        if tick() - lastParry < cooldn then return end
        lastParry = tick()

        -- ---- face attacker ------------------------------------------------------
        if faceOn and model then
            lastAttacker = model
            pcall(function()
                local hrp = myHRP()
                local theirs = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                if hrp and theirs then
                    local flat = Vector3.new(theirs.Position.X, hrp.Position.Y, theirs.Position.Z)
                    if (Toggles.UAP_FaceSmooth and Toggles.UAP_FaceSmooth.Value) then
                        local tgt = CFrame.lookAt(hrp.Position, flat)
                        for _ = 1, 5 do
                            hrp.CFrame = hrp.CFrame:Lerp(tgt, 0.4)
                            task.wait()
                        end
                    else
                        hrp.CFrame = CFrame.lookAt(hrp.Position, flat)
                    end
                end
            end)
        end

        -- ---- dodge direction ----------------------------------------------------
        if dodge and dodge ~= "None" then Adapter.dodge(dodge) end

        -- ---- block (with repeat) ------------------------------------------------
        for rep = 1, repCount do
            setBlock(true)
            task.wait(hold / 1000)
            setBlock(false)
            if rep < repCount then task.wait(repDelay) end
        end

        -- ---- notification -------------------------------------------------------
        if notifyOn and notifyMode ~= "None" then
            local nm = (info and info.name) or "?"
            local aid = tostring(track.Animation and tostring(track.Animation.AnimationId):match("%d+") or "?")
            local msg = ("Parried: %s #%s"):format(nm, aid)
            if notifyMode == "Library" then Library:Notify(msg, 1.5)
            elseif notifyMode == "Print" then print("[UAP] " .. msg) end
        end
    end)
end

local function onAnim(model, track)
    local id = tostring(track.Animation and track.Animation.AnimationId or ""):match("%d+")
    if not id then return end
    if track.Speed and track.Speed >= 50 then return end

    local animName = (track.Animation and track.Animation.Name) or track.Name or "?"
    local dist = enemyDist(model)

    -- blacklist (always logged)
    if blacklist[id] then
        pushLog(id, model.Name, animName, dist, "BLACKLIST", model)
        return
    end

    -- player whitelist
    if Adapter.isPlayer(model) and playerWhitelist[model.Name] then
        pushLog(id, model.Name, animName, dist, "SKIP:whitelisted", model)
        return
    end

    -- log radius gate (anything beyond log radius is completely ignored)
    local logRadius = (Options.UAP_LogRadius and Options.UAP_LogRadius.Value) or 300
    if dist > logRadius then return end

    local skipReason = nil
    if Adapter.isPlayer(model) then
        if Toggles.UAP_IgnorePlayers and Toggles.UAP_IgnorePlayers.Value then
            skipReason = "SKIP:player"
        end
    else
        if Toggles.UAP_IgnoreNPCs and Toggles.UAP_IgnoreNPCs.Value then
            skipReason = "SKIP:npc"
        end
    end
    if not skipReason and dist > (Options.UAP_MaxDist and Options.UAP_MaxDist.Value or 150) then
        skipReason = "SKIP:dist"
    end
    if not skipReason and not inFOV(model) then
        skipReason = "SKIP:fov"
    end
    if not skipReason and not isAttackTrack(track) then
        skipReason = "SKIP:prio"
    end
    if not skipReason then
        local prio = (Options.UAP_Priority and Options.UAP_Priority.Value) or "All"
        if prio ~= "All" and priorityTarget and model ~= priorityTarget then
            skipReason = "SKIP:priority"
        end
    end

    local info  = learnedAttacks[id]
    local isNew = info == nil

    pushLog(id, model.Name, animName, dist, skipReason or (isNew and "NEW" or "known"), model)

    -- hitbox visual (highlight enemy during attack)
    if not skipReason and (Toggles.UAP_Hitbox and Toggles.UAP_Hitbox.Value) then
        pcall(function()
            local old = model:FindFirstChild("UAP_Highlight")
            if old then old:Destroy() end
            
            local hl = Instance.new("Highlight")
            hl.Name = "UAP_Highlight"
            hl.FillColor = Color3.fromRGB(0, 255, 0) -- Green neon
            hl.FillTransparency = 0.5
            hl.OutlineColor = Color3.fromRGB(0, 255, 0)
            hl.OutlineTransparency = 0
            hl.Parent = model
            
            task.spawn(function()
                local feintPct = ((Options.UAP_FeintThresh and Options.UAP_FeintThresh.Value) or 40) / 100
                local length = track.Length
                while track.IsPlaying do task.wait() end
                
                local wasFeint = false
                if length and length > 0 and track.TimePosition < feintPct * length then
                    wasFeint = true
                end
                
                if wasFeint then
                    pcall(function()
                        if hl and hl.Parent then
                            hl.FillColor = Color3.fromRGB(255, 255, 0) -- Yellow
                            hl.OutlineColor = Color3.fromRGB(255, 255, 0)
                            task.wait(1.0)
                        end
                    end)
                end
                pcall(function() if hl and hl.Parent then hl:Destroy() end end)
            end)
        end)
    end

    -- parry-decision only below
    if skipReason then return end

    if captureArmed then
        if isNew then
            learnedAttacks[id] = {
                frac = defaultFrac(), enabled = true,
                name = animName .. " (" .. model.Name .. ")", samples = 0,
            }
            saveDB()
            if refreshDbDropdown then refreshDbDropdown() end
        end
        captureArmed = false
    end

    if Toggles.UAP_Learn and Toggles.UAP_Learn.Value then
        table.insert(pendingAttacks, { id = id, t = os.clock(), track = track, model = model })
        if #pendingAttacks > 12 then table.remove(pendingAttacks, 1) end
    end

    if info then
        if info.minDist and dist < info.minDist then return end
        if info.maxDist and info.maxDist > 0 and dist > info.maxDist then return end
    end

    if Toggles.UAP_Enabled and Toggles.UAP_Enabled.Value then
        local known     = info and info.enabled ~= false
        local unlearned = isNew and Toggles.UAP_ParryUnlearned and Toggles.UAP_ParryUnlearned.Value
        if known or unlearned then
            triggerParry(track, (info and info.frac) or defaultFrac(), info, model)
        end
    end
end

-- =============================================================================
-- MODEL HOOKS + POLLING
-- =============================================================================
local hooked = setmetatable({}, { __mode = "k" })
local function hookModel(model)
    if hooked[model] then return end
    local animator = Adapter.getAnimator(model)
    if not animator then return end
    hooked[model] = true
    AddConn(animator.AnimationPlayed:Connect(function(track)
        pcall(onAnim, model, track)
    end))
end

task.spawn(function()
    while not Library.Unloaded do
        local enemies = Adapter.getEnemies()
        local maxTargets = (Options.UAP_MaxTargets and Options.UAP_MaxTargets.Value) or 10

        -- sort by distance (nearest first) for priority + max-target cap
        table.sort(enemies, function(a, b) return enemyDist(a) < enemyDist(b) end)

        -- update priority target
        local prio = (Options.UAP_Priority and Options.UAP_Priority.Value) or "All"
        if prio == "Closest Only" and #enemies > 0 then
            priorityTarget = enemies[1]
        elseif prio == "Lowest HP" and #enemies > 0 then
            local best, bestHP = nil, math.huge
            for _, m in ipairs(enemies) do
                local hum = m:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health < bestHP then best = m; bestHP = hum.Health end
            end
            priorityTarget = best
        else
            priorityTarget = nil
        end

        for i = 1, math.min(#enemies, maxTargets) do hookModel(enemies[i]) end

        -- clean pending
        local now = os.clock()
        for i = #pendingAttacks, 1, -1 do
            if now - pendingAttacks[i].t > 2 then table.remove(pendingAttacks, i) end
        end
        -- clean dedup cache
        local t = tick()
        for k, v in pairs(logDedup) do if t - v > 10 then logDedup[k] = nil end end

        task.wait(0.4)
    end
end)

-- sticky face lock (continuous)
AddConn(RunService.Heartbeat:Connect(function()
    if Library.Unloaded then return end
    if not (Toggles.UAP_FaceAttacker and Toggles.UAP_FaceAttacker.Value) then return end
    if not (Toggles.UAP_FaceSticky and Toggles.UAP_FaceSticky.Value) then return end
    if not lastAttacker or not lastAttacker.Parent then return end
    pcall(function()
        local hrp = myHRP()
        local theirs = lastAttacker:FindFirstChild("HumanoidRootPart") or lastAttacker.PrimaryPart
        if not hrp or not theirs then return end
        local flat = Vector3.new(theirs.Position.X, hrp.Position.Y, theirs.Position.Z)
        if Toggles.UAP_FaceSmooth and Toggles.UAP_FaceSmooth.Value then
            hrp.CFrame = hrp.CFrame:Lerp(CFrame.lookAt(hrp.Position, flat), 0.15)
        else
            hrp.CFrame = CFrame.lookAt(hrp.Position, flat)
        end
    end)
end))

-- learn-on-damage
local function measureFrac(entry)
    local tr = entry.track
    local len = tr and tr.Length
    if not len or len <= 0 then return nil end
    local observed = (tr.IsPlaying and tr.TimePosition > 0) and tr.TimePosition or (os.clock() - entry.t)
    local pingSec = 0; pcall(function() pingSec = LocalPlayer:GetNetworkPing() end)
    observed = observed - pingSec * 0.5
    return math.clamp(observed / len, 0.02, 0.98)
end
local function onDamaged()
    if not (Toggles.UAP_Learn and Toggles.UAP_Learn.Value) then return end
    local best = pendingAttacks[#pendingAttacks]
    if not best then return end
    local frac = measureFrac(best)
    if not frac then return end
    local isNew = (learnedAttacks[best.id] == nil)
    local info = learnedAttacks[best.id] or { enabled = true, samples = 0, name = best.model.Name }
    info.frac = frac
    info.samples = (info.samples or 0) + 1
    learnedAttacks[best.id] = info
    saveDB()
    if refreshDbDropdown then refreshDbDropdown() end
    
    local animName = (best.track and best.track.Animation and best.track.Animation.Name) or (best.track and best.track.Name) or "?"
    if isNew then
        Library:Notify(("[Auto-Learn] New attack learned: %s (#%s) @ %d%%"):format(animName, best.id, math.floor(frac * 100)), 4)
    else
        Library:Notify(("[Auto-Learn] Updated %s (#%s) to %d%% (Samples: %d)"):format(animName, best.id, math.floor(frac * 100), info.samples), 3)
    end
end
local function hookHealth(char)
    local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
    if not hum then return end
    local last = hum.Health
    AddConn(hum.HealthChanged:Connect(function(h)
        if h < last - 0.5 then onDamaged() end
        last = h
    end))
end
if LocalPlayer.Character then hookHealth(LocalPlayer.Character) end
AddConn(LocalPlayer.CharacterAdded:Connect(hookHealth))

-- =============================================================================
-- LINORIA MENU
-- =============================================================================

local ContentProvider = game:GetService("ContentProvider")
local animsToLoad = {}
pcall(function()
    for _, v in ipairs(game:GetDescendants()) do
        if v:IsA("Animation") and v.AnimationId and v.AnimationId ~= "" then
            table.insert(animsToLoad, v)
        end
    end
end)
if #animsToLoad > 0 then
    Library:Notify("Preloading " .. #animsToLoad .. " animations, please wait...", 5)
    pcall(function() ContentProvider:PreloadAsync(animsToLoad) end)
    Library:Notify("Animations preloaded!", 3)
end






-- Forward decls: the Builder buttons open these floating panels (defined later).
local openViewer, openLogger, refreshDbDropdown

-- ---- Combat tab -------------------------------------------------------------
local CombatBox = TabParryCombat:AddLeftGroupbox("Auto Parry")
CombatBox:AddToggle("UAP_Enabled", { Text = "Enable Auto Parry", Default = false })
    :AddKeyPicker("UAP_Toggle", { Default = "None", SyncToggleState = true, Mode = "Toggle", Text = "Auto Parry" })
CombatBox:AddToggle("UAP_Learn", { Text = "Auto-Learn New Attacks", Default = false,
    Tooltip = "Measures an attack's hit timing when you get hit." })
CombatBox:AddToggle("UAP_ParryUnlearned", { Text = "Parry Unknown Attacks", Default = true,
    Tooltip = "Block unlearned attacks at the Default Hit %." })
CombatBox:AddToggle("UAP_Feint", { Text = "Feint Detection", Default = true,
    Tooltip = "Abort parry if the enemy cancels their attack animation early." })
CombatBox:AddSlider("UAP_FeintThresh", { Text = "Feint Threshold %", Default = 40, Min = 10, Max = 80, Rounding = 0, Suffix = "%",
    Tooltip = "If animation stops before this % of its length, treat as feint." })
CombatBox:AddToggle("UAP_Notify", { Text = "Parry Notifications", Default = true,
    Tooltip = "Show a notification when a parry triggers." })
CombatBox:AddSlider("UAP_Offset", { Text = "Timing Offset (ms)", Default = 0, Min = -200, Max = 200, Rounding = 0,
    Tooltip = "Raise block earlier (+) to beat lag, or later (-)." })
CombatBox:AddSlider("UAP_DefaultFrac", { Text = "Default Hit %", Default = 45, Min = 5, Max = 95, Rounding = 0, Suffix = "%" })
CombatBox:AddSlider("UAP_BlockHold", { Text = "Block Hold Time (ms)", Default = 220, Min = 50, Max = 1000, Rounding = 0, Suffix = "ms",
    Tooltip = "How long the block key/remote is held." })

local ActionBox = TabParryCombat:AddLeftGroupbox("Block Action")
ActionBox:AddDropdown("UAP_Action", { Values = { "Auto", "Remote", "Key" }, Default = "Auto", Multi = false, Text = "Parry Method",
    Tooltip = "Auto: use the game's block remote if found, else the key.\nRemote: force the block remote.\nKey: force a key press." })
ActionBox:AddDropdown("UAP_Key", { Values = { "F","Q","E","R","T","Z","X","C","V","MouseButton2" }, Default = "F", Multi = false, Text = "Parry Key (Key mode)" })

local TargetBox = TabParryCombat:AddRightGroupbox("Targeting")
TargetBox:AddToggle("UAP_IgnorePlayers", { Text = "Ignore Players", Default = false })
TargetBox:AddToggle("UAP_IgnoreNPCs", { Text = "Ignore NPCs/Mobs", Default = false })
TargetBox:AddSlider("UAP_FOV", { Text = "FOV Limit (deg)", Default = 180, Min = 10, Max = 180, Rounding = 0,
    Tooltip = "180 = all directions. Lower = only parry attackers in front." })
TargetBox:AddSlider("UAP_MaxDist", { Text = "Max Distance", Default = 150, Min = 10, Max = 500, Rounding = 0, Suffix = " studs" })
TargetBox:AddDropdown("UAP_Priority", { Values = { "All", "Closest Only", "Lowest HP" }, Default = "All", Multi = false, Text = "Target Priority",
    Tooltip = "All = parry every enemy. Closest Only / Lowest HP = single-target." })
TargetBox:AddSlider("UAP_MaxTargets", { Text = "Max Tracked Targets", Default = 10, Min = 1, Max = 15, Rounding = 0 })
TargetBox:AddToggle("UAP_Hitbox", { Text = "Hitbox Visuals", Default = false,
    Tooltip = "Highlight enemies when their attack animation is playing." })

local FaceBox = TabParryCombat:AddRightGroupbox("Face Lock")
FaceBox:AddToggle("UAP_FaceAttacker", { Text = "Face Attacker", Default = false,
    Tooltip = "Snap toward the attacker when parrying." })
FaceBox:AddToggle("UAP_FaceSticky", { Text = "Sticky Target", Default = false,
    Tooltip = "Continuously face the last attacker between parries." })
FaceBox:AddToggle("UAP_FaceSmooth", { Text = "Smooth", Default = true,
    Tooltip = "Lerp rotation instead of snapping." })

local WlBox = TabParryCombat:AddRightGroupbox("Player Whitelist")
WlBox:AddInput("UAP_WlName", { Text = "Username", Placeholder = "e.g. Player123" })
WlBox:AddButton("Add to Whitelist", function()
    local name = Options.UAP_WlName and Options.UAP_WlName.Value
    if not name or name == "" then Library:Notify("Enter a username.", 3) return end
    playerWhitelist[name] = true; saveDB()
    Library:Notify("Whitelisted: " .. name, 2)
end)
WlBox:AddButton("Remove from Whitelist", function()
    local name = Options.UAP_WlName and Options.UAP_WlName.Value
    if name then playerWhitelist[name] = nil; saveDB(); Library:Notify("Removed: " .. name, 2) end
end)
WlBox:AddButton("Clear Whitelist", function()
    table.clear(playerWhitelist); saveDB(); Library:Notify("Whitelist cleared.", 2)
end)

-- ---- Builder tab (Linoria) : the timing DB authoring ------------------------
local BuildBox = TabParryBuilder:AddLeftGroupbox("Timing DB")
local dbLabel = BuildBox:AddLabel("Entries: " .. dbCount())
local function refreshDbLabel() dbLabel:SetText("Entries: " .. dbCount()) end

BuildBox:AddDropdown("UAP_Selected", { Values = {}, Default = nil, AllowNull = true, Multi = false, Text = "Attack (anim id)" })
local function dbIds()
    local ids = {}
    for id in pairs(learnedAttacks) do table.insert(ids, id) end
    table.sort(ids)
    return ids
end
refreshDbDropdown = function()
    if Options.UAP_Selected then Options.UAP_Selected:SetValues(dbIds()) end
    refreshDbLabel()
end

BuildBox:AddInput("UAP_AnimId", { Text = "Animation ID", Placeholder = "e.g. 17440095233" })
BuildBox:AddInput("UAP_Name",  { Text = "Name (label)",  Placeholder = "e.g. Heavy Slam" })
BuildBox:AddSlider("UAP_EditFrac", { Text = "Hit %", Default = 45, Min = 2, Max = 98, Rounding = 0, Suffix = "%" })
BuildBox:AddSlider("UAP_EditDelay", { Text = "Delay (ms)", Default = 0, Min = 0, Max = 2000, Rounding = 0, Suffix = "ms",
    Tooltip = "Fixed delay from animation start. Overrides Hit % when > 0." })
BuildBox:AddSlider("UAP_EditMin", { Text = "Min Distance", Default = 0, Min = 0, Max = 500, Rounding = 0, Suffix = " studs",
    Tooltip = "Ignore this attack when the enemy is closer than this. 0 = no minimum." })
BuildBox:AddSlider("UAP_EditMax", { Text = "Max Distance", Default = 0, Min = 0, Max = 500, Rounding = 0, Suffix = " studs",
    Tooltip = "Ignore this attack past this range. 0 = use the global Max Distance." })
BuildBox:AddDropdown("UAP_EditDodge", { Values = { "None", "Left", "Right", "Back" }, Default = "None", Multi = false, Text = "Dodge Direction",
    Tooltip = "Dodge instead of (or in addition to) blocking." })
BuildBox:AddSlider("UAP_EditRepeat", { Text = "Repeat", Default = 1, Min = 1, Max = 10, Rounding = 0,
    Tooltip = "Re-trigger block for multi-hit attacks." })
BuildBox:AddSlider("UAP_EditRepDelay", { Text = "Repeat Delay (s)", Default = 0.35, Min = 0.1, Max = 2.0, Rounding = 2, Suffix = "s" })

BuildBox:AddButton("Save Entry", function()
    local id = tostring(Options.UAP_AnimId and Options.UAP_AnimId.Value or ""):match("%d+") or (Options.UAP_Selected and Options.UAP_Selected.Value)
    if not id then Library:Notify("Enter an animation id (or select one).", 3) return end
    local e = learnedAttacks[id] or { enabled = true, samples = 0 }
    e.frac        = Options.UAP_EditFrac.Value / 100
    e.delayMs     = Options.UAP_EditDelay.Value
    e.minDist     = Options.UAP_EditMin.Value
    e.maxDist     = Options.UAP_EditMax.Value
    e.dodge       = Options.UAP_EditDodge and Options.UAP_EditDodge.Value or "None"
    e.repeatCount = Options.UAP_EditRepeat and Options.UAP_EditRepeat.Value or 1
    e.repeatDelay = Options.UAP_EditRepDelay and Options.UAP_EditRepDelay.Value or 0.35
    local nm = Options.UAP_Name and Options.UAP_Name.Value
    if nm and nm ~= "" then e.name = nm elseif not e.name then e.name = "manual" end
    learnedAttacks[id] = e
    saveDB(); refreshDbDropdown()
    if Options.UAP_Selected then Options.UAP_Selected:SetValue(id) end
    local timing = (e.delayMs and e.delayMs > 0) and (e.delayMs .. "ms") or (math.floor(e.frac * 100) .. "%")
    Library:Notify(("Saved %s (%s) @ %s"):format(id, e.name, timing), 2)
end)
BuildBox:AddButton("Capture Next Attack", function()
    captureArmed = true
    Library:Notify("Next attack that plays in range will be captured.", 3)
end)
BuildBox:AddButton("Toggle Enabled", function()
    local id = Options.UAP_Selected and Options.UAP_Selected.Value
    if id and learnedAttacks[id] then
        learnedAttacks[id].enabled = not (learnedAttacks[id].enabled ~= false)
        saveDB(); Library:Notify(id .. " enabled=" .. tostring(learnedAttacks[id].enabled), 2)
    end
end)
BuildBox:AddButton("Delete Selected", function()
    local id = Options.UAP_Selected and Options.UAP_Selected.Value
    if id then learnedAttacks[id] = nil; saveDB(); refreshDbDropdown() end
end)
BuildBox:AddButton("Delete All Entries", function()
    table.clear(learnedAttacks)
    saveDB()
    refreshDbDropdown()
    Library:Notify("Deleted all database entries.", 3)
end)
BuildBox:AddButton("Refresh List", refreshDbDropdown)

local BlBox = TabParryBuilder:AddLeftGroupbox("Blacklist")
local blLabel = BlBox:AddLabel("Blacklisted: 0")
local function refreshBlLabel()
    local n = 0; for _ in pairs(blacklist) do n = n + 1 end
    blLabel:SetText("Blacklisted: " .. n)
end
refreshBlLabel()
BlBox:AddInput("UAP_BlId", { Text = "Animation ID", Placeholder = "id to never parry" })
BlBox:AddButton("Add to Blacklist", function()
    local id = tostring(Options.UAP_BlId and Options.UAP_BlId.Value or ""):match("%d+")
    if not id then Library:Notify("Enter a numeric id.", 3) return end
    blacklist[id] = true; saveDB(); refreshBlLabel(); Library:Notify("Blacklisted #" .. id, 2)
end)
BlBox:AddButton("Blacklist Selected Attack", function()
    local id = Options.UAP_Selected and Options.UAP_Selected.Value
    if id then blacklist[id] = true; saveDB(); refreshBlLabel(); Library:Notify("Blacklisted #" .. id, 2) end
end)
BlBox:AddButton("Clear Blacklist", function() table.clear(blacklist); saveDB(); refreshBlLabel() end)

local ToolsBox = TabParryBuilder:AddRightGroupbox("Tools")
ToolsBox:AddButton("Open Live Logger", function() if openLogger then openLogger() end end)
ToolsBox:AddButton("Open Animation Visualizer", function() if openViewer then openViewer() end end)
ToolsBox:AddButton("Export Config (clipboard)", function()
    local ok, blob = pcall(function() return HttpService:JSONEncode({ v = 2, attacks = learnedAttacks, blacklist = blacklist, whitelist = playerWhitelist }) end)
    if ok and setclipboard then setclipboard("DHP:" .. b64encode(blob)); Library:Notify("Copied config (" .. dbCount() .. " attacks).", 3)
    else Library:Notify("Export failed.", 3) end
end)
ToolsBox:AddButton("Import Config (clipboard)", function()
    local raw; pcall(function() if getclipboard then raw = getclipboard() end end)
    if type(raw) ~= "string" or raw == "" then Library:Notify("Clipboard empty.", 3) return end
    raw = raw:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^DHP:", "")
    local ok, data = pcall(function() return HttpService:JSONDecode(b64decode(raw)) end)
    local attacks = ok and type(data) == "table" and (data.attacks or data) or nil
    if type(attacks) ~= "table" then Library:Notify("Import failed (bad string).", 3) return end
    local n = 0; for id, info in pairs(attacks) do learnedAttacks[tostring(id)] = info; n = n + 1 end
    if type(data.blacklist) == "table" then for id in pairs(data.blacklist) do blacklist[tostring(id)] = true end end
    if type(data.whitelist) == "table" then for k, v in pairs(data.whitelist) do playerWhitelist[tostring(k)] = v end end
    saveDB(); refreshDbDropdown(); refreshBlLabel(); Library:Notify("Imported " .. n .. " attacks.", 3)
end)

local LogBox = TabParryBuilder:AddRightGroupbox("Logger Settings")
LogBox:AddToggle("UAP_LogAttacksOnly", { Text = "Attacks Only", Default = true,
    Tooltip = "Only show attack-priority animations in the logger." })
LogBox:AddToggle("UAP_LogHideKnown", { Text = "Hide Known", Default = false,
    Tooltip = "Hide animations already in the timing DB." })
LogBox:AddToggle("UAP_LogHideSkipped", { Text = "Hide Skipped", Default = false,
    Tooltip = "Hide all SKIP:* entries." })
LogBox:AddToggle("UAP_LogHideBlacklisted", { Text = "Hide Blacklisted", Default = false,
    Tooltip = "Hide all blacklisted animations in the logger." })
LogBox:AddSlider("UAP_LogRadius", { Text = "Log Radius", Default = 300, Min = 10, Max = 500, Rounding = 0, Suffix = " studs",
    Tooltip = "Range for the logger. Independent from parry Max Distance." })
LogBox:AddSlider("UAP_LogDedup", { Text = "Dedup Interval (s)", Default = 2, Min = 0, Max = 10, Rounding = 1, Suffix = "s",
    Tooltip = "Suppress duplicate logs from the same enemy+animation within this window. 0 = off." })

-- Selecting an entry populates the editor fields.
if Options.UAP_Selected then
    Options.UAP_Selected:OnChanged(function()
        pcall(function()
            local id = Options.UAP_Selected.Value
            local e = id and learnedAttacks[id]
            if not e then return end
            if Options.UAP_EditFrac     then Options.UAP_EditFrac:SetValue(math.floor((e.frac or 0.45) * 100)) end
            if Options.UAP_EditDelay    then Options.UAP_EditDelay:SetValue(e.delayMs or 0) end
            if Options.UAP_EditMin      then Options.UAP_EditMin:SetValue(e.minDist or 0) end
            if Options.UAP_EditMax      then Options.UAP_EditMax:SetValue(e.maxDist or 0) end
            if Options.UAP_EditDodge    then Options.UAP_EditDodge:SetValue(e.dodge or "None") end
            if Options.UAP_EditRepeat   then Options.UAP_EditRepeat:SetValue(e.repeatCount or 1) end
            if Options.UAP_EditRepDelay then Options.UAP_EditRepDelay:SetValue(e.repeatDelay or 0.35) end
            if Options.UAP_Name         then Options.UAP_Name:SetValue(e.name or "") end
        end)
    end)
end

-- =============================================================================
-- FLOATING PANELS  (custom UI kit) : Live Logger + Animation Visualizer
-- Two separate draggable windows. DisplayOrder forced high so they sit above the
-- Linoria menu; parented to PlayerGui (always renders) with a fallback.
-- =============================================================================
do
    local vgui, vroot, vLoadAnim, vcurId
    local lgui, lroot, lscroll
    local TH = {
        bg = Color3.fromRGB(20, 21, 27), panel = Color3.fromRGB(28, 30, 38),
        card = Color3.fromRGB(36, 39, 49), accent = Color3.fromRGB(96, 165, 250),
        green = Color3.fromRGB(104, 211, 145), red = Color3.fromRGB(239, 105, 105),
        yellow = Color3.fromRGB(250, 204, 21),
        text = Color3.fromRGB(232, 234, 240), sub = Color3.fromRGB(150, 154, 165),
        stroke = Color3.fromRGB(54, 58, 70),
    }
    local function mk(cls, props, parent)
        local o = Instance.new(cls)
        for k, v in pairs(props or {}) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local function corner(o, r) mk("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o); return o end
    local function stroke(o, c, t) mk("UIStroke", { Color = c or TH.stroke, Transparency = t or 0, Thickness = 1 }, o); return o end
    local function guiParent()
        if gethui then local ok, h = pcall(gethui); if ok and h then return h end end
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then return pg end
        return LocalPlayer:WaitForChild("PlayerGui")
    end
    local function copyId(id)
        if setclipboard then setclipboard(tostring(id)) end
        Library:Notify("Copied #" .. tostring(id), 1.5)
    end
    local function button(parent, text, color, cb)
        local b = corner(mk("TextButton", { Size = UDim2.new(0, 0, 0, 28), BackgroundColor3 = color or TH.card,
            Text = text, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = TH.text,
            AutoButtonColor = true, BorderSizePixel = 0 }, parent), 6)
        if cb then b.MouseButton1Click:Connect(cb) end
        return b
    end
    local function inputBox(parent, labelText, placeholder)
        local holder = mk("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 }, parent)
        mk("TextLabel", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = labelText, Font = Enum.Font.Gotham,
            TextSize = 12, TextColor3 = TH.sub, TextXAlignment = Enum.TextXAlignment.Left }, holder)
        local boxBg = corner(mk("Frame", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 18),
            BackgroundColor3 = TH.bg, BorderSizePixel = 0 }, holder), 6)
        return mk("TextBox", { Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1,
            Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = TH.text, PlaceholderText = placeholder or "",
            PlaceholderColor3 = TH.sub, Text = "", ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, boxBg)
    end

    -- Shared draggable window shell. Returns gui, root, body.
    local function makeWindow(titleText, w, h)
        local gui = mk("ScreenGui", { Name = "UAP_" .. titleText:gsub("%s", ""), ResetOnSpawn = false,
            IgnoreGuiInset = true, DisplayOrder = 999999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
        local ok = pcall(function() gui.Parent = guiParent() end)
        if not ok or not gui.Parent then pcall(function() gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end) end
        local root = stroke(corner(mk("Frame", { Size = UDim2.new(0, w, 0, h), Position = UDim2.new(0.5, -w / 2, 0.5, -h / 2),
            BackgroundColor3 = TH.bg, BorderSizePixel = 0, Visible = false }, gui), 10), TH.stroke, 0.2)
        local title = mk("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, root)
        mk("TextLabel", { Size = UDim2.new(1, -80, 1, 0), Position = UDim2.new(0, 14, 0, 0), BackgroundTransparency = 1,
            Text = titleText, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = TH.text, TextXAlignment = Enum.TextXAlignment.Left }, title)
        local closeB = button(title, "Close", TH.card, function() root.Visible = false end)
        closeB.Size = UDim2.new(0, 64, 0, 24); closeB.Position = UDim2.new(1, -72, 0, 5)
        do
            local dragging, ds, sp
            title.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; ds = i.Position; sp = root.Position end end)
            title.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
            AddConn(UserInputService.InputChanged:Connect(function(i)
                if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
                    local d = i.Position - ds
                    root.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
                end
            end))
        end
        local body = mk("Frame", { Size = UDim2.new(1, -20, 1, -44), Position = UDim2.new(0, 10, 0, 38), BackgroundTransparency = 1 }, root)
        return gui, root, body
    end

    -- ---- LIVE LOGGER panel --------------------------------------------------
    local lpaused = false
    local lautoScroll = true
    local function buildLogger()
        local body
        lgui, lroot, body = makeWindow("Live Logger", 540, 400)
        local topRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, body)
        mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, topRow)
        local pauseB  = button(topRow, "Pause", TH.card); pauseB.Size = UDim2.new(0, 64, 1, 0)
        button(topRow, "Clear", TH.card, function() table.clear(logRows) end).Size = UDim2.new(0, 50, 1, 0)
        local scrollB = button(topRow, "Auto-Scroll: ON", TH.card); scrollB.Size = UDim2.new(0, 108, 1, 0)
        pauseB.MouseButton1Click:Connect(function() lpaused = not lpaused; pauseB.Text = lpaused and "Resume" or "Pause" end)
        scrollB.MouseButton1Click:Connect(function()
            lautoScroll = not lautoScroll
            scrollB.Text = lautoScroll and "Auto-Scroll: ON" or "Auto-Scroll: OFF"
        end)
        lscroll = corner(mk("ScrollingFrame", { Size = UDim2.new(1, 0, 1, -32), Position = UDim2.new(0, 0, 0, 32),
            BackgroundColor3 = TH.panel, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(0, 0, 0, 0) }, body), 8)
        local lLayout = mk("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, lscroll)
        lLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            lscroll.CanvasSize = UDim2.new(0, 0, 0, lLayout.AbsoluteContentSize.Y + 8)
        end)
        mk("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, lscroll)
        task.spawn(function()
            while lgui and not Library.Unloaded do
                if lscroll and lroot.Visible and not lpaused then
                    for _, c in ipairs(lscroll:GetChildren()) do if c.Name == "logrow" then c:Destroy() end end

                    local attacksOnly  = Toggles.UAP_LogAttacksOnly and Toggles.UAP_LogAttacksOnly.Value
                    local hideKnown    = Toggles.UAP_LogHideKnown and Toggles.UAP_LogHideKnown.Value
                    local hideSkipped  = Toggles.UAP_LogHideSkipped and Toggles.UAP_LogHideSkipped.Value
                    local hideBlacklisted = Toggles.UAP_LogHideBlacklisted and Toggles.UAP_LogHideBlacklisted.Value

                    local shown = 0
                    for i = 1, #logRows do
                        if shown >= 60 then break end
                        local r = logRows[i]
                        local skip = false
                        if attacksOnly  and r.status == "SKIP:prio"      then skip = true end
                        if hideKnown    and r.status == "known"          then skip = true end
                        if hideSkipped  and r.status:sub(1, 4) == "SKIP" then skip = true end
                        if hideBlacklisted and r.status == "BLACKLIST"   then skip = true end

                        if not skip then
                            shown = shown + 1
                            local col = TH.sub
                            if     r.status == "NEW"       then col = TH.green
                            elseif r.status == "BLACKLIST" then col = TH.red
                            elseif r.status == "known"     then col = TH.accent
                            elseif r.status:sub(1,4) == "SKIP" then col = TH.yellow end

                            local row = mk("Frame", { Name = "logrow", Size = UDim2.new(1, -4, 0, 22), BackgroundTransparency = 1, LayoutOrder = i }, lscroll)
                             local countStr = (r.count and r.count > 1) and (" (x%d)"):format(r.count) or ""
                             local txt = ("%s  %s  #%s  %s  %dm  %s%s"):format(r.t, r.anim, r.id, r.enemy, r.dist, r.status, countStr)
                            mk("TextLabel", { Size = UDim2.new(1, -150, 1, 0), Position = UDim2.new(0, 2, 0, 0), BackgroundTransparency = 1,
                                Text = txt, Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = col,
                                TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, row)

                            -- per-row action buttons
                            local addB = button(row, "+Add", TH.green)
                            addB.MouseButton1Down:Connect(function()
                                if not learnedAttacks[r.id] then
                                    learnedAttacks[r.id] = { frac = defaultFrac(), enabled = true, name = r.anim, samples = 0 }
                                    saveDB(); if refreshDbDropdown then refreshDbDropdown() end
                                    Library:Notify("Added #" .. r.id .. " (" .. r.anim .. ")", 2)
                                else Library:Notify("#" .. r.id .. " already in DB.", 2) end
                            end)
                            addB.Size = UDim2.new(0, 34, 0, 18); addB.Position = UDim2.new(1, -148, 0, 2); addB.TextSize = 9; addB.TextColor3 = TH.bg

                            local blB = button(row, "BL", TH.red)
                            blB.MouseButton1Down:Connect(function()
                                blacklist[r.id] = true; saveDB(); refreshBlLabel()
                                Library:Notify("Blacklisted #" .. r.id, 2)
                            end)
                            blB.Size = UDim2.new(0, 24, 0, 18); blB.Position = UDim2.new(1, -110, 0, 2); blB.TextSize = 9; blB.TextColor3 = TH.bg

                            local viewB = button(row, "View", TH.accent)
                            viewB.MouseButton1Down:Connect(function()
                                if not vgui then if openViewer then openViewer() end end
                                if vroot and not vroot.Visible then vroot.Visible = true end
                                if vLoadAnim then vLoadAnim(r.id, r.model) end
                            end)
                            viewB.Size = UDim2.new(0, 34, 0, 18); viewB.Position = UDim2.new(1, -82, 0, 2); viewB.TextSize = 9; viewB.TextColor3 = TH.bg

                            local cpB = button(row, "Copy", TH.bg)
                            cpB.MouseButton1Down:Connect(function() copyId(r.id) end)
                            cpB.Size = UDim2.new(0, 38, 0, 18); cpB.Position = UDim2.new(1, -44, 0, 2); cpB.TextSize = 9
                        end
                    end
                    if lautoScroll then lscroll.CanvasPosition = Vector2.new(0, 0) end
                end
                task.wait(0.4)
            end
        end)
    end
    openLogger = function()
        if not lgui then buildLogger() end
        if lroot then lroot.Visible = not lroot.Visible end
    end

    -- ---- ANIMATION VISUALIZER panel -----------------------------------------
    local vrig, vanimator, vtrack, vplaying, vmodel = nil, nil, nil, true, nil
    local vspeed = 1
    local function buildViewer()
        local body
        vgui, vroot, body = makeWindow("Animation Visualizer", 460, 340)

        local vpBg = corner(mk("Frame", { Size = UDim2.new(0, 200, 1, -34), BackgroundColor3 = TH.panel, BorderSizePixel = 0 }, body), 8)
        local viewport = mk("ViewportFrame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
            CurrentCamera = mk("Camera", { CFrame = CFrame.new(0, 3, -9) * CFrame.Angles(0, math.pi, 0) }) }, vpBg)
        viewport.CurrentCamera.Parent = viewport
        vmodel = mk("WorldModel", {}, viewport)

        local ctrl = mk("Frame", { Size = UDim2.new(1, -212, 1, -34), Position = UDim2.new(0, 212, 0, 0), BackgroundTransparency = 1 }, body)
        mk("UIListLayout", { Padding = UDim.new(0, 6) }, ctrl)

        -- animation name/length header
        local vNameLabel = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
            Text = "No animation loaded", Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = TH.accent,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, ctrl)

        local vIdBox = inputBox(ctrl, "Animation ID", "type id, or uses selected")
        local loadB = button(ctrl, "Load Animation", TH.accent); loadB.Size = UDim2.new(1, 0, 0, 28); loadB.TextColor3 = TH.bg

        local rowc = mk("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, ctrl)
        mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, rowc)
        local playB = button(rowc, "Pause", TH.card); playB.Size = UDim2.new(0, 80, 1, 0)
        local setB  = button(rowc, "Set Hit %", TH.green); setB.Size = UDim2.new(0, 80, 1, 0); setB.TextColor3 = TH.bg

        -- speed buttons
        local speedRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 }, ctrl)
        mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }, speedRow)
        mk("TextLabel", { Size = UDim2.new(0, 40, 1, 0), BackgroundTransparency = 1, Text = "Speed:", Font = Enum.Font.Gotham,
            TextSize = 11, TextColor3 = TH.sub, TextXAlignment = Enum.TextXAlignment.Left }, speedRow)
        for _, sp in ipairs({ 0.25, 0.5, 1, 2 }) do
            local sb = button(speedRow, tostring(sp) .. "x", TH.card, function()
                vspeed = sp
                if vtrack then vtrack:AdjustSpeed(vplaying and sp or 0) end
            end)
            sb.Size = UDim2.new(0, 36, 0, 22); sb.TextSize = 10
        end

        local vtime = mk("TextLabel", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = "0% / 0ms",
            Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = TH.sub, TextXAlignment = Enum.TextXAlignment.Left }, ctrl)

        local bar   = corner(mk("Frame", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -26),
            BackgroundColor3 = TH.panel, BorderSizePixel = 0 }, body), 6)
        local vfill = corner(mk("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = TH.accent, BackgroundTransparency = 0.4, BorderSizePixel = 0 }, bar), 6)
        local vtick = mk("Frame", { Size = UDim2.new(0, 2, 1, 0), Position = UDim2.new(0, -1, 0, 0), BackgroundColor3 = TH.green, BorderSizePixel = 0 }, bar)
        local vplayhead = mk("Frame", { Size = UDim2.new(0, 2, 1, 0), Position = UDim2.new(0, -1, 0, 0), BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0 }, bar)

        local function buildRig(sourceModel)
            if vrig and vrig.Parent then
                local currentSource = vrig:GetAttribute("SourceModelName")
                local targetSource = sourceModel and sourceModel.Name or "LocalPlayer"
                if currentSource == targetSource then
                    return false
                end
                pcall(function() vrig:Destroy() end)
                vrig = nil
            end
            local char = sourceModel
            if not char or not char.Parent then
                char = LocalPlayer.Character
            end
            if not char then return false end
            
            local wasArch = char.Archivable; char.Archivable = true
            local ok, clone = pcall(function() return char:Clone() end)
            char.Archivable = wasArch
            
            if not ok or not clone then return false end
            vrig = clone
            vrig:SetAttribute("SourceModelName", sourceModel and sourceModel.Name or "LocalPlayer")
            
            for _, d in ipairs(vrig:GetDescendants()) do
                if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy()
                elseif d:IsA("BasePart") then d.CanCollide = false end
            end
            local hum = vrig:FindFirstChildOfClass("Humanoid") or vrig:FindFirstChildOfClass("AnimationController")
            if hum then 
                if hum:IsA("Humanoid") then
                    hum.AutoRotate = false
                    pcall(function() hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end) 
                end
                local oldAnim = hum:FindFirstChildOfClass("Animator")
                if oldAnim then oldAnim:Destroy() end
                vanimator = Instance.new("Animator", hum)
            end
            local hrp = vrig:FindFirstChild("HumanoidRootPart") or vrig.PrimaryPart or vrig:FindFirstChildWhichIsA("BasePart")
            if hrp then 
                vrig.PrimaryPart = hrp
                hrp.Anchored = true 
            end
            pcall(function() vrig:PivotTo(CFrame.new(0, 0, 0)) end)
            vrig.Parent = vmodel
            
            -- Auto-fit camera to model bounds
            pcall(function()
                local size = vrig:GetExtentsSize()
                local center = vrig:GetPivot().Position
                local camera = viewport.CurrentCamera
                if camera then
                    local maxDim = math.max(size.X, size.Y, size.Z)
                    local fov = camera.FieldOfView
                    local dist = (maxDim / 2) / math.sin(math.rad(fov / 2))
                    camera.CFrame = CFrame.new(center + Vector3.new(0, size.Y * 0.1, -dist * 1.25)) * CFrame.Angles(0, math.pi, 0)
                end
            end)
            
            return true
        end
        vLoadAnim = function(id, sourceModel)
            if not id then return end
            if vIdBox then vIdBox.Text = tostring(id) end
            
            local justBuilt = buildRig(sourceModel)
            if not vanimator then Library:Notify("Need a character to preview on.", 3) return end
            if justBuilt then task.wait() end -- Yield 1 frame for Animator to bind Motor6Ds
            
            if vtrack then pcall(function() vtrack:Stop() end); vtrack = nil end
            local anim = Instance.new("Animation"); anim.AnimationId = "rbxassetid://" .. id
            local ok, t = pcall(function() return vanimator:LoadAnimation(anim) end)
            if not ok or not t then Library:Notify("Couldn't load " .. id, 3) return end
            
            vplaying = true
            if playB then playB.Text = "Pause" end
            
            vtrack = t; vtrack.Looped = true; vtrack:Play(); vtrack:AdjustSpeed(vspeed); vcurId = id
            
            task.spawn(function()
                local t0 = tick()
                while vtrack == t and t.Length <= 0.01 and tick() - t0 < 3 do task.wait() end
                if vtrack == t then
                    local nm = t.Animation and t.Animation.Name or "Animation"
                    vNameLabel.Text = ("%s  #%s  (%dms)"):format(nm, id, math.floor(t.Length * 1000))
                    vtrack:AdjustSpeed(vplaying and vspeed or 0)
                end
            end)
        end

        loadB.MouseButton1Click:Connect(function()
            local id = tostring(vIdBox.Text):match("%d+") or (Options.UAP_Selected and Options.UAP_Selected.Value)
            if id then vLoadAnim(id) else Library:Notify("Type or select an id.", 3) end
        end)
        playB.MouseButton1Click:Connect(function()
            vplaying = not vplaying; playB.Text = vplaying and "Pause" or "Play"
            if vtrack then vtrack:AdjustSpeed(vplaying and vspeed or 0) end
        end)
        setB.MouseButton1Click:Connect(function()
            if not (vtrack and vtrack.Length and vtrack.Length > 0 and vcurId) then return end
            local frac = math.clamp(vtrack.TimePosition / vtrack.Length, 0.02, 0.98)
            local e = learnedAttacks[vcurId] or { enabled = true, samples = 0, name = "manual" }
            e.frac = frac; learnedAttacks[vcurId] = e; saveDB()
            if refreshDbDropdown then refreshDbDropdown() end
            if Options.UAP_Selected and Options.UAP_Selected.Value == vcurId and Options.UAP_EditFrac then
                Options.UAP_EditFrac:SetValue(math.floor(frac * 100))
            end
            Library:Notify(("Set %s -> %d%%"):format(vcurId, math.floor(frac * 100)), 2)
        end)
        do
            local dragging
            local function scrub(px)
                if not (vtrack and vtrack.Length and vtrack.Length > 0) then return end
                local rel = math.clamp((px - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
                vplaying = false; playB.Text = "Play"; vtrack:AdjustSpeed(0); vtrack.TimePosition = rel * vtrack.Length
            end
            bar.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; scrub(i.Position.X) end end)
            bar.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
            AddConn(UserInputService.InputChanged:Connect(function(i) if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then scrub(i.Position.X) end end))
        end
        AddConn(RunService.RenderStepped:Connect(function()
            if not (vroot and vroot.Visible and vtrack) then return end
            local len = vtrack.Length
            if len and len > 0.01 then
                local p = math.clamp(vtrack.TimePosition / len, 0, 1)
                vtime.Text = ("%.0f%% / %dms (Total: %dms)"):format(p * 100, math.floor(vtrack.TimePosition * 1000), math.floor(len * 1000))
                vfill.Size = UDim2.new(p, 0, 1, 0)
                local e = vcurId and learnedAttacks[vcurId]
                local hf = (e and e.frac) or 0.45
                vtick.Position = UDim2.new(math.clamp(hf, 0, 1), -1, 0, 0)
                vplayhead.Position = UDim2.new(p, -1, 0, 0)
            else
                vtime.Text = "Loading... / 0ms"
            end
        end))
    end
    openViewer = function()
        if not vgui then buildViewer() end
        if not vroot then return end
        vroot.Visible = not vroot.Visible
        if vroot.Visible then
            local id = tostring(Options.UAP_AnimId and Options.UAP_AnimId.Value or ""):match("%d+") or (Options.UAP_Selected and Options.UAP_Selected.Value)
            if id and id ~= vcurId and vLoadAnim then vLoadAnim(id) end
        end
    end

    -- destroy both panels on unload
    AddConn(RunService.Heartbeat:Connect(function()
        if Library.Unloaded then
            if lgui then pcall(function() lgui:Destroy() end); lgui = nil end
            if vgui then pcall(function() vgui:Destroy() end); vgui = nil end
        end
    end))
end

-- =============================================================================
-- SETTINGS / config
-- =============================================================================

local NotifGroup = TabParrySettings:AddLeftGroupbox("Notifications")
NotifGroup:AddDropdown("UAP_NotifyStyle", { Values = { "Library", "Print", "None" }, Default = "Library", Multi = false, Text = "Notification Style",
    Tooltip = "How parry notifications are displayed." })

-- (Theme/Save config UI is built ONCE in the main Settings tab above. It is not rebuilt
-- here -- doing so created duplicate "Themes"/"Save Profiles" sections on the same tab.)

Library:OnUnload(function()
    pcall(function() setBlock(false) end)
    lastAttacker = nil
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    table.clear(Connections)
end)

refreshDbDropdown()
Library:Notify("Universal Auto Parry loaded. DB: " .. dbCount() .. " attacks.", 4)


end

-- =====================================================================
-- FINALISE: build the Samet window now that every tab/section exists, then
-- run the autoload config (QoL). Samet finalises layout in :Init(), so this
-- must come AFTER all UI above is constructed.
-- =====================================================================
pcall(function() Window:Init() end)
pcall(function() SaveManager:LoadAutoloadConfig() end)
