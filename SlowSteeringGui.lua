-- SlowSteeringGui.lua  v2.1.0.0
-- In-game settings overlay for SlowSteering.
-- Tabbed UI with live curve preview, preset cycle, and per-setting help.
--
-- Controls:
--   Up/Down       navigate settings in current tab
--   Left/Right    change selected value
--   Tab / Q / E   cycle tab    (Shift+Tab = previous)
--   P             cycle preset
--   F1            reset selected setting to default
--   F5            reset ALL settings to active preset (or defaults)
--   Enter         save & close
--   Esc / Bksp    cancel & close

SlowSteeringGui = {}
SlowSteeringGui.isOpen          = false
SlowSteeringGui.activeTab       = 1
SlowSteeringGui.selectedIdx     = 1
SlowSteeringGui.tempValues      = {}
SlowSteeringGui.originalProfile = nil  -- snapshot for cancel
SlowSteeringGui.bgOverlay       = nil
SlowSteeringGui.flashFrames     = 0    -- brief tint after F5/preset
SlowSteeringGui.flashColor      = nil

-- =========================================================
-- TAB & SETTING DEFINITIONS
-- =========================================================
SlowSteeringGui.TABS = {
    {
        id    = "general",
        label = "Allgemein",
        items = {
            { key = "isActive",    label = "Mod aktiv",            type = "bool",
              help = "Schaltet die Lenkungs-Reduktion komplett ein oder aus." },
            { key = "showHud",     label = "HUD anzeigen",         type = "bool",
              help = "Zeigt die kleine Anzeige im Spiel mit aktueller Reduktion." },
            { key = "_preset",     label = "Profil",               type = "preset",
              help = "Auswahl Voreinstellung. Aenderungen schalten auf 'Eigen'." },
            { key = "refSpeed",    label = "Referenzgeschw.",      type = "float", step = 5,
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
            { key = "returnMultiplier",       label = "Rueckst.-Multipl.",      type = "float",
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
-- HELPERS
-- =========================================================
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
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

-- Apply a preset to the temp buffer (so Cancel still works)
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

-- After any value change in 'steering' or 'realism' tab,
-- if the value diverges from the active preset, switch profile to 'custom'.
local function maybeUnlockCustomProfile(def)
    if def.key == "_preset" or def.key == "isActive" or def.key == "showHud" then
        return
    end
    if def.key:sub(1, 3) == "hud" then return end
    -- only check curve/realism keys
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
        SlowSteeringGui.flashColor  = { 0.20, 0.55, 0.85 }
        SlowSteeringGui.flashFrames = 12
        return
    end
    -- float
    local r = SlowSteering.RANGES[def.key]
    if r == nil then return end
    local v = getValue(def) + dir * (def.step or 0.05)
    v = clamp(v, r[1], r[2])
    -- Round to step grid to avoid float drift
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
    SlowSteeringGui.flashColor  = { 0.85, 0.55, 0.15 }
    SlowSteeringGui.flashFrames = 10
end

local function resetAllToProfile()
    local profile = SlowSteering.activeProfile or "custom"
    if profile == "custom" then
        -- Reset to defaults
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
    SlowSteeringGui.flashColor  = { 0.85, 0.55, 0.15 }
    SlowSteeringGui.flashFrames = 12
end

-- =========================================================
-- OPEN / CLOSE
-- =========================================================
function SlowSteeringGui.open()
    if SlowSteeringGui.isOpen then return end

    -- Snapshot current values into temp buffer
    SlowSteeringGui.tempValues = {}
    for _, tab in ipairs(SlowSteeringGui.TABS) do
        for _, def in ipairs(tab.items) do
            if def.type ~= "preset" then
                SlowSteeringGui.tempValues[def.key] = SlowSteering[def.key]
            end
        end
    end

    -- Snapshot profile (lives outside tempValues - changed live by changeValue)
    SlowSteeringGui.originalProfile = SlowSteering.activeProfile or "custom"

    SlowSteeringGui.isOpen      = true
    SlowSteeringGui.activeTab   = 1
    SlowSteeringGui.selectedIdx = 1
    SlowSteeringGui.flashFrames = 0
end

function SlowSteeringGui.close(save)
    if not SlowSteeringGui.isOpen then return end

    if save then
        for key, value in pairs(SlowSteeringGui.tempValues) do
            SlowSteering[key] = value
        end
        -- profile state was already updated live - keep it
        SlowSteering.saveConfig()

        if g_currentMission ~= nil then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                "Slow Steering: Einstellungen gespeichert")
        end
    else
        -- Cancel: restore the profile string we snapshotted
        if SlowSteeringGui.originalProfile ~= nil then
            SlowSteering.activeProfile = SlowSteeringGui.originalProfile
        end
    end

    SlowSteeringGui.isOpen = false
end

-- =========================================================
-- INPUT
-- =========================================================
function SlowSteeringGui.onKeyEvent(unicode, sym, modifier, isDown)
    if not SlowSteeringGui.isOpen then return end
    if not isDown then return end

    local items = currentItems()
    local idx   = SlowSteeringGui.selectedIdx

    -- Tab cycling: Tab/E forward, Shift+Tab/Q backward
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

    -- Vertical nav
    if sym == Input.KEY_up then
        SlowSteeringGui.selectedIdx = ((idx - 2) % #items) + 1
        return
    elseif sym == Input.KEY_down then
        SlowSteeringGui.selectedIdx = (idx % #items) + 1
        return
    end

    -- Value change
    local def = items[idx]
    if def == nil then return end

    if sym == Input.KEY_left then
        changeValue(def, -1)
        return
    elseif sym == Input.KEY_right then
        changeValue(def,  1)
        return
    end

    -- Quick preset cycle
    if sym == Input.KEY_p then
        local order = SlowSteering.PRESET_ORDER
        local cur = SlowSteering.activeProfile or "custom"
        local i = 1
        for k, v in ipairs(order) do if v == cur then i = k end end
        i = (i % #order) + 1
        applyPresetToTemp(order[i])
        SlowSteeringGui.flashColor  = { 0.20, 0.55, 0.85 }
        SlowSteeringGui.flashFrames = 12
        return
    end

    -- Resets
    if sym == Input.KEY_f1 then
        resetSelectedToDefault()
        return
    elseif sym == Input.KEY_f5 then
        resetAllToProfile()
        return
    end

    -- Confirm / cancel
    if sym == Input.KEY_return or sym == Input.KEY_KP_enter then
        SlowSteeringGui.close(true)
    elseif sym == Input.KEY_escape or sym == Input.KEY_backspace then
        SlowSteeringGui.close(false)
    end
end

-- =========================================================
-- UPDATE
-- =========================================================
function SlowSteeringGui.onUpdate(dt)
    if not SlowSteeringGui.isOpen then return end

    -- Freeze vehicle steering input while GUI is open
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
-- DRAW
-- =========================================================
local function ensureBgOverlay()
    if SlowSteeringGui.bgOverlay == nil then
        SlowSteeringGui.bgOverlay = createImageOverlay("dataS/menu/base/graph_pixel.png")
    end
    return SlowSteeringGui.bgOverlay
end

local function drawRect(overlay, x, y, w, h, r, g, b, a)
    setOverlayColor(overlay, r, g, b, a)
    renderOverlay(overlay, x, y, w, h)
end

-- Layout constants (screen 0..1)
local L = {}
L.dialogX = 0.18
L.dialogY = 0.10
L.dialogW = 0.64
L.dialogH = 0.80

L.titleH    = 0.045
L.tabH      = 0.040
L.footerH   = 0.038
L.padding   = 0.018

-- Two-column body
L.leftRatio = 0.55  -- left column width fraction

-- =========================================================
-- DRAW: title bar
-- =========================================================
local function drawTitleBar(overlay)
    local x, y, w, h = L.dialogX, L.dialogY + L.dialogH - L.titleH, L.dialogW, L.titleH

    -- Gradient-ish title using two layers
    drawRect(overlay, x, y, w, h,         0.10, 0.18, 0.30, 1.0)
    drawRect(overlay, x, y + h * 0.5, w, h * 0.5, 0.13, 0.25, 0.42, 1.0)
    -- accent line
    drawRect(overlay, x, y, w, 0.002, 0.30, 0.65, 0.95, 1.0)

    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1.0, 1.0, 1.0, 1.0)
    renderText(x + L.padding, y + h * 0.30, 0.022, "SLOW STEERING")

    setTextBold(false)
    setTextColor(0.65, 0.78, 0.92, 0.9)
    renderText(x + L.padding + 0.16, y + h * 0.34, 0.014, "Geschwindigkeitsabhaengige Lenkungs-Reduktion")

    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(0.55, 0.65, 0.78, 0.9)
    renderText(x + w - L.padding, y + h * 0.34, 0.013, "v2.1.0.0")
end

-- =========================================================
-- DRAW: tab bar
-- =========================================================
local function drawTabBar(overlay)
    local barY = L.dialogY + L.dialogH - L.titleH - L.tabH
    local barX = L.dialogX
    local barW = L.dialogW
    local barH = L.tabH

    drawRect(overlay, barX, barY, barW, barH, 0.07, 0.09, 0.12, 1.0)
    -- bottom accent under bar
    drawRect(overlay, barX, barY, barW, 0.0015, 0.30, 0.65, 0.95, 0.6)

    local n = #SlowSteeringGui.TABS
    local tabW = barW / n
    for i, tab in ipairs(SlowSteeringGui.TABS) do
        local tx = barX + (i - 1) * tabW
        local active = (i == SlowSteeringGui.activeTab)
        if active then
            drawRect(overlay, tx, barY, tabW, barH, 0.18, 0.32, 0.50, 1.0)
            -- top highlight strip
            drawRect(overlay, tx, barY + barH - 0.003, tabW, 0.003, 0.40, 0.78, 1.00, 1.0)
        else
            drawRect(overlay, tx + 0.001, barY, tabW - 0.002, barH, 0.10, 0.13, 0.17, 1.0)
        end

        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(active)
        if active then
            setTextColor(1.0, 1.0, 1.0, 1.0)
        else
            setTextColor(0.65, 0.70, 0.75, 0.9)
        end
        renderText(tx + tabW * 0.5, barY + barH * 0.32, 0.016, tab.label)
    end
    setTextBold(false)
end

-- =========================================================
-- DRAW: settings list (left column)
-- =========================================================
local function drawSettingsList(overlay)
    local items   = currentItems()
    local idx     = SlowSteeringGui.selectedIdx

    local listX = L.dialogX
    local listW = L.dialogW * L.leftRatio
    local listTop = L.dialogY + L.dialogH - L.titleH - L.tabH
    local listBottom = L.dialogY + L.footerH

    -- Background
    drawRect(overlay, listX, listBottom, listW, listTop - listBottom, 0.10, 0.12, 0.15, 1.0)

    local rowH = 0.052
    local startY = listTop - L.padding - rowH
    local labelX = listX + L.padding
    local valueX = listX + listW - L.padding

    for i, def in ipairs(items) do
        local y = startY - (i - 1) * rowH
        local isSelected = (i == idx)

        if isSelected then
            -- Selected row - filled accent
            drawRect(overlay, listX + 0.006, y - 0.004, listW - 0.012, rowH - 0.004,
                0.18, 0.32, 0.50, 0.55)
            -- Left bar
            drawRect(overlay, listX + 0.006, y - 0.004, 0.0035, rowH - 0.004,
                0.40, 0.78, 1.00, 1.0)
        end

        -- Label
        setTextAlignment(RenderText.ALIGN_LEFT)
        if isSelected then
            setTextColor(1.0, 1.0, 1.0, 1.0)
            setTextBold(true)
        else
            setTextColor(0.78, 0.80, 0.83, 0.95)
            setTextBold(false)
        end
        renderText(labelX, y + 0.010, 0.0165, def.label)
        setTextBold(false)

        -- Value formatting + colour
        local val = getValue(def)
        local valStr = formatItem(def, val)

        -- Slider track for floats / enums (between label and value text)
        local sliderShown = false
        local r = SlowSteering.RANGES[def.key]
        if def.type == "float" and r ~= nil and overlay ~= nil and overlay ~= 0 then
            local sliderX = labelX + 0.135
            local sliderY = y + 0.014
            local sliderW = listW - L.padding * 2 - 0.135 - 0.075
            local sliderH = 0.005
            if sliderW > 0.04 then
                local norm = (val - r[1]) / (r[2] - r[1])
                norm = clamp(norm, 0, 1)
                drawRect(overlay, sliderX, sliderY, sliderW, sliderH,
                    0.18, 0.20, 0.24, 0.9)
                local fillR, fillG, fillB
                if isSelected then
                    fillR, fillG, fillB = 0.40, 0.78, 1.00
                else
                    fillR, fillG, fillB = 0.30, 0.55, 0.80
                end
                drawRect(overlay, sliderX, sliderY, sliderW * norm, sliderH,
                    fillR, fillG, fillB, 0.95)
                -- Knob
                local knobW = 0.005
                drawRect(overlay, sliderX + sliderW * norm - knobW * 0.5, sliderY - 0.003,
                    knobW, sliderH + 0.006, 1.0, 1.0, 1.0, 1.0)
                sliderShown = true
            end
        end

        -- Coloured value text
        local isChanged = false
        if def.type ~= "preset" then
            local current = SlowSteering[def.key]
            if current ~= nil and val ~= current then isChanged = true end
        end

        if def.type == "bool" then
            -- Pill style for bool
            if overlay ~= nil and overlay ~= 0 then
                local pillW = 0.045
                local pillH = 0.022
                local pillX = valueX - pillW
                local pillY = y + 0.005
                local on = val
                if on then
                    drawRect(overlay, pillX, pillY, pillW, pillH, 0.20, 0.55, 0.30, 1.0)
                    drawRect(overlay, pillX, pillY + pillH - 0.002, pillW, 0.002,
                        0.45, 0.85, 0.55, 1.0)
                else
                    drawRect(overlay, pillX, pillY, pillW, pillH, 0.45, 0.20, 0.20, 1.0)
                    drawRect(overlay, pillX, pillY + pillH - 0.002, pillW, 0.002,
                        0.78, 0.40, 0.40, 1.0)
                end
                setTextAlignment(RenderText.ALIGN_CENTER)
                setTextColor(1, 1, 1, 1.0)
                setTextBold(true)
                renderText(pillX + pillW * 0.5, pillY + pillH * 0.30, 0.013, on and "AN" or "AUS")
                setTextBold(false)
            end
        else
            if isChanged then
                setTextColor(1.0, 0.85, 0.20, 1.0)
            elseif isSelected then
                setTextColor(0.55, 0.88, 1.0, 1.0)
            else
                setTextColor(0.65, 0.85, 0.65, 0.95)
            end
            setTextAlignment(RenderText.ALIGN_RIGHT)
            if isSelected then
                renderText(valueX, y + 0.010, 0.016, "<  " .. valStr .. "  >")
            else
                renderText(valueX, y + 0.010, 0.016, valStr)
            end
        end
    end

    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

-- =========================================================
-- DRAW: right column (curve preview + help text + preset)
-- =========================================================
local function evalCurve(t, reduction, exponent)
    -- Returns reduction value at speed-fraction t (0..1)
    local curved = t ^ exponent
    return clamp(1 - reduction * curved, 0.05, 1.0)
end

local function drawCurvePreview(overlay, gx, gy, gw, gh)
    -- Frame
    drawRect(overlay, gx, gy, gw, gh, 0.08, 0.10, 0.13, 1.0)
    drawRect(overlay, gx, gy, gw, 0.0015, 0.30, 0.45, 0.65, 0.6)
    drawRect(overlay, gx, gy + gh - 0.0015, gw, 0.0015, 0.30, 0.45, 0.65, 0.6)
    drawRect(overlay, gx, gy, 0.0015, gh, 0.30, 0.45, 0.65, 0.6)
    drawRect(overlay, gx + gw - 0.0015, gy, 0.0015, gh, 0.30, 0.45, 0.65, 0.6)

    -- Grid lines (4 horizontal, 4 vertical)
    for i = 1, 3 do
        local fy = gy + (gh / 4) * i
        drawRect(overlay, gx + 0.002, fy, gw - 0.004, 0.0008, 0.18, 0.22, 0.28, 0.7)
    end
    for i = 1, 3 do
        local fx = gx + (gw / 4) * i
        drawRect(overlay, fx, gy + 0.002, 0.0008, gh - 0.004, 0.18, 0.22, 0.28, 0.7)
    end

    -- Plot reduction curve (1.0 = no reduction; lower = reduced)
    local tv  = SlowSteeringGui.tempValues
    local red = tv.steeringReductionAtRef or SlowSteering.steeringReductionAtRef
    local exp = tv.curveExponent          or SlowSteering.curveExponent

    local steps = 60
    local pad = 0.004
    local plotX = gx + pad
    local plotY = gy + pad
    local plotW = gw - pad * 2
    local plotH = gh - pad * 2

    -- Filled area under the curve = reduction strength
    for i = 0, steps do
        local t  = i / steps
        local rv = evalCurve(t, red, exp)
        local h  = (1 - rv) * plotH  -- height of "reduced" zone from top
        if h > 0.001 then
            drawRect(overlay, plotX + t * plotW, plotY + plotH - h,
                plotW / steps + 0.0008, h, 0.30, 0.55, 0.85, 0.30)
        end
    end

    -- Curve line (small overlay segments) - rv=1.0 -> top, rv=0.0 -> bottom
    for i = 0, steps do
        local t  = i / steps
        local rv = evalCurve(t, red, exp)
        local px = plotX + t * plotW
        local py = plotY + rv * plotH

        -- Colour by reduction level: green->yellow->red
        local nr, ng, nb
        if rv > 0.7 then
            nr, ng, nb = 0.40, 0.95, 0.45
        elseif rv > 0.4 then
            nr, ng, nb = 0.95, 0.80, 0.30
        else
            nr, ng, nb = 0.95, 0.40, 0.30
        end
        drawRect(overlay, px - 0.0015, py - 0.0015, 0.003, 0.003, nr, ng, nb, 1.0)
    end

    -- Live cursor at current vehicle speed (if controlled vehicle exists)
    local cv = g_currentMission and g_currentMission.controlledVehicle
    if cv ~= nil then
        local sp = math.abs(cv:getLastSpeed() or 0)
        local refSpeed = tv.refSpeed or SlowSteering.refSpeed
        local t = clamp(sp / (refSpeed * 1.0), 0, 1)
        local rv = evalCurve(t, red, exp)
        local cx = plotX + t * plotW
        local cy = plotY + rv * plotH
        -- Dashed vertical line
        for k = 0, 10 do
            local kk = plotY + (k / 10) * plotH
            if (k % 2) == 0 then
                drawRect(overlay, cx - 0.0008, kk, 0.0016, plotH / 22, 1.0, 0.78, 0.20, 0.85)
            end
        end
        -- Cursor dot
        drawRect(overlay, cx - 0.004, cy - 0.004, 0.008, 0.008, 1.0, 0.85, 0.20, 1.0)
        drawRect(overlay, cx - 0.0025, cy - 0.0025, 0.005, 0.005, 0.10, 0.10, 0.10, 1.0)
    end

    -- Axis labels
    setTextColor(0.55, 0.65, 0.75, 0.9)
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(gx + 0.004, gy - 0.018, 0.011,
        string.format("0  ->  %.0f km/h (Ref)", tv.refSpeed or SlowSteering.refSpeed))

    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(0.55, 0.95, 0.55, 0.9)
    renderText(gx + gw, gy + gh + 0.004, 0.011, "100% Lenkung")
    setTextColor(0.95, 0.55, 0.40, 0.9)
    renderText(gx + gw, gy - 0.018, 0.011,
        string.format("%.0f%% am Ref",
            (1 - (tv.steeringReductionAtRef or SlowSteering.steeringReductionAtRef)) * 100))
end

local function drawRightColumn(overlay)
    local rx = L.dialogX + L.dialogW * L.leftRatio
    local rw = L.dialogW * (1 - L.leftRatio)
    local rTop = L.dialogY + L.dialogH - L.titleH - L.tabH
    local rBot = L.dialogY + L.footerH

    -- Panel background
    drawRect(overlay, rx, rBot, rw, rTop - rBot, 0.07, 0.09, 0.12, 1.0)
    -- Vertical divider
    drawRect(overlay, rx, rBot, 0.0015, rTop - rBot, 0.20, 0.28, 0.36, 1.0)

    local pad = L.padding

    -- Section: profile row (cycle indicator)
    local profY = rTop - pad - 0.025
    setTextBold(true)
    setTextColor(0.78, 0.85, 0.92, 1.0)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(rx + pad, profY, 0.014, "AKTIVES PROFIL")
    local profile = SlowSteering.activeProfile or "custom"
    setTextBold(false)
    setTextColor(1.0, 0.95, 0.55, 1.0)
    setTextAlignment(RenderText.ALIGN_RIGHT)
    renderText(rx + rw - pad, profY, 0.016,
        SlowSteering.PRESET_LABELS[profile] or profile)

    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)

    -- Section: curve preview
    local graphTop = profY - 0.030
    setTextColor(0.78, 0.85, 0.92, 1.0)
    setTextBold(true)
    renderText(rx + pad, graphTop, 0.013, "LENKUNGS-KURVE")
    setTextBold(false)

    local gx = rx + pad
    local gy = graphTop - 0.190
    local gw = rw - pad * 2
    local gh = 0.170
    drawCurvePreview(overlay, gx, gy, gw, gh)

    -- Section: help text for selected setting
    local helpTop = gy - 0.025
    setTextColor(0.78, 0.85, 0.92, 1.0)
    setTextBold(true)
    renderText(rx + pad, helpTop, 0.013, "ERLAEUTERUNG")
    setTextBold(false)

    local def = currentItem()
    if def ~= nil then
        setTextColor(0.85, 0.88, 0.92, 1.0)
        setTextBold(true)
        renderText(rx + pad, helpTop - 0.022, 0.014, def.label)
        setTextBold(false)
        setTextColor(0.70, 0.75, 0.80, 0.95)

        -- Word-wrap by character count (~46 chars per line at this size)
        local helpText = def.help or ""
        local maxLine = 46
        local cursor = 1
        local lineY = helpTop - 0.040
        while cursor <= #helpText do
            local stop = math.min(cursor + maxLine - 1, #helpText)
            -- back up to a space if not at end
            if stop < #helpText then
                local space = helpText:sub(cursor, stop):match(".*() ")
                if space and space > 10 then
                    stop = cursor + space - 2
                end
            end
            local line = helpText:sub(cursor, stop)
            renderText(rx + pad, lineY, 0.012, line)
            lineY = lineY - 0.016
            cursor = stop + 2
            if lineY < rBot + 0.030 then break end
        end
    end
end

-- =========================================================
-- DRAW: footer (action hints)
-- =========================================================
local function drawFooter(overlay)
    local fx = L.dialogX
    local fy = L.dialogY
    local fw = L.dialogW
    local fh = L.footerH

    drawRect(overlay, fx, fy, fw, fh, 0.07, 0.09, 0.12, 1.0)
    drawRect(overlay, fx, fy + fh - 0.0015, fw, 0.0015, 0.20, 0.28, 0.36, 0.9)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(0.65, 0.70, 0.78, 1.0)
    setTextBold(false)
    local hintY = fy + fh * 0.32
    renderText(fx + L.padding, hintY, 0.0125,
        "[Tab] Kategorie    [P] Profil    [F1] Reset    [F5] Alle zuruecksetzen")

    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(0.85, 0.95, 0.65, 1.0)
    renderText(fx + fw - L.padding, hintY, 0.0125,
        "[Enter] Speichern    [Esc] Abbrechen")
end

-- =========================================================
-- DRAW: master
-- =========================================================
function SlowSteeringGui.onDraw()
    if not SlowSteeringGui.isOpen then return end

    local overlay = ensureBgOverlay()
    if overlay == nil or overlay == 0 then
        -- Fallback bare-bones if overlay couldn't be created
        setTextColor(1, 1, 1, 1)
        setTextAlignment(RenderText.ALIGN_CENTER)
        renderText(0.5, 0.5, 0.02, "Slow Steering: Overlay nicht verfuegbar")
        return
    end

    -- Full-screen dim
    drawRect(overlay, 0, 0, 1, 1, 0, 0, 0, 0.55)

    -- Dialog backdrop (subtle inner panel)
    drawRect(overlay, L.dialogX, L.dialogY, L.dialogW, L.dialogH, 0.05, 0.07, 0.10, 0.97)
    -- Outer accent border (top + bottom)
    drawRect(overlay, L.dialogX, L.dialogY + L.dialogH - 0.001, L.dialogW, 0.001, 0.30, 0.65, 0.95, 0.4)
    drawRect(overlay, L.dialogX, L.dialogY, L.dialogW, 0.001, 0.30, 0.65, 0.95, 0.4)

    drawTitleBar(overlay)
    drawTabBar(overlay)
    drawSettingsList(overlay)
    drawRightColumn(overlay)
    drawFooter(overlay)

    -- Brief tint flash on F1/F5/preset change
    if SlowSteeringGui.flashFrames > 0 and SlowSteeringGui.flashColor ~= nil then
        local a = SlowSteeringGui.flashFrames / 12 * 0.18
        local c = SlowSteeringGui.flashColor
        drawRect(overlay, L.dialogX, L.dialogY, L.dialogW, L.dialogH, c[1], c[2], c[3], a)
    end

    -- Reset render state
    setTextColor(1, 1, 1, 1)
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
