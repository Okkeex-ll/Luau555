-- ============================================================
-- fife | 1.1
-- ============================================================

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "fife | 1.1",
    LoadingTitle = "fife",
    LoadingSubtitle = "loading...",
    ConfigurationSaving = { Enabled = false, FileName = "fife11" },
    KeySystem = false,
})

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local RepStorage  = game:GetService("ReplicatedStorage")
local WS          = game:GetService("Workspace")
local UIS         = game:GetService("UserInputService")
local StarterGui  = game:GetService("StarterGui")
local Stats       = game:GetService("Stats")

local LP    = Players.LocalPlayer
local Mouse = LP:GetMouse()

-- ============================================================
-- GrabEvents
-- ============================================================
local GE = RepStorage:WaitForChild("GrabEvents", 10)
if not GE then
    Rayfield:Notify({Title = "Error", Content = "GrabEvents not found", Duration = 5})
    return
end

local destroyGrabLine = GE:WaitForChild("DestroyGrabLine", 5)
local setOwner        = GE:WaitForChild("SetNetworkOwner", 5)
local extendLine      = GE:FindFirstChild("ExtendGrabLine")
local createLine      = GE:FindFirstChild("CreateGrabLine")

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

-- ============================================================
-- утилиты
-- ============================================================
local function sysChat(text, color)
    pcall(function()
        StarterGui:SetCore("ChatMakeSystemMessage", {
            Text = "[fife]: " .. text,
            Color = color or Color3.fromRGB(255, 80, 80),
            Font = Enum.Font.GothamBold,
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
-- переменные
-- ============================================================
local selectedTarget = nil
local savedTargets   = {}
local currentSaved   = nil

_G.KickEnabled   = false
_G.StopKickFunc  = nil
_G.PacketMonitor = false

local espEnabled   = false
local espColor     = Color3.fromRGB(0, 170, 255)
local espObjects   = {}

local pcldOn       = false
local pcldColor    = Color3.fromRGB(255, 0, 0)
local pcldTrans    = 0.5
local trackedPCLD  = nil
local pcldConns    = {}

local noclipOn     = false
local noclipConn   = nil
local noclipParts  = {}

local loopTPOn     = false
local customSpeed  = 16
local customJump   = 50
local selectBind   = Enum.KeyCode.X

-- kick конфиг
local KICK_HOLD_OFFSET = Vector3.new(0, 15, 0)
local KICK_BP_P        = 500000
local KICK_BP_D        = 50
local KICK_BG_D        = 100
local REGRAB_DIST      = 30
local REGRAB_CD        = 0.6
local REGRAB_BURSTS    = 5
local REGRAB_WAIT      = 0.2
local SPAM_INTERVAL    = 0.04
local WEAPON_INTERVAL  = 0.12

-- ============================================================
-- HUD (красивый, по центру, скруглённый)
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

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 18)
    corner.Parent = bar

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(80, 80, 120)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.5
    stroke.Parent = bar

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 20)
    layout.Parent = bar

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

    local frameCount = 0
    local lastFPS = tick()
    RunService.Heartbeat:Connect(function()
        frameCount = frameCount + 1
        local now = tick()
        if now - lastFPS >= 0.4 then
            lblFPS.Text = "FPS: " .. math.floor(frameCount / (now - lastFPS))
            frameCount = 0
            lastFPS = now
        end
    end)

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

-- ============================================================
-- KICK (с BodyMovers + ownership — как работало раньше)
-- ============================================================
local function StopKick()
    if _G.StopKickFunc then
        pcall(function() _G.StopKickFunc() end)
        _G.StopKickFunc = nil
    end
end

local function KickPlayer(target)
    if not target then return end
    StopKick()
    task.wait(0.05)

    local active = true
    local conns = {}
    local lastGrab = 0

    local function cleanBM(hrp)
        if not hrp then return end
        pcall(function()
            if hrp:FindFirstChild("KickBP") then hrp.KickBP:Destroy() end
            if hrp:FindFirstChild("KickBG") then hrp.KickBG:Destroy() end
        end)
    end

    local function ensureBM(tHRP, holdPos, lookCF)
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

    local function removeWeapons()
        pcall(function()
            if not target or not target.Parent then return end
            local spawned = WS:FindFirstChild(target.Name .. "SpawnedInToys")
            if not spawned then return end
            local function yeet(container, partName)
                local c = spawned:FindFirstChild(container)
                if not c then return end
                local p = c:FindFirstChild(partName)
                if not p then return end
                fireOwner(p, p.CFrame)
                if p:FindFirstChild("PartOwner") and p.PartOwner.Value == LP.Name then
                    p.CFrame = CFrame.new(0, 10000, 0)
                end
            end
            yeet("NinjaKunai", "SoundPart")
            yeet("NinjaShuriken", "SoundPart")
        end)
    end

    local function cleanup()
        active = false
        for _, c in pairs(conns) do pcall(function() c:Disconnect() end) end
        conns = {}
        pcall(function()
            if target and target.Character then
                local r = target.Character:FindFirstChild("HumanoidRootPart")
                cleanBM(r)
                local h = target.Character:FindFirstChild("Humanoid")
                if h then h.PlatformStand = false end
            end
        end)
    end

    -- ПОТОК 1: Heartbeat — ownership + freeze + BodyMovers каждый кадр
    local hb = RunService.Heartbeat:Connect(function()
        if not active then return end
        pcall(function()
            if not target or not target.Parent then return end
            local tChar = target.Character
            if not tChar then return end
            local tHRP = tChar:FindFirstChild("HumanoidRootPart")
            local tHum = tChar:FindFirstChild("Humanoid")
            if not tHRP then return end

            local mHRP = getHRP(LP)
            if not mHRP then return end

            -- ownership каждый кадр
            if tHRP.Position.Y < 2000 then
                fireOwner(tHRP, tHRP.CFrame)
                fireDestroy(tHRP)
            end

            -- freeze
            freezeTarget(tHRP, tHum)

            -- BodyMovers
            local holdPos = mHRP.Position + KICK_HOLD_OFFSET
            ensureBM(tHRP, holdPos, mHRP.CFrame)
        end)
    end)
    table.insert(conns, hb)

    -- ПОТОК 2: доп спам ownership
    task.spawn(function()
        while active do
            pcall(function()
                if not target or not target.Parent then return end
                local tHRP = getHRP(target)
                if tHRP and tHRP.Position.Y < 2000 then
                    fireOwner(tHRP, tHRP.CFrame)
                    fireDestroy(tHRP)
                end
            end)
            task.wait(SPAM_INTERVAL)
        end
    end)

    -- ПОТОК 3: TP перехват + оружие
    task.spawn(function()
        while active do
            pcall(function()
                if not target or not target.Parent then return end
                local tHRP = getHRP(target)
                local mHRP = getHRP(LP)
                if not tHRP or not mHRP then return end

                removeWeapons()

                local dist = (mHRP.Position - tHRP.Position).Magnitude
                if dist > REGRAB_DIST and tHRP.Position.Y < 2000 then
                    local now = tick()
                    if now - lastGrab > REGRAB_CD then
                        lastGrab = now
                        local oldCF = mHRP.CFrame
                        mHRP.CFrame = tHRP.CFrame * CFrame.new(0, 0, 3)
                        for _ = 1, REGRAB_BURSTS do
                            fireOwner(tHRP, tHRP.CFrame)
                            fireDestroy(tHRP)
                        end
                        task.wait(REGRAB_WAIT)
                        pcall(function()
                            if mHRP and mHRP.Parent then mHRP.CFrame = oldCF end
                        end)
                    end
                end
            end)
            task.wait(WEAPON_INTERVAL)
        end
        cleanup()
    end)

    -- респавн цели
    local rc = target.CharacterAdded:Connect(function(newChar)
        if not active then return end
        local hrp = newChar:WaitForChild("HumanoidRootPart", 5)
        if not hrp or not active then return end
        task.wait(0.5)
        for _ = 1, 5 do
            fireOwner(hrp, hrp.CFrame)
            fireDestroy(hrp)
            task.wait(0.1)
        end
    end)
    table.insert(conns, rc)

    local mc = LP.CharacterAdded:Connect(function() task.wait(1) end)
    table.insert(conns, mc)

    _G.StopKickFunc = function() cleanup() end
end

-- ============================================================
-- NOCLIP
-- ============================================================
local function cacheNoclipParts()
    noclipParts = {}
    local c = LP.Character
    if not c then return end
    for _, p in pairs(c:GetChildren()) do
        if p:IsA("BasePart") then table.insert(noclipParts, p) end
    end
end

local function toggleNoclip(state)
    noclipOn = state
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    if state then
        cacheNoclipParts()
        noclipConn = RunService.Stepped:Connect(function()
            for _, p in pairs(noclipParts) do
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
    if customJump ~= 50 then hum.JumpPower = customJump end
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
    hl.FillTransparency = 0.75
    hl.OutlineTransparency = 0
    hl.OutlineColor = espColor
    hl.FillColor = espColor
    hl.Parent = char
    table.insert(espObjects, hl)

    local bb = Instance.new("BillboardGui")
    bb.Name = "fifeBB"
    bb.Adornee = head
    bb.Size = UDim2.new(0, 180, 0, 44)
    bb.StudsOffset = Vector3.new(0, 2.5, 0)
    bb.AlwaysOnTop = true
    bb.Parent = head

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    bg.BackgroundTransparency = 0.35
    bg.BorderSizePixel = 0
    bg.Parent = bb

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = bg

    local uiStroke = Instance.new("UIStroke")
    uiStroke.Color = espColor
    uiStroke.Thickness = 1.5
    uiStroke.Transparency = 0.3
    uiStroke.Parent = bg

    local nameL = Instance.new("TextLabel")
    nameL.Size = UDim2.new(1, -8, 0.5, 0)
    nameL.Position = UDim2.new(0, 4, 0, 2)
    nameL.BackgroundTransparency = 1
    nameL.Font = Enum.Font.GothamBold
    nameL.TextSize = 13
    nameL.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.TextStrokeTransparency = 0.5
    nameL.Text = plr.Name
    nameL.Parent = bg

    local distL = Instance.new("TextLabel")
    distL.Name = "Dist"
    distL.Size = UDim2.new(1, -8, 0.5, 0)
    distL.Position = UDim2.new(0, 4, 0.5, 0)
    distL.BackgroundTransparency = 1
    distL.Font = Enum.Font.Gotham
    distL.TextSize = 11
    distL.TextColor3 = Color3.fromRGB(200, 200, 100)
    distL.TextXAlignment = Enum.TextXAlignment.Left
    distL.TextStrokeTransparency = 0.5
    distL.Text = "0m"
    distL.Parent = bg

    table.insert(espObjects, bb)
end

local function createESP()
    clearESP()
    if not espEnabled then return end
    for _, plr in pairs(Players:GetPlayers()) do makeESP(plr) end
end

local function updateESPColor()
    for _, obj in pairs(espObjects) do
        pcall(function()
            if obj:IsA("Highlight") then
                obj.OutlineColor = espColor
                obj.FillColor = espColor
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
                                if d < 30 then
                                    dl.TextColor3 = Color3.fromRGB(255, 60, 60)
                                elseif d < 80 then
                                    dl.TextColor3 = Color3.fromRGB(255, 220, 60)
                                else
                                    dl.TextColor3 = Color3.fromRGB(60, 255, 60)
                                end
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
        trackedPCLD.Color = pcldColor
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
    for _, child in pairs(WS:GetChildren()) do
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
            sysChat("LAG! " .. who .. " | " .. (s >= 1024 and string.format("%.1fMB", s/1024) or string.format("%.1fKB", s)), Color3.fromRGB(255, 0, 0))
        end
    end)
end
if extendLine then pcall(function() extendLine.OnClientEvent:Connect(function(...) analyzePacket("E", {...}) end) end) end
if createLine then pcall(function() createLine.OnClientEvent:Connect(function(...) analyzePacket("C", {...}) end) end) end

-- ============================================================
-- TARGET MANAGER
-- ============================================================
local DropSaved = nil
local lastSelectedName = nil -- отслеживаем реальный выбор в dropdown

local function getPlayerNames()
    local t = {}
    for _, p in pairs(Players:GetPlayers()) do
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

-- алерты
Players.PlayerAdded:Connect(function(plr)
    for _, n in pairs(savedTargets) do
        if n == plr.Name then
            sysChat(plr.Name .. " JOINED!", Color3.fromRGB(255, 50, 50))
            Rayfield:Notify({Title = "Alert", Content = plr.Name .. " joined!", Duration = 5})
            if _G.KickEnabled and selectedTarget and selectedTarget.Name == plr.Name then
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
    local toRemove = {}
    for i, obj in pairs(espObjects) do
        pcall(function()
            if obj:IsA("Highlight") and obj.Parent and Players:GetPlayerFromCharacter(obj.Parent) == plr then
                obj:Destroy() table.insert(toRemove, i)
            elseif obj:IsA("BillboardGui") and obj.Adornee then
                local char = obj.Adornee.Parent
                if char and Players:GetPlayerFromCharacter(char) == plr then
                    obj:Destroy() table.insert(toRemove, i)
                end
            end
        end)
    end
    for i = #toRemove, 1, -1 do table.remove(espObjects, toRemove[i]) end
end)

-- loop TP
task.spawn(function()
    while true do
        task.wait(0.3)
        if loopTPOn and selectedTarget then
            pcall(function()
                local m = getHRP(LP)
                local t = getHRP(selectedTarget)
                if m and t then m.CFrame = t.CFrame * CFrame.new(0, 0, 10) end
            end)
        end
    end
end)

-- ============================================================
-- GUI
-- ============================================================
local TabCombat = Window:CreateTab("Combat", 4483362458)
local TabMove   = Window:CreateTab("Movement", 4483362458)
local TabVisual = Window:CreateTab("Visuals", 4483362458)

-- ==================== COMBAT ====================
TabCombat:CreateSection("Target")

TabCombat:CreateDropdown({
    Name = "Server Players",
    Options = getPlayerNames(),
    CurrentOption = {},
    MultiSelection = false,
    Callback = function(val)
        local name = type(val) == "table" and val[1] or val
        if not name or name == "---" then return end
        local plr = Players:FindFirstChild(name)
        if not plr then return end
        selectedTarget = plr
        lastSelectedName = name
    end,
})

TabCombat:CreateButton({
    Name = "Add to Saved",
    Callback = function()
        if not selectedTarget or not selectedTarget.Parent then
            Rayfield:Notify({Title = "Error", Content = "Select a player first", Duration = 2})
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
        Rayfield:Notify({Title = "Saved", Content = name .. " added", Duration = 2})
    end,
})

DropSaved = TabCombat:CreateDropdown({
    Name = "Saved Targets",
    Options = {"---"},
    CurrentOption = {},
    MultiSelection = false,
    Callback = function(val)
        local name = type(val) == "table" and val[1] or val
        if not name or name == "---" then return end

        if _G.KickEnabled and selectedTarget and selectedTarget.Parent and selectedTarget.Name ~= name then
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
                if v == currentSaved then table.remove(savedTargets, i) break end
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
        currentSaved = nil
        StopKick()
    end,
})

TabCombat:CreateSection("Kick")

TabCombat:CreateToggle({
    Name = "Kick",
    CurrentValue = false,
    Callback = function(v)
        _G.KickEnabled = v
        if v then
            if selectedTarget and selectedTarget.Parent then
                KickPlayer(selectedTarget)
                Rayfield:Notify({Title = "Kick", Content = selectedTarget.Name, Duration = 2})
            else
                Rayfield:Notify({Title = "Ready", Content = "Select target", Duration = 2})
            end
        else
            StopKick()
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
        local conn
        conn = UIS.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode ~= Enum.KeyCode.Unknown then
                selectBind = input.KeyCode
                pcall(function() bindLabel:Set("Select bind: " .. selectBind.Name) end)
                waiting = false
                conn:Disconnect()
            end
        end)
        task.delay(5, function()
            if waiting then pcall(function() conn:Disconnect() end) end
        end)
    end,
})

UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end

    if input.KeyCode == Enum.KeyCode.T then
        pcall(function()
            local hrp = getHRP(LP)
            if hrp then hrp.CFrame = CFrame.new(Mouse.Hit.Position + Vector3.new(0, 3, 0)) end
        end)
    end

    if input.KeyCode == selectBind then
        pcall(function()
            local model = Mouse.Target and Mouse.Target:FindFirstAncestorOfClass("Model")
            if not model then return end
            local plr = Players:GetPlayerFromCharacter(model)
            if not plr or plr == LP then return end

            if _G.KickEnabled and selectedTarget and selectedTarget ~= plr and selectedTarget.Parent then
                Rayfield:Notify({Title = "Blocked", Content = "Stop kick first", Duration = 2})
                return
            end

            selectedTarget = plr
            lastSelectedName = plr.Name
            addToSaved(plr.Name)
            Rayfield:Notify({Title = "Selected", Content = plr.Name, Duration = 2})
            if _G.KickEnabled then KickPlayer(plr) end
        end)
    end
end)

-- ==================== MOVEMENT ====================
TabMove:CreateSection("Teleport")
TabMove:CreateToggle({Name = "Loop TP to Target", CurrentValue = false, Callback = function(v) loopTPOn = v end})

TabMove:CreateSection("Speed")
TabMove:CreateSlider({Name = "Walk Speed", Range = {16, 200}, Increment = 1, Suffix = "", CurrentValue = 16, Callback = function(v) customSpeed = v end})
TabMove:CreateSlider({Name = "Jump Power", Range = {50, 300}, Increment = 5, Suffix = "", CurrentValue = 50, Callback = function(v) customJump = v end})
TabMove:CreateToggle({Name = "Noclip", CurrentValue = false, Callback = function(v) toggleNoclip(v) end})

-- ==================== VISUALS ====================
TabVisual:CreateSection("Player ESP")
TabVisual:CreateToggle({Name = "ESP", CurrentValue = false, Callback = function(v) espEnabled = v if v then createESP() else clearESP() end end})
TabVisual:CreateColorPicker({Name = "ESP Color", Color = espColor, Flag = "ESPColor", Callback = function(v) espColor = v if espEnabled then updateESPColor() end end})
TabVisual:CreateButton({Name = "Refresh ESP", Callback = function() if espEnabled then createESP() end end})

TabVisual:CreateSection("PCLD ESP")
TabVisual:CreateToggle({Name = "PCLD ESP", CurrentValue = false, Callback = function(v) if v then enablePCLD() else disablePCLD() end end})
TabVisual:CreateColorPicker({Name = "PCLD Color", Color = pcldColor, Flag = "PCLDCol", Callback = function(v) pcldColor = v if pcldOn and trackedPCLD then applyPCLD() end end})
TabVisual:CreateSlider({Name = "PCLD Transparency", Range = {0, 1}, Increment = 0.05, Suffix = "", CurrentValue = pcldTrans, Flag = "PCLDTr", Callback = function(v) pcldTrans = v if pcldOn and trackedPCLD then applyPCLD() end end})

TabVisual:CreateSection("Network")
TabVisual:CreateToggle({Name = "Packet Detector", CurrentValue = false, Callback = function(v) _G.PacketMonitor = v end})

local simRadiusOn = false
TabVisual:CreateToggle({Name = "PCLD SimRadius", CurrentValue = false, Callback = function(v) simRadiusOn = v end})

task.spawn(function()
    while true do
        task.wait(0.5)
        if simRadiusOn then
            pcall(function()
                LP.SimulationRadius = math.huge
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
