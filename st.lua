--!nonstrict
--[[
    =============================================================================
    dildo.lua — Полный деобфусцированный модуль "PP" / "PulseWobble" (3D Дилдак)
    Извлечено из: C:\script-dumps\slient\pensil\puls.orig.lua
    
    В оригинальном дампе:
      * PP (строка 9205): Менеджер создания и жизненного цикла ("PP")
      * t  (строка 1774): Очистка деталей и отключение RunService-соединений
      * xP (строка 7895): Проверка отрыва от LowerTorso/Torso (> 30 studs)
      * DP (строка 2042): Фильтр коллизий и рейкастов (префикс "PulseWobble")
      * cP (строка 542) : Диспетчер косметики персонажа (K.wob -> scale)
      * getgenv().__pulseWobBuild: Внешний конструктор геометрии (воссоздан до байта)
    =============================================================================
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local DildoManager = {}
DildoManager.__index = DildoManager

--=============================================================================
-- 1. Настройки по умолчанию
--=============================================================================

export type DildoSettings = {
    enabled: boolean,          -- Включён ли объект
    scale: number,             -- Масштаб размера (в дампе a.sc, по дефолту 1.0)
    color: Color3,             -- Цвет (телесный по умолчанию)
    tipColor: Color3,          -- Цвет головки
    material: Enum.Material,   -- Материал (SmoothPlastic / Neon)
    wobble: boolean,           -- Физика раскачивания при движении
    wobbleSpeed: number,       -- Скорость покачивания
    wobbleIntensity: number,   -- Амплитуда покачивания
    angleOffset: number,       -- Базовый угол наклона в градусах
}

local defaultSettings: DildoSettings = {
    enabled = true,
    scale = 1.0,
    color = Color3.fromRGB(240, 160, 140),
    tipColor = Color3.fromRGB(225, 120, 130),
    material = Enum.Material.SmoothPlastic,
    wobble = true,
    wobbleSpeed = 8.0,
    wobbleIntensity = 0.25,
    angleOffset = 25,
}

DildoManager.DefaultSettings = defaultSettings

-- Хранилище активных объектов персонажей (состояние m из строки 9208)
local activeStates: { [Model]: { wob: { any }?, wobSig: string?, wobAt: number? } } = {}

--=============================================================================
-- 2. Деобфусцированная функция xP (строка 7895 в puls.orig.lua)
--    Проверяет, не оторвались ли детали дальше 30 студов от торса
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

    -- В оригинале: (U.Position - d.Position).Magnitude > 30
    return (firstPart.Position - torso.Position).Magnitude > 30
end

--=============================================================================
-- 3. Деобфусцированная функция t (строка 1774 в puls.orig.lua)
--    Удаляет детали и отключает RBXScriptConnection
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
-- 4. Деобфусцированная функция DP (строка 2042 в puls.orig.lua)
--    Фильтр для лучей/коллизий: игнорирует всё с префиксом "PulseWobble"
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
-- 5. Конструктор __pulseWobBuild (вызывается в строке 9226 puls.orig.lua)
--    Создаёт 3D модель: цилиндрический стержень, два шара у основания и головку
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

    -- Поиск точки крепления на теле (R15 LowerTorso или R6 Torso)
    local rootPart = character:FindFirstChild("LowerTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("HumanoidRootPart")

    if not rootPart or not rootPart:IsA("BasePart") then
        return
    end

    -- Папка-контейнер
    local container = Instance.new("Folder")
    container.Name = "PulseWobble_Container"
    container.Parent = character
    table.insert(outTable, container)

    -- Размеры с учётом коэффициента scale
    local shaftRadius = 0.35 * sc
    local shaftLength = 2.0 * sc
    local ballRadius = 0.5 * sc
    local tipRadius = 0.4 * sc

    -- 1. Левое яйцо (Sphere)
    local ballL = Instance.new("Part")
    ballL.Name = "PulseWobble_BallL"
    ballL.Shape = Enum.PartType.Ball
    ballL.Size = Vector3.new(ballRadius * 2, ballRadius * 2, ballRadius * 2)
    ballL.Material = cfg.material
    ballL.Color = cfg.color
    ballL.CanCollide = false
    ballL.Massless = true
    ballL.CastShadow = false
    ballL.Parent = container
    table.insert(outTable, ballL)

    -- 2. Правое яйцо (Sphere)
    local ballR = Instance.new("Part")
    ballR.Name = "PulseWobble_BallR"
    ballR.Shape = Enum.PartType.Ball
    ballR.Size = Vector3.new(ballRadius * 2, ballRadius * 2, ballRadius * 2)
    ballR.Material = cfg.material
    ballR.Color = cfg.color
    ballR.CanCollide = false
    ballR.Massless = true
    ballR.CastShadow = false
    ballR.Parent = container
    table.insert(outTable, ballR)

    -- 3. Стержень (Cylinder)
    -- В Roblox Cylinder ориентирован вдоль оси X (Size.X = длина, Size.Y/Z = диаметр)
    local shaft = Instance.new("Part")
    shaft.Name = "PulseWobble_Shaft"
    shaft.Shape = Enum.PartType.Cylinder
    shaft.Size = Vector3.new(shaftLength, shaftRadius * 2, shaftRadius * 2)
    shaft.Material = cfg.material
    shaft.Color = cfg.color
    shaft.CanCollide = false
    shaft.Massless = true
    shaft.CastShadow = false
    shaft.Parent = container
    table.insert(outTable, shaft)

    -- 4. Головка (Sphere / SpecialMesh)
    local tip = Instance.new("Part")
    tip.Name = "PulseWobble_Tip"
    tip.Shape = Enum.PartType.Ball
    tip.Size = Vector3.new(tipRadius * 2, tipRadius * 2, tipRadius * 2)
    tip.Material = cfg.material
    tip.Color = cfg.tipColor
    tip.CanCollide = false
    tip.Massless = true
    tip.CastShadow = false
    tip.Parent = container
    table.insert(outTable, tip)

    -- Сварка яиц к торсу
    local weldBallL = Instance.new("Weld")
    weldBallL.Name = "WeldL"
    weldBallL.Part0 = rootPart
    weldBallL.Part1 = ballL
    weldBallL.C0 = CFrame.new(-ballRadius * 0.7, -0.6 * sc, -0.45 * sc)
    weldBallL.Parent = ballL
    table.insert(outTable, weldBallL)

    local weldBallR = Instance.new("Weld")
    weldBallR.Name = "WeldR"
    weldBallR.Part0 = rootPart
    weldBallR.Part1 = ballR
    weldBallR.C0 = CFrame.new(ballRadius * 0.7, -0.6 * sc, -0.45 * sc)
    weldBallR.Parent = ballR
    table.insert(outTable, weldBallR)

    -- Motor6D для стержня (для динамического покачивания/вобблинга)
    local motor = Instance.new("Motor6D")
    motor.Name = "ShaftMotor"
    motor.Part0 = rootPart
    motor.Part1 = shaft
    -- Базовая C0: вынос вперед и поворот цилиндра вдоль направления взгляда
    local baseAngle = math.rad(cfg.angleOffset)
    local baseC0 = CFrame.new(0, -0.5 * sc, -0.6 * sc) 
        * CFrame.Angles(baseAngle, 0, 0)
        * CFrame.Angles(0, math.rad(90), 0) -- разворот цилиндра Roblox торцом вперед
        * CFrame.new(shaftLength / 2, 0, 0)

    motor.C0 = baseC0
    motor.Parent = shaft
    table.insert(outTable, motor)

    -- Сварка головки к концу цилиндра
    local weldTip = Instance.new("Weld")
    weldTip.Name = "WeldTip"
    weldTip.Part0 = shaft
    weldTip.Part1 = tip
    weldTip.C0 = CFrame.new(shaftLength / 2, 0, 0)
    weldTip.Parent = tip
    table.insert(outTable, weldTip)

    -- 6. Физическая анимация раскачивания (RenderStepped)
    if cfg.wobble then
        local clock = 0
        local conn = RunService.RenderStepped:Connect(function(dt)
            if not rootPart.Parent or not shaft.Parent then
                return
            end
            clock = clock + dt * cfg.wobbleSpeed

            -- Учет скорости персонажа для естественной инерции
            local vel = rootPart.AssemblyLinearVelocity or Vector3.zero
            local horizSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
            local speedMultiplier = math.clamp(horizSpeed / 16, 0.5, 3.0)

            local swayX = math.sin(clock) * cfg.wobbleIntensity * speedMultiplier
            local swayY = math.cos(clock * 0.5) * (cfg.wobbleIntensity * 0.6) * speedMultiplier
            local bounce = math.abs(math.sin(clock * 1.5)) * (cfg.wobbleIntensity * 0.4) * speedMultiplier

            motor.C0 = baseC0 
                * CFrame.Angles(0, swayX, swayY)
                * CFrame.new(0, bounce, 0)
        end)
        table.insert(outTable, conn)
    end
end

-- Регистрируем глобальный хук, как в строке 9223 puls.orig.lua
getgenv().__pulseWobBuild = pulseWobBuild

--=============================================================================
-- 6. Деобфусцированная функция PP (строка 9205 в puls.orig.lua)
--    Главный цикл привязки, валидации и перестроения
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

    -- Проверка из строки 9211 puls.orig.lua:
    -- если сигнатура совпадает, не оторвался ли объект и прошло ли < 2 сек
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

-- Полное снятие
function DildoManager.remove(character: Model)
    local state = activeStates[character]
    if state then
        clearDildo(state)
        activeStates[character] = nil
    end
end

--=============================================================================
-- 7. Быстрый запуск для локального игрока
--=============================================================================

function DildoManager.attachToLocalPlayer(scale: number?, customSettings: DildoSettings?)
    local lp = Players.LocalPlayer
    local char = lp.Character or lp.CharacterAdded:Wait()
    
    DildoManager.apply(char, scale, customSettings)

    -- Авто-восстановление при респавне
    lp.CharacterAdded:Connect(function(newChar)
        task.wait(0.5)
        DildoManager.apply(newChar, scale, customSettings)
    end)
end

-- Авто-запуск для экзекутора при прямом выполнении скрипта
if not getgenv().__disableAutoRun then
    pcall(function()
        DildoManager.attachToLocalPlayer(1.5)
    end)
end

return DildoManager
