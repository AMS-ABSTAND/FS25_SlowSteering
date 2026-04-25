-- SlowSteering.lua  v2.1.0.0
-- Realistic, speed-dependent steering reduction for FS25.
--
-- Hooks into the FS25 steering system:
--   self.maxRotTime / self.minRotTime       - steering angle range
--   self.wheelSteeringDuration              - steering speed (full sweep time)
--   self.autoRotateBackSpeed                - return-to-centre speed
--   Drivable:setSteeringInput()             - input sensitivity
--
-- Realism layers:
--   1. Speed-dependent input reduction (curve-based)
--   2. Counter-steer extra damping
--   3. Input deadzone + exponential input curve
--   4. Power-steering effort (longer sweep at high speed)
--   5. Smoothed transitions (frame-independent lerp)
--   6. Return-to-centre slowdown
--   7. Optional brake-force scaling
--
-- All base values are captured once and restored on delete / mod-off.

SlowSteering = {}
SlowSteering.isActive = true
SlowSteering.showHud  = true

-- =========================================================
-- DEFAULTS  (single source of truth - "realistic" baseline)
-- =========================================================
SlowSteering.DEFAULTS = {
    -- Core curve
    refSpeed                 = 50,     -- km/h at which full reduction is reached
    steeringReductionAtRef   = 0.55,   -- fraction of steering reduced at refSpeed (0-1)
    counterSteerReduction    = 0.40,   -- extra reduction when counter-steering (0-1)
    returnSlowdown           = 0.50,   -- fraction of return-to-centre slowdown (0-1)
    baseSteeringSpeed        = 1.0,    -- multiplier for steering speed
    returnMultiplier         = 1.5,    -- weight of return-slowdown curve
    smoothingFactor          = 0.10,   -- lerp alpha per frame - lower = smoother
    curveExponent            = 1.5,    -- >1 = gentle at low speed, aggressive at high
    brakeForceMultiplier     = 1.0,    -- brake force scale (0.05 = very weak, 1.0 = normal)

    -- Realism additions
    deadzone                 = 0.04,   -- input deadzone (0-0.3)
    inputCurve               = 1.20,   -- input exponent (1=linear, >1=softer near centre)
    powerSteeringEffort      = 0.30,   -- 0..0.9 - extra wheel-duration scaling at speed

    -- HUD
    hudPosition              = 1,      -- 1=TR, 2=TL, 3=BR, 4=BL
    hudShowGauge             = true,   -- show coloured bar
    hudShowSpeed             = true,   -- show speed in HUD
    hudOpacity               = 0.85,

    -- Profile name (informational; drives presets in GUI)
    activeProfile            = "realistic",
}

-- Validation ranges  { min, max }
SlowSteering.RANGES = {
    refSpeed                 = {  5,    200   },
    steeringReductionAtRef   = {  0.01, 0.95  },
    counterSteerReduction    = {  0.0,  0.95  },
    returnSlowdown           = {  0.01, 0.99  },
    baseSteeringSpeed        = {  0.1,  3.0   },
    returnMultiplier         = {  0.5,  3.0   },
    smoothingFactor          = {  0.01, 1.0   },
    curveExponent            = {  0.5,  3.0   },
    brakeForceMultiplier     = {  0.05, 1.0   },
    deadzone                 = {  0.0,  0.30  },
    inputCurve               = {  1.0,  3.0   },
    powerSteeringEffort      = {  0.0,  0.90  },
    hudOpacity               = {  0.20, 1.0   },
    hudPosition              = {  1,    4     },
}

-- =========================================================
-- PRESETS - tuned for different play styles
-- =========================================================
SlowSteering.PRESETS = {
    arcade = {
        steeringReductionAtRef = 0.20,
        counterSteerReduction  = 0.10,
        returnSlowdown         = 0.20,
        curveExponent          = 1.0,
        deadzone               = 0.00,
        inputCurve             = 1.0,
        powerSteeringEffort    = 0.00,
        smoothingFactor        = 0.30,
        baseSteeringSpeed      = 1.2,
        returnMultiplier       = 1.0,
        brakeForceMultiplier   = 1.0,
    },
    normal = {
        steeringReductionAtRef = 0.40,
        counterSteerReduction  = 0.30,
        returnSlowdown         = 0.40,
        curveExponent          = 1.3,
        deadzone               = 0.02,
        inputCurve             = 1.1,
        powerSteeringEffort    = 0.15,
        smoothingFactor        = 0.15,
        baseSteeringSpeed      = 1.0,
        returnMultiplier       = 1.3,
        brakeForceMultiplier   = 1.0,
    },
    realistic = {
        steeringReductionAtRef = 0.55,
        counterSteerReduction  = 0.40,
        returnSlowdown         = 0.50,
        curveExponent          = 1.5,
        deadzone               = 0.04,
        inputCurve             = 1.2,
        powerSteeringEffort    = 0.30,
        smoothingFactor        = 0.10,
        baseSteeringSpeed      = 0.95,
        returnMultiplier       = 1.5,
        brakeForceMultiplier   = 1.0,
    },
    sim = {
        steeringReductionAtRef = 0.70,
        counterSteerReduction  = 0.55,
        returnSlowdown         = 0.65,
        curveExponent          = 1.8,
        deadzone               = 0.06,
        inputCurve             = 1.4,
        powerSteeringEffort    = 0.55,
        smoothingFactor        = 0.07,
        baseSteeringSpeed      = 0.85,
        returnMultiplier       = 1.7,
        brakeForceMultiplier   = 0.95,
    },
}

SlowSteering.PRESET_ORDER = { "arcade", "normal", "realistic", "sim", "custom" }
SlowSteering.PRESET_LABELS = {
    arcade    = "Arcade",
    normal    = "Standard",
    realistic = "Realistisch",
    sim       = "Simulation",
    custom    = "Eigen",
}

-- Apply defaults as initial runtime values
for k, v in pairs(SlowSteering.DEFAULTS) do
    SlowSteering[k] = v
end

-- CONFIG paths
SlowSteering.CONF_DIR  = getUserProfileAppPath() .. "modsSettings/FS25_SlowSteering/"
SlowSteering.CONF_FILE = SlowSteering.CONF_DIR .. "settings.xml"

-- =========================================================
-- HELPERS
-- =========================================================
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function lerp(a, b, t)
    return a + (b - a) * clamp(t, 0, 1)
end

local function sign(v)
    if v > 0 then return 1 end
    if v < 0 then return -1 end
    return 0
end

local function log(msg)
    print("SlowSteering: " .. tostring(msg))
end

local function ensureDir(path)
    pcall(createFolder, path)
end

--- Validate and clamp a single setting
local function validateSetting(key, value)
    local r = SlowSteering.RANGES[key]
    if r then
        local clamped = clamp(value, r[1], r[2])
        if clamped ~= value then
            log(string.format("  '%s' clamped: %.4f -> %.4f (range %.4f-%.4f)",
                key, value, clamped, r[1], r[2]))
        end
        return clamped
    end
    return value
end

-- =========================================================
-- PRESET SYSTEM
-- =========================================================

--- Apply a preset (does NOT save) - 'custom' is a no-op
function SlowSteering.applyPreset(name)
    if name == "custom" then
        SlowSteering.activeProfile = "custom"
        return true
    end
    local preset = SlowSteering.PRESETS[name]
    if preset == nil then return false end
    for key, value in pairs(preset) do
        SlowSteering[key] = validateSetting(key, value)
    end
    SlowSteering.activeProfile = name
    return true
end

--- Detect which preset (if any) currently matches the active values
function SlowSteering.detectActivePreset()
    for _, name in ipairs(SlowSteering.PRESET_ORDER) do
        if name ~= "custom" then
            local preset = SlowSteering.PRESETS[name]
            local match = true
            for key, value in pairs(preset) do
                local current = SlowSteering[key]
                if current == nil or math.abs(current - value) > 0.001 then
                    match = false
                    break
                end
            end
            if match then return name end
        end
    end
    return "custom"
end

-- =========================================================
-- SPECIALIZATION BOILERPLATE
-- =========================================================
function SlowSteering.initSpecialization()
end

function SlowSteering.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Motorized,  specializations)
       and SpecializationUtil.hasSpecialization(Drivable,   specializations)
       and SpecializationUtil.hasSpecialization(Enterable,  specializations)
end

function SlowSteering.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad",                  SlowSteering)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad",              SlowSteering)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate",                SlowSteering)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw",                  SlowSteering)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete",                SlowSteering)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents",  SlowSteering)
end

function SlowSteering.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setSteeringInput", SlowSteering.setSteeringInput)
end

-- =========================================================
-- LOAD
-- =========================================================
function SlowSteering:onLoad(savegame)
    self.spec_slowSteering = {
        actionEvents            = {},
        smoothedReduction       = 1.0,
        currentReduction        = 1.0,
        currentSpeed            = 0,
        -- base values captured in onPostLoad
        baseMaxRotTime          = nil,
        baseMinRotTime          = nil,
        baseWheelSteeringDur    = nil,
        baseAutoRotateBackSpeed = nil,
        baseBrakeForce          = nil,
    }
end

function SlowSteering:onPostLoad(savegame)
    local s = self.spec_slowSteering
    if s == nil then return end

    -- Steering angle range
    if self.maxRotTime ~= nil and self.maxRotTime ~= 0 then
        s.baseMaxRotTime = self.maxRotTime
        s.baseMinRotTime = self.minRotTime
    end
    if self.wheelSteeringDuration ~= nil then
        s.baseWheelSteeringDur = self.wheelSteeringDuration
    end
    if self.autoRotateBackSpeed ~= nil then
        s.baseAutoRotateBackSpeed = self.autoRotateBackSpeed
    end

    local motor = self.spec_motorized and self.spec_motorized.motor
    if motor ~= nil and motor.brakeForce ~= nil then
        s.baseBrakeForce = motor.brakeForce
    end
end

-- =========================================================
-- DELETE  (restore everything)
-- =========================================================
function SlowSteering:onDelete()
    SlowSteering.restoreBaseValues(self)
end

function SlowSteering.restoreBaseValues(vehicle)
    local s = vehicle.spec_slowSteering
    if s == nil then return end

    if s.baseMaxRotTime ~= nil then
        vehicle.maxRotTime = s.baseMaxRotTime
        vehicle.minRotTime = s.baseMinRotTime
    end
    if s.baseWheelSteeringDur ~= nil then
        vehicle.wheelSteeringDuration = s.baseWheelSteeringDur
    end
    if s.baseAutoRotateBackSpeed ~= nil then
        vehicle.autoRotateBackSpeed = s.baseAutoRotateBackSpeed
    end
    if s.baseBrakeForce ~= nil then
        local motor = vehicle.spec_motorized and vehicle.spec_motorized.motor
        if motor ~= nil then
            motor.brakeForce = s.baseBrakeForce
        end
    end

    s.smoothedReduction = 1.0
    s.currentReduction  = 1.0
end

-- =========================================================
-- OVERWRITTEN: setSteeringInput
-- =========================================================
function SlowSteering:setSteeringInput(superFunc, inputValue, isAnalog, deviceCategory)
    -- Block steering while settings GUI is open
    if SlowSteeringGui ~= nil and SlowSteeringGui.isOpen then
        return superFunc(self, 0, isAnalog, deviceCategory)
    end

    if SlowSteering.isActive and inputValue ~= nil and inputValue ~= 0 then
        local speed  = math.abs(self:getLastSpeed() or 0)
        local t      = clamp(speed / SlowSteering.refSpeed, 0, 1)
        local curved = t ^ SlowSteering.curveExponent

        -- (1) Deadzone - filter very small inputs
        local absIn = math.abs(inputValue)
        if absIn < SlowSteering.deadzone then
            inputValue = 0
        else
            -- Re-scale so input outside deadzone runs 0..1 again
            absIn = (absIn - SlowSteering.deadzone) / (1 - SlowSteering.deadzone)

            -- (2) Input curve - softer near centre, full deflection at edges
            if SlowSteering.inputCurve > 1.0 then
                absIn = absIn ^ SlowSteering.inputCurve
            end
            inputValue = sign(inputValue) * absIn
        end

        if inputValue ~= 0 then
            -- (3) Speed-based reduction
            local reduction = 1 - (SlowSteering.steeringReductionAtRef * curved)
            reduction       = clamp(reduction, 0.05, 1.0)

            -- (4) Counter-steer extra damping
            if SlowSteering.counterSteerReduction > 0 then
                local spec_d = self.spec_drivable
                if spec_d ~= nil then
                    local currentSide = spec_d.axisSide or 0
                    if currentSide ~= 0 and (inputValue * currentSide) < 0 then
                        local counterFactor = 1 - (SlowSteering.counterSteerReduction * curved)
                        counterFactor = clamp(counterFactor, 0.05, 1.0)
                        reduction = reduction * counterFactor
                    end
                end
            end

            inputValue = inputValue * reduction
        end
    end
    return superFunc(self, inputValue, isAnalog, deviceCategory)
end

-- =========================================================
-- ACTION EVENTS  (hotkeys)
-- =========================================================
function SlowSteering:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient then return end

    local s = self.spec_slowSteering
    if s == nil then return end

    self:clearActionEventsTable(s.actionEvents)

    if not isActiveForInputIgnoreSelection then return end

    local entered = self.getIsEntered ~= nil and self:getIsEntered()
    if not entered then return end

    local _, eventId

    _, eventId = self:addActionEvent(s.actionEvents,
        InputAction.SlowSteering_Toggle, self, SlowSteering.onToggle,
        false, true, false, true, nil)
    if eventId ~= nil then
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_LOW)
        g_inputBinding:setActionEventTextVisibility(eventId, false)
    end

    _, eventId = self:addActionEvent(s.actionEvents,
        InputAction.SlowSteering_Reload, self, SlowSteering.onOpenSettings,
        false, true, false, true, nil)
    if eventId ~= nil then
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_LOW)
        g_inputBinding:setActionEventTextVisibility(eventId, false)
    end
end

function SlowSteering.onToggle(self, actionName, inputValue, callbackState, isAnalog)
    SlowSteering.isActive = not SlowSteering.isActive

    if g_currentMission ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format("Slow Steering: %s", SlowSteering.isActive and "AN" or "AUS"))
    end

    log(SlowSteering.isActive and "ON" or "OFF")
    SlowSteering.saveConfig()
end

function SlowSteering.onOpenSettings(self, actionName, inputValue, callbackState, isAnalog)
    if SlowSteeringGui ~= nil then
        if SlowSteeringGui.isOpen then
            SlowSteeringGui.close(false)
        else
            SlowSteeringGui.open()
        end
    end
end

-- =========================================================
-- UPDATE  (per frame - modifies vehicle steering properties)
-- =========================================================
function SlowSteering:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local s = self.spec_slowSteering
    if s == nil then return end

    if not SlowSteering.isActive or not isActiveForInputIgnoreSelection then
        SlowSteering.restoreBaseValues(self)
        return
    end

    local speed   = math.abs(self:getLastSpeed() or 0)
    local t       = clamp(speed / SlowSteering.refSpeed, 0, 1)
    local curved  = t ^ SlowSteering.curveExponent

    s.currentSpeed = speed

    -- Frame-independent lerp alpha  (dt in ms, 16.667 ms ~ 60 fps)
    local alpha = 1 - (1 - SlowSteering.smoothingFactor) ^ (dt / 16.667)

    -- Target reduction (1.0 = no change, lower = more reduction)
    local targetFactor = 1 - (SlowSteering.steeringReductionAtRef * curved)
    targetFactor       = clamp(targetFactor, 0.05, 1.0)

    s.smoothedReduction = lerp(s.smoothedReduction, targetFactor, alpha)
    s.currentReduction  = s.smoothedReduction

    -- ---- Steering angle limit ----
    if s.baseMaxRotTime ~= nil then
        local angleFactor = clamp(targetFactor, 0.15, 1.0)
        self.maxRotTime = s.baseMaxRotTime * angleFactor
        self.minRotTime = s.baseMinRotTime * angleFactor
    end

    -- ---- Steering speed (sweep duration) ----
    -- Combined with power-steering effort: at speed, sweep gets longer
    if s.baseWheelSteeringDur ~= nil then
        local speedMul = clamp(s.smoothedReduction * SlowSteering.baseSteeringSpeed, 0.1, 3.0)
        local effort   = 1.0 + (SlowSteering.powerSteeringEffort * curved)
        self.wheelSteeringDuration = (s.baseWheelSteeringDur / speedMul) * effort
    end

    -- ---- Return-to-centre slowdown ----
    if s.baseAutoRotateBackSpeed ~= nil then
        local returnFactor = 1 - (SlowSteering.returnSlowdown * SlowSteering.returnMultiplier * curved)
        returnFactor = clamp(returnFactor, 0.05, 1.0)
        self.autoRotateBackSpeed = s.baseAutoRotateBackSpeed * returnFactor
    end

    -- ---- Brake force ----
    if s.baseBrakeForce ~= nil then
        local motor = self.spec_motorized and self.spec_motorized.motor
        if motor ~= nil then
            if SlowSteering.brakeForceMultiplier < 1.0 then
                motor.brakeForce = s.baseBrakeForce * SlowSteering.brakeForceMultiplier
            else
                motor.brakeForce = s.baseBrakeForce
            end
        end
    end
end

-- =========================================================
-- HUD - draws via the per-vehicle onDraw event
-- =========================================================

-- HUD anchor positions (x, y, alignment)
local HUD_POSITIONS = {
    [1] = { x = 0.985, y = 0.022, align = "right" }, -- TR
    [2] = { x = 0.015, y = 0.022, align = "left"  }, -- TL
    [3] = { x = 0.985, y = 0.965, align = "right" }, -- BR
    [4] = { x = 0.015, y = 0.965, align = "left"  }, -- BL
}

local function ensureHudOverlay()
    if SlowSteering._hudOverlay == nil then
        SlowSteering._hudOverlay = createImageOverlay("dataS/menu/base/graph_pixel.png")
    end
    return SlowSteering._hudOverlay
end

local function colorForReduction(pctNorm)
    -- 100 % -> green, 50 % -> yellow, 0 % -> red
    local r, g
    if pctNorm > 0.5 then
        local k = (pctNorm - 0.5) * 2  -- 0..1 (mid->top)
        r = 1.0 - 0.7 * k
        g = 0.85
    else
        local k = pctNorm * 2  -- 0..1 (bottom->mid)
        r = 1.0
        g = 0.30 + 0.55 * k
    end
    return r, g, 0.15
end

function SlowSteering:onDraw()
    if not SlowSteering.showHud or not SlowSteering.isActive then return end

    local s = self.spec_slowSteering
    if s == nil then return end

    local pos = HUD_POSITIONS[SlowSteering.hudPosition] or HUD_POSITIONS[1]
    local pct       = math.floor(s.currentReduction * 100 + 0.5)
    local pctNorm   = pct / 100
    local cr, cg, cb = colorForReduction(pctNorm)

    local alpha = SlowSteering.hudOpacity
    local overlay = ensureHudOverlay()

    -- Layout dimensions (screen-space, 0..1)
    local panelW = 0.140
    local panelH = SlowSteering.hudShowGauge and 0.045 or 0.028
    local px = pos.x - (pos.align == "right" and panelW or 0)
    local py = pos.y - panelH * 0.5

    -- Background panel (subtle)
    if overlay ~= nil and overlay ~= 0 then
        setOverlayColor(overlay, 0.05, 0.07, 0.10, 0.55 * alpha)
        renderOverlay(overlay, px, py, panelW, panelH)
        -- left accent bar
        setOverlayColor(overlay, cr, cg, cb, 0.85 * alpha)
        renderOverlay(overlay, px, py, 0.003, panelH)
    end

    local textY = py + panelH - 0.020
    local labelX, valueX
    if pos.align == "right" then
        labelX = px + 0.012
        valueX = px + panelW - 0.008
    else
        labelX = px + 0.012
        valueX = px + panelW - 0.008
    end

    -- Title text (left aligned)
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(0.85, 0.88, 0.92, alpha)
    renderText(labelX, textY, 0.0125, "SLOW STEERING")

    -- Value text (right aligned)
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(cr, cg, cb, alpha)
    renderText(valueX, textY, 0.014, string.format("%d%%", pct))

    -- Gauge bar
    if SlowSteering.hudShowGauge and overlay ~= nil and overlay ~= 0 then
        local barX = px + 0.012
        local barY = py + 0.008
        local barW = panelW - 0.024
        local barH = 0.006

        -- Track
        setOverlayColor(overlay, 0.15, 0.17, 0.20, 0.85 * alpha)
        renderOverlay(overlay, barX, barY, barW, barH)
        -- Fill
        setOverlayColor(overlay, cr, cg, cb, alpha)
        renderOverlay(overlay, barX, barY, barW * pctNorm, barH)
    end

    -- Optional speed line
    if SlowSteering.hudShowSpeed then
        setTextBold(false)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(0.65, 0.70, 0.75, alpha * 0.9)
        local subY = py - 0.013
        local speedKmh = s.currentSpeed
        local speedTxt = string.format("%d km/h", math.floor(speedKmh + 0.5))
        if SlowSteering.brakeForceMultiplier < 1.0 then
            speedTxt = speedTxt .. string.format("   BRK %d%%",
                math.floor(SlowSteering.brakeForceMultiplier * 100 + 0.5))
        end
        renderText(labelX, subY, 0.011, speedTxt)
    end

    -- Reset render state
    setTextColor(1, 1, 1, 1)
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

-- =========================================================
-- CONFIG  (save / load)
-- =========================================================
local CONFIG_KEYS = {
    -- { xmlKey, luaField, type }
    { "isActive",                "isActive",                "bool"   },
    { "showHud",                 "showHud",                 "bool"   },
    { "refSpeed",                "refSpeed",                "float"  },
    { "steeringReductionAtRef",  "steeringReductionAtRef",  "float"  },
    { "counterSteerReduction",   "counterSteerReduction",   "float"  },
    { "returnSlowdown",          "returnSlowdown",          "float"  },
    { "baseSteeringSpeed",       "baseSteeringSpeed",       "float"  },
    { "returnMultiplier",        "returnMultiplier",        "float"  },
    { "smoothingFactor",         "smoothingFactor",         "float"  },
    { "curveExponent",           "curveExponent",           "float"  },
    { "brakeForceMultiplier",    "brakeForceMultiplier",    "float"  },
    { "deadzone",                "deadzone",                "float"  },
    { "inputCurve",              "inputCurve",              "float"  },
    { "powerSteeringEffort",     "powerSteeringEffort",     "float"  },
    { "hudPosition",             "hudPosition",             "int"    },
    { "hudShowGauge",            "hudShowGauge",            "bool"   },
    { "hudShowSpeed",            "hudShowSpeed",            "bool"   },
    { "hudOpacity",              "hudOpacity",              "float"  },
    { "activeProfile",           "activeProfile",           "string" },
}

function SlowSteering.saveConfig()
    ensureDir(getUserProfileAppPath() .. "modsSettings/")
    ensureDir(SlowSteering.CONF_DIR)

    local xml = XMLFile.create("SlowSteeringCfg", SlowSteering.CONF_FILE, "SlowSteering")
    if xml == nil then return end

    for _, entry in ipairs(CONFIG_KEYS) do
        local path = "SlowSteering.settings#" .. entry[1]
        local val  = SlowSteering[entry[2]]
        if entry[3] == "bool" then
            xml:setBool(path, val)
        elseif entry[3] == "int" then
            xml:setInt(path, val)
        elseif entry[3] == "string" then
            xml:setString(path, tostring(val))
        else
            xml:setFloat(path, val)
        end
    end

    xml:save()
    xml:delete()
end

function SlowSteering.loadConfig(isFirstLoad)
    ensureDir(getUserProfileAppPath() .. "modsSettings/")
    ensureDir(SlowSteering.CONF_DIR)

    if not fileExists(SlowSteering.CONF_FILE) then
        log("No config found - creating defaults")
        SlowSteering.saveConfig()
        return
    end

    -- Try new format first, then legacy formats
    local xml = XMLFile.load("SlowSteeringCfg", SlowSteering.CONF_FILE, "SlowSteering")
    local xmlPrefix = "SlowSteering.settings#"
    local isLegacy = false

    if xml == nil then
        xml = XMLFile.load("SlowSteeringCfg", SlowSteering.CONF_FILE, "SS")
        xmlPrefix = "SS.general#"
        isLegacy = true
    end

    if xml == nil then
        log("WARNING: could not read config - using defaults")
        return
    end

    for _, entry in ipairs(CONFIG_KEYS) do
        local path    = xmlPrefix .. entry[1]
        local default = SlowSteering.DEFAULTS[entry[2]]

        if entry[3] == "bool" then
            SlowSteering[entry[2]] = xml:getBool(path, SlowSteering[entry[2]])
        elseif entry[3] == "int" then
            local val = xml:getInt(path, default or SlowSteering[entry[2]])
            SlowSteering[entry[2]] = validateSetting(entry[2], val)
        elseif entry[3] == "string" then
            SlowSteering[entry[2]] = xml:getString(path, default or SlowSteering[entry[2]])
        else
            local val = xml:getFloat(path, default or SlowSteering[entry[2]])
            SlowSteering[entry[2]] = validateSetting(entry[2], val)
        end
    end

    xml:delete()
    log("Config loaded")

    if isLegacy then
        SlowSteering.saveConfig()
        log("Config migrated to new format")
    end
end
