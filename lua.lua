-- ═══════════════════════════════════════════════════════════════
-- fife | 2.0
-- ═══════════════════════════════════════════════════════════════

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name            = "fife | 2.0",
    LoadingTitle    = "fife",
    LoadingSubtitle = "loading...",
    ConfigurationSaving = { Enabled = false, FileName = "fife20" },
    KeySystem       = false,
})

-- ═══════════════════════════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════════════════════════

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local RepStorage = game:GetService("ReplicatedStorage")
local Workspace  = game:GetService("Workspace")
local UIS        = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Stats      = game:GetService("Stats")
local CoreGui    = game:GetService("CoreGui")

local LP    = Players.LocalPlayer
local Mouse = LP:GetMouse()

-- ═══════════════════════════════════════════════════════════════
-- CONFIG — все числа в одном месте
-- ═══════════════════════════════════════════════════════════════

local CFG = {
    KICK = {
        -- BodyPosition
        BP_POWER      = 300000,    -- жёсткость притяжения
        BP_DAMP       = 1,      -- демпфирование (плавность)
        BP_OFFSET_Y   = 15,        -- высота над LP (стадов)

        -- BodyGyro
        BG_POWER      = 15000,
        BG_DAMP       = 150,

        -- Сетевой спам
        HEAVY_EVERY   = 4,        -- extend + extra parts каждые N кадров
        TOY_INTERVAL  = 0.3,      -- проверка игрушек (сек)

        -- TP-перехват
        TP_DIST       = 40,       -- порог дистанции (стадов)
        TP_COOLDOWN   = 0.5,      -- кулдаун между TP (сек)
        TP_BURST      = 3,        -- burst-вызовов при TP
        TP_LINGER     = 0.12,     -- пауза у цели перед возвратом
        TP_OFFSET     = 4,        -- отступ от цели при TP
        TP_INTERVAL   = 0.1,      -- интервал проверки TP

        -- Респавн
        RESPAWN_DELAY = 1.2,      -- ожидание после респавна цели
        RESPAWN_BURST = 5,        -- burst при респавне

        -- Лимиты
        Y_LIMIT       = 2000,     -- выше этого — не трогаем (уже улетел)
    },

    -- Имена BodyMover-инстансов (уникальные, не палевные)
    TAG_BP = "__fBP",
    TAG_BG = "__fBG",
}

-- ═══════════════════════════════════════════════════════════════
-- REMOTES
-- ═══════════════════════════════════════════════════════════════

local GE = RepStorage:WaitForChild("GrabEvents", 10)
if not GE then
    Rayfield:Notify({Title = "Error", Content = "GrabEvents folder not found", Duration = 5})
end

local remotes = {
    setOwner   = GE and GE:WaitForChild("SetNetworkOwner", 5),
    destroy    = GE and GE:WaitForChild("DestroyGrabLine", 5),
    extend     = GE and GE:FindFirstChild("ExtendGrabLine"),
    create     = GE and GE:FindFirstChild("CreateGrabLine"),
}

-- Безопасные обёртки — каждая проверяет remote и part перед вызовом
local function fireOwner(part, cf)
    if remotes.setOwner and part and part.Parent then
        pcall(remotes.setOwner.FireServer, remotes.setOwner, part, cf)
    end
end

local function fireDestroy(part)
    if remotes.destroy and part and part.Parent then
        pcall(remotes.destroy.FireServer, remotes.destroy, part)
    end
end

local function fireExtend(part, cf)
    if remotes.extend and part and part.Parent then
        pcall(remotes.extend.FireServer, remotes.extend, part, cf)
    end
end

local function fireCreate(part, cf)
    if remotes.create and part and part.Parent then
        pcall(remotes.create.FireServer, remotes.create, part, cf)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════

local function getCharacter(player)
    return player and player.Character
end

local function getHRP(player)
    local char = getCharacter(player)
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(player)
    local char = getCharacter(player)
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function isAlive(player)
    local hrp = getHRP(player)
    local hum = getHumanoid(player)
    return hrp and hum and hum.Health > 0
end

local function sysChat(text, color)
    pcall(StarterGui.SetCore, StarterGui, "ChatMakeSystemMessage", {
        Text     = "[fife] " .. text,
        Color    = color or Color3.fromRGB(255, 80, 80),
        Font     = Enum.Font.GothamBold,
        FontSize = Enum.FontSize.Size18,
    })
end

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local state = {
    target       = nil,       -- текущая цель (Player)
    saved        = {},        -- сохранённые ники
    currentSaved = nil,       -- выбранный из saved

    kickEnabled  = false,
    espEnabled   = false,
    espColor     = Color3.fromRGB(0, 170, 255),

    pcldOn       = false,
    pcldColor    = Color3.fromRGB(255, 0, 0),
    pcldTrans    = 0.5,

    noclipOn     = false,
    loopTP       = false,
    walkSpeed    = 16,
    jumpPower    = 50,
    selectBind   = Enum.KeyCode.X,
    packetMon    = false,
    simRadius    = false,
}

-- Обратная совместимость с внешними проверками
_G.KickEnabled  = false
_G.StopKickFunc = nil
_G.PacketMonitor = false

-- ═══════════════════════════════════════════════════════════════
-- HUD
-- ═══════════════════════════════════════════════════════════════

do
    local old = CoreGui:FindFirstChild("fifeHUD")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name            = "fifeHUD"
    gui.ResetOnSpawn    = false
    gui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    gui.IgnoreGuiInset  = true

    local bar = Instance.new("Frame")
    bar.Size                  = UDim2.new(0, 520, 0, 36)
    bar.Position              = UDim2.new(0.5, -260, 0, 6)
    bar.BackgroundColor3      = Color3.fromRGB(18, 18, 22)
    bar.BackgroundTransparency = 0.15
    bar.BorderSizePixel       = 0
    bar.Parent                = gui

    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 18)

    local stroke = Instance.new("UIStroke")
    stroke.Color        = Color3.fromRGB(80, 80, 120)
    stroke.Thickness    = 1.5
    stroke.Transparency = 0.5
    stroke.Parent       = bar

    local layout = Instance.new("UIListLayout")
    layout.FillDirection        = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment   = Enum.VerticalAlignment.Center
    layout.Padding             = UDim.new(0, 20)
    layout.Parent              = bar

    local function label(text, col)
        local lbl = Instance.new("TextLabel")
        lbl.Size                 = UDim2.new(0, 110, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.Font                 = Enum.Font.GothamBold
        lbl.TextSize             = 12
        lbl.TextColor3           = col or Color3.fromRGB(200, 200, 210)
        lbl.Text                 = text
        lbl.Parent               = bar
        return lbl
    end

    local lblName    = label(LP.Name, Color3.fromRGB(130, 180, 255))
    local lblFPS     = label("FPS: --")
    local lblPing    = label("Ping: --")
    local lblPlayers = label("0 online")

    gui.Parent = CoreGui

    -- FPS через Heartbeat
    local frames, lastTick = 0, tick()
    RunService.Heartbeat:Connect(function()
        frames += 1
        local now = tick()
        if now - lastTick >= 0.4 then
            lblFPS.Text = "FPS: " .. math.floor(frames / (now - lastTick))
            frames = 0
            lastTick = now
        end
    end)

    -- Ping + online — медленный цикл
    task.spawn(function()
        while true do
            pcall(function()
                local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
                lblPing.Text = "Ping: " .. math.floor(ping) .. "ms"
            end)
            lblPlayers.Text = #Players:GetPlayers() .. " online"
            task.wait(0.5)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- KICK ENGINE
-- ═══════════════════════════════════════════════════════════════

local kick = {
    active      = false,
    target      = nil,
    conns       = {},
    lastTP      = 0,
    lastToys    = 0,
    frame       = 0,
}

-- ── Утилиты кика ─────────────────────────────────────────────

-- Расширение SimulationRadius для контроля удалённых частей
local function boostSimRadius()
    pcall(function()
        LP.SimulationRadius        = math.huge
        LP.MaximumSimulationRadius = math.huge
        settings().Physics.AllowSleep = false
    end)
end

-- Овнершип + уничтожение граб-линий по одной части (базовый набор)
local function pressureBasic(part)
    if not part or not part.Parent then return end
    local cf = part.CFrame
    fireOwner(part, cf)
    fireDestroy(part)
end

-- Расширенное давление: + extend + дополнительные части тела
local function pressureHeavy(char, hrp)
    if not char or not hrp or not hrp.Parent then return end
    local cf = hrp.CFrame
    fireOwner(hrp, cf)
    fireDestroy(hrp)
    fireExtend(hrp, cf)
    -- Захват доп. частей — усиливает контроль, не давая серверу
    -- вернуть ownership другому клиенту
    for _, name in ipairs({"Head", "Torso", "UpperTorso", "LowerTorso"}) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            fireOwner(part, part.CFrame)
        end
    end
end

-- Обнуление физики цели — убирает инерцию перед BodyPosition
local function killVelocity(hrp)
    pcall(function()
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end

-- Создание или обновление BodyPosition
local function applyBodyPosition(hrp, targetPos)
    local bp = hrp:FindFirstChild(CFG.TAG_BP)
    if not bp then
        bp          = Instance.new("BodyPosition")
        bp.Name     = CFG.TAG_BP
        bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bp.D        = CFG.KICK.BP_DAMP
        bp.P        = CFG.KICK.BP_POWER
        bp.Parent   = hrp
    end
    bp.Position = targetPos
end

-- Создание или обновление BodyGyro
local function applyBodyGyro(hrp, targetCF)
    local bg = hrp:FindFirstChild(CFG.TAG_BG)
    if not bg then
        bg           = Instance.new("BodyGyro")
        bg.Name      = CFG.TAG_BG
        bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        bg.D         = CFG.KICK.BG_DAMP
        bg.P         = CFG.KICK.BG_POWER
        bg.Parent    = hrp
    end
    bg.CFrame = targetCF
end

-- Удаление BodyMovers с части
local function removeBodyMovers(hrp)
    if not hrp then return end
    local bp = hrp:FindFirstChild(CFG.TAG_BP)
    local bg = hrp:FindFirstChild(CFG.TAG_BG)
    if bp then bp:Destroy() end
    if bg then bg:Destroy() end
end

-- Нейтрализация оружия цели (NinjaKunai, NinjaShuriken)
local function processToys(targetName)
    local spawned = Workspace:FindFirstChild(targetName .. "SpawnedInToys")
    if not spawned then return end

    for _, toyName in ipairs({"NinjaKunai", "NinjaShuriken"}) do
        local toy = spawned:FindFirstChild(toyName)
        if toy then
            local sp = toy:FindFirstChild("SoundPart")
            if sp and sp.Parent then
                fireOwner(sp, sp.CFrame)
                -- Если перехватили — выбрасываем далеко
                local ownerVal = sp:FindFirstChild("PartOwner")
                if ownerVal and ownerVal.Value == LP.Name then
                    pcall(function() sp.CFrame = CFrame.new(0, 10000, 0) end)
                end
            end
        end
    end
end

-- ── Cleanup ──────────────────────────────────────────────────

local function kickCleanup()
    if not kick.active then return end -- идемпотентность
    kick.active = false

    -- Отключаем все коннекты
    for i = #kick.conns, 1, -1 do
        pcall(function() kick.conns[i]:Disconnect() end)
        kick.conns[i] = nil
    end

    -- Убираем следы с цели
    local target = kick.target
    if target then
        local char = getCharacter(target)
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            removeBodyMovers(hrp)
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                pcall(function() hum.PlatformStand = false end)
            end
        end
    end

    kick.target = nil
    kick.frame  = 0
    kick.lastTP = 0
    kick.lastToys = 0
end

-- ── Публичные функции ────────────────────────────────────────

local function StopKick()
    kickCleanup()
    _G.StopKickFunc = nil
end

local function KickPlayer(target)
    if not target then return end

    -- Проверка: есть ли remote events
    if not remotes.setOwner or not remotes.destroy then
        Rayfield:Notify({
            Title    = "Error",
            Content  = "Remote events not found",
            Duration = 3,
        })
        state.kickEnabled = false
        _G.KickEnabled    = false
        return
    end

    -- Чистим предыдущий кик если был
    StopKick()

    -- Инициализация состояния
    kick.active   = true
    kick.target   = target
    kick.frame    = 0
    kick.lastTP   = 0
    kick.lastToys = 0

    -- Регистрация функции остановки
    _G.StopKickFunc = StopKick

    -- ══════════════════════════════════════════════════════════
    -- HEARTBEAT — основной цикл
    -- Один коннект, все задачи с разной частотой
    -- ══════════════════════════════════════════════════════════

    local heartbeatConn = RunService.Heartbeat:Connect(function()
        if not kick.active then return end

        local tgt = kick.target
        if not tgt or not tgt.Parent then return end

        local tChar = getCharacter(tgt)
        if not tChar then return end

        local tHRP = tChar:FindFirstChild("HumanoidRootPart")
        if not tHRP or not tHRP.Parent then return end

        -- Цель уже улетела за лимит — пропускаем
        if tHRP.Position.Y > CFG.KICK.Y_LIMIT then return end

        local mHRP = getHRP(LP)
        if not mHRP then return end

        kick.frame += 1
        local now = tick()

        -- [КАЖДЫЙ КАДР] —————————————————————————————————————

        -- SimRadius: без него ownership удалённых частей не работает
        boostSimRadius()

        -- Базовое сетевое давление: owner + destroy
        pressureBasic(tHRP)

        -- Выключаем humanoid-контроль (без этого BodyPosition бессилен
        -- против ходьбы/прыжков игрока)
        local tHum = tChar:FindFirstChildOfClass("Humanoid")
        if tHum then
            pcall(function() tHum.PlatformStand = true end)
        end

        -- Обнуляем инерцию ПЕРЕД установкой BodyPosition,
        -- чтобы BP сразу начал тянуть без «борьбы» с velocity
        killVelocity(tHRP)

        -- BodyPosition: тянем цель к позиции чуть выше LP
        -- Достаточно близко для стабильного ownership,
        -- в воздухе — цель не может убежать
        local pullTarget = mHRP.Position + Vector3.new(0, CFG.KICK.BP_OFFSET_Y, 0)
        applyBodyPosition(tHRP, pullTarget)

        -- BodyGyro: фиксируем ориентацию на LP
        applyBodyGyro(tHRP, mHRP.CFrame)

        -- [КАЖДЫЕ N КАДРОВ] —————————————————————————————————

        if kick.frame % CFG.KICK.HEAVY_EVERY == 0 then
            pressureHeavy(tChar, tHRP)
        end

        -- [THROTTLED] — игрушки ——————————————————————————————

        if now - kick.lastToys >= CFG.KICK.TOY_INTERVAL then
            kick.lastToys = now
            pcall(processToys, tgt.Name)
        end
    end)
    table.insert(kick.conns, heartbeatConn)

    -- ══════════════════════════════════════════════════════════
    -- TP-ПЕРЕХВАТ — отдельный медленный цикл
    -- Единственная задача: если цель далеко — подлететь, перехватить,
    -- вернуться. С кулдауном чтобы не мерцать.
    -- ══════════════════════════════════════════════════════════

    task.spawn(function()
        while kick.active do
            -- Guard: цель ещё в игре?
            local tgt = kick.target
            if not tgt or not tgt.Parent then break end

            local mHRP = getHRP(LP)
            local tHRP = getHRP(tgt)

            if mHRP and tHRP and tHRP.Position.Y < CFG.KICK.Y_LIMIT then
                local dist = (mHRP.Position - tHRP.Position).Magnitude
                local now  = tick()

                -- Три условия: далеко + кулдаун прошёл + цель не в небе
                if dist > CFG.KICK.TP_DIST
                   and now - kick.lastTP >= CFG.KICK.TP_COOLDOWN
                then
                    kick.lastTP = now

                    -- Запоминаем позицию LP
                    local savedCF = mHRP.CFrame

                    -- Телепорт к цели (чуть в стороне чтобы не внутри модели)
                    pcall(function()
                        mHRP.CFrame = tHRP.CFrame * CFrame.new(0, 0, CFG.KICK.TP_OFFSET)
                    end)

                    -- Burst-спам при сближении —
                    -- момент максимальной эффективности ownership-перехвата
                    for _ = 1, CFG.KICK.TP_BURST do
                        if not kick.active then break end
                        pressureBasic(tHRP)
                    end

                    -- Даём серверу время обработать наш burst
                    task.wait(CFG.KICK.TP_LINGER)

                    -- Возвращаемся на исходную позицию
                    if kick.active then
                        local hrpNow = getHRP(LP)
                        if hrpNow then
                            pcall(function() hrpNow.CFrame = savedCF end)
                        end
                    end
                end
            end

            task.wait(CFG.KICK.TP_INTERVAL)
        end

        -- Цикл завершился (цель ушла) — cleanup
        if kick.active then kickCleanup() end
    end)

    -- ══════════════════════════════════════════════════════════
    -- RESPAWN HANDLER — перехват после респавна цели
    -- ══════════════════════════════════════════════════════════

    local charAddedConn = target.CharacterAdded:Connect(function(newChar)
        if not kick.active then return end

        -- Ждём загрузки нового персонажа
        task.wait(CFG.KICK.RESPAWN_DELAY)
        if not kick.active then return end

        local tHRP = newChar:FindFirstChild("HumanoidRootPart")
                  or newChar:WaitForChild("HumanoidRootPart", 3)
        if not tHRP then return end

        -- Агрессивный перехват сразу после респавна:
        -- сервер ещё не раздал ownership, самое время захватить
        for i = 1, CFG.KICK.RESPAWN_BURST do
            if not kick.active then return end
            pressureBasic(tHRP)
            if i < CFG.KICK.RESPAWN_BURST then task.wait(0.05) end
        end
    end)
    table.insert(kick.conns, charAddedConn)
end

-- ═══════════════════════════════════════════════════════════════
-- MOVEMENT
-- ═══════════════════════════════════════════════════════════════

-- Noclip
local noclipConn  = nil
local noclipParts = {}

local function cacheNoclipParts()
    noclipParts = {}
    local char = getCharacter(LP)
    if not char then return end
    for _, p in ipairs(char:GetChildren()) do
        if p:IsA("BasePart") then table.insert(noclipParts, p) end
    end
end

local function setNoclip(enabled)
    state.noclipOn = enabled
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    if enabled then
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
    if state.noclipOn then cacheNoclipParts() end
end)

-- Speed / Jump — применяется каждый кадр
RunService.Heartbeat:Connect(function()
    local hum = getHumanoid(LP)
    if not hum then return end
    if state.walkSpeed ~= 16 then hum.WalkSpeed = state.walkSpeed end
    if state.jumpPower ~= 50 then hum.JumpPower  = state.jumpPower end
end)

-- ═══════════════════════════════════════════════════════════════
-- ESP
-- ═══════════════════════════════════════════════════════════════

local espObjects = {}

local function clearESP()
    for _, obj in ipairs(espObjects) do pcall(obj.Destroy, obj) end
    table.clear(espObjects)
end

local function makeESP(plr)
    if plr == LP then return end
    local char = getCharacter(plr)
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end

    -- Highlight
    local hl              = Instance.new("Highlight")
    hl.Name               = "fifeHL"
    hl.FillTransparency   = 0.75
    hl.OutlineTransparency = 0
    hl.OutlineColor       = state.espColor
    hl.FillColor          = state.espColor
    hl.Parent             = char
    table.insert(espObjects, hl)

    -- Billboard
    local bb          = Instance.new("BillboardGui")
    bb.Name           = "fifeBB"
    bb.Adornee        = head
    bb.Size           = UDim2.new(0, 180, 0, 44)
    bb.StudsOffset    = Vector3.new(0, 2.5, 0)
    bb.AlwaysOnTop    = true
    bb.Parent         = head

    local bg                     = Instance.new("Frame")
    bg.Size                      = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3          = Color3.fromRGB(15, 15, 15)
    bg.BackgroundTransparency    = 0.35
    bg.BorderSizePixel           = 0
    bg.Parent                    = bb
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 6)

    local us          = Instance.new("UIStroke")
    us.Color          = state.espColor
    us.Thickness      = 1.5
    us.Transparency   = 0.3
    us.Parent         = bg

    local nameLabel                   = Instance.new("TextLabel")
    nameLabel.Size                    = UDim2.new(1, -8, 0.5, 0)
    nameLabel.Position                = UDim2.new(0, 4, 0, 2)
    nameLabel.BackgroundTransparency  = 1
    nameLabel.Font                    = Enum.Font.GothamBold
    nameLabel.TextSize                = 13
    nameLabel.TextColor3              = Color3.fromRGB(255, 255, 255)
    nameLabel.TextXAlignment          = Enum.TextXAlignment.Left
    nameLabel.TextStrokeTransparency  = 0.5
    nameLabel.Text                    = plr.Name
    nameLabel.Parent                  = bg

    local distLabel                   = Instance.new("TextLabel")
    distLabel.Name                    = "Dist"
    distLabel.Size                    = UDim2.new(1, -8, 0.5, 0)
    distLabel.Position                = UDim2.new(0, 4, 0.5, 0)
    distLabel.BackgroundTransparency  = 1
    distLabel.Font                    = Enum.Font.Gotham
    distLabel.TextSize                = 11
    distLabel.TextColor3              = Color3.fromRGB(200, 200, 100)
    distLabel.TextXAlignment          = Enum.TextXAlignment.Left
    distLabel.TextStrokeTransparency  = 0.5
    distLabel.Text                    = "0m"
    distLabel.Parent                  = bg

    table.insert(espObjects, bb)
end

local function refreshESP()
    clearESP()
    if not state.espEnabled then return end
    for _, plr in ipairs(Players:GetPlayers()) do makeESP(plr) end
end

local function updateESPColors()
    for _, obj in ipairs(espObjects) do
        pcall(function()
            if obj:IsA("Highlight") then
                obj.OutlineColor = state.espColor
                obj.FillColor    = state.espColor
            elseif obj:IsA("BillboardGui") then
                local bg = obj:FindFirstChildWhichIsA("Frame")
                if bg then
                    local s = bg:FindFirstChildWhichIsA("UIStroke")
                    if s then s.Color = state.espColor end
                end
            end
        end)
    end
end

-- Обновление дистанции в ESP-лейблах
task.spawn(function()
    while true do
        task.wait(0.4)
        if state.espEnabled then
            local mHRP = getHRP(LP)
            if mHRP then
                for _, obj in ipairs(espObjects) do
                    pcall(function()
                        if not obj:IsA("BillboardGui") then return end
                        if not obj.Adornee or not obj.Adornee.Parent then return end
                        local bg = obj:FindFirstChildWhichIsA("Frame")
                        if not bg then return end
                        local dl = bg:FindFirstChild("Dist")
                        if not dl then return end
                        local d = (mHRP.Position - obj.Adornee.Position).Magnitude
                        dl.Text = string.format("%.0fm", d)
                        dl.TextColor3 = d < 30
                            and Color3.fromRGB(255, 60, 60)
                            or d < 80
                            and Color3.fromRGB(255, 220, 60)
                            or Color3.fromRGB(60, 255, 60)
                    end)
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- PCLD ESP
-- ═══════════════════════════════════════════════════════════════

local PCLD_NAME    = "PlayerCharacterLocationDetector"
local trackedPCLD  = nil
local pcldConns    = {}

local function disconnectPCLD(key)
    if pcldConns[key] then
        pcall(function() pcldConns[key]:Disconnect() end)
        pcldConns[key] = nil
    end
end

local function isMyPCLD(part)
    local hrp = getHRP(LP)
    return hrp and (part.Position - hrp.Position).Magnitude < 2
end

local function stylePCLD()
    if not trackedPCLD or not trackedPCLD.Parent then return end
    pcall(function()
        trackedPCLD.Transparency = state.pcldTrans
        trackedPCLD.Color        = state.pcldColor
    end)
end

local function resetPCLD()
    if trackedPCLD and trackedPCLD.Parent then
        pcall(function() trackedPCLD.Transparency = 1 end)
    end
    trackedPCLD = nil
end

local function enablePCLD()
    state.pcldOn = true

    -- Поиск существующего PCLD
    trackedPCLD = nil
    for _, child in ipairs(Workspace:GetChildren()) do
        if child.Name == PCLD_NAME and child:IsA("BasePart") and not isMyPCLD(child) then
            trackedPCLD = child
            break
        end
    end
    if trackedPCLD then stylePCLD() end

    -- Отслеживание новых
    disconnectPCLD("add")
    pcldConns["add"] = Workspace.ChildAdded:Connect(function(part)
        if not state.pcldOn or part.Name ~= PCLD_NAME then return end
        task.wait(0.15)
        if part:IsA("BasePart") and not isMyPCLD(part) then
            trackedPCLD = part
            stylePCLD()
        end
    end)

    disconnectPCLD("rem")
    pcldConns["rem"] = Workspace.ChildRemoved:Connect(function(part)
        if part == trackedPCLD then trackedPCLD = nil end
    end)
end

local function disablePCLD()
    state.pcldOn = false
    resetPCLD()
    disconnectPCLD("add")
    disconnectPCLD("rem")
end

-- ═══════════════════════════════════════════════════════════════
-- PACKET MONITOR
-- ═══════════════════════════════════════════════════════════════

local function onPacket(_, args)
    if not state.packetMon then return end
    pcall(function()
        local sz, who = 0, "?"
        for _, a in pairs(args) do
            if type(a) == "string" then sz += #a end
            if typeof(a) == "Instance" and a:IsA("BasePart") then
                local p = Players:GetPlayerFromCharacter(a.Parent)
                if p then who = p.Name end
            end
        end
        if sz / 1024 > 10 then
            local kb = sz / 1024
            local txt = kb >= 1024
                and string.format("%.1fMB", kb / 1024)
                or  string.format("%.1fKB", kb)
            sysChat("LAG! " .. who .. " | " .. txt)
        end
    end)
end

if remotes.extend then
    pcall(function()
        remotes.extend.OnClientEvent:Connect(function(...)
            onPacket("E", {...})
        end)
    end)
end
if remotes.create then
    pcall(function()
        remotes.create.OnClientEvent:Connect(function(...)
            onPacket("C", {...})
        end)
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- TARGET MANAGER
-- ═══════════════════════════════════════════════════════════════

local DropSaved = nil -- ссылка на Rayfield dropdown, заполняется позже

local function getPlayerNames()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then table.insert(names, p.Name) end
    end
    if #names == 0 then table.insert(names, "---") end
    return names
end

local function syncSavedDropdown()
    if DropSaved then
        pcall(function()
            DropSaved:Set(#state.saved > 0 and state.saved or {"---"})
        end)
    end
end

local function addToSaved(name)
    if not name then return end
    for _, v in ipairs(state.saved) do
        if v == name then return end
    end
    table.insert(state.saved, name)
    syncSavedDropdown()
end

-- Автоматическое отслеживание join/leave сохранённых целей
Players.PlayerAdded:Connect(function(plr)
    for _, name in ipairs(state.saved) do
        if name == plr.Name then
            sysChat(plr.Name .. " JOINED!", Color3.fromRGB(255, 50, 50))
            Rayfield:Notify({
                Title    = "Target Alert",
                Content  = plr.Name .. " joined the server",
                Duration = 5,
            })
            -- Если кик включён и мы ждали именно этого игрока
            if state.kickEnabled and state.target
               and state.target.Name == plr.Name then
                task.wait(2)
                state.target = plr
                task.spawn(KickPlayer, plr)
            end
        end
    end
    if state.espEnabled then task.wait(2); makeESP(plr) end
end)

Players.PlayerRemoving:Connect(function(plr)
    for _, name in ipairs(state.saved) do
        if name == plr.Name then
            sysChat(plr.Name .. " left", Color3.fromRGB(100, 255, 100))
        end
    end

    -- Удаляем ESP-объекты ушедшего игрока
    local toRemove = {}
    for i, obj in ipairs(espObjects) do
        pcall(function()
            local match = false
            if obj:IsA("Highlight") and obj.Parent then
                match = Players:GetPlayerFromCharacter(obj.Parent) == plr
            elseif obj:IsA("BillboardGui") and obj.Adornee and obj.Adornee.Parent then
                match = Players:GetPlayerFromCharacter(obj.Adornee.Parent) == plr
            end
            if match then
                obj:Destroy()
                table.insert(toRemove, i)
            end
        end)
    end
    for i = #toRemove, 1, -1 do table.remove(espObjects, toRemove[i]) end
end)

-- Loop TP
task.spawn(function()
    while true do
        task.wait(0.3)
        if state.loopTP and state.target then
            pcall(function()
                local m = getHRP(LP)
                local t = getHRP(state.target)
                if m and t then
                    m.CFrame = t.CFrame * CFrame.new(0, 0, 10)
                end
            end)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- SIM RADIUS (отдельный toggle, для PCLD и прочего)
-- ═══════════════════════════════════════════════════════════════

task.spawn(function()
    while true do
        task.wait(0.5)
        if state.simRadius then
            boostSimRadius()
            if state.target then
                local hrp = getHRP(state.target)
                if hrp then fireOwner(hrp, hrp.CFrame) end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- INPUT
-- ═══════════════════════════════════════════════════════════════

UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    -- T = клик-телепорт к курсору
    if input.KeyCode == Enum.KeyCode.T then
        pcall(function()
            local hrp = getHRP(LP)
            if hrp then
                hrp.CFrame = CFrame.new(Mouse.Hit.Position + Vector3.new(0, 3, 0))
            end
        end)
        return
    end

    -- Кастомный бинд = выбор цели курсором
    if input.KeyCode == state.selectBind then
        pcall(function()
            local model = Mouse.Target
                      and Mouse.Target:FindFirstAncestorOfClass("Model")
            if not model then return end

            local plr = Players:GetPlayerFromCharacter(model)
            if not plr or plr == LP then return end

            -- Нельзя менять цель во время активного кика
            if state.kickEnabled and state.target
               and state.target ~= plr and state.target.Parent then
                Rayfield:Notify({
                    Title   = "Blocked",
                    Content = "Stop kick before switching target",
                    Duration = 2,
                })
                return
            end

            state.target = plr
            addToSaved(plr.Name)
            Rayfield:Notify({Title = "Selected", Content = plr.Name, Duration = 2})

            if state.kickEnabled then
                task.spawn(KickPlayer, plr)
            end
        end)
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- UI (Rayfield)
-- ═══════════════════════════════════════════════════════════════

local TabCombat = Window:CreateTab("Combat",   4483362458)
local TabMove   = Window:CreateTab("Movement", 4483362458)
local TabVisual = Window:CreateTab("Visuals",  4483362458)

-- ── Combat ───────────────────────────────────────────────────

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
        if plr then state.target = plr end
    end,
})

TabCombat:CreateButton({
    Name = "Add to Saved",
    Callback = function()
        if not state.target or not state.target.Parent then
            Rayfield:Notify({Title = "Error", Content = "Select target first", Duration = 2})
            return
        end
        addToSaved(state.target.Name)
        Rayfield:Notify({Title = "Saved", Content = state.target.Name, Duration = 2})
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

        if state.kickEnabled and state.target and state.target.Parent
           and state.target.Name ~= name then
            Rayfield:Notify({Title = "Blocked", Content = "Stop kick first", Duration = 2})
            return
        end

        state.currentSaved = name
        local plr = Players:FindFirstChild(name)
        if plr then
            state.target = plr
            if state.kickEnabled then task.spawn(KickPlayer, plr) end
        else
            Rayfield:Notify({Title = "Offline", Content = name, Duration = 2})
        end
    end,
})

TabCombat:CreateButton({
    Name = "Remove from Saved",
    Callback = function()
        if not state.currentSaved then return end
        for i, v in ipairs(state.saved) do
            if v == state.currentSaved then
                table.remove(state.saved, i)
                break
            end
        end
        syncSavedDropdown()
        state.currentSaved = nil
    end,
})

TabCombat:CreateButton({
    Name = "Clear Saved",
    Callback = function()
        table.clear(state.saved)
        syncSavedDropdown()
        state.target       = nil
        state.currentSaved = nil
        StopKick()
    end,
})

TabCombat:CreateSection("Kick")

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  КЛЮЧЕВОЙ МОМЕНТ: KickPlayer содержит task.wait(), поэтому ║
-- ║  вызываем через task.spawn, чтобы не yield'ить callback    ║
-- ║  Rayfield → это решает Callback Error                      ║
-- ╚══════════════════════════════════════════════════════════════╝

TabCombat:CreateToggle({
    Name         = "Kick",
    CurrentValue = false,
    Callback     = function(enabled)
        state.kickEnabled = enabled
        _G.KickEnabled    = enabled

        if enabled then
            if state.target and state.target.Parent then
                local name = state.target.Name
                -- task.spawn: KickPlayer делает yield, нельзя в callback напрямую
                task.spawn(KickPlayer, state.target)
                Rayfield:Notify({Title = "Kick", Content = name, Duration = 2})
            else
                Rayfield:Notify({Title = "Kick", Content = "Select target first", Duration = 2})
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
        Rayfield:Notify({Title = "Bind", Content = "Press any key...", Duration = 3})
        local waiting = true
        local conn
        conn = UIS.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode == Enum.KeyCode.Unknown then return end
            state.selectBind = input.KeyCode
            pcall(function() bindLabel:Set("Select bind: " .. state.selectBind.Name) end)
            waiting = false
            conn:Disconnect()
        end)
        task.delay(5, function()
            if waiting then pcall(function() conn:Disconnect() end) end
        end)
    end,
})

-- ── Movement ─────────────────────────────────────────────────

TabMove:CreateSection("Teleport")
TabMove:CreateToggle({
    Name = "Loop TP", CurrentValue = false,
    Callback = function(v) state.loopTP = v end,
})

TabMove:CreateSection("Speed")
TabMove:CreateSlider({
    Name = "Walk Speed", Range = {16, 200}, Increment = 1,
    Suffix = "", CurrentValue = 16,
    Callback = function(v) state.walkSpeed = v end,
})
TabMove:CreateSlider({
    Name = "Jump Power", Range = {50, 300}, Increment = 5,
    Suffix = "", CurrentValue = 50,
    Callback = function(v) state.jumpPower = v end,
})
TabMove:CreateToggle({
    Name = "Noclip", CurrentValue = false,
    Callback = function(v) setNoclip(v) end,
})

-- ── Visuals ──────────────────────────────────────────────────

TabVisual:CreateSection("Player ESP")
TabVisual:CreateToggle({
    Name = "ESP", CurrentValue = false,
    Callback = function(v)
        state.espEnabled = v
        if v then refreshESP() else clearESP() end
    end,
})
TabVisual:CreateColorPicker({
    Name = "ESP Color", Color = state.espColor, Flag = "ESPColor",
    Callback = function(v)
        state.espColor = v
        if state.espEnabled then updateESPColors() end
    end,
})
TabVisual:CreateButton({
    Name = "Refresh ESP",
    Callback = function()
        if state.espEnabled then refreshESP() end
    end,
})

TabVisual:CreateSection("PCLD ESP")
TabVisual:CreateToggle({
    Name = "PCLD ESP", CurrentValue = false,
    Callback = function(v)
        if v then enablePCLD() else disablePCLD() end
    end,
})
TabVisual:CreateColorPicker({
    Name = "PCLD Color", Color = state.pcldColor, Flag = "PCLDCol",
    Callback = function(v)
        state.pcldColor = v
        if state.pcldOn and trackedPCLD then stylePCLD() end
    end,
})
TabVisual:CreateSlider({
    Name = "PCLD Transparency", Range = {0, 1}, Increment = 0.05,
    Suffix = "", CurrentValue = state.pcldTrans, Flag = "PCLDTr",
    Callback = function(v)
        state.pcldTrans = v
        if state.pcldOn and trackedPCLD then stylePCLD() end
    end,
})

TabVisual:CreateSection("Network")
TabVisual:CreateToggle({
    Name = "Packet Detector", CurrentValue = false,
    Callback = function(v) state.packetMon = v; _G.PacketMonitor = v end,
})
TabVisual:CreateToggle({
    Name = "PCLD SimRadius", CurrentValue = false,
    Callback = function(v) state.simRadius = v end,
})
