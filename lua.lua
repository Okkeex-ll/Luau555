-- [[ RAYFIELD ]]
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "fife | 0.4",
    LoadingTitle = "Loading...",
    ConfigurationSaving = {
        Enabled = false,
        FileName = "YOURMOMSOFAT"
    },
    KeySystem = false,
})

-- [[ СЕРВИСЫ ]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- =========================================================
-- [[ КОНФИГ КИКА — тюнить здесь ]]
-- =========================================================
local KICK_HOLD_OFFSET    = Vector3.new(0, 15, 0)  -- смещение цели над головой
local KICK_BP_P           = 500000                   -- сила притяжения BodyPosition (чем больше = жёстче)
local KICK_BP_D           = 50                       -- демпфирование BodyPosition (чем меньше = резче)
local KICK_BG_D           = 100                      -- демпфирование BodyGyro
local KICK_REGRAB_DIST    = 30                       -- дистанция для TP-перехвата
local KICK_REGRAB_CD      = 0.7                      -- кулдаун между перехватами (сек)
local KICK_REGRAB_BURSTS  = 5                        -- сколько раз спамить при перехвате
local KICK_REGRAB_WAIT    = 0.25                     -- сколько ждать у цели перед возвратом
local KICK_SPAM_INTERVAL  = 0.05                     -- интервал доп. спама ownership
local KICK_WEAPON_INTERVAL = 0.15                    -- интервал проверки оружия/перехвата

-- [[ ПЕРЕМЕННЫЕ ]]
local selectedTarget = nil
local pcldActive = false
local noclipActive = false
local espActive = false
local loopTPActive = false
local customSpeed = 16
local customJump = 50
_G.KickEnabled = false
_G.PacketMonitor = false
_G.StopKickFunc = nil
local savedTargets = {}
local currentSaved = nil
local espObjects = {}
local selectBind = Enum.KeyCode.X

-- [[ ИВЕНТЫ — безопасная загрузка ]]
local GE = ReplicatedStorage:WaitForChild("GrabEvents", 10)
if not GE then
    Rayfield:Notify({Title = "Error", Content = "No GrabEvents!", Duration = 5})
    return
end
local destroyGrabLine = GE:FindFirstChild("DestroyGrabLine")
local setOwner = GE:FindFirstChild("SetNetworkOwner")
local extendLine = GE:FindFirstChild("ExtendGrabLine")
local createLine = GE:FindFirstChild("CreateGrabLine")

-- Ждём если не нашлись сразу
if not destroyGrabLine then destroyGrabLine = GE:WaitForChild("DestroyGrabLine", 5) end
if not setOwner then setOwner = GE:WaitForChild("SetNetworkOwner", 5) end
if not extendLine then extendLine = GE:WaitForChild("ExtendGrabLine", 5) end
if not createLine then createLine = GE:WaitForChild("CreateGrabLine", 5) end

-- [[ УТИЛИТЫ ]]
local function SystemChat(text, color)
    pcall(function()
        StarterGui:SetCore("ChatMakeSystemMessage", {
            Text = "[System]: " .. text,
            Color = color or Color3.fromRGB(255, 0, 0),
            Font = Enum.Font.SourceSansBold,
            FontSize = Enum.FontSize.Size24,
        })
    end)
end

-- Безопасные обёртки для серверных вызовов
local function fireSetOwner(part, cf)
    if setOwner and part and part.Parent then
        pcall(function() setOwner:FireServer(part, cf) end)
    end
end

local function fireDestroyGrab(part)
    if destroyGrabLine and part and part.Parent then
        pcall(function() destroyGrabLine:FireServer(part) end)
    end
end

local DropSaved = nil

local function AddToSaved(name)
    if not name then return end
    for _, v in pairs(savedTargets) do
        if v == name then return end
    end
    table.insert(savedTargets, name)
    if DropSaved then pcall(function() DropSaved:Set(savedTargets) end) end
end

local function GetNames()
    local t = {}
    for _, v in pairs(Players:GetPlayers()) do
        if v ~= LocalPlayer then table.insert(t, v.Name) end
    end
    if #t == 0 then table.insert(t, "No players") end
    return t
end

-- =========================================================
-- [[ КИК — УЛУЧШЕННЫЙ ]]
-- =========================================================

local function StopKick()
    if _G.StopKickFunc then
        pcall(function() _G.StopKickFunc() end)
        _G.StopKickFunc = nil
    end
end

local function KickPlayer(targetPlayer)
    if not targetPlayer then return end
    StopKick()
    task.wait(0.05)

    local kickActive = true
    local allConnections = {} -- все подписки для гарантированной очистки
    local lastGrabTime = 0

    -- === Очистка BodyMovers с любого HRP ===
    local function cleanBodyMovers(hrp)
        if not hrp then return end
        pcall(function()
            local bp = hrp:FindFirstChild("KickBP")
            if bp then bp:Destroy() end
            local bg = hrp:FindFirstChild("KickBG")
            if bg then bg:Destroy() end
        end)
    end

    -- === Создать / обновить BodyMovers на HRP ===
    local function ensureBodyMovers(tHRP, holdPos, lookCF)
        if not tHRP or not tHRP.Parent then return end

        local bp = tHRP:FindFirstChild("KickBP")
        if not bp then
            bp = Instance.new("BodyPosition")
            bp.Name = "KickBP"
            bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bp.D = KICK_BP_D
            bp.P = KICK_BP_P
            bp.Parent = tHRP
        end
        bp.Position = holdPos

        local bg = tHRP:FindFirstChild("KickBG")
        if not bg then
            bg = Instance.new("BodyGyro")
            bg.Name = "KickBG"
            bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            bg.D = KICK_BG_D
            bg.Parent = tHRP
        end
        bg.CFrame = lookCF
    end

    -- === Убить физику цели ===
    local function freezeTarget(tHRP, tHum)
        if tHRP and tHRP.Parent then
            pcall(function()
                tHRP.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                tHRP.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                tHRP.Velocity = Vector3.new(0, 0, 0)
                tHRP.RotVelocity = Vector3.new(0, 0, 0)
            end)
        end
        if tHum then
            pcall(function() tHum.PlatformStand = true end)
        end
    end

    -- === Удалить оружие цели ===
    local function removeWeapons()
        pcall(function()
            if not targetPlayer or not targetPlayer.Parent then return end
            local spawned = Workspace:FindFirstChild(targetPlayer.Name .. "SpawnedInToys")
            if not spawned then return end
            local function yeet(container, partName)
                local c = spawned:FindFirstChild(container)
                if not c then return end
                local part = c:FindFirstChild(partName)
                if not part then return end
                fireSetOwner(part, part.CFrame)
                if part:FindFirstChild("PartOwner") and part.PartOwner.Value == LocalPlayer.Name then
                    part.CFrame = CFrame.new(0, 10000, 0)
                end
            end
            yeet("NinjaKunai", "SoundPart")
            yeet("NinjaShuriken", "SoundPart")
        end)
    end

    -- === Полная остановка и очистка ===
    local function fullCleanup()
        kickActive = false

        -- Отключить все подписки
        for _, conn in pairs(allConnections) do
            pcall(function() conn:Disconnect() end)
        end
        allConnections = {}

        -- Убрать BodyMovers и PlatformStand
        pcall(function()
            if targetPlayer and targetPlayer.Character then
                local r = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                cleanBodyMovers(r)
                local h = targetPlayer.Character:FindFirstChild("Humanoid")
                if h then h.PlatformStand = false end
            end
        end)
    end

    -- =====================================================
    -- ПОТОК 1: Heartbeat — основной контроль (каждый кадр)
    -- =====================================================
    local hbConn = RunService.Heartbeat:Connect(function()
        if not kickActive then return end

        pcall(function()
            if not targetPlayer or not targetPlayer.Parent then return end

            local tChar = targetPlayer.Character
            if not tChar then return end
            local tHRP = tChar:FindFirstChild("HumanoidRootPart")
            local tHum = tChar:FindFirstChild("Humanoid")
            if not tHRP then return end

            local myChar = LocalPlayer.Character
            if not myChar then return end
            local mHRP = myChar:FindFirstChild("HumanoidRootPart")
            if not mHRP then return end

            -- Серверный ownership — каждый кадр
            if tHRP.Position.Y < 2000 then
                fireSetOwner(tHRP, tHRP.CFrame)
                fireDestroyGrab(tHRP)
            end

            -- Локально: убить физику
            freezeTarget(tHRP, tHum)

            -- BodyMovers: создать если нет, обновить позицию
            local holdPos = mHRP.Position + KICK_HOLD_OFFSET
            ensureBodyMovers(tHRP, holdPos, mHRP.CFrame)
        end)
    end)
    table.insert(allConnections, hbConn)

    -- =====================================================
    -- ПОТОК 2: Дополнительный ownership спам
    -- =====================================================
    task.spawn(function()
        while kickActive do
            pcall(function()
                if not targetPlayer or not targetPlayer.Parent then return end
                local tChar = targetPlayer.Character
                if not tChar then return end
                local tHRP = tChar:FindFirstChild("HumanoidRootPart")
                if not tHRP then return end
                if tHRP.Position.Y < 2000 then
                    fireSetOwner(tHRP, tHRP.CFrame)
                    fireDestroyGrab(tHRP)
                end
            end)
            task.wait(KICK_SPAM_INTERVAL)
        end
    end)

    -- =====================================================
    -- ПОТОК 3: TP-перехват + оружие + основная очистка
    -- =====================================================
    task.spawn(function()
        while kickActive do
            pcall(function()
                if not targetPlayer or not targetPlayer.Parent then return end

                local targetChar = targetPlayer.Character
                local myChar = LocalPlayer.Character
                if not targetChar or not myChar then return end

                local tHRP = targetChar:FindFirstChild("HumanoidRootPart")
                local mHRP = myChar:FindFirstChild("HumanoidRootPart")
                if not tHRP or not mHRP then return end

                -- Убираем оружие
                removeWeapons()

                -- Перехват если далеко
                local dist = (mHRP.Position - tHRP.Position).Magnitude
                if dist > KICK_REGRAB_DIST and tHRP.Position.Y < 2000 then
                    local now = tick()
                    if now - lastGrabTime > KICK_REGRAB_CD then
                        lastGrabTime = now

                        local oldCF = mHRP.CFrame
                        mHRP.CFrame = tHRP.CFrame * CFrame.new(0, 0, 3)

                        -- Burst-спам ownership
                        for _ = 1, KICK_REGRAB_BURSTS do
                            fireSetOwner(tHRP, tHRP.CFrame)
                            fireDestroyGrab(tHRP)
                        end

                        task.wait(KICK_REGRAB_WAIT)

                        -- Вернуться назад (безопасно)
                        pcall(function()
                            if myChar and myChar.Parent and mHRP and mHRP.Parent then
                                mHRP.CFrame = oldCF
                            end
                        end)
                    end
                end
            end)
            task.wait(KICK_WEAPON_INTERVAL)
        end

        -- Этот поток последний — делаем финальную очистку
        fullCleanup()
    end)

    -- =====================================================
    -- Обработка респавна цели — пересоздаём BodyMovers
    -- =====================================================
    local respawnConn = targetPlayer.CharacterAdded:Connect(function(newChar)
        if not kickActive then return end
        -- Ждём пока HRP появится
        local tHRP = newChar:WaitForChild("HumanoidRootPart", 5)
        if not tHRP then return end
        if not kickActive then return end

        task.wait(0.5) -- даём серверу обработать спавн

        -- Сразу берём ownership нового тела
        for _ = 1, 5 do
            fireSetOwner(tHRP, tHRP.CFrame)
            fireDestroyGrab(tHRP)
            task.wait(0.1)
        end
    end)
    table.insert(allConnections, respawnConn)

    -- =====================================================
    -- Обработка респавна ЛОКАЛЬНОГО игрока
    -- =====================================================
    local myRespawnConn = LocalPlayer.CharacterAdded:Connect(function()
        if not kickActive then return end
        task.wait(1)
        -- После респавна просто продолжаем — Heartbeat сам подхватит новый mHRP
    end)
    table.insert(allConnections, myRespawnConn)

    -- Функция остановки
    _G.StopKickFunc = function()
        fullCleanup()
    end
end

-- =========================================================
-- [[ PCLD ESP ]] — вставить после создания Window
-- =========================================================
do
    local WS = game:GetService("Workspace")
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer

    local pcldOn = false
    local pcldColor = Color3.fromRGB(255, 0, 0)
    local pcldTrans = 0.5

    local trackedPCLD = nil -- ссылка на единственный PCLD
    local conns = {}        -- коннекты для очистки

    local PCLD_NAME = "PlayerCharacterLocationDetector"

    -- отключить коннект
    local function disc(key)
        if conns[key] then
            pcall(function() conns[key]:Disconnect() end)
            conns[key] = nil
        end
    end

    -- это мой PCLD? (проверяем по расстоянию до своего персонажа)
    local function isMine(part)
        local char = LP.Character
        if not char then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
        if not hrp then return false end
        -- PCLD спавнится почти на позиции игрока
        return (part.Position - hrp.Position).Magnitude < 2
    end

    -- применить стиль
    local function applyStyle()
        if not trackedPCLD or not trackedPCLD.Parent then return end
        pcall(function()
            trackedPCLD.Transparency = pcldTrans
            trackedPCLD.Color = pcldColor
        end)
    end

    -- сбросить стиль
    local function resetStyle()
        if trackedPCLD and trackedPCLD.Parent then
            pcall(function() trackedPCLD.Transparency = 1 end)
        end
        trackedPCLD = nil
    end

    -- попробовать захватить PCLD
    local function tryTrack(part)
        if not part or not part.Parent then return end
        if part.Name ~= PCLD_NAME then return end
        if not part:IsA("BasePart") then return end

        -- свой пропускаем
        if isMine(part) then return end

        trackedPCLD = part
        if pcldOn then applyStyle() end
    end

    -- найти PCLD среди текущих детей workspace
    local function scanWorkspace()
        trackedPCLD = nil
        for _, child in pairs(WS:GetChildren()) do
            if child.Name == PCLD_NAME and child:IsA("BasePart") then
                if not isMine(child) then
                    trackedPCLD = child
                    break
                end
            end
        end
    end

    -- включить
    local function enable()
        pcldOn = true
        scanWorkspace()
        if trackedPCLD then applyStyle() end

        -- новый PCLD появился
        disc("added")
        conns["added"] = WS.ChildAdded:Connect(function(part)
            if not pcldOn then return end
            if part.Name ~= PCLD_NAME then return end
            task.wait(0.15) -- ждём пока сервер выставит позицию
            tryTrack(part)
        end)

        -- PCLD удалён (игрок вышел, респавн и т.д.)
        disc("removed")
        conns["removed"] = WS.ChildRemoved:Connect(function(part)
            if part == trackedPCLD then
                trackedPCLD = nil
            end
        end)
    end

    -- выключить
    local function disable()
        pcldOn = false
        resetStyle()
        disc("added")
        disc("removed")
    end

    -- ====== GUI ======
    local TabPCLD = Window:CreateTab("PCLD ESP", 4483362458)
    TabPCLD:CreateSection("PCLD ESP")

    TabPCLD:CreateToggle({
        Name = "PCLD ESP",
        CurrentValue = false,
        Flag = "PCLDToggle",
        Callback = function(v)
            if v then enable() else disable() end
        end,
    })

    TabPCLD:CreateColorPicker({
        Name = "Color",
        Color = pcldColor,
        Flag = "PCLDColor",
        Callback = function(v)
            pcldColor = v
            if pcldOn and trackedPCLD then applyStyle() end
        end,
    })

    TabPCLD:CreateSlider({
        Name = "Transparency",
        Range = {0, 1},
        Increment = 0.05,
        Suffix = "",
        CurrentValue = pcldTrans,
        Flag = "PCLDTrans",
        Callback = function(v)
            pcldTrans = v
            if pcldOn and trackedPCLD then applyStyle() end
        end,
    })
end

-- =========================================================
-- [[ NOCLIP ]]
-- =========================================================
local noclipConn = nil
local function ToggleNoclip(state)
    noclipActive = state
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if state then
        noclipConn = RunService.Stepped:Connect(function()
            local c = LocalPlayer.Character
            if c then
                for _, p in pairs(c:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end
        end)
    end
end

-- =========================================================
-- [[ ESP ]]
-- =========================================================
local function ClearESP()
    for _, o in pairs(espObjects) do pcall(function() o:Destroy() end) end
    espObjects = {}
end

local function CreateESP()
    ClearESP()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local head = plr.Character:FindFirstChild("Head")
            if head then
                local bb = Instance.new("BillboardGui")
                bb.Adornee = head
                bb.Size = UDim2.new(0, 200, 0, 50)
                bb.StudsOffset = Vector3.new(0, 3, 0)
                bb.AlwaysOnTop = true
                bb.Parent = head

                local nl = Instance.new("TextLabel")
                nl.Size = UDim2.new(1, 0, 0.5, 0)
                nl.BackgroundTransparency = 1
                nl.TextColor3 = Color3.fromRGB(255, 255, 255)
                nl.TextStrokeTransparency = 0
                nl.Font = Enum.Font.GothamBold
                nl.TextSize = 14
                nl.Text = plr.Name
                nl.Parent = bb

                local dl = Instance.new("TextLabel")
                dl.Name = "Dist"
                dl.Size = UDim2.new(1, 0, 0.5, 0)
                dl.Position = UDim2.new(0, 0, 0.5, 0)
                dl.BackgroundTransparency = 1
                dl.TextColor3 = Color3.fromRGB(255, 255, 100)
                dl.TextStrokeTransparency = 0
                dl.Font = Enum.Font.Gotham
                dl.TextSize = 12
                dl.Text = "0m"
                dl.Parent = bb

                table.insert(espObjects, bb)

                local hl = Instance.new("Highlight")
                hl.FillTransparency = 0.7
                hl.OutlineTransparency = 0
                hl.FillColor = Color3.fromRGB(0, 100, 255)
                hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                hl.Parent = plr.Character
                table.insert(espObjects, hl)
            end
        end
    end
end

-- ESP дистанция обновляется в фоне
task.spawn(function()
    while true do
        task.wait(0.5)
        if espActive then
            local mHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if mHRP then
                for _, o in pairs(espObjects) do
                    pcall(function()
                        if o:IsA("BillboardGui") and o.Adornee and o.Adornee.Parent then
                            local dl = o:FindFirstChild("Dist")
                            if dl then
                                local d = (mHRP.Position - o.Adornee.Position).Magnitude
                                dl.Text = string.format("%.0fm", d)
                                if d < 30 then
                                    dl.TextColor3 = Color3.fromRGB(255, 50, 50)
                                elseif d < 80 then
                                    dl.TextColor3 = Color3.fromRGB(255, 255, 50)
                                else
                                    dl.TextColor3 = Color3.fromRGB(50, 255, 50)
                                end
                            end
                        end
                    end)
                end
            end
        end
    end
end)

-- =========================================================
-- [[ БИНДЫ ]]
-- =========================================================
local waitingForBind = false

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end

    if waitingForBind then
        if input.KeyCode ~= Enum.KeyCode.Unknown then
            selectBind = input.KeyCode
            waitingForBind = false
            Rayfield:Notify({Title = "Bind Set", Content = "Select bind: " .. selectBind.Name, Duration = 2})
        end
        return
    end

    -- T = TP к курсору
    if input.KeyCode == Enum.KeyCode.T then
        pcall(function()
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then root.CFrame = CFrame.new(Mouse.Hit.Position + Vector3.new(0, 3, 0)) end
        end)
    end

    -- Бинд выбора цели
    if input.KeyCode == selectBind then
        pcall(function()
            local model = Mouse.Target and Mouse.Target:FindFirstAncestorOfClass("Model")
            if model then
                local plr = Players:GetPlayerFromCharacter(model)
                if plr and plr ~= LocalPlayer then
                    if _G.KickEnabled and selectedTarget and selectedTarget ~= plr and selectedTarget.Parent then
                        Rayfield:Notify({Title = "Blocked", Content = "Already kicking " .. selectedTarget.Name .. "! Stop kick first.", Duration = 3})
                        return
                    end
                    selectedTarget = plr
                    AddToSaved(plr.Name)
                    Rayfield:Notify({Title = "Selected", Content = plr.Name, Duration = 2})
                    if _G.KickEnabled then
                        KickPlayer(selectedTarget)
                    end
                end
            end
        end)
    end
end)

-- Loop TP
task.spawn(function()
    while true do
        task.wait(0.3)
        if loopTPActive and selectedTarget then
            pcall(function()
                local mR = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                local tR = selectedTarget.Character and selectedTarget.Character:FindFirstChild("HumanoidRootPart")
                if mR and tR then mR.CFrame = tR.CFrame * CFrame.new(0, 0, 10) end
            end)
        end
    end
end)

-- Speed/Jump
task.spawn(function()
    while true do
        task.wait(1)
        pcall(function()
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
            if hum then
                if customSpeed ~= 16 then hum.WalkSpeed = customSpeed end
                if customJump ~= 50 then hum.JumpPower = customJump end
            end
        end)
    end
end)

-- Packet Detector
local function AnalyzePacket(_, args)
    if not _G.PacketMonitor then return end
    pcall(function()
        local sz = 0
        local who = "?"
        for _, a in pairs(args) do
            if type(a) == "string" then sz = sz + #a end
            if typeof(a) == "Instance" and a:IsA("BasePart") then
                local p = Players:GetPlayerFromCharacter(a.Parent)
                if p then who = p.Name end
            end
        end
        if sz / 1024 > 10 then
            local s = sz / 1024
            SystemChat("LAG! " .. who .. " | " .. (s >= 1024 and string.format("%.1fMB", s/1024) or string.format("%.1fKB", s)), Color3.fromRGB(255, 0, 0))
        end
    end)
end
if extendLine then pcall(function() extendLine.OnClientEvent:Connect(function(...) AnalyzePacket("E", {...}) end) end) end
if createLine then pcall(function() createLine.OnClientEvent:Connect(function(...) AnalyzePacket("C", {...}) end) end) end

-- =========================================================
-- [[ GUI ]]
-- =========================================================
local TabCombat = Window:CreateTab("Combat", 4483362458)
local TabMove = Window:CreateTab("Movement", 4483362458)
local TabVisual = Window:CreateTab("Visuals", 4483362458)
local TabPhys = Window:CreateTab("Physics", 4483362458)

-- === TARGET MANAGER ===
TabCombat:CreateSection("Target Manager")

TabCombat:CreateDropdown({
    Name = "Server Players",
    Options = GetNames(),
    CurrentOption = {},
    MultiSelection = false,
    Callback = function(Value)
        local name = Value
        if type(Value) == "table" then name = Value[1] end
        if not name or name == "No players" then return end
        if _G.KickEnabled and selectedTarget and selectedTarget.Parent then
            local newPlr = Players:FindFirstChild(name)
            if newPlr and newPlr ~= selectedTarget then
                Rayfield:Notify({Title = "Blocked", Content = "Stop kick first!", Duration = 3})
                return
            end
        end
        selectedTarget = Players:FindFirstChild(name)
        if selectedTarget then
            AddToSaved(name)
            Rayfield:Notify({Title = "Selected", Content = name, Duration = 2})
            if _G.KickEnabled then KickPlayer(selectedTarget) end
        end
    end,
})

DropSaved = TabCombat:CreateDropdown({
    Name = "Saved Targets",
    Options = {"Empty"},
    CurrentOption = {},
    MultiSelection = false,
    Callback = function(Value)
        local name = Value
        if type(Value) == "table" then name = Value[1] end
        if not name or name == "Empty" then return end
        if _G.KickEnabled and selectedTarget and selectedTarget.Parent then
            local newPlr = Players:FindFirstChild(name)
            if newPlr and newPlr ~= selectedTarget then
                Rayfield:Notify({Title = "Blocked", Content = "Stop kick first!", Duration = 3})
                return
            end
        end
        currentSaved = name
        local plr = Players:FindFirstChild(name)
        if plr then
            selectedTarget = plr
            Rayfield:Notify({Title = "Locked", Content = name, Duration = 2})
            if _G.KickEnabled then KickPlayer(selectedTarget) end
        else
            Rayfield:Notify({Title = "Offline", Content = name .. " not in server", Duration = 3})
        end
    end,
})

TabCombat:CreateButton({
    Name = "Remove Selected",
    Callback = function()
        if currentSaved then
            for i, v in ipairs(savedTargets) do
                if v == currentSaved then table.remove(savedTargets, i) break end
            end
            pcall(function()
                DropSaved:Set(#savedTargets > 0 and savedTargets or {"Empty"})
            end)
            currentSaved = nil
        end
    end
})

TabCombat:CreateButton({
    Name = "Clear All",
    Callback = function()
        savedTargets = {}
        pcall(function() DropSaved:Set({"Empty"}) end)
        selectedTarget = nil
        currentSaved = nil
        StopKick()
    end
})

-- Игрок зашёл
Players.PlayerAdded:Connect(function(plr)
    for _, n in pairs(savedTargets) do
        if n == plr.Name then
            SystemChat(plr.Name .. " JOINED!", Color3.fromRGB(255, 0, 0))
            Rayfield:Notify({Title = "Alert", Content = plr.Name .. " is back!", Duration = 5})
            if _G.KickEnabled and selectedTarget and selectedTarget.Name == plr.Name then
                task.wait(2)
                selectedTarget = plr
                KickPlayer(plr)
            end
        end
    end
    if espActive then task.wait(2) CreateESP() end
end)

-- Игрок вышел
Players.PlayerRemoving:Connect(function(plr)
    for _, n in pairs(savedTargets) do
        if n == plr.Name then
            SystemChat(plr.Name .. " LEFT!", Color3.fromRGB(0, 255, 0))
        end
    end
end)

-- === KICK ===
TabCombat:CreateSection("Kick")

TabCombat:CreateToggle({
    Name = "Start Kick",
    CurrentValue = false,
    Callback = function(Value)
        _G.KickEnabled = Value
        if Value then
            if selectedTarget and selectedTarget.Parent then
                KickPlayer(selectedTarget)
                Rayfield:Notify({Title = "Kick", Content = "Kicking: " .. selectedTarget.Name, Duration = 3})
            else
                Rayfield:Notify({Title = "Ready", Content = "Select target to kick", Duration = 3})
            end
        else
            StopKick()
        end
    end,
})

-- === SELECT BIND ===
TabCombat:CreateSection("Select Bind")

local bindLabel = TabCombat:CreateLabel("Current bind: E")

TabCombat:CreateButton({
    Name = "Change Select Bind",
    Callback = function()
        waitingForBind = true
        Rayfield:Notify({Title = "Waiting...", Content = "Press any key", Duration = 5})
        task.spawn(function()
            while waitingForBind do task.wait(0.1) end
            pcall(function() bindLabel:Set("Current bind: " .. selectBind.Name) end)
        end)
    end,
})

TabCombat:CreateParagraph({
    Title = "How it works",
    Content = "Thread 1 (Heartbeat): ownership + freeze + BodyMovers every frame\nThread 2: extra ownership spam every 0.05s\nThread 3: TP re-grab + weapon remove\nRespawn: auto re-grab on target/self respawn\nBP: D=" .. KICK_BP_D .. " P=" .. KICK_BP_P,
})

-- === MOVEMENT ===
TabMove:CreateSection("Teleport")
TabMove:CreateToggle({Name = "Loop TP to Target", CurrentValue = false, Callback = function(v) loopTPActive = v end})

TabMove:CreateSection("Speed")
TabMove:CreateSlider({
    Name = "Walk Speed", Range = {16, 200}, Increment = 1, Suffix = "",
    CurrentValue = 16,
    Callback = function(v)
        customSpeed = v
        pcall(function()
            local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
            if h then h.WalkSpeed = v end
        end)
    end
})
TabMove:CreateSlider({
    Name = "Jump Power", Range = {50, 300}, Increment = 5, Suffix = "",
    CurrentValue = 50,
    Callback = function(v)
        customJump = v
        pcall(function()
            local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
            if h then h.JumpPower = v end
        end)
    end
})
TabMove:CreateToggle({Name = "Noclip", CurrentValue = false, Callback = function(v) ToggleNoclip(v) end})

-- === VISUALS ===
TabVisual:CreateSection("ESP")
TabVisual:CreateToggle({
    Name = "Player ESP", CurrentValue = false,
    Callback = function(v)
        espActive = v
        if v then CreateESP() else ClearESP() end
    end
})
TabVisual:CreateButton({Name = "Refresh ESP", Callback = function() if espActive then CreateESP() end end})

-- === PHYSICS ===
TabPhys:CreateToggle({Name = "PCLD", CurrentValue = false, Callback = function(v) pcldActive = v end})
TabPhys:CreateToggle({Name = "Packet Detector", CurrentValue = false, Callback = function(v) _G.PacketMonitor = v end})



