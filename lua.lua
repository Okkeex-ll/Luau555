-- ============================================================
-- fife | 1.3 — улучшенный KickPlayer
-- ============================================================

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "fife | 1.3",
    LoadingTitle = "fife",
    LoadingSubtitle = "loading...",
    ConfigurationSaving = { Enabled = false, FileName = "fife13" },
    KeySystem = false,
})

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local RepStorage = game:GetService("ReplicatedStorage")
local WS         = game:GetService("Workspace")
local UIS        = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Stats      = game:GetService("Stats")

local LP    = Players.LocalPlayer
local Mouse = LP:GetMouse()

-- ============================================================
-- GrabEvents
-- ============================================================
local GE = RepStorage:WaitForChild("GrabEvents", 10)
if not GE then
    Rayfield:Notify({Title = "Error", Content = "GrabEvents not found", Duration = 5})
end

local destroyGrabLine = GE and GE:WaitForChild("DestroyGrabLine", 5)
local setOwner        = GE and GE:WaitForChild("SetNetworkOwner", 5)
local extendLine      = GE and GE:FindFirstChild("ExtendGrabLine")
local createLine      = GE and GE:FindFirstChild("CreateGrabLine")

-- Безопасные обёртки для Remote-вызовов
local function fireOwner(part, cf)
    if setOwner and part and part.Parent then
        pcall(function() setOwner:FireServer(part, cf) end)
    end
end

local function fireDestroy(part)
    if destroyGrabLine and part and part.Parent then
        pcall(function() destroyGrabLine:FireServer(part) end)
    end
end

local function fireExtend(part, cf)
    if extendLine and part and part.Parent then
        pcall(function() extendLine:FireServer(part, cf) end)
    end
end

local function fireCreate(part, cf)
    if createLine and part and part.Parent then
        pcall(function() createLine:FireServer(part, cf) end)
    end
end

-- ============================================================
-- Утилиты
-- ============================================================
local function sysChat(text, color)
    pcall(function()
        StarterGui:SetCore("ChatMakeSystemMessage", {
            Text  = "[fife]: " .. text,
            Color = color or Color3.fromRGB(255, 80, 80),
            Font  = Enum.Font.GothamBold,
            FontSize = Enum.FontSize.Size18,
        })
    end)
end

local function getHRP(player)
    local c = player and player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHum(player)
    local c = player and player.Character
    return c and c:FindFirstChild("Humanoid")
end

-- ============================================================
-- Переменные
-- ============================================================
local selectedTarget = nil
local savedTargets   = {}
local currentSaved   = nil

_G.KickEnabled   = false
_G.StopKickFunc  = nil
_G.PacketMonitor = false

local espEnabled  = false
local espColor    = Color3.fromRGB(0, 170, 255)
local espObjects  = {}

local pcldOn      = false
local pcldColor   = Color3.fromRGB(255, 0, 0)
local pcldTrans   = 0.5
local trackedPCLD = nil
local pcldConns   = {}

local noclipOn    = false
local noclipConn  = nil
local noclipParts = {}

local loopTPOn    = false
local customSpeed = 16
local customJump  = 50
local selectBind  = Enum.KeyCode.X

-- ============================================================
-- HUD
-- ============================================================
do
    local old = game:GetService("CoreGui"):FindFirstChild("fifeHUD")
    if old then old:Destroy() end

    local hud = Instance.new("ScreenGui")
    hud.Name = "fifeHUD"
    hud.ResetOnSpawn = false
    hud.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hud.IgnoreGuiInset = true

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 520, 0, 36)
    bar.Position = UDim2.new(0.5, -260, 0, 6)
    bar.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    bar.BackgroundTransparency = 0.15
    bar.BorderSizePixel = 0
    bar.Parent = hud

    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 18)

    local st = Instance.new("UIStroke")
    st.Color = Color3.fromRGB(80, 80, 120)
    st.Thickness = 1.5
    st.Transparency = 0.5
    st.Parent = bar

    local lay = Instance.new("UIListLayout")
    lay.FillDirection = Enum.FillDirection.Horizontal
    lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
    lay.VerticalAlignment = Enum.VerticalAlignment.Center
    lay.Padding = UDim.new(0, 20)
    lay.Parent = bar

    local function makeLabel(text, col)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, 110, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.TextColor3 = col or Color3.fromRGB(200, 200, 210)
        lbl.Text = text
        lbl.Parent = bar
        return lbl
    end

    local lblNick    = makeLabel(LP.Name, Color3.fromRGB(130, 180, 255))
    local lblFPS     = makeLabel("FPS: --")
    local lblPing    = makeLabel("Ping: --")
    local lblPlayers = makeLabel("0 online")

    hud.Parent = game:GetService("CoreGui")

    local fc, lf = 0, tick()
    RunService.Heartbeat:Connect(function()
        fc = fc + 1
        local n = tick()
        if n - lf >= 0.4 then
            lblFPS.Text = "FPS: " .. math.floor(fc / (n - lf))
            fc = 0
            lf = n
        end
    end)

    task.spawn(function()
        while true do
            pcall(function()
                lblPing.Text = "Ping: " .. math.floor(
                    Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
                ) .. "ms"
            end)
            lblPlayers.Text = #Players:GetPlayers() .. " online"
            task.wait(0.5)
        end
    end)
end

-- ============================================================
-- KICK — v2 (полностью переработанный)
-- ============================================================
--[[
    Архитектура:
    • Один Heartbeat-коннект: овнершип + destroy + extend + velocity-контроль + SimRadius
    • Один task.spawn: TP-перехват с кулдауном + обработка игрушек (throttled)
    • CharacterAdded: автоматический перехват после респавна цели
    • Без BodyMovers и PlatformStand — чисто сетевой контроль
    
    Баланс нагрузки:
    • Heartbeat: ~60 FireServer/сек (owner) + ~60 (destroy) + ~60 (extend) = ~180/сек
    • Task.spawn: ~12.5 итераций/сек, TP макс 2/сек, игрушки каждые 0.3с
    • Итого ~200 FireServer/сек — агрессивно, но не убивает пинг
]]

-- Константы кика — все параметры в одном месте
local KICK_CFG = {
    TASK_INTERVAL   = 0.08,  -- интервал доп. потока (сек)
    TP_THRESHOLD    = 40,    -- дистанция для телепорта (стадов)
    TP_COOLDOWN     = 0.5,   -- минимум между телепортами (сек)
    TP_BURST        = 2,     -- кол-во burst-вызовов при TP
    TP_WAIT         = 0.12,  -- пауза перед возвратом после TP
    TP_OFFSET       = 4,     -- отступ от цели при TP (стадов)
    TOY_INTERVAL    = 0.3,   -- интервал проверки игрушек (сек)
    RESPAWN_DELAY   = 1.2,   -- задержка перехвата после респавна (сек)
    Y_LIMIT         = 2000,  -- граница по Y для пропуска (цель уже улетела)
}

local function StopKick()
    if _G.StopKickFunc then
        pcall(_G.StopKickFunc)
        _G.StopKickFunc = nil
    end
end

local function KickPlayer(target)
    if not target then return end
    
    -- Проверяем наличие инструментов до начала
    if not setOwner or not destroyGrabLine then
        Rayfield:Notify({
            Title = "Error",
            Content = "Remote events missing",
            Duration = 3,
        })
        _G.KickEnabled = false
        return
    end
    
    -- Останавливаем предыдущий кик (если был)
    StopKick()
    task.wait(0.02)

    local active = true
    local conns  = {}         -- все коннекты для cleanup
    local lastTP = 0          -- таймстамп последнего TP
    local lastToy = 0         -- таймстамп последней проверки игрушек
    local kickFrame = 0       -- счётчик кадров (для throttle внутри heartbeat)

    -- ── Cleanup ──────────────────────────────────────────────
    local function cleanup()
        if not active then return end
        active = false
        for _, c in ipairs(conns) do
            pcall(function() c:Disconnect() end)
        end
        conns = {}
    end

    -- ── Обработка игрушек (throttled) ────────────────────────
    local function processToys()
        local now = tick()
        if now - lastToy < KICK_CFG.TOY_INTERVAL then return end
        lastToy = now

        if not target or not target.Parent then return end
        local spawned = WS:FindFirstChild(target.Name .. "SpawnedInToys")
        if not spawned then return end

        local toyNames = {"NinjaKunai", "NinjaShuriken"}
        for _, toyName in ipairs(toyNames) do
            local toy = spawned:FindFirstChild(toyName)
            if toy then
                local sp = toy:FindFirstChild("SoundPart")
                if sp and sp.Parent then
                    fireOwner(sp, sp.CFrame)
                    -- Если мы владелец — убираем в небо
                    local ownerVal = sp:FindFirstChild("PartOwner")
                    if ownerVal and ownerVal.Value == LP.Name then
                        pcall(function()
                            sp.CFrame = CFrame.new(0, 10000, 0)
                        end)
                    end
                end
            end
        end
    end

    -- ── Обнуление физики цели ────────────────────────────────
    local function neutralizePhysics(tHRP)
        pcall(function()
            tHRP.AssemblyLinearVelocity  = Vector3.zero
            tHRP.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    -- ── Буст SimRadius ───────────────────────────────────────
    local function boostSim()
        pcall(function()
            LP.SimulationRadius        = math.huge
            LP.MaximumSimulationRadius  = math.huge
        end)
    end

    -- ── Сетевой спам (основная "давилка") ────────────────────
    -- Вызывается в Heartbeat — один набор вызовов за кадр
    local function networkPressure(tHRP)
        local cf = tHRP.CFrame
        fireOwner(tHRP, cf)
        fireDestroy(tHRP)
        fireExtend(tHRP, cf)
    end

    -- ── Дополнительные части персонажа ───────────────────────
    -- Берём овнершип не только HRP, но и Head/Torso для усиления
    local function grabExtraParts(tChar)
        for _, partName in ipairs({"Head", "UpperTorso", "LowerTorso", "Torso"}) do
            local p = tChar:FindFirstChild(partName)
            if p and p:IsA("BasePart") then
                fireOwner(p, p.CFrame)
            end
        end
    end

    -- ══════════════════════════════════════════════════════════
    -- HEARTBEAT — основной цикл (~60 fps)
    -- Задачи: SimRadius, овнершип, destroy, extend, velocity
    -- ══════════════════════════════════════════════════════════
    local hbConn = RunService.Heartbeat:Connect(function()
        if not active then return end
        if not target or not target.Parent then return end

        local tChar = target.Character
        if not tChar then return end
        local tHRP = tChar:FindFirstChild("HumanoidRootPart")
        if not tHRP then return end

        -- Пропускаем если цель уже улетела за пределы
        if tHRP.Position.Y > KICK_CFG.Y_LIMIT then return end

        kickFrame = kickFrame + 1

        -- SimRadius — каждый кадр
        boostSim()

        -- Основной сетевой спам — каждый кадр
        networkPressure(tHRP)

        -- Обнуление физики — каждый кадр
        neutralizePhysics(tHRP)

        -- Дополнительные части — каждые 3 кадра (не каждый, чтобы не перегружать)
        if kickFrame % 3 == 0 then
            grabExtraParts(tChar)
        end

        -- Игрушки — по throttle-таймеру
        processToys()
    end)
    table.insert(conns, hbConn)

    -- ══════════════════════════════════════════════════════════
    -- TASK.SPAWN — TP-перехват
    -- Единственная задача: если далеко — подлететь, перехватить, вернуться
    -- ══════════════════════════════════════════════════════════
    task.spawn(function()
        while active do
            -- Проверка валидности
            if not target or not target.Parent then break end

            local myChar = LP.Character
            local tChar  = target.Character

            if myChar and tChar then
                local mHRP = myChar:FindFirstChild("HumanoidRootPart")
                local tHRP = tChar:FindFirstChild("HumanoidRootPart")

                if mHRP and mHRP.Parent and tHRP and tHRP.Parent then
                    local dist = (mHRP.Position - tHRP.Position).Magnitude
                    local now  = tick()

                    -- TP только если: далеко + кулдаун прошёл + цель не в небе
                    if dist > KICK_CFG.TP_THRESHOLD
                       and now - lastTP >= KICK_CFG.TP_COOLDOWN
                       and tHRP.Position.Y < KICK_CFG.Y_LIMIT
                    then
                        lastTP = now

                        -- Сохраняем позицию
                        local savedCF = mHRP.CFrame

                        -- Телепорт к цели
                        pcall(function()
                            mHRP.CFrame = tHRP.CFrame * CFrame.new(0, 0, KICK_CFG.TP_OFFSET)
                        end)

                        -- Burst-спам при сближении
                        for _ = 1, KICK_CFG.TP_BURST do
                            if not active then break end
                            if tHRP and tHRP.Parent then
                                local cf = tHRP.CFrame
                                fireOwner(tHRP, cf)
                                fireDestroy(tHRP)
                                fireExtend(tHRP, cf)
                            end
                        end

                        -- Короткая пауза, чтобы сервер обработал
                        task.wait(KICK_CFG.TP_WAIT)

                        -- Возврат на исходную позицию
                        if active and myChar and myChar.Parent then
                            local hrpNow = myChar:FindFirstChild("HumanoidRootPart")
                            if hrpNow and hrpNow.Parent then
                                pcall(function()
                                    hrpNow.CFrame = savedCF
                                end)
                            end
                        end
                    end
                end
            end

            task.wait(KICK_CFG.TASK_INTERVAL)
        end

        -- Если цикл вышел сам (target ушёл) — cleanup
        cleanup()
    end)

    -- ══════════════════════════════════════════════════════════
    -- CharacterAdded — перехват после респавна цели
    -- ══════════════════════════════════════════════════════════
    local charConn = target.CharacterAdded:Connect(function(newChar)
        if not active then return end

        -- Ждём загрузки нового персонажа
        task.wait(KICK_CFG.RESPAWN_DELAY)

        if not active then return end
        if not target or not target.Parent then return end

        local tHRP = newChar:FindFirstChild("HumanoidRootPart")
                  or newChar:WaitForChild("HumanoidRootPart", 3)
        if not tHRP then return end

        -- Агрессивный перехват сразу после респавна
        for _ = 1, 5 do
            if not active then return end
            fireOwner(tHRP, tHRP.CFrame)
            fireDestroy(tHRP)
            task.wait(0.05)
        end
    end)
    table.insert(conns, charConn)

    -- Сохраняем функцию остановки
    _G.StopKickFunc = function()
        cleanup()
    end
end

-- ============================================================
-- NOCLIP
-- ============================================================
local function cacheNoclipParts()
    noclipParts = {}
    local c = LP.Character
    if not c then return end
    for _, p in ipairs(c:GetChildren()) do
        if p:IsA("BasePart") then table.insert(noclipParts, p) end
    end
end

local function toggleNoclip(state)
    noclipOn = state
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if state then
        cacheNoclipParts()
        noclipConn = RunService.Stepped:Connect(function()
            for _, p in ipairs(noclipParts) do
                if p and p.Parent then p.CanCollide = false end
            end
        end)
    end
end

LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    if noclipOn then cacheNoclipParts() end
end)

-- ============================================================
-- SPEED / JUMP
-- ============================================================
RunService.Heartbeat:Connect(function()
    local hum = getHum(LP)
    if not hum then return end
    if customSpeed ~= 16 then hum.WalkSpeed = customSpeed end
    if customJump  ~= 50 then hum.JumpPower = customJump end
end)

-- ============================================================
-- PLAYER ESP
-- ============================================================
local function clearESP()
    for _, obj in pairs(espObjects) do pcall(function() obj:Destroy() end) end
    espObjects = {}
end

local function makeESP(plr)
    if plr == LP then return end
    local char = plr.Character
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end

    local hl = Instance.new("Highlight")
    hl.Name = "fifeHL"
    hl.FillTransparency    = 0.75
    hl.OutlineTransparency = 0
    hl.OutlineColor        = espColor
    hl.FillColor           = espColor
    hl.Parent              = char
    table.insert(espObjects, hl)

    local bb = Instance.new("BillboardGui")
    bb.Name         = "fifeBB"
    bb.Adornee      = head
    bb.Size         = UDim2.new(0, 180, 0, 44)
    bb.StudsOffset  = Vector3.new(0, 2.5, 0)
    bb.AlwaysOnTop  = true
    bb.Parent       = head

    local bg = Instance.new("Frame")
    bg.Size                 = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3     = Color3.fromRGB(15, 15, 15)
    bg.BackgroundTransparency = 0.35
    bg.BorderSizePixel      = 0
    bg.Parent               = bb

    Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 6)

    local us = Instance.new("UIStroke")
    us.Color        = espColor
    us.Thickness    = 1.5
    us.Transparency = 0.3
    us.Parent       = bg

    local nameL = Instance.new("TextLabel")
    nameL.Size                  = UDim2.new(1, -8, 0.5, 0)
    nameL.Position              = UDim2.new(0, 4, 0, 2)
    nameL.BackgroundTransparency = 1
    nameL.Font                  = Enum.Font.GothamBold
    nameL.TextSize              = 13
    nameL.TextColor3            = Color3.fromRGB(255, 255, 255)
    nameL.TextXAlignment        = Enum.TextXAlignment.Left
    nameL.TextStrokeTransparency = 0.5
    nameL.Text                  = plr.Name
    nameL.Parent                = bg

    local distL = Instance.new("TextLabel")
    distL.Name                   = "Dist"
    distL.Size                   = UDim2.new(1, -8, 0.5, 0)
    distL.Position               = UDim2.new(0, 4, 0.5, 0)
    distL.BackgroundTransparency = 1
    distL.Font                   = Enum.Font.Gotham
    distL.TextSize               = 11
    distL.TextColor3             = Color3.fromRGB(200, 200, 100)
    distL.TextXAlignment         = Enum.TextXAlignment.Left
    distL.TextStrokeTransparency = 0.5
    distL.Text                   = "0m"
    distL.Parent                 = bg

    table.insert(espObjects, bb)
end

local function createESP()
    clearESP()
    if not espEnabled then return end
    for _, plr in ipairs(Players:GetPlayers()) do makeESP(plr) end
end

local function updateESPColor()
    for _, obj in pairs(espObjects) do
        pcall(function()
            if obj:IsA("Highlight") then
                obj.OutlineColor = espColor
                obj.FillColor    = espColor
            elseif obj:IsA("BillboardGui") then
                local bg = obj:FindFirstChildWhichIsA("Frame")
                if bg then
                    local s = bg:FindFirstChildWhichIsA("UIStroke")
                    if s then s.Color = espColor end
                end
            end
        end)
    end
end

task.spawn(function()
    while true do
        task.wait(0.4)
        if espEnabled then
            local mHRP = getHRP(LP)
            if mHRP then
                for _, obj in pairs(espObjects) do
                    pcall(function()
                        if obj:IsA("BillboardGui") and obj.Adornee and obj.Adornee.Parent then
                            local bg = obj:FindFirstChildWhichIsA("Frame")
                            if not bg then return end
                            local dl = bg:FindFirstChild("Dist")
                            if dl then
                                local d = (mHRP.Position - obj.Adornee.Position).Magnitude
                                dl.Text = string.format("%.0fm", d)
                                dl.TextColor3 = d < 30
                                    and Color3.fromRGB(255, 60, 60)
                                    or d < 80
                                    and Color3.fromRGB(255, 220, 60)
                                    or Color3.fromRGB(60, 255, 60)
                            end
                        end
                    end)
                end
            end
        end
    end
end)

-- ============================================================
-- PCLD ESP
-- ============================================================
local PCLD_NAME = "PlayerCharacterLocationDetector"

local function pcldDisc(key)
    if pcldConns[key] then
        pcall(function() pcldConns[key]:Disconnect() end)
        pcldConns[key] = nil
    end
end

local function isMine(part)
    local hrp = getHRP(LP)
    if not hrp then return false end
    return (part.Position - hrp.Position).Magnitude < 2
end

local function applyPCLD()
    if not trackedPCLD or not trackedPCLD.Parent then return end
    pcall(function()
        trackedPCLD.Transparency = pcldTrans
        trackedPCLD.Color        = pcldColor
    end)
end

local function resetPCLD()
    if trackedPCLD and trackedPCLD.Parent then
        pcall(function() trackedPCLD.Transparency = 1 end)
    end
    trackedPCLD = nil
end

local function scanPCLD()
    trackedPCLD = nil
    for _, child in ipairs(WS:GetChildren()) do
        if child.Name == PCLD_NAME and child:IsA("BasePart") and not isMine(child) then
            trackedPCLD = child
            break
        end
    end
end

local function enablePCLD()
    pcldOn = true
    scanPCLD()
    if trackedPCLD then applyPCLD() end

    pcldDisc("add")
    pcldConns["add"] = WS.ChildAdded:Connect(function(part)
        if not pcldOn or part.Name ~= PCLD_NAME then return end
        task.wait(0.15)
        if part:IsA("BasePart") and not isMine(part) then
            trackedPCLD = part
            applyPCLD()
        end
    end)

    pcldDisc("rem")
    pcldConns["rem"] = WS.ChildRemoved:Connect(function(part)
        if part == trackedPCLD then trackedPCLD = nil end
    end)
end

local function disablePCLD()
    pcldOn = false
    resetPCLD()
    pcldDisc("add")
    pcldDisc("rem")
end

-- ============================================================
-- PACKET DETECTOR
-- ============================================================
local function analyzePacket(_, args)
    if not _G.PacketMonitor then return end
    pcall(function()
        local sz, who = 0, "?"
        for _, a in pairs(args) do
            if type(a) == "string" then sz = sz + #a end
            if typeof(a) == "Instance" and a:IsA("BasePart") then
                local p = Players:GetPlayerFromCharacter(a.Parent)
                if p then who = p.Name end
            end
        end
        if sz / 1024 > 10 then
            local s = sz / 1024
            sysChat("LAG! " .. who .. " | "
                .. (s >= 1024
                    and string.format("%.1fMB", s / 1024)
                    or  string.format("%.1fKB", s)))
        end
    end)
end

if extendLine then
    pcall(function()
        extendLine.OnClientEvent:Connect(function(...)
            analyzePacket("E", {...})
        end)
    end)
end
if createLine then
    pcall(function()
        createLine.OnClientEvent:Connect(function(...)
            analyzePacket("C", {...})
        end)
    end)
end

-- ============================================================
-- TARGET MANAGER
-- ============================================================
local DropSaved = nil

local function getPlayerNames()
    local t = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then table.insert(t, p.Name) end
    end
    if #t == 0 then table.insert(t, "---") end
    return t
end

local function updateSavedDrop()
    if DropSaved then
        pcall(function()
            DropSaved:Set(#savedTargets > 0 and savedTargets or {"---"})
        end)
    end
end

local function addToSaved(name)
    if not name then return end
    for _, v in pairs(savedTargets) do
        if v == name then return end
    end
    table.insert(savedTargets, name)
    updateSavedDrop()
end

Players.PlayerAdded:Connect(function(plr)
    for _, n in pairs(savedTargets) do
        if n == plr.Name then
            sysChat(plr.Name .. " JOINED!", Color3.fromRGB(255, 50, 50))
            Rayfield:Notify({
                Title   = "Alert",
                Content = plr.Name .. " joined!",
                Duration = 5,
            })
            if _G.KickEnabled and selectedTarget
               and selectedTarget.Name == plr.Name then
                task.wait(2)
                selectedTarget = plr
                KickPlayer(plr)
            end
        end
    end
    if espEnabled then task.wait(2) makeESP(plr) end
end)

Players.PlayerRemoving:Connect(function(plr)
    for _, n in pairs(savedTargets) do
        if n == plr.Name then
            sysChat(plr.Name .. " left", Color3.fromRGB(100, 255, 100))
        end
    end
    local rem = {}
    for i, obj in pairs(espObjects) do
        pcall(function()
            if obj:IsA("Highlight") and obj.Parent
               and Players:GetPlayerFromCharacter(obj.Parent) == plr then
                obj:Destroy()
                table.insert(rem, i)
            elseif obj:IsA("BillboardGui") and obj.Adornee
               and obj.Adornee.Parent
               and Players:GetPlayerFromCharacter(obj.Adornee.Parent) == plr then
                obj:Destroy()
                table.insert(rem, i)
            end
        end)
    end
    for i = #rem, 1, -1 do table.remove(espObjects, rem[i]) end
end)

task.spawn(function()
    while true do
        task.wait(0.3)
        if loopTPOn and selectedTarget then
            pcall(function()
                local m, t = getHRP(LP), getHRP(selectedTarget)
                if m and t then
                    m.CFrame = t.CFrame * CFrame.new(0, 0, 10)
                end
            end)
        end
    end
end)

-- ============================================================
-- GUI
-- ============================================================
local TabCombat = Window:CreateTab("Combat",   4483362458)
local TabMove   = Window:CreateTab("Movement", 4483362458)
local TabVisual = Window:CreateTab("Visuals",  4483362458)

-- ── Combat Tab ───────────────────────────────────────────────
TabCombat:CreateSection("Target")

TabCombat:CreateDropdown({
    Name           = "Server Players",
    Options        = getPlayerNames(),
    CurrentOption  = {},
    MultiSelection = false,
    Callback       = function(val)
        local name = type(val) == "table" and val[1] or val
        if not name or name == "---" then return end
        local plr = Players:FindFirstChild(name)
        if plr then selectedTarget = plr end
    end,
})

TabCombat:CreateButton({
    Name = "Add to Saved",
    Callback = function()
        if not selectedTarget or not selectedTarget.Parent then
            Rayfield:Notify({Title = "Error", Content = "Select player first", Duration = 2})
            return
        end
        local name = selectedTarget.Name
        for _, v in pairs(savedTargets) do
            if v == name then
                Rayfield:Notify({Title = "Info", Content = name .. " already saved", Duration = 2})
                return
            end
        end
        table.insert(savedTargets, name)
        updateSavedDrop()
        Rayfield:Notify({Title = "Saved", Content = name, Duration = 2})
    end,
})

DropSaved = TabCombat:CreateDropdown({
    Name           = "Saved Targets",
    Options        = {"---"},
    CurrentOption  = {},
    MultiSelection = false,
    Callback       = function(val)
        local name = type(val) == "table" and val[1] or val
        if not name or name == "---" then return end
        if _G.KickEnabled and selectedTarget and selectedTarget.Parent
           and selectedTarget.Name ~= name then
            Rayfield:Notify({Title = "Blocked", Content = "Stop kick first", Duration = 2})
            return
        end
        currentSaved = name
        local plr = Players:FindFirstChild(name)
        if plr then
            selectedTarget = plr
            if _G.KickEnabled then KickPlayer(plr) end
        else
            Rayfield:Notify({Title = "Offline", Content = name, Duration = 2})
        end
    end,
})

TabCombat:CreateButton({
    Name = "Remove from Saved",
    Callback = function()
        if currentSaved then
            for i, v in ipairs(savedTargets) do
                if v == currentSaved then
                    table.remove(savedTargets, i)
                    break
                end
            end
            updateSavedDrop()
            currentSaved = nil
        end
    end,
})

TabCombat:CreateButton({
    Name = "Clear Saved",
    Callback = function()
        savedTargets = {}
        updateSavedDrop()
        selectedTarget = nil
        currentSaved   = nil
        StopKick()
    end,
})

TabCombat:CreateSection("Kick")

TabCombat:CreateToggle({
    Name         = "Kick",
    CurrentValue = false,
    Callback     = function(v)
        _G.KickEnabled = v
        if v then
            if selectedTarget and selectedTarget.Parent then
                local tName = selectedTarget.Name -- сохраняем до вызова
                KickPlayer(selectedTarget)
                Rayfield:Notify({Title = "Kick", Content = tName, Duration = 2})
            else
                Rayfield:Notify({Title = "Ready", Content = "Select target", Duration = 2})
            end
        else
            StopKick()
            Rayfield:Notify({Title = "Kick", Content = "Stopped", Duration = 2})
        end
    end,
})

TabCombat:CreateSection("Bind")

local bindLabel = TabCombat:CreateLabel("Select bind: X")

TabCombat:CreateButton({
    Name = "Change Bind",
    Callback = function()
        Rayfield:Notify({Title = "Press any key...", Content = "", Duration = 3})
        local waiting = true
        local cn
        cn = UIS.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode ~= Enum.KeyCode.Unknown then
                selectBind = input.KeyCode
                pcall(function()
                    bindLabel:Set("Select bind: " .. selectBind.Name)
                end)
                waiting = false
                cn:Disconnect()
            end
        end)
        task.delay(5, function()
            if waiting then pcall(function() cn:Disconnect() end) end
        end)
    end,
})

UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end

    -- T = клик-TP
    if input.KeyCode == Enum.KeyCode.T then
        pcall(function()
            local hrp = getHRP(LP)
            if hrp then
                hrp.CFrame = CFrame.new(Mouse.Hit.Position + Vector3.new(0, 3, 0))
            end
        end)
    end

    -- Кастомный бинд = выбор цели курсором
    if input.KeyCode == selectBind then
        pcall(function()
            local model = Mouse.Target and Mouse.Target:FindFirstAncestorOfClass("Model")
            if not model then return end
            local plr = Players:GetPlayerFromCharacter(model)
            if not plr or plr == LP then return end
            if _G.KickEnabled and selectedTarget
               and selectedTarget ~= plr and selectedTarget.Parent then
                Rayfield:Notify({Title = "Blocked", Content = "Stop kick first", Duration = 2})
                return
            end
            selectedTarget = plr
            addToSaved(plr.Name)
            Rayfield:Notify({Title = "Selected", Content = plr.Name, Duration = 2})
            if _G.KickEnabled then KickPlayer(plr) end
        end)
    end
end)

-- ── Movement Tab ─────────────────────────────────────────────
TabMove:CreateSection("Teleport")
TabMove:CreateToggle({
    Name = "Loop TP", CurrentValue = false,
    Callback = function(v) loopTPOn = v end,
})

TabMove:CreateSection("Speed")
TabMove:CreateSlider({
    Name = "Walk Speed", Range = {16, 200}, Increment = 1,
    Suffix = "", CurrentValue = 16,
    Callback = function(v) customSpeed = v end,
})
TabMove:CreateSlider({
    Name = "Jump Power", Range = {50, 300}, Increment = 5,
    Suffix = "", CurrentValue = 50,
    Callback = function(v) customJump = v end,
})
TabMove:CreateToggle({
    Name = "Noclip", CurrentValue = false,
    Callback = function(v) toggleNoclip(v) end,
})

-- ── Visuals Tab ──────────────────────────────────────────────
TabVisual:CreateSection("Player ESP")
TabVisual:CreateToggle({
    Name = "ESP", CurrentValue = false,
    Callback = function(v)
        espEnabled = v
        if v then createESP() else clearESP() end
    end,
})
TabVisual:CreateColorPicker({
    Name = "ESP Color", Color = espColor, Flag = "ESPColor",
    Callback = function(v)
        espColor = v
        if espEnabled then updateESPColor() end
    end,
})
TabVisual:CreateButton({
    Name = "Refresh ESP",
    Callback = function() if espEnabled then createESP() end end,
})

TabVisual:CreateSection("PCLD ESP")
TabVisual:CreateToggle({
    Name = "PCLD ESP", CurrentValue = false,
    Callback = function(v) if v then enablePCLD() else disablePCLD() end end,
})
TabVisual:CreateColorPicker({
    Name = "PCLD Color", Color = pcldColor, Flag = "PCLDCol",
    Callback = function(v)
        pcldColor = v
        if pcldOn and trackedPCLD then applyPCLD() end
    end,
})
TabVisual:CreateSlider({
    Name = "PCLD Transparency", Range = {0, 1}, Increment = 0.05,
    Suffix = "", CurrentValue = pcldTrans, Flag = "PCLDTr",
    Callback = function(v)
        pcldTrans = v
        if pcldOn and trackedPCLD then applyPCLD() end
    end,
})

TabVisual:CreateSection("Network")
TabVisual:CreateToggle({
    Name = "Packet Detector", CurrentValue = false,
    Callback = function(v) _G.PacketMonitor = v end,
})

local simOn = false
TabVisual:CreateToggle({
    Name = "PCLD SimRadius", CurrentValue = false,
    Callback = function(v) simOn = v end,
})

task.spawn(function()
    while true do
        task.wait(0.5)
        if simOn then
            pcall(function()
                LP.SimulationRadius       = math.huge
                LP.MaximumSimulationRadius = math.huge
                settings().Physics.AllowSleep = false
            end)
            if selectedTarget then
                local hrp = getHRP(selectedTarget)
                if hrp then fireOwner(hrp, hrp.CFrame) end
            end
        end
    end
end)
