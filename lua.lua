-- [[ RAYFIELD ]]
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "Universal Hack v10",
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
local selectBind = Enum.KeyCode.E

-- [[ ИВЕНТЫ ]]
local GE = ReplicatedStorage:WaitForChild("GrabEvents", 10)
if not GE then Rayfield:Notify({Title = "Error", Content = "No GrabEvents!", Duration = 5}) return end
local destroyGrabLine = GE:WaitForChild("DestroyGrabLine", 5)
local setOwner = GE:WaitForChild("SetNetworkOwner", 5)
local extendLine = GE:WaitForChild("ExtendGrabLine", 5)
local createLine = GE:WaitForChild("CreateGrabLine", 5)

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

local DropSaved = nil

local function AddToSaved(name)
    if not name then return end
    for _, v in pairs(savedTargets) do
        if v == name then return end
    end
    table.insert(savedTargets, name)
    if DropSaved then DropSaved:Set(savedTargets) end
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
-- [[ КИК — ОПТИМИЗИРОВАННЫЙ ]]
-- =========================================================
local function StopKick()
    if _G.StopKickFunc then
        _G.StopKickFunc()
        _G.StopKickFunc = nil
    end
end

local function KickPlayer(targetPlayer)
    if not targetPlayer then return end
    StopKick()
    task.wait(0.05)

    local kickActive = true
    local connections = {}

    -- Респавн реконнект
    local respawnConn = targetPlayer.CharacterAdded:Connect(function()
        task.wait(1.5)
    end)
    table.insert(connections, respawnConn)

    -- Счётчик кадров — спамим НЕ каждый кадр, а раз в 2-3 кадра
    local frameCounter = 0

    local heartbeatConn = RunService.Heartbeat:Connect(function()
        if not kickActive then return end
        if not targetPlayer or not targetPlayer.Parent then return end

        frameCounter = frameCounter + 1

        local tChar = targetPlayer.Character
        if not tChar then return end
        local tHRP = tChar:FindFirstChild("HumanoidRootPart")
        local tHum = tChar:FindFirstChild("Humanoid")
        if not tHRP then return end

        -- Каждый кадр: убираем физику локально (не сервер)
        pcall(function()
            tHRP.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            tHRP.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        end)

        if tHum then
            tHum.PlatformStand = true
        end

        -- Серверные вызовы — раз в 3 кадра (≈20 раз/сек вместо 60)
        if frameCounter % 3 == 0 then
            if tHRP.Position.Y < 2000 and setOwner and destroyGrabLine then
                setOwner:FireServer(tHRP, tHRP.CFrame)
                destroyGrabLine:FireServer(tHRP)
            end
        end
    end)
    table.insert(connections, heartbeatConn)

    -- Основной цикл — TP + BodyMovers
    task.spawn(function()
        while kickActive do
            if not targetPlayer or not targetPlayer.Parent then break end

            local targetChar = targetPlayer.Character
            local myChar = LocalPlayer.Character
            if targetChar and myChar then
                local tHRP = targetChar:FindFirstChild("HumanoidRootPart")
                local mHRP = myChar:FindFirstChild("HumanoidRootPart")
                if tHRP and mHRP then
                    -- BodyPosition — держим над собой
                    local holdPos = mHRP.Position + Vector3.new(0, 15, 0)

                    local bp = tHRP:FindFirstChild("KickBP")
                    if not bp then
                        bp = Instance.new("BodyPosition")
                        bp.Name = "KickBP"
                        bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                        bp.D = 200
                        bp.P = 20000
                        bp.Parent = tHRP
                    end
                    bp.Position = holdPos

                    local bg = tHRP:FindFirstChild("KickBG")
                    if not bg then
                        bg = Instance.new("BodyGyro")
                        bg.Name = "KickBG"
                        bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                        bg.Parent = tHRP
                    end
                    bg.CFrame = mHRP.CFrame

                    -- Убираем оружие
                    local spawned = Workspace:FindFirstChild(targetPlayer.Name .. "SpawnedInToys")
                    if spawned then
                        local function yeet(part)
                            if part and setOwner then
                                setOwner:FireServer(part, part.CFrame)
                                if part:FindFirstChild("PartOwner") and part.PartOwner.Value == LocalPlayer.Name then
                                    part.CFrame = CFrame.new(0, 10000, 0)
                                end
                            end
                        end
                        if spawned:FindFirstChild("NinjaKunai") then yeet(spawned.NinjaKunai:FindFirstChild("SoundPart")) end
                        if spawned:FindFirstChild("NinjaShuriken") then yeet(spawned.NinjaShuriken:FindFirstChild("SoundPart")) end
                    end

                    -- TP к цели если далеко — берём ownership
                    local dist = (mHRP.Position - tHRP.Position).Magnitude
                    if tHRP.Position.Y < 2000 and dist > 25 then
                        local oldCF = mHRP.CFrame
                        mHRP.CFrame = tHRP.CFrame * CFrame.new(0, 0, 5)

                        -- 3 вызова — не 5, не 10, достаточно
                        for _ = 1, 3 do
                            setOwner:FireServer(tHRP, tHRP.CFrame)
                            destroyGrabLine:FireServer(tHRP)
                        end

                        task.wait(0.15)
                        if myChar and mHRP and mHRP.Parent then
                            mHRP.CFrame = oldCF
                        end
                    end
                end
            end
            task.wait(0.08)
        end

        -- Очистка
        for _, conn in pairs(connections) do
            pcall(function() conn:Disconnect() end)
        end

        if targetPlayer and targetPlayer.Character then
            local r = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
            local h = targetPlayer.Character:FindFirstChild("Humanoid")
            if r then
                if r:FindFirstChild("KickBP") then r.KickBP:Destroy() end
                if r:FindFirstChild("KickBG") then r.KickBG:Destroy() end
            end
            if h then h.PlatformStand = false end
        end
    end)

    _G.StopKickFunc = function()
        kickActive = false
    end
end

-- =========================================================
-- [[ PCLD ]]
-- =========================================================
task.spawn(function()
    while true do
        task.wait(0.5)
        if pcldActive then
            pcall(function()
                LocalPlayer.SimulationRadius = math.huge
                LocalPlayer.MaximumSimulationRadius = math.huge
                settings().Physics.AllowSleep = false
            end)
            if selectedTarget and selectedTarget.Character and setOwner then
                local tRoot = selectedTarget.Character:FindFirstChild("HumanoidRootPart")
                if tRoot then pcall(function() setOwner:FireServer(tRoot, tRoot.CFrame) end) end
            end
        end
    end
end)

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
            if c then for _, p in pairs(c:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = false end end end
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

task.spawn(function()
    while true do
        task.wait(0.5)
        if espActive then
            local mHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if mHRP then
                for _, o in pairs(espObjects) do
                    if o:IsA("BillboardGui") and o.Adornee and o.Adornee.Parent then
                        local dl = o:FindFirstChild("Dist")
                        if dl then
                            local d = (mHRP.Position - o.Adornee.Position).Magnitude
                            dl.Text = string.format("%.0fm", d)
                            dl.TextColor3 = d < 30 and Color3.fromRGB(255,50,50) or d < 80 and Color3.fromRGB(255,255,50) or Color3.fromRGB(50,255,50)
                        end
                    end
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

    if input.KeyCode == Enum.KeyCode.T then
        local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if root then root.CFrame = CFrame.new(Mouse.Hit.Position + Vector3.new(0, 3, 0)) end
    end

    if input.KeyCode == selectBind then
        local model = Mouse.Target and Mouse.Target:FindFirstAncestorOfClass("Model")
        if model then
            local plr = Players:GetPlayerFromCharacter(model)
            if plr and plr ~= LocalPlayer then
                selectedTarget = plr
                AddToSaved(plr.Name)
                Rayfield:Notify({Title = "Selected", Content = plr.Name, Duration = 2})
                if _G.KickEnabled then
                    KickPlayer(selectedTarget)
                end
            end
        end
    end
end)

-- Loop TP
task.spawn(function()
    while true do
        task.wait(0.3)
        if loopTPActive and selectedTarget then
            local mR = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local tR = selectedTarget.Character and selectedTarget.Character:FindFirstChild("HumanoidRootPart")
            if mR and tR then mR.CFrame = tR.CFrame * CFrame.new(0, 0, 10) end
        end
    end
end)

-- Speed/Jump
task.spawn(function()
    while true do
        task.wait(1)
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then
            if customSpeed ~= 16 then hum.WalkSpeed = customSpeed end
            if customJump ~= 50 then hum.JumpPower = customJump end
        end
    end
end)

-- Packet Detector
local function AnalyzePacket(_, args)
    if not _G.PacketMonitor then return end
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
end
if extendLine then extendLine.OnClientEvent:Connect(function(...) AnalyzePacket("E", {...}) end) end
if createLine then createLine.OnClientEvent:Connect(function(...) AnalyzePacket("C", {...}) end) end

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
        selectedTarget = Players:FindFirstChild(name)
        AddToSaved(name)
        Rayfield:Notify({Title = "Selected", Content = name, Duration = 2})
        if _G.KickEnabled and selectedTarget then
            KickPlayer(selectedTarget)
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
        currentSaved = name
        local plr = Players:FindFirstChild(name)
        if plr then
            selectedTarget = plr
            Rayfield:Notify({Title = "Locked", Content = name, Duration = 2})
            if _G.KickEnabled then
                KickPlayer(selectedTarget)
            end
        else
            Rayfield:Notify({Title = "Offline", Content = name .. " not in server", Duration = 3})
        end
    end,
})

TabCombat:CreateButton({Name = "Remove Selected", Callback = function()
    if currentSaved then
        for i, v in ipairs(savedTargets) do
            if v == currentSaved then table.remove(savedTargets, i) break end
        end
        DropSaved:Set(#savedTargets > 0 and savedTargets or {"Empty"})
        currentSaved = nil
    end
end})

TabCombat:CreateButton({Name = "Clear All", Callback = function()
    savedTargets = {}
    DropSaved:Set({"Empty"})
    selectedTarget = nil
    currentSaved = nil
    StopKick()
end})

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
            bindLabel:Set("Current bind: " .. selectBind.Name)
        end)
    end,
})

TabCombat:CreateParagraph({
    Title = "Controls",
    Content = "Bind = aim + press to select target\nT = teleport to mouse\nKick holds target above your head\nOptimized: ~20 server calls/sec (no ping lag)",
})

-- === MOVEMENT ===
TabMove:CreateSection("Teleport")
TabMove:CreateToggle({Name = "Loop TP to Target", CurrentValue = false, Callback = function(v) loopTPActive = v end})

TabMove:CreateSection("Speed")
TabMove:CreateSlider({Name = "Walk Speed", Range = {16, 200}, Increment = 1, Suffix = "", CurrentValue = 16, Callback = function(v)
    customSpeed = v
    local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
    if h then h.WalkSpeed = v end
end})
TabMove:CreateSlider({Name = "Jump Power", Range = {50, 300}, Increment = 5, Suffix = "", CurrentValue = 50, Callback = function(v)
    customJump = v
    local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
    if h then h.JumpPower = v end
end})
TabMove:CreateToggle({Name = "Noclip", CurrentValue = false, Callback = function(v) ToggleNoclip(v) end})

-- === VISUALS ===
TabVisual:CreateSection("ESP")
TabVisual:CreateToggle({Name = "Player ESP", CurrentValue = false, Callback = function(v) espActive = v if v then CreateESP() else ClearESP() end end})
TabVisual:CreateButton({Name = "Refresh ESP", Callback = function() if espActive then CreateESP() end end})

-- === PHYSICS ===
TabPhys:CreateToggle({Name = "PCLD", CurrentValue = false, Callback = function(v) pcldActive = v end})
TabPhys:CreateToggle({Name = "Packet Detector", CurrentValue = false, Callback = function(v) _G.PacketMonitor = v end})