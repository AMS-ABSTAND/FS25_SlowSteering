-- SlowSteeringGui.lua  v2.2.0.0
-- Redesigned settings overlay for SlowSteering.
-- FS25-style dark panel with orange accent, full mouse + keyboard support,
-- live curve preview, preset cycle, and per-setting help.
--
-- Keyboard:
--   Up/Down       navigate settings in current tab
--   Left/Right    change selected value
--   Tab / Q / E   cycle tab    (Shift+Tab = previous)
--   P             cycle preset
--   F1            reset selected setting to default
--   F5            reset ALL settings to active preset (or defaults)
--   Enter         save & close
--   Esc / Bksp    cancel & close
--
-- Mouse:
--   Click tab            switch tab
--   Click row            select setting
--   Click value < / >    decrement / increment
--   Drag slider          live update value
--   Click toggle pill    flip bool
--   Click footer button  Save / Cancel / Reset

SlowSteeringGui = {}
SlowSteeringGui.isOpen          = false
SlowSteeringGui.activeTab       = 1
SlowSteeringGui.selectedIdx     = 1
SlowSteeringGui.tempValues      = {}
SlowSteeringGui.originalProfile = nil
SlowSteeringGui.bgOverlay       = nil
SlowSteeringGui.flashFrames     = 0
SlowSteeringGui.flashColor      = nil
SlowSteeringGui.hoverTab        = 0
SlowSteeringGui.hoverRow        = 0
SlowSteeringGui.hoverFooter     = 0   -- 1=save 2=cancel 3=reset
SlowSteeringGui.dragging        = nil -- def currently dragged
SlowSteeringGui.mouseX          = 0
SlowSteeringGui.mouseY          = 0
SlowSteeringGui._rowRects       = {}  -- runtime row hitboxes
SlowSteeringGui._tabRects       = {}
SlowSteeringGui._sliderRects    = {}
SlowSteeringGui._valueLeftRects = {}
SlowSteeringGui._valueRightRects= {}
SlowSteeringGui._togglePillRects= {}
SlowSteeringGui._footerRects    = {}

-- =========================================================
-- TAB & SETTING DEFINITIONS
-- =========================================================
SlowSteeringGui.TABS = {
    {
        id    = "general",
        label = "Allgemein",
        icon  = "[A]",
        items = {
            { key = "isActive",    label = "Mod aktiv",            type = "bool",
              help = "Schaltet die Lenkungs-Reduktion komplett ein oder aus." },
            { key = "showHud",     label = "HUD anzeigen",         type = "bool",
              help = "Zeigt die kleine Anzeige im Spiel mit aktueller Reduktion." },
            { key = "_preset",     label = "Profil",               type = "preset",
              help = "Auswahl Voreinstellung. Aenderungen schalten auf 'Eigen'." },
            { key = "refSpeed",    label = "Referenzgeschwindigkeit", type = "float", step = 5,
              fmt = "%.0f km/h",
              help = "Geschwindigkeit, bei der die volle Reduktion erreicht wird." },
            { key = "smoothingFactor", label = "Glaettung",        type = "float", step = 0.02, fmt = "%.2f",
              help = "Wie traege Reduktion auf Geschwindigkeit reagiert. Kleiner = weicher." },
            { key = "curveExponent",   label = "Kurvenexponent",   type = "float", step = 0.1, fmt = "%.1f",
              help = ">1 = sanft bei langsam, aggressiv bei schnell. 1.0 = linear." },
        }
    },
    {
        id    = "steering",
        label = "Lenkung",
        icon  = "[L]",
        items = {
            { key = "steeringReductionAtRef", label = "Lenkreduktion",          type = "float",
              step = 0.05, fmt = "%.0f%%", scale = 100,
              help = "Prozent Lenkreduktion bei Referenzgeschwindigkeit." },
            { key = "counterSteerReduction",  label = "Gegenlenk-Daempfung",    type = "float",
              step = 0.05, fmt = "%.0f%%", scale = 100,
              help = "Zusaetzliche Daempfung beim Gegenlenken aus einer Kurve." },
            { key = "returnSlowdown",         label = "Rueckstellung",          type = "float",
              step = 0.05, fmt = "%.0f%%", scale = 100,
              help = "Wie stark die Lenkraeder bei Tempo langsamer zurueck zentrieren." },
            { key = "returnMultiplier",       label = "Rueckstell-Multiplikator", type = "float",
              step = 0.1, fmt = "%.1fx",
              help = "Verstaerkt den Rueckstellungs-Effekt zusaetzlich." },
            { key = "baseSteeringSpeed",      label = "Lenkgeschwindigkeit",    type = "float",
              step = 0.1, fmt = "%.1fx",
              help = "Globaler Multiplikator fuer Lenktempo. <1 = traeger." },
        }
    },
    {
        id    = "realism",
        label = "Realismus",
        icon  = "[R]",
        items = {
            { key = "deadzone",            label = "Eingabe-Totzone",         type = "float",
              step = 0.01, fmt = "%.0f%%", scale = 100,
              help = "Filtert kleine Eingaben um Mikro-Wackeln zu vermeiden." },
            { key = "inputCurve",          label = "Eingabe-Kurve",           type = "float",
              step = 0.1, fmt = "%.1f",
              help = "Exponent fuer Eingabe. >1 = weicher in der Mitte (besser fuer Tastatur)." },
            { key = "powerSteeringEffort", label = "Servo-Aufwand",           type = "float",
              step = 0.05, fmt = "%.0f%%", scale = 100,
              help = "Bei Tempo dauert die Lenkbewegung laenger - wie ohne Servohilfe." },
            { key = "brakeForceMultiplier", label = "Bremskraft",             type = "float",
              step = 0.05, fmt = "%.0f%%", scale = 100,
              help = "Skaliert die Bremskraft. 100% = Original, weniger = traegere Bremse." },
        }
    },
    {
        id    = "hud",
        label = "HUD",
        icon  = "[H]",
        items = {
            { key = "hudPosition",  label = "HUD-Position",  type = "enum",
              values = { 1, 2, 3, 4 },
              labels = { [1]="Oben rechts", [2]="Oben links", [3]="Unten rechts", [4]="Unten links" },
              help = "Wo die Anzeige im Bild erscheint." },
            { key = "hudShowGauge", label = "Balken-Anzeige", type = "bool",
              help = "Farbiger Balken neben der Prozentzahl." },
            { key = "hudShowSpeed", label = "Tempo anzeigen", type = "bool",
              help = "Aktuelle Geschwindigkeit unter der Hauptzeile." },
            { key = "hudOpacity",   label = "Deckkraft",      type = "float",
              step = 0.05, fmt = "%.0f%%", scale = 100,
              help = "Transparenz der HUD-Anzeige." },
        }
    },
}

-- =========================================================
-- THEME (FS25-style: deep grey panel + orange accent)
-- =========================================================
local C = {
    dim         = { 0.00, 0.00, 0.00, 0.62 },
    panelBg     = { 0.078, 0.090, 0.110, 0.985 },
    panelEdge   = { 0.20,  0.22,  0.26,  1.00  },
    headerBg    = { 0.118, 0.137, 0.169, 1.00  },
    headerLine  = { 1.00,  0.62,  0.06,  1.00  }, -- FS orange accent
    tabBg       = { 0.090, 0.107, 0.130, 1.00  },
    tabActiveBg = { 0.137, 0.165, 0.200, 1.00  },
    tabHover    = { 0.114, 0.137, 0.170, 1.00  },
    tabUnderline= { 1.00,  0.62,  0.06,  1.00  },
    rowBg       = { 0.105, 0.125, 0.150, 0.55  },
    rowSelected = { 0.18,  0.22,  0.27,  1.00  },
    rowHover    = { 0.140, 0.165, 0.198, 1.00  },
    rowAccent   = { 1.00,  0.62,  0.06,  1.00  },
    sliderTrack = { 0.18,  0.20,  0.24,  1.00  },
    sliderFill  = { 1.00,  0.62,  0.06,  1.00  },
    sliderFillD = { 0.55,  0.36,  0.06,  1.00  },
    sliderKnob  = { 1.00,  1.00,  1.00,  1.00  },
    txtPrimary  = { 0.94,  0.95,  0.96,  1.00  },
    txtSecond   = { 0.70,  0.74,  0.78,  1.00  },
    txtMuted    = { 0.50,  0.54,  0.58,  1.00  },
    txtAccent   = { 1.00,  0.74,  0.30,  1.00  },
    txtChanged  = { 1.00,  0.85,  0.30,  1.00  },
    txtOk       = { 0.45,  0.85,  0.55,  1.00  },
    pillOn      = { 0.20,  0.55,  0.30,  1.00  },
    pillOff     = { 0.45,  0.20,  0.20,  1.00  },
    pillEdgeOn  = { 0.45,  0.85,  0.55,  1.00  },
    pillEdgeOff = { 0.78,  0.40,  0.40,  1.00  },
    panelInner  = { 0.058, 0.068, 0.082, 1.00  },
    divider     = { 0.18,  0.20,  0.24,  1.00  },
    btnBg       = { 0.12,  0.14,  0.17,  1.00  },
    btnBgHover  = { 0.18,  0.22,  0.27,  1.00  },
    btnSaveBg   = { 0.18,  0.45,  0.20,  1.00  },
    btnSaveBgH  = { 0.25,  0.60,  0.27,  1.00  },
    btnCancelBg = { 0.42,  0.18,  0.18,  1.00  },
    btnCancelBgH= { 0.55,  0.24,  0.24,  1.00  },
}

-- =========================================================
-- LAYOUT (computed once, depends on screen aspect)
-- =========================================================
local L = {}
local function computeLayout()
    L.dialogX = 0.18
    L.dialogY = 0.10
    L.dialogW = 0.64
    L.dialogH = 0.80

    L.headerH  = 0.058
    L.tabH     = 0.044
    L.footerH  = 0.060
    L.padX     = 0.020
    L.padY     = 0.014

    L.leftRatio = 0.56
    L.rowH      = 0.054
end
computeLayout()

-- =========================================================
-- HELPERS
-- =========================================================
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function pointIn(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

local function setColor(t)
    setTextColor(t[1], t[2], t[3], t[4])
end

local function currentItems()
    return SlowSteeringGui.TABS[SlowSteeringGui.activeTab].items
end

local function currentItem()
    return currentItems()[SlowSteeringGui.selectedIdx]
end

local function formatItem(def, val)
    if def.type == "bool" then
        return val and "AN" or "AUS"
    end
    if def.type == "enum" then
        return def.labels[val] or tostring(val)
    end
    if def.type == "preset" then
        local key = SlowSteering.activeProfile or "custom"
        return SlowSteering.PRESET_LABELS[key] or key
    end
    local display = val * (def.scale or 1)
    return string.format(def.fmt, display)
end

local function getValue(def)
    if def.type == "preset" then
        return SlowSteering.activeProfile or "custom"
    end
    return SlowSteeringGui.tempValues[def.key]
end

local function setValueRaw(def, value)
    SlowSteeringGui.tempValues[def.key] = value
end

local function applyPresetToTemp(name)
    if name == "custom" then
        SlowSteering.activeProfile = "custom"
        return
    end
    local preset = SlowSteering.PRESETS[name]
    if preset == nil then return end
    for k, v in pairs(preset) do
        SlowSteeringGui.tempValues[k] = v
    end
    SlowSteering.activeProfile = name
end

local function maybeUnlockCustomProfile(def)
    if def.key == "_preset" or def.key == "isActive" or def.key == "showHud" then return end
    if def.key:sub(1, 3) == "hud" then return end
    local profile = SlowSteering.activeProfile or "custom"
    if profile == "custom" then return end
    local preset = SlowSteering.PRESETS[profile]
    if preset == nil then return end
    local cur = SlowSteeringGui.tempValues[def.key]
    if cur == nil then return end
    local target = preset[def.key]
    if target == nil then return end
    if math.abs(cur - target) > 0.001 then
        SlowSteering.activeProfile = "custom"
    end
end

local function changeValue(def, dir)
    if def.type == "bool" then
        setValueRaw(def, not getValue(def))
        return
    end
    if def.type == "enum" then
        local values = def.values
        local cur = getValue(def)
        local idx = 1
        for i, v in ipairs(values) do
            if v == cur then idx = i; break end
        end
        idx = ((idx - 1 + dir) % #values) + 1
        setValueRaw(def, values[idx])
        return
    end
    if def.type == "preset" then
        local order = SlowSteering.PRESET_ORDER
        local cur = SlowSteering.activeProfile or "custom"
        local idx = 1
        for i, v in ipairs(order) do
            if v == cur then idx = i; break end
        end
        idx = ((idx - 1 + dir) % #order) + 1
        applyPresetToTemp(order[idx])
        SlowSteeringGui.flashColor  = { 1.00, 0.62, 0.06 }
        SlowSteeringGui.flashFrames = 12
        return
    end
    local r = SlowSteering.RANGES[def.key]
    if r == nil then return end
    local v = getValue(def) + dir * (def.step or 0.05)
    v = clamp(v, r[1], r[2])
    if def.step and def.step > 0 then
        v = math.floor(v / def.step + 0.5) * def.step
        v = clamp(v, r[1], r[2])
    end
    setValueRaw(def, v)
    maybeUnlockCustomProfile(def)
end

local function setSliderNorm(def, norm)
    local r = SlowSteering.RANGES[def.key]
    if r == nil then return end
    norm = clamp(norm, 0, 1)
    local v = r[1] + norm * (r[2] - r[1])
    if def.step and def.step > 0 then
        v = math.floor(v / def.step + 0.5) * def.step
        v = clamp(v, r[1], r[2])
    end
    setValueRaw(def, v)
    maybeUnlockCustomProfile(def)
end

local function resetSelectedToDefault()
    local def = currentItem()
    if def == nil then return end
    if def.type == "preset" then return end
    local default = SlowSteering.DEFAULTS[def.key]
    if default == nil then return end
    setValueRaw(def, default)
    maybeUnlockCustomProfile(def)
    SlowSteeringGui.flashColor  = { 1.00, 0.62, 0.06 }
    SlowSteeringGui.flashFrames = 10
end

local function resetAllToProfile()
    local profile = SlowSteering.activeProfile or "custom"
    if profile == "custom" then
        for _, tab in ipairs(SlowSteeringGui.TABS) do
            for _, def in ipairs(tab.items) do
                local d = SlowSteering.DEFAULTS[def.key]
                if d ~= nil then setValueRaw(def, d) end
            end
        end
        SlowSteering.activeProfile = SlowSteering.DEFAULTS.activeProfile or "realistic"
        local p = SlowSteering.PRESETS[SlowSteering.activeProfile]
        if p ~= nil then
            for k, v in pairs(p) do
                SlowSteeringGui.tempValues[k] = v
            end
        end
    else
        applyPresetToTemp(profile)
    end
    SlowSteeringGui.flashColor  = { 1.00, 0.62, 0.06 }
    SlowSteeringGui.flashFrames = 12
end

-- =========================================================
-- OPEN / CLOSE
-- =========================================================
function SlowSteeringGui.open()
    if SlowSteeringGui.isOpen then return end
    computeLayout()

    SlowSteeringGui.tempValues = {}
    for _, tab in ipairs(SlowSteeringGui.TABS) do
        for _, def in ipairs(tab.items) do
            if def.type ~= "preset" then
                SlowSteeringGui.tempValues[def.key] = SlowSteering[def.key]
            end
        end
    end

    SlowSteeringGui.originalProfile = SlowSteering.activeProfile or "custom"
    SlowSteeringGui.isOpen      = true
    SlowSteeringGui.activeTab   = 1
    SlowSteeringGui.selectedIdx = 1
    SlowSteeringGui.flashFrames = 0
    SlowSteeringGui.dragging    = nil

    if g_inputBinding ~= nil and g_inputBinding.setShowMouseCursor ~= nil then
        pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, true)
    end
end

function SlowSteeringGui.close(save)
    if not SlowSteeringGui.isOpen then return end

    if save then
        for key, value in pairs(SlowSteeringGui.tempValues) do
            SlowSteering[key] = value
        end
        SlowSteering.saveConfig()
        if g_currentMission ~= nil then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                "Slow Steering: Einstellungen gespeichert")
        end
    else
        if SlowSteeringGui.originalProfile ~= nil then
            SlowSteering.activeProfile = SlowSteeringGui.originalProfile
        end
    end

    SlowSteeringGui.isOpen = false
    SlowSteeringGui.dragging = nil

    if g_inputBinding ~= nil and g_inputBinding.setShowMouseCursor ~= nil then
        pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, false)
    end
end

-- =========================================================
-- INPUT (keyboard)
-- =========================================================
function SlowSteeringGui.onKeyEvent(unicode, sym, modifier, isDown)
    if not SlowSteeringGui.isOpen then return end
    if not isDown then return end

    local items = currentItems()
    local idx   = SlowSteeringGui.selectedIdx

    if sym == Input.KEY_tab or sym == Input.KEY_e or sym == Input.KEY_q then
        local n = #SlowSteeringGui.TABS
        local dir = 1
        if sym == Input.KEY_q then
            dir = -1
        elseif Input.MOD_lshift ~= nil and modifier == Input.MOD_lshift then
            dir = -1
        end
        SlowSteeringGui.activeTab   = ((SlowSteeringGui.activeTab - 1 + dir) % n) + 1
        SlowSteeringGui.selectedIdx = 1
        return
    end

    if sym == Input.KEY_up then
        SlowSteeringGui.selectedIdx = ((idx - 2) % #items) + 1
        return
    elseif sym == Input.KEY_down then
        SlowSteeringGui.selectedIdx = (idx % #items) + 1
        return
    end

    local def = items[idx]
    if def == nil then return end

    if sym == Input.KEY_left then
        changeValue(def, -1)
        return
    elseif sym == Input.KEY_right then
        changeValue(def,  1)
        return
    end

    if sym == Input.KEY_p then
        local order = SlowSteering.PRESET_ORDER
        local cur = SlowSteering.activeProfile or "custom"
        local i = 1
        for k, v in ipairs(order) do if v == cur then i = k end end
        i = (i % #order) + 1
        applyPresetToTemp(order[i])
        SlowSteeringGui.flashColor  = { 1.00, 0.62, 0.06 }
        SlowSteeringGui.flashFrames = 12
        return
    end

    if sym == Input.KEY_f1 then
        resetSelectedToDefault()
        return
    elseif sym == Input.KEY_f5 then
        resetAllToProfile()
        return
    end

    if sym == Input.KEY_return or sym == Input.KEY_KP_enter then
        SlowSteeringGui.close(true)
    elseif sym == Input.KEY_escape or sym == Input.KEY_backspace then
        SlowSteeringGui.close(false)
    end
end

-- =========================================================
-- INPUT (mouse)
-- =========================================================
function SlowSteeringGui.onMouseEvent(posX, posY, isDown, isUp, button)
    if not SlowSteeringGui.isOpen then return end

    SlowSteeringGui.mouseX = posX
    SlowSteeringGui.mouseY = posY

    -- Hover state
    SlowSteeringGui.hoverTab = 0
    for i, r in ipairs(SlowSteeringGui._tabRects) do
        if pointIn(posX, posY, r[1], r[2], r[3], r[4]) then
            SlowSteeringGui.hoverTab = i; break
        end
    end
    SlowSteeringGui.hoverRow = 0
    for i, r in ipairs(SlowSteeringGui._rowRects) do
        if pointIn(posX, posY, r[1], r[2], r[3], r[4]) then
            SlowSteeringGui.hoverRow = i; break
        end
    end
    SlowSteeringGui.hoverFooter = 0
    for i, r in ipairs(SlowSteeringGui._footerRects) do
        if pointIn(posX, posY, r[1], r[2], r[3], r[4]) then
            SlowSteeringGui.hoverFooter = i; break
        end
    end

    -- Drag updates
    if SlowSteeringGui.dragging ~= nil then
        local def = SlowSteeringGui.dragging
        local sr  = SlowSteeringGui._sliderRects[def.key]
        if sr ~= nil then
            local norm = (posX - sr[1]) / sr[3]
            setSliderNorm(def, norm)
        end
        if isUp and button == Input.MOUSE_BUTTON_LEFT then
            SlowSteeringGui.dragging = nil
        end
    end

    if not isDown then return end
    if button ~= Input.MOUSE_BUTTON_LEFT then return end

    -- Tab click
    if SlowSteeringGui.hoverTab > 0 then
        SlowSteeringGui.activeTab   = SlowSteeringGui.hoverTab
        SlowSteeringGui.selectedIdx = 1
        return
    end

    -- Footer click
    if SlowSteeringGui.hoverFooter > 0 then
        local btn = SlowSteeringGui.hoverFooter
        if btn == 1 then
            SlowSteeringGui.close(true)
        elseif btn == 2 then
            SlowSteeringGui.close(false)
        elseif btn == 3 then
            resetAllToProfile()
        end
        return
    end

    -- Row click - select
    if SlowSteeringGui.hoverRow > 0 then
        SlowSteeringGui.selectedIdx = SlowSteeringGui.hoverRow
        local def = currentItems()[SlowSteeringGui.hoverRow]

        -- Bool pill click toggles directly
        if def ~= nil and def.type == "bool" then
            local pr = SlowSteeringGui._togglePillRects[def.key]
            if pr ~= nil and pointIn(posX, posY, pr[1], pr[2], pr[3], pr[4]) then
                changeValue(def, 1)
                return
            end
        end

        -- Slider drag start
        if def ~= nil and def.type == "float" then
            local sr = SlowSteeringGui._sliderRects[def.key]
            if sr ~= nil and pointIn(posX, posY, sr[1], sr[2] - 0.005, sr[3], sr[4] + 0.010) then
                local norm = (posX - sr[1]) / sr[3]
                setSliderNorm(def, norm)
                SlowSteeringGui.dragging = def
                return
            end
        end

        -- < value > buttons
        if def ~= nil then
            local lr = SlowSteeringGui._valueLeftRects[def.key]
            local rr = SlowSteeringGui._valueRightRects[def.key]
            if lr ~= nil and pointIn(posX, posY, lr[1], lr[2], lr[3], lr[4]) then
                changeValue(def, -1); return
            end
            if rr ~= nil and pointIn(posX, posY, rr[1], rr[2], rr[3], rr[4]) then
                changeValue(def,  1); return
            end
        end
    end
end

-- =========================================================
-- UPDATE
-- =========================================================
function SlowSteeringGui.onUpdate(dt)
    if not SlowSteeringGui.isOpen then return end

    if g_currentMission ~= nil and g_currentMission.controlledVehicle ~= nil then
        local vehicle = g_currentMission.controlledVehicle
        local spec_d = vehicle.spec_drivable
        if spec_d ~= nil then
            spec_d.lastInputValues.axisSteer = 0
        end
    end

    if SlowSteeringGui.flashFrames > 0 then
        SlowSteeringGui.flashFrames = SlowSteeringGui.flashFrames - 1
    end
end

-- =========================================================
-- DRAW HELPERS
-- =========================================================
local function ensureBgOverlay()
    if SlowSteeringGui.bgOverlay == nil then
        SlowSteeringGui.bgOverlay = createImageOverlay("dataS/menu/base/graph_pixel.png")
    end
    return SlowSteeringGui.bgOverlay
end

local function drawRect(overlay, x, y, w, h, c)
    setOverlayColor(overlay, c[1], c[2], c[3], c[4])
    renderOverlay(overlay, x, y, w, h)
end

local function drawRectRGBA(overlay, x, y, w, h, r, g, b, a)
    setOverlayColor(overlay, r, g, b, a)
    renderOverlay(overlay, x, y, w, h)
end

-- 1px border outline
local function drawOutline(overlay, x, y, w, h, c, t)
    t = t or 0.0012
    drawRect(overlay, x,         y,           w, t, c)
    drawRect(overlay, x,         y + h - t,   w, t, c)
    drawRect(overlay, x,         y,           t, h, c)
    drawRect(overlay, x + w - t, y,           t, h, c)
end

-- =========================================================
-- DRAW: header
-- =========================================================
local function drawHeader(overlay)
    local x, y, w, h = L.dialogX, L.dialogY + L.dialogH - L.headerH, L.dialogW, L.headerH
    drawRect(overlay, x, y, w, h, C.headerBg)
    -- Bottom orange accent line
    drawRect(overlay, x, y, w, 0.0025, C.headerLine)

    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setColor(C.txtPrimary)
    renderText(x + L.padX, y + h * 0.50 - 0.005, 0.0235, "SLOW STEERING")

    setTextBold(false)
    setColor(C.txtSecond)
    renderText(x + L.padX + 0.175, y + h * 0.50, 0.0135,
        "Geschwindigkeitsabhaengige Lenkungs-Reduktion")

    setTextAlignment(RenderText.ALIGN_RIGHT)
    setColor(C.txtAccent)
    renderText(x + w - L.padX, y + h * 0.50 - 0.003, 0.0135, "v2.2.0.0")

    -- Active profile pill (right side, under version)
    local profile = SlowSteering.activeProfile or "custom"
    local plabel  = SlowSteering.PRESET_LABELS[profile] or profile
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setColor(C.txtSecond)
    renderText(x + w - L.padX, y + h * 0.50 - 0.022, 0.0115,
        "Profil:  " .. plabel)
end

-- =========================================================
-- DRAW: tabs
-- =========================================================
local function drawTabs(overlay)
    SlowSteeringGui._tabRects = {}
    local barY = L.dialogY + L.dialogH - L.headerH - L.tabH
    local barX = L.dialogX
    local barW = L.dialogW
    local barH = L.tabH

    drawRect(overlay, barX, barY, barW, barH, C.tabBg)

    local n = #SlowSteeringGui.TABS
    local tabW = barW / n
    for i, tab in ipairs(SlowSteeringGui.TABS) do
        local tx = barX + (i - 1) * tabW
        local active = (i == SlowSteeringGui.activeTab)
        local hover  = (i == SlowSteeringGui.hoverTab)

        if active then
            drawRect(overlay, tx, barY, tabW, barH, C.tabActiveBg)
            drawRect(overlay, tx, barY, tabW, 0.0028, C.tabUnderline) -- underline at bottom
        elseif hover then
            drawRect(overlay, tx, barY, tabW, barH, C.tabHover)
        end

        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(active)
        if active then
            setColor(C.txtPrimary)
        elseif hover then
            setColor(C.txtPrimary)
        else
            setColor(C.txtSecond)
        end
        renderText(tx + tabW * 0.5, barY + barH * 0.34, 0.0165, tab.label)

        SlowSteeringGui._tabRects[i] = { tx, barY, tabW, barH }
    end
    setTextBold(false)
end

-- =========================================================
-- DRAW: settings list
-- =========================================================
local function drawList(overlay)
    SlowSteeringGui._rowRects        = {}
    SlowSteeringGui._sliderRects     = {}
    SlowSteeringGui._valueLeftRects  = {}
    SlowSteeringGui._valueRightRects = {}
    SlowSteeringGui._togglePillRects = {}

    local items = currentItems()
    local idx   = SlowSteeringGui.selectedIdx

    local listX     = L.dialogX
    local listW     = L.dialogW * L.leftRatio
    local listTop   = L.dialogY + L.dialogH - L.headerH - L.tabH
    local listBot   = L.dialogY + L.footerH
    local listH     = listTop - listBot

    drawRect(overlay, listX, listBot, listW, listH, C.panelInner)

    local rowH = L.rowH
    local startY = listTop - L.padY - rowH
    local labelX = listX + L.padX
    local rowRight = listX + listW - L.padX

    for i, def in ipairs(items) do
        local y = startY - (i - 1) * rowH
        local isSelected = (i == idx)
        local isHover    = (i == SlowSteeringGui.hoverRow)

        local rowRectX = listX + 0.005
        local rowRectY = y - 0.004
        local rowRectW = listW - 0.010
        local rowRectH = rowH - 0.006

        if isSelected then
            drawRect(overlay, rowRectX, rowRectY, rowRectW, rowRectH, C.rowSelected)
            drawRect(overlay, rowRectX, rowRectY, 0.004, rowRectH, C.rowAccent)
        elseif isHover then
            drawRect(overlay, rowRectX, rowRectY, rowRectW, rowRectH, C.rowHover)
        else
            drawRect(overlay, rowRectX, rowRectY, rowRectW, rowRectH, C.rowBg)
        end

        SlowSteeringGui._rowRects[i] = { rowRectX, rowRectY, rowRectW, rowRectH }

        -- Label
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextBold(isSelected)
        if isSelected then setColor(C.txtPrimary)
        elseif isHover    then setColor(C.txtPrimary)
        else                   setColor(C.txtSecond) end
        renderText(labelX + 0.006, y + 0.029, 0.0155, def.label)
        setTextBold(false)

        local val = getValue(def)
        local valStr = formatItem(def, val)

        -- Slider track for floats
        local r = SlowSteering.RANGES[def.key]
        local sliderEndX
        if def.type == "float" and r ~= nil then
            local sliderX = labelX + 0.006
            local sliderY = y + 0.012
            local sliderW = (rowRight - sliderX) - 0.105
            local sliderH = 0.005
            if sliderW > 0.06 then
                local norm = (val - r[1]) / (r[2] - r[1])
                norm = clamp(norm, 0, 1)

                drawRect(overlay, sliderX, sliderY, sliderW, sliderH, C.sliderTrack)
                local fillCol = isSelected and C.sliderFill or C.sliderFillD
                drawRect(overlay, sliderX, sliderY, sliderW * norm, sliderH, fillCol)

                -- Knob
                local knobW = 0.006
                local knobH = sliderH + 0.008
                drawRect(overlay,
                    sliderX + sliderW * norm - knobW * 0.5,
                    sliderY - 0.0015,
                    knobW, knobH, C.sliderKnob)

                SlowSteeringGui._sliderRects[def.key] = { sliderX, sliderY, sliderW, sliderH }
                sliderEndX = sliderX + sliderW
            end
        end

        local isChanged = false
        if def.type ~= "preset" then
            local current = SlowSteering[def.key]
            if current ~= nil and val ~= current then isChanged = true end
        end

        if def.type == "bool" then
            local pillW = 0.052
            local pillH = 0.024
            local pillX = rowRight - pillW
            local pillY = y + 0.011
            local on = val
            if on then
                drawRect(overlay, pillX, pillY, pillW, pillH, C.pillOn)
                drawRect(overlay, pillX, pillY + pillH - 0.0022, pillW, 0.0022, C.pillEdgeOn)
            else
                drawRect(overlay, pillX, pillY, pillW, pillH, C.pillOff)
                drawRect(overlay, pillX, pillY + pillH - 0.0022, pillW, 0.0022, C.pillEdgeOff)
            end
            setTextAlignment(RenderText.ALIGN_CENTER)
            setTextBold(true)
            setColor(C.txtPrimary)
            renderText(pillX + pillW * 0.5, pillY + pillH * 0.30, 0.0135, on and "AN" or "AUS")
            setTextBold(false)
            SlowSteeringGui._togglePillRects[def.key] = { pillX, pillY, pillW, pillH }
        else
            -- < value >
            setTextAlignment(RenderText.ALIGN_RIGHT)
            if isChanged then setColor(C.txtChanged)
            elseif isSelected then setColor(C.txtAccent)
            else setColor(C.txtOk) end

            local valY = y + 0.029
            renderText(rowRight, valY, 0.0155, valStr)

            -- Hit-test rectangles for chevrons (only useful when row selected)
            local arrowGap = 0.012
            -- estimate value width by font (rough)
            local valW = (#valStr) * 0.0085
            if valW < 0.04 then valW = 0.04 end
            local rightArrowX = rowRight - valW - arrowGap
            local leftArrowX  = rowRight - valW - arrowGap - 0.030

            if isSelected then
                setColor(C.txtAccent)
                renderText(rightArrowX + 0.020, valY, 0.018, ">")
                setTextAlignment(RenderText.ALIGN_LEFT)
                renderText(leftArrowX, valY, 0.018, "<")

                -- Hitboxes only when selected (so non-selected rows don't steal slider clicks)
                local hitW = 0.018
                local hitH = 0.026
                local hitY = y + 0.014
                SlowSteeringGui._valueLeftRects[def.key]  = { leftArrowX - 0.002,           hitY, hitW, hitH }
                SlowSteeringGui._valueRightRects[def.key] = { rightArrowX + 0.020 - hitW * 0.5, hitY, hitW, hitH }
            else
                SlowSteeringGui._valueLeftRects[def.key]  = nil
                SlowSteeringGui._valueRightRects[def.key] = nil
            end
        end
    end

    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

-- =========================================================
-- DRAW: right column (curve + help)
-- =========================================================
local function evalCurve(t, reduction, exponent)
    local curved = t ^ exponent
    return clamp(1 - reduction * curved, 0.05, 1.0)
end

local function drawCurvePreview(overlay, gx, gy, gw, gh)
    drawRect(overlay, gx, gy, gw, gh, C.panelInner)
    drawOutline(overlay, gx, gy, gw, gh, C.divider)

    -- Grid
    for i = 1, 3 do
        local fy = gy + (gh / 4) * i
        drawRectRGBA(overlay, gx + 0.003, fy, gw - 0.006, 0.0007, 0.18, 0.20, 0.24, 0.7)
        local fx = gx + (gw / 4) * i
        drawRectRGBA(overlay, fx, gy + 0.003, 0.0007, gh - 0.006, 0.18, 0.20, 0.24, 0.7)
    end

    local tv  = SlowSteeringGui.tempValues
    local red = tv.steeringReductionAtRef or SlowSteering.steeringReductionAtRef
    local exp = tv.curveExponent          or SlowSteering.curveExponent

    local steps = 70
    local pad = 0.005
    local plotX = gx + pad
    local plotY = gy + pad
    local plotW = gw - pad * 2
    local plotH = gh - pad * 2

    -- Filled area below curve = reduction zone
    for i = 0, steps do
        local t  = i / steps
        local rv = evalCurve(t, red, exp)
        local h  = (1 - rv) * plotH
        if h > 0.001 then
            drawRectRGBA(overlay, plotX + t * plotW, plotY + plotH - h,
                plotW / steps + 0.0008, h, 1.00, 0.62, 0.06, 0.22)
        end
    end

    -- Curve points
    for i = 0, steps do
        local t  = i / steps
        local rv = evalCurve(t, red, exp)
        local px = plotX + t * plotW
        local py = plotY + rv * plotH
        local nr, ng, nb
        if rv > 0.7 then
            nr, ng, nb = 0.45, 0.90, 0.50
        elseif rv > 0.4 then
            nr, ng, nb = 1.00, 0.78, 0.20
        else
            nr, ng, nb = 1.00, 0.40, 0.30
        end
        drawRectRGBA(overlay, px - 0.0015, py - 0.0015, 0.0030, 0.0030, nr, ng, nb, 1.0)
    end

    -- Live cursor
    local cv = g_currentMission and g_currentMission.controlledVehicle
    if cv ~= nil then
        local sp = math.abs(cv:getLastSpeed() or 0)
        local refSpeed = tv.refSpeed or SlowSteering.refSpeed
        local t = clamp(sp / refSpeed, 0, 1)
        local rv = evalCurve(t, red, exp)
        local cx = plotX + t * plotW
        local cy = plotY + rv * plotH
        for k = 0, 12 do
            if (k % 2) == 0 then
                drawRectRGBA(overlay, cx - 0.0008, plotY + (k / 12) * plotH,
                    0.0016, plotH / 26, 1.00, 0.74, 0.20, 0.85)
            end
        end
        drawRectRGBA(overlay, cx - 0.0050, cy - 0.0050, 0.010, 0.010, 1.00, 0.85, 0.20, 1.0)
        drawRectRGBA(overlay, cx - 0.0028, cy - 0.0028, 0.0056, 0.0056, 0.10, 0.10, 0.10, 1.0)
    end

    -- Axis labels
    setTextBold(false)
    setColor(C.txtMuted)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(gx + 0.005, gy - 0.018, 0.0110,
        string.format("0  ->  %.0f km/h", SlowSteeringGui.tempValues.refSpeed or SlowSteering.refSpeed))
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setColor(C.txtOk)
    renderText(gx + gw, gy + gh + 0.004, 0.0110, "100% Lenkung")
    setColor({ 1.00, 0.55, 0.40, 1.0 })
    renderText(gx + gw, gy - 0.018, 0.0110,
        string.format("%.0f%% am Ref",
            (1 - (SlowSteeringGui.tempValues.steeringReductionAtRef or SlowSteering.steeringReductionAtRef)) * 100))
end

local function drawRightPanel(overlay)
    local rx = L.dialogX + L.dialogW * L.leftRatio
    local rw = L.dialogW * (1 - L.leftRatio)
    local rTop = L.dialogY + L.dialogH - L.headerH - L.tabH
    local rBot = L.dialogY + L.footerH

    drawRect(overlay, rx, rBot, rw, rTop - rBot, C.panelInner)
    drawRect(overlay, rx, rBot, 0.0015, rTop - rBot, C.divider)

    local pad = L.padX

    -- Section: Curve preview
    local hdrY = rTop - L.padY - 0.018
    setTextBold(true)
    setColor(C.txtAccent)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(rx + pad, hdrY, 0.0125, "LENKUNGS-KURVE")
    setTextBold(false)

    local gx = rx + pad
    local gy = hdrY - 0.190
    local gw = rw - pad * 2
    local gh = 0.170
    drawCurvePreview(overlay, gx, gy, gw, gh)

    -- Section: help text — anchored to bottom of right panel
    -- Card with a clear top divider so it can't be confused with the list rows
    local helpCardTop = rBot + 0.150
    local helpCardBot = rBot + 0.012
    drawRect(overlay, rx + 0.001, helpCardBot, rw - 0.002, helpCardTop - helpCardBot, C.panelBg)
    drawRect(overlay, rx + pad, helpCardTop - 0.0014, rw - pad * 2, 0.0014, C.headerLine)

    setColor(C.txtAccent)
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(rx + pad, helpCardTop - 0.020, 0.0125, "ERLAEUTERUNG")
    setTextBold(false)

    local def = currentItem()
    if def ~= nil then
        setColor(C.txtPrimary)
        setTextBold(true)
        renderText(rx + pad, helpCardTop - 0.040, 0.0140, def.label)
        setTextBold(false)
        setColor(C.txtSecond)

        local helpText = def.help or ""
        local maxLine = 42
        local cursor = 1
        local lineY = helpCardTop - 0.058
        while cursor <= #helpText do
            local stop = math.min(cursor + maxLine - 1, #helpText)
            if stop < #helpText then
                local space = helpText:sub(cursor, stop):match(".*() ")
                if space and space > 10 then
                    stop = cursor + space - 2
                end
            end
            local line = helpText:sub(cursor, stop)
            renderText(rx + pad, lineY, 0.0115, line)
            lineY = lineY - 0.015
            cursor = stop + 2
            if lineY < helpCardBot + 0.008 then break end
        end
    end
end

-- =========================================================
-- DRAW: footer with action buttons
-- =========================================================
local function drawFooterButton(overlay, idx, x, y, w, h, label, baseCol, hoverCol)
    local hover = (idx == SlowSteeringGui.hoverFooter)
    drawRect(overlay, x, y, w, h, hover and hoverCol or baseCol)
    drawOutline(overlay, x, y, w, h, C.divider)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setColor(C.txtPrimary)
    renderText(x + w * 0.5, y + h * 0.30, 0.0135, label)
    setTextBold(false)
    SlowSteeringGui._footerRects[idx] = { x, y, w, h }
end

local function drawFooter(overlay)
    SlowSteeringGui._footerRects = {}
    local fx = L.dialogX
    local fy = L.dialogY
    local fw = L.dialogW
    local fh = L.footerH

    drawRect(overlay, fx, fy, fw, fh, C.headerBg)
    drawRect(overlay, fx, fy + fh, fw, 0.0018, C.divider)

    -- Hint text on left
    setTextAlignment(RenderText.ALIGN_LEFT)
    setColor(C.txtMuted)
    setTextBold(false)
    renderText(fx + L.padX, fy + fh * 0.62, 0.0115,
        "[Tab] Kategorie   [Pfeile] Wert   [P] Profil   [F1] Reset Wert   [F5] Alle")

    -- Buttons on right
    local btnH = fh - 0.018
    local btnY = fy + 0.009
    local btnW = 0.110
    local gap  = 0.008

    local saveX   = fx + fw - L.padX - btnW
    local cancelX = saveX - gap - btnW
    local resetX  = cancelX - gap - btnW

    drawFooterButton(overlay, 3, resetX,  btnY, btnW, btnH, "Zuruecksetzen", C.btnBg,     C.btnBgHover)
    drawFooterButton(overlay, 2, cancelX, btnY, btnW, btnH, "Abbrechen",     C.btnCancelBg, C.btnCancelBgH)
    drawFooterButton(overlay, 1, saveX,   btnY, btnW, btnH, "Speichern",     C.btnSaveBg,   C.btnSaveBgH)
end

-- =========================================================
-- DRAW: master
-- =========================================================
function SlowSteeringGui.onDraw()
    if not SlowSteeringGui.isOpen then return end

    local overlay = ensureBgOverlay()
    if overlay == nil or overlay == 0 then
        setColor(C.txtPrimary)
        setTextAlignment(RenderText.ALIGN_CENTER)
        renderText(0.5, 0.5, 0.02, "Slow Steering: Overlay nicht verfuegbar")
        return
    end

    -- Full-screen dim
    drawRect(overlay, 0, 0, 1, 1, C.dim)

    -- Dialog body + outline
    drawRect(overlay, L.dialogX, L.dialogY, L.dialogW, L.dialogH, C.panelBg)
    drawOutline(overlay, L.dialogX, L.dialogY, L.dialogW, L.dialogH, C.panelEdge, 0.0014)

    drawHeader(overlay)
    drawTabs(overlay)
    drawList(overlay)
    drawRightPanel(overlay)
    drawFooter(overlay)

    -- Flash tint
    if SlowSteeringGui.flashFrames > 0 and SlowSteeringGui.flashColor ~= nil then
        local a = SlowSteeringGui.flashFrames / 12 * 0.18
        local c = SlowSteeringGui.flashColor
        drawRectRGBA(overlay, L.dialogX, L.dialogY, L.dialogW, L.dialogH, c[1], c[2], c[3], a)
    end

    setColor(C.txtPrimary)
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

-- =========================================================
-- CLEANUP
-- =========================================================
function SlowSteeringGui.destroy()
    if SlowSteeringGui.bgOverlay ~= nil and SlowSteeringGui.bgOverlay ~= 0 then
        delete(SlowSteeringGui.bgOverlay)
        SlowSteeringGui.bgOverlay = nil
    end
end
