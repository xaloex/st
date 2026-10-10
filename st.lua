--!nonstrict
--[[
    =============================================================================
    pencil-gui.txt — Полный автономный GUI с визуализатором 3D акрилового стекла
    Извлечено и адаптировано из: puls.orig.lua (PulseAcrGlass)
    
    Скрипт полностью самодостаточен:
      * Встроен движок Pencil (3D Triangle / 4-Wedge Quad / ScreenPointToRay)
      * Интерактивное перетаскиваемое (Draggable) окно с тёмным стилем
      * Подложка из физического 3D Glass стекла (настоящий блюр Roblox)
      * Контроллеры: включение/выключение стекла, настройка прозрачности,
        выбор цветов преломления, демо 3D треугольников в мире и 2D углов
      * Кнопка чистого закрытия/выгрузки (Unload)
    =============================================================================
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- Защищённое получение контейнера GUI для любых экзекуторов
local function getGuiParent(): Instance
    if gethui then
        return gethui()
    end
    local success, core = pcall(function()
        return CoreGui
    end)
    if success and core then
        return core
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- Удаление предыдущей копии при перезапуске
local GUI_NAME = "PencilAcrylicDemoGUI"
local oldGui = getGuiParent():FindFirstChild(GUI_NAME)
if oldGui then
    oldGui:Destroy()
end

--=============================================================================
-- 1. ДВИЖОК PENCIL (3D GLASS / ACRYLIC RASTERIZER)
--=============================================================================

local Pencil = {}
Pencil.__index = Pencil

export type PencilSettings = {
    enabled: boolean,
    glassWant: boolean,
    winOpen: boolean,
    transparency: number,
    color: Color3,
    material: Enum.Material,
    partName: string,
    zIndexOffset: number,
    baseDepth: number,
}

local defaultSettings: PencilSettings = {
    enabled = true,
    glassWant = true,
    winOpen = true,
    transparency = 0.98,
    color = Color3.fromRGB(248, 248, 252),
    material = Enum.Material.Glass,
    partName = "PulseAcrGlass",
    zIndexOffset = 0.05,
    baseDepth = 1.0,
}

local function createGlassWedge(name: string, material: Enum.Material): Part
    local wedge = Instance.new("Part")
    wedge.Name = name
    wedge.Material = material
    wedge.TopSurface = Enum.SurfaceType.Smooth
    wedge.BottomSurface = Enum.SurfaceType.Smooth
    wedge.Anchored = true
    wedge.CanCollide = false
    wedge.CanQuery = false
    wedge.CanTouch = false
    wedge.CastShadow = false
    wedge.Size = Vector3.new(0.2, 0.2, 0.2)

    local mesh = Instance.new("SpecialMesh")
    mesh.Name = "M"
    mesh.MeshType = Enum.MeshType.Wedge
    mesh.Parent = wedge

    return wedge
end

function Pencil.drawTriangle3D(
    p1: Vector3,
    p2: Vector3,
    p3: Vector3,
    wedge1: Part?,
    wedge2: Part?,
    settings: PencilSettings?
): (Part, Part)
    local cfg = settings or defaultSettings

    local l1 = (p1 - p2).Magnitude
    local l2 = (p2 - p3).Magnitude
    local l3 = (p3 - p1).Magnitude
    local maxLen = math.max(l1, l2, l3)

    local a: Vector3, b: Vector3, c: Vector3
    if l1 == maxLen then
        a, b, c = p1, p2, p3
    elseif l2 == maxLen then
        a, b, c = p2, p3, p1
    else
        a, b, c = p3, p1, p2
    end

    local ab = a - b
    local abMag = ab.Magnitude
    local f = ((b - a).X * (c - a).X + (b - a).Y * (c - a).Y + (b - a).Z * (c - a).Z) / abMag
    local height = math.sqrt(math.max((c - a).Magnitude ^ 2 - f * f, 0))
    local length = abMag - f

    local cf = CFrame.new(b, a)
    local rot = CFrame.Angles(math.pi / 2, 0, 0)
    local cf1 = cf
    local look = (cf1 * rot).LookVector
    local hPoint = a + CFrame.new(a, b).LookVector * f
    local dir = CFrame.new(hPoint, c).LookVector
    local dot = math.clamp(look.X * dir.X + look.Y * dir.Y + look.Z * dir.Z, -1.0, 1.0)
    local angle = CFrame.Angles(0, 0, math.acos(dot))

    cf1 = cf1 * angle
    if ((cf1 * rot).LookVector - dir).Magnitude > 0.01 then
        cf1 = cf1 * CFrame.Angles(0, 0, -2.0 * math.acos(dot))
    end
    cf1 = cf1 * CFrame.new(0, height / 2, -(length + f / 2))

    local cf2 = cf * angle * CFrame.Angles(0, math.pi, 0)
    if ((cf2 * rot).LookVector - dir).Magnitude > 0.01 then
        cf2 = cf2 * CFrame.Angles(0, 0, 2.0 * math.acos(dot))
    end
    cf2 = cf2 * CFrame.new(0, height / 2, length / 2)

    if not wedge1 then
        wedge1 = createGlassWedge(cfg.partName, cfg.material)
    end
    if not wedge2 then
        wedge2 = wedge1:Clone()
    end

    local m1 = wedge1:FindFirstChild("M") :: SpecialMesh? or wedge1:FindFirstChildOfClass("SpecialMesh")
    if m1 then
        m1.Scale = Vector3.new(0, height / 0.2, f / 0.2)
    end
    wedge1.CFrame = cf1

    local m2 = wedge2:FindFirstChild("M") :: SpecialMesh? or wedge2:FindFirstChildOfClass("SpecialMesh")
    if m2 then
        m2.Scale = Vector3.new(0, height / 0.2, length / 0.2)
    end
    wedge2.CFrame = cf2

    return wedge1, wedge2
end

function Pencil.drawQuad3D(
    p1: Vector3,
    p2: Vector3,
    p3: Vector3,
    p4: Vector3,
    parts: { Part },
    settings: PencilSettings?
): ()
    parts[1], parts[2] = Pencil.drawTriangle3D(p1, p2, p3, parts[1], parts[2], settings)
    parts[3], parts[4] = Pencil.drawTriangle3D(p3, p2, p4, parts[3], parts[4], settings)
end

function Pencil.attach(rootFrame: GuiObject, customSettings: any?)
    local settings: PencilSettings = table.clone(defaultSettings)
    if customSettings then
        for k, v in pairs(customSettings) do
            settings[k] = v
        end
    end

    local parts: { Part } = {}
    local cache = {
        cf = nil :: CFrame?,
        vs = nil :: Vector2?,
        fov = nil :: number?,
        tl = nil :: Vector2?,
        br = nil :: Vector2?,
        z = nil :: number?,
    }

    local handler = {
        settings = settings,
        parts = parts,
        root = rootFrame,
        connection = nil :: RBXScriptConnection?,
    }

    function handler:hide()
        for _, part in ipairs(parts) do
            part.Parent = nil
        end
        cache.cf = nil
    end

    function handler:destroy()
        if self.connection then
            self.connection:Disconnect()
            self.connection = nil
        end
        for _, part in ipairs(parts) do
            part:Destroy()
        end
        table.clear(parts)
    end

    function handler:update()
        local root = self.root
        local cam = Workspace.CurrentCamera

        if not (self.settings.enabled and self.settings.glassWant and self.settings.winOpen) then
            self:hide()
            return
        end

        if not (root and root.Parent and cam) or not root.Visible then
            self:hide()
            return
        end

        local screenGui = root:FindFirstAncestorWhichIsA("ScreenGui")
        if screenGui and not screenGui.Enabled then
            self:hide()
            return
        end

        local zDist = self.settings.baseDepth - self.settings.zIndexOffset * (root.ZIndex or 1)
        local tl = root.AbsolutePosition
        local br = root.AbsolutePosition + root.AbsoluteSize
        local cf = cam.CFrame
        local vs = cam.ViewportSize
        local fov = cam.FieldOfView

        if parts[1]
            and cache.cf == cf
            and cache.vs == vs
            and cache.fov == fov
            and cache.tl == tl
            and cache.br == br
            and cache.z == zDist
        then
            for _, part in ipairs(parts) do
                if part.Parent ~= cam then
                    part.Parent = cam
                end
                part.Transparency = self.settings.transparency
                part.Color = self.settings.color
            end
            return
        end

        cache.cf, cache.vs, cache.fov, cache.tl, cache.br, cache.z = cf, vs, fov, tl, br, zDist

        local tr = Vector2.new(br.X, tl.Y)
        local bl = Vector2.new(tl.X, br.Y)

        local rayTL = cam:ScreenPointToRay(tl.X, tl.Y, zDist)
        local rayTR = cam:ScreenPointToRay(tr.X, tr.Y, zDist)
        local rayBL = cam:ScreenPointToRay(bl.X, bl.Y, zDist)
        local rayBR = cam:ScreenPointToRay(br.X, br.Y, zDist)

        Pencil.drawQuad3D(
            rayTL.Origin,
            rayTR.Origin,
            rayBL.Origin,
            rayBR.Origin,
            parts,
            self.settings
        )

        for _, part in ipairs(parts) do
            if part.Parent ~= cam then
                part.Parent = cam
            end
            part.Transparency = self.settings.transparency
            part.Color = self.settings.color
        end
    end

    handler.connection = RunService.RenderStepped:Connect(function()
        handler:update()
    end)

    return handler
end

--=============================================================================
-- 2. СОЗДАНИЕ ИНТЕРФЕЙСА (GUI)
--=============================================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_NAME
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = getGuiParent()

-- Главное окно
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.fromOffset(360, 420)
MainFrame.Position = UDim2.new(0.5, -180, 0.5, -210)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 19, 23)
MainFrame.BackgroundTransparency = 0.35 -- Полупрозрачный фон, чтобы видеть 3D стекло
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.ZIndex = 2
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(255, 255, 255)
MainStroke.Transparency = 0.82
MainStroke.Thickness = 1.2
MainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
MainStroke.Parent = MainFrame

-- Заголовок (TitleBar)
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(12, 13, 16)
TitleBar.BackgroundTransparency = 0.4
TitleBar.BorderSizePixel = 0
TitleBar.ZIndex = 3
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- Блокировка скругления снизу заголовка
local TitleBottomCover = Instance.new("Frame")
TitleBottomCover.Size = UDim2.new(1, 0, 0, 10)
TitleBottomCover.Position = UDim2.new(0, 0, 1, -10)
TitleBottomCover.BackgroundColor3 = Color3.fromRGB(12, 13, 16)
TitleBottomCover.BackgroundTransparency = 0.4
TitleBottomCover.BorderSizePixel = 0
TitleBottomCover.ZIndex = 3
TitleBottomCover.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -70, 1, 0)
TitleLabel.Position = UDim2.fromOffset(12, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "PENCIL • 3D ACRYLIC GLASS"
TitleLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.ZIndex = 4
TitleLabel.Parent = TitleBar

-- Кнопка закрытия
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.fromOffset(26, 26)
CloseBtn.Position = UDim2.new(1, -30, 0.5, -13)
CloseBtn.BackgroundColor3 = Color3.fromRGB(235, 75, 75)
CloseBtn.BackgroundTransparency = 0.2
CloseBtn.BorderSizePixel = 0
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.TextSize = 12
CloseBtn.ZIndex = 4
CloseBtn.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

-- Контейнер содержимого
local Content = Instance.new("ScrollingFrame")
Content.Name = "Content"
Content.Size = UDim2.new(1, -20, 1, -48)
Content.Position = UDim2.fromOffset(10, 42)
Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0
Content.ScrollBarThickness = 3
Content.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120)
Content.CanvasSize = UDim2.fromOffset(0, 480)
Content.ZIndex = 3
Content.Parent = MainFrame

local ContentLayout = Instance.new("UIListLayout")
ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
ContentLayout.Padding = UDim.new(0, 10)
ContentLayout.Parent = Content

--=============================================================================
-- 3. ПРИВЯЗКА 3D СТЕКЛА К ОКНУ (PENCIL ACRYLIC)
--=============================================================================

local acrylic = Pencil.attach(MainFrame, {
    enabled = true,
    glassWant = true,
    winOpen = true,
    transparency = 0.98,
    color = Color3.fromRGB(248, 248, 252),
})

--=============================================================================
-- 4. ХЕЛПЕРЫ ДЛЯ ЭЛЕМЕНТОВ ИНТЕРФЕЙСА
--=============================================================================

local function createSection(title: string, order: number): (Frame, TextLabel)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 70)
    card.BackgroundColor3 = Color3.fromRGB(25, 27, 34)
    card.BackgroundTransparency = 0.5
    card.BorderSizePixel = 0
    card.LayoutOrder = order
    card.ZIndex = 4
    card.Parent = Content

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Transparency = 0.9
    stroke.Thickness = 1
    stroke.Parent = card

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -16, 0, 24)
    lbl.Position = UDim2.fromOffset(10, 4)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamMedium
    lbl.Text = title
    lbl.TextColor3 = Color3.fromRGB(200, 205, 220)
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 5
    lbl.Parent = card

    return card, lbl
end

-- Кнопка-переключатель (Toggle)
local function createToggle(parent: Frame, text: string, defaultState: boolean, callback: (boolean) -> ())
    local state = defaultState

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 32)
    btn.Position = UDim2.fromOffset(10, 30)
    btn.BackgroundColor3 = state and Color3.fromRGB(50, 160, 95) or Color3.fromRGB(45, 48, 58)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.Text = text .. ": " .. (state and "ВКЛ (ON)" or "ВЫКЛ (OFF)")
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 12
    btn.ZIndex = 5
    btn.Parent = parent

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = btn

    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.BackgroundColor3 = state and Color3.fromRGB(50, 160, 95) or Color3.fromRGB(45, 48, 58)
        btn.Text = text .. ": " .. (state and "ВКЛ (ON)" or "ВЫКЛ (OFF)")
        callback(state)
    end)

    return btn
end

--=============================================================================
-- 5. СОДЕРЖИМОЕ ОКНА НАСТРОЕК
--=============================================================================

-- 1. Секция: Переключатель 3D Акрила
local card1 = createSection("ОСНОВНОЙ ЭФФЕКТ СТЕКЛА", 1)
createToggle(card1, "3D Acrylic Blur", true, function(enabled)
    acrylic.settings.glassWant = enabled
    acrylic.settings.enabled = enabled
    if not enabled then
        acrylic:hide()
    end
end)

-- 2. Секция: Прозрачность (Transparency)
local card2, card2Lbl = createSection("ПРОЗРАЧНОСТЬ СТЕКЛА (КЛИНИ)", 2)
card2.Size = UDim2.new(1, 0, 0, 80)

local trValues = { 0.95, 0.98, 0.99 }
local trButtons = {}

for idx, tr in ipairs(trValues) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.31, 0, 0, 30)
    b.Position = UDim2.new(0.02 + (idx - 1) * 0.33, 0, 0, 36)
    b.BackgroundColor3 = (tr == acrylic.settings.transparency) and Color3.fromRGB(80, 120, 220) or Color3.fromRGB(40, 43, 52)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamMedium
    b.Text = tostring(tr)
    b.TextColor3 = Color3.fromRGB(240, 240, 250)
    b.TextSize = 12
    b.ZIndex = 5
    b.Parent = card2

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 6)
    bc.Parent = b

    trButtons[tr] = b

    b.MouseButton1Click:Connect(function()
        acrylic.settings.transparency = tr
        for _, otherB in pairs(trButtons) do
            otherB.BackgroundColor3 = Color3.fromRGB(40, 43, 52)
        end
        b.BackgroundColor3 = Color3.fromRGB(80, 120, 220)
    end)
end

-- 3. Секция: Оттенки цвета стекла
local card3 = createSection("ОТТЕНОК СТЕКЛА (COLOR PRESET)", 3)
card3.Size = UDim2.new(1, 0, 0, 85)

local presets = {
    { name = "Стандарт", col = Color3.fromRGB(248, 248, 252) },
    { name = "Холодный", col = Color3.fromRGB(180, 215, 255) },
    { name = "Неон", col = Color3.fromRGB(255, 140, 210) },
    { name = "Изумруд", col = Color3.fromRGB(150, 255, 190) },
}

for i, p in ipairs(presets) do
    local pb = Instance.new("TextButton")
    pb.Size = UDim2.new(0.46, 0, 0, 26)
    local colIdx = (i - 1) % 2
    local rowIdx = math.floor((i - 1) / 2)
    pb.Position = UDim2.new(0.03 + colIdx * 0.49, 0, 0, 30 + rowIdx * 30)
    pb.BackgroundColor3 = Color3.fromRGB(35, 38, 48)
    pb.BorderSizePixel = 0
    pb.Font = Enum.Font.GothamMedium
    pb.Text = p.name
    pb.TextColor3 = p.col
    pb.TextSize = 11
    pb.ZIndex = 5
    pb.Parent = card3

    local pc = Instance.new("UICorner")
    pc.CornerRadius = UDim.new(0, 6)
    pc.Parent = pb

    pb.MouseButton1Click:Connect(function()
        acrylic.settings.color = p.col
    end)
end

-- 4. Секция: Демо 3D Треугольника в мире (DrawTriangle3D)
local card4 = createSection("3D ТРЕУГОЛЬНИК В МИРЕ (PENCIL 3D)", 4)
local demoWedges: { Part } = {}
local demoConn: RBXScriptConnection? = nil

createToggle(card4, "3D Rotating Triangle", false, function(active)
    if active then
        local angle = 0
        demoConn = RunService.RenderStepped:Connect(function(dt)
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if not root then return end

            angle = (angle + dt * 2) % (math.pi * 2)
            local center = root.Position + root.CFrame.LookVector * 10 + Vector3.new(0, 1, 0)
            
            local r = 4
            local p1 = center + Vector3.new(math.cos(angle) * r, math.sin(angle) * 2, math.sin(angle) * r)
            local p2 = center + Vector3.new(math.cos(angle + 2.1) * r, -1, math.sin(angle + 2.1) * r)
            local p3 = center + Vector3.new(math.cos(angle + 4.2) * r, 2, math.sin(angle + 4.2) * r)

            demoWedges[1], demoWedges[2] = Pencil.drawTriangle3D(p1, p2, p3, demoWedges[1], demoWedges[2])
            for _, w in ipairs(demoWedges) do
                w.Parent = Workspace
                w.Material = Enum.Material.Neon
                w.Color = Color3.fromHSV((angle / (math.pi * 2)), 0.8, 1)
                w.Transparency = 0.2
            end
        end)
    else
        if demoConn then
            demoConn:Disconnect()
            demoConn = nil
        end
        for _, w in ipairs(demoWedges) do
            w:Destroy()
        end
        table.clear(demoWedges)
    end
end)

--=============================================================================
-- 6. ПЕРЕТАСКИВАНИЕ ОКНА (DRAGGABLE WINDOW)
--=============================================================================

local dragging = false
local dragInput: InputObject? = nil
local dragStart: Vector3? = nil
local startPos: UDim2? = nil

TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

TitleBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging and dragStart and startPos then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

--=============================================================================
-- 7. ЗАКРЫТИЕ И ВЫГРУЗКА (CLEANUP)
--=============================================================================

local function unload()
    if demoConn then
        demoConn:Disconnect()
        demoConn = nil
    end
    for _, w in ipairs(demoWedges) do
        w:Destroy()
    end
    table.clear(demoWedges)

    acrylic:destroy()
    ScreenGui:Destroy()
end

CloseBtn.MouseButton1Click:Connect(unload)

print("[Pencil] 3D Acrylic Glass GUI успешно запущен!")
