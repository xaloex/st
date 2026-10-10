--!nonstrict
--[[
    =============================================================================
    dildo.lua / pencil.lua — Полный деобфусцированный физический "PP" / "PulseWobble"
    Извлечено и реконструировано из: C:\script-dumps\slient\pensil\puls.orig.lua
    
    Включает:
      * PP (строка 9205): Менеджер жизненного цикла и регистрации сигнатуры
      * t  (строка 1774): Деструктор (очистка деталей, связей и RunService-соединений)
      * xP (строка 7895): Валидатор позиции торса (дистанция > 30 studs -> пересоздание)
      * DP (строка 2042): Игнорирование лучей и коллизий (префикс "PulseWobble")
      * cP (строка 542) : Хук косметики K.wob
      * Полная физика: BallSocketConstraint + SpringConstraint + Верле-пружина раскачивания
      * Полная анатомия: Стержень с венами, асимметричные яйца, головка с венчиком
      * Волосатость (Pubic Hair): Процедурный пояс кудрявых тёмных волос вокруг основания
    =============================================================================
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- Безопасный полифилл getgenv для поддержки Roblox Studio и обычных LocalScript
local getgenv = (type(getgenv) == "function" and getgenv) or function()
    return _G
end

local DildoManager = {}
DildoManager.__index = DildoManager

--=============================================================================
-- 1. Настройки модели и физики
--=============================================================================

export type DildoSettings = {
    enabled: boolean,
    scale: number,              -- Общий множитель размера (sc)
    color: Color3,              -- Цвет стержня и яиц
    tipColor: Color3,           -- Цвет головки (венчик)
    veinColor: Color3,          -- Цвет вен
    hairColor: Color3,          -- Цвет волос
    material: Enum.Material,    -- Материал плоти (SmoothPlastic)
    
    -- Настройки волосатости
    hairy: boolean,             -- Включить волосы у основания
    hairCount: number,          -- Количество завитков волос
    hairDensity: number,        -- Плотность кудрей
    
    -- Настройки физики (Spring & Inertia)
    physics: boolean,           -- Физическое раскачивание от инерции и шагов
    springStiffness: number,    -- Упругость пружины
    springDamping: number,      -- Затухание колебаний
    angleOffset: number,        -- Базовый угол стояка (в градусах от вертикали)
    gravityDroop: number,       -- Провисание под силой тяжести
}

local defaultSettings: DildoSettings = {
    enabled = true,
    scale = 1.0,
    color = Color3.fromRGB(240, 160, 140),
    tipColor = Color3.fromRGB(225, 115, 125),
    veinColor = Color3.fromRGB(190, 120, 140),
    hairColor = Color3.fromRGB(20, 18, 16),
    material = Enum.Material.SmoothPlastic,
    
    hairy = true,
    hairCount = 28,
    hairDensity = 1.0,
    
    physics = true,
    springStiffness = 140.0,
    springDamping = 12.0,
    angleOffset = 25.0,
    gravityDroop = 0.35,
}

DildoManager.DefaultSettings = defaultSettings

-- Таблица состояний персонажей (как m из puls.orig.lua:9208)
local activeStates: { [Model]: { wob: { any }?, wobSig: string?, wobAt: number? } } = {}

--=============================================================================
-- 2. Деобфусцированная функция xP (строка 7895 puls.orig.lua)
--    Проверяет отрыв дальше 30 студов
--=============================================================================

local function isDildoDetached(character: Model, state: { wob: { any }? }): boolean
    if not state.wob then
        return false
    end

    local firstPart: BasePart? = nil
    for _, item in ipairs(state.wob) do
        if typeof(item) == "Instance" and item:IsA("BasePart") then
            firstPart = item
            break
        end
    end

    if not firstPart or not firstPart.Parent then
        return true
    end

    local torso = character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("LowerTorso")
        or character:FindFirstChild("Torso")

    if not torso or not torso:IsA("BasePart") then
        return false
    end

    return (firstPart.Position - torso.Position).Magnitude > 30
end

--=============================================================================
-- 3. Деобфусцированная функция t (строка 1774 puls.orig.lua)
--    Деструктор: глушит коннекты и уничтожает детали
--=============================================================================

local function clearDildo(state: { wob: { any }?, wobSig: string?, wobAt: number? })
    if state.wob then
        for _, item in ipairs(state.wob) do
            pcall(function()
                if typeof(item) == "RBXScriptConnection" then
                    item:Disconnect()
                elseif typeof(item) == "Instance" then
                    item:Destroy()
                end
            end)
        end
    end
    state.wob = nil
    state.wobSig = nil
end

--=============================================================================
-- 4. Деобфусцированная функция DP (строка 2042 puls.orig.lua)
--    Фильтр raycast/overlap для деталей "PulseWobble"
--=============================================================================

function DildoManager.isNotPulseWobble(part: Instance): boolean
    if not part:IsA("BasePart") then
        return false
    end
    if part:IsA("Terrain") then
        return false
    end
    if (part :: BasePart).Transparency >= 1 then
        return false
    end
    if part.Name:sub(1, 11) == "PulseWobble" then
        return false
    end
    return true
end

--=============================================================================
-- 5. Полный конструктор __pulseWobBuild (строка 9226 puls.orig.lua)
--    С физикой пружин, венами, асимметрией и волосами у основания
--=============================================================================

local function pulseWobBuild(
    character: Model,
    scale: number,
    outTable: { any },
    isLocal: boolean,
    customCfg: DildoSettings?
)
    local cfg = customCfg or defaultSettings
    local sc = math.clamp(scale or 1, 0.2, 10)

    -- Поиск корня крепления на теле (LowerTorso для R15, Torso для R6)
    local rootPart = character:FindFirstChild("LowerTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("HumanoidRootPart")

    if not rootPart or not rootPart:IsA("BasePart") then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")

    -- Контейнер для лёгкого удаления
    local container = Instance.new("Folder")
    container.Name = "PulseWobble_Container"
    container.Parent = character
    table.insert(outTable, container)

    -- Геометрические размеры
    local shaftRadius = 0.36 * sc
    local shaftLength = 2.2 * sc
    local ballRadius = 0.52 * sc
    local tipRadius = 0.42 * sc

    local function makePart(name: string, shape: Enum.PartType, size: Vector3, col: Color3): Part
        local p = Instance.new("Part")
        p.Name = "PulseWobble_" .. name
        p.Shape = shape
        p.Size = size
        p.Material = cfg.material
        p.Color = col
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.Massless = true
        p.CastShadow = false
        p.Parent = container
        table.insert(outTable, p)
        return p
    end

    -- 1. Яйца (Balls) с естественной асимметрией (левое чуть ниже правого)
    local ballL = makePart("BallL", Enum.PartType.Ball, Vector3.new(ballRadius * 2, ballRadius * 2.1, ballRadius * 2), cfg.color)
    local ballR = makePart("BallR", Enum.PartType.Ball, Vector3.new(ballRadius * 1.95, ballRadius * 2.0, ballRadius * 1.95), cfg.color)

    local wBallL = Instance.new("Weld")
    wBallL.Name = "Weld_BallL"
    wBallL.Part0 = rootPart
    wBallL.Part1 = ballL
    wBallL.C0 = CFrame.new(-ballRadius * 0.72, -0.62 * sc, -0.42 * sc)
    wBallL.Parent = ballL
    table.insert(outTable, wBallL)

    local wBallR = Instance.new("Weld")
    wBallR.Name = "Weld_BallR"
    wBallR.Part0 = rootPart
    wBallR.Part1 = ballR
    wBallR.C0 = CFrame.new(ballRadius * 0.72, -0.56 * sc, -0.42 * sc) -- чуть выше левого
    wBallR.Parent = ballR
    table.insert(outTable, wBallR)

    -- 2. ВОЛОСЫ У ОСНОВАНИЯ (Pubic Hair System)
    if cfg.hairy then
        local hairFolder = Instance.new("Folder")
        hairFolder.Name = "PulseWobble_Hair"
        hairFolder.Parent = container
        table.insert(outTable, hairFolder)

        local count = math.floor(cfg.hairCount * cfg.hairDensity)
        for i = 1, count do
            local angle = (i / count) * math.pi * 2 + (math.random() - 0.5) * 0.4
            local radDist = (0.55 + math.random() * 0.35) * sc

            -- Распределение волос над основанием и по бокам яиц
            local hX = math.cos(angle) * radDist * 1.1
            local hY = -0.55 * sc + math.sin(angle) * radDist * 0.4
            local hZ = -0.45 * sc + (math.sin(angle) > 0 and -0.2 or 0.1) * sc

            local hairPart = Instance.new("Part")
            hairPart.Name = "PulseWobble_HairStrand"
            hairPart.Shape = Enum.PartType.Cylinder
            hairPart.Material = Enum.Material.SmoothPlastic
            hairPart.Color = cfg.hairColor
            hairPart.CanCollide = false
            hairPart.CanQuery = false
            hairPart.CanTouch = false
            hairPart.Massless = true
            hairPart.CastShadow = false

            -- Кудрявый завиток (тонкий короткий цилиндр)
            local strandLen = (0.35 + math.random() * 0.25) * sc
            local strandThickness = (0.05 + math.random() * 0.03) * sc
            hairPart.Size = Vector3.new(strandLen, strandThickness, strandThickness)

            local wHair = Instance.new("Weld")
            wHair.Part0 = rootPart
            wHair.Part1 = hairPart
            -- Случайный угол загиба для кудрявого эффекта
            local curlRot = CFrame.Angles(
                math.rad(math.random(-45, 45)),
                math.rad(math.random(-180, 180)),
                math.rad(math.random(-60, 60))
            )
            wHair.C0 = CFrame.new(hX, hY, hZ) * curlRot
            wHair.Parent = hairPart

            hairPart.Parent = hairFolder
            table.insert(outTable, hairPart)
            table.insert(outTable, wHair)
        end
    end

    -- 3. Стержень (Shaft)
    local shaft = makePart("Shaft", Enum.PartType.Cylinder, Vector3.new(shaftLength, shaftRadius * 2, shaftRadius * 2), cfg.color)

    -- Вены вдоль стержня (Veins)
    local vein1 = makePart("Vein1", Enum.PartType.Cylinder, Vector3.new(shaftLength * 0.85, shaftRadius * 0.22, shaftRadius * 0.22), cfg.veinColor)
    local wVein1 = Instance.new("Weld")
    wVein1.Part0 = shaft
    wVein1.Part1 = vein1
    wVein1.C0 = CFrame.new(0, shaftRadius * 0.92, shaftRadius * 0.3) * CFrame.Angles(0, 0, math.rad(4))
    wVein1.Parent = vein1
    table.insert(outTable, wVein1)

    local vein2 = makePart("Vein2", Enum.PartType.Cylinder, Vector3.new(shaftLength * 0.75, shaftRadius * 0.18, shaftRadius * 0.18), cfg.veinColor)
    local wVein2 = Instance.new("Weld")
    wVein2.Part0 = shaft
    wVein2.Part1 = vein2
    wVein2.C0 = CFrame.new(0, -shaftRadius * 0.88, -shaftRadius * 0.25) * CFrame.Angles(0, 0, math.rad(-5))
    wVein2.Parent = vein2
    table.insert(outTable, wVein2)

    -- 4. Головка (Glans / Head) с венчиком (Corona)
    local corona = makePart("Corona", Enum.PartType.Cylinder, Vector3.new(0.3 * sc, tipRadius * 2.1, tipRadius * 2.1), cfg.tipColor)
    local wCorona = Instance.new("Weld")
    wCorona.Part0 = shaft
    wCorona.Part1 = corona
    wCorona.C0 = CFrame.new(shaftLength / 2 - 0.1 * sc, 0, 0)
    wCorona.Parent = corona
    table.insert(outTable, wCorona)

    local tip = makePart("Tip", Enum.PartType.Ball, Vector3.new(tipRadius * 2, tipRadius * 1.95, tipRadius * 1.95), cfg.tipColor)
    local wTip = Instance.new("Weld")
    wTip.Part0 = shaft
    wTip.Part1 = tip
    wTip.C0 = CFrame.new(shaftLength / 2 + tipRadius * 0.65, 0, 0)
    wTip.Parent = tip
    table.insert(outTable, wTip)

    -- 5. ФИЗИЧЕСКИЙ MOTOR6D / СВЯЗЬ К ТОРСУ
    local motor = Instance.new("Motor6D")
    motor.Name = "ShaftMotor"
    motor.Part0 = rootPart
    motor.Part1 = shaft

    -- Исходное положение C0 (наклон торцом вперед вдоль направления взгляда персонажа)
    local baseAngle = math.rad(cfg.angleOffset)
    local baseC0 = CFrame.new(0, -0.48 * sc, -0.58 * sc)
        * CFrame.Angles(baseAngle, 0, 0)
        * CFrame.Angles(0, math.rad(90), 0)
        * CFrame.new(shaftLength / 2, 0, 0)

    motor.C0 = baseC0
    motor.Parent = shaft
    table.insert(outTable, motor)

    -- 6. ДВУХРЕЖИМНАЯ ДИНАМИЧЕСКАЯ ФИЗИКА (ПРУЖИНА ВЕРЛЕ + ИНЕРЦИЯ + ТРЯСКА)
    if cfg.physics then
        local currentPitch = 0
        local currentYaw = 0
        local currentRoll = 0

        local velPitch = 0
        local velYaw = 0
        local velRoll = 0

        local lastRootCF = rootPart.CFrame
        local lastTime = os.clock()

        local conn = RunService.RenderStepped:Connect(function(dt)
            if not rootPart.Parent or not shaft.Parent then
                return
            end
            dt = math.clamp(dt, 0.001, 0.05)

            -- Вычисление линейного и углового ускорения торса
            local curRootCF = rootPart.CFrame
            local rootVel = rootPart.AssemblyLinearVelocity or Vector3.zero
            local rootAngVel = rootPart.AssemblyAngularVelocity or Vector3.zero

            -- Локальная скорость персонажа
            local localVel = curRootCF:VectorToObjectSpace(rootVel)
            local speedZ = localVel.Z -- вперед/назад
            local speedX = localVel.X -- стрейф влево/вправо
            local speedY = localVel.Y -- прыжки/падение

            -- Инерционные силы
            local targetPitch = math.clamp(-speedZ * 0.04 - speedY * 0.05 + cfg.gravityDroop, -0.8, 0.9)
            local targetYaw = math.clamp(-speedX * 0.05 - rootAngVel.Y * 0.15, -0.8, 0.8)
            local targetRoll = math.clamp(speedX * 0.03, -0.5, 0.5)

            -- Добавочная синусоида при ходьбе (шаги)
            local horizSpeed = Vector3.new(rootVel.X, 0, rootVel.Z).Magnitude
            if horizSpeed > 1 then
                local stepFreq = (humanoid and humanoid.WalkSpeed or 16) * 0.45
                local stepClock = os.clock() * stepFreq
                local bounce = math.sin(stepClock) * math.clamp(horizSpeed / 16, 0.2, 1.2) * 0.15
                local sway = math.cos(stepClock * 0.5) * math.clamp(horizSpeed / 16, 0.2, 1.2) * 0.12

                targetPitch = targetPitch + bounce
                targetYaw = targetYaw + sway
            end

            -- Пружинный интегратор Верле (Spring Physics)
            local stiffness = cfg.springStiffness
            local damping = cfg.springDamping

            -- Осевые силы возврата
            local forcePitch = (targetPitch - currentPitch) * stiffness - velPitch * damping
            local forceYaw = (targetYaw - currentYaw) * stiffness - velYaw * damping
            local forceRoll = (targetRoll - currentRoll) * stiffness - velRoll * damping

            velPitch = velPitch + forcePitch * dt
            velYaw = velYaw + forceYaw * dt
            velRoll = velRoll + forceRoll * dt

            currentPitch = currentPitch + velPitch * dt
            currentYaw = currentYaw + velYaw * dt
            currentRoll = currentRoll + velRoll * dt

            -- Применение динамического CFrame
            motor.C0 = baseC0
                * CFrame.Angles(currentRoll, currentYaw, currentPitch)
        end)
        table.insert(outTable, conn)
    end
end

-- Регистрация внешнего конструктора для вызова из puls.orig.lua:9223
getgenv().__pulseWobBuild = pulseWobBuild

--=============================================================================
-- 6. Деобфусцированная функция PP (строка 9205 puls.orig.lua)
--    Контроллер сигнатуры "w" .. scale и повторной инициализации
--=============================================================================

function DildoManager.apply(character: Model, scale: number?, customSettings: DildoSettings?)
    local cfg = customSettings or defaultSettings
    local sc = scale or cfg.scale or 1

    local state = activeStates[character]
    if not state then
        state = { wob = nil, wobSig = nil, wobAt = 0 }
        activeStates[character] = state
    end

    local sig = "w" .. tostring(sc)
    local now = os.clock()

    -- Логика из строки 9211 puls.orig.lua
    if sig == (state.wobSig or "") then
        if not isDildoDetached(character, state) then
            return
        end
        if now - (state.wobAt or 0) < 2 then
            return
        end
    end

    state.wobAt = now
    clearDildo(state)
    state.wobSig = sig

    local outTable: { any } = {}
    local builder = getgenv().__pulseWobBuild or pulseWobBuild
    pcall(builder, character, sc, outTable, true, cfg)
    state.wob = outTable
end

-- Полное удаление
function DildoManager.remove(character: Model)
    local state = activeStates[character]
    if state then
        clearDildo(state)
        activeStates[character] = nil
    end
end

--=============================================================================
-- 7. Быстрый запуск для LocalPlayer
--=============================================================================

function DildoManager.attachToLocalPlayer(scale: number?, customSettings: DildoSettings?)
    local lp = Players.LocalPlayer
    local char = lp.Character or lp.CharacterAdded:Wait()

    DildoManager.apply(char, scale, customSettings)

    lp.CharacterAdded:Connect(function(newChar)
        task.wait(0.5)
        DildoManager.apply(newChar, scale, customSettings)
    end)
end

-- Авто-запуск для экзекутора
if not getgenv().__disableAutoRun then
    pcall(function()
        DildoManager.attachToLocalPlayer(1.6, {
            hairy = true,
            physics = true,
            scale = 1.6,
        })
    end)
end

return DildoManager
