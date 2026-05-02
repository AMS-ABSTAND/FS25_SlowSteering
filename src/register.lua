-- FS25_SlowSteering – registration
-- Adds the SlowSteering specialization to all drivable vehicles

source(Utils.getFilename("src/SlowSteering.lua", g_currentModDirectory))
source(Utils.getFilename("src/SlowSteeringGui.lua", g_currentModDirectory))

SlowSteering.MOD_DIR  = g_currentModDirectory
SlowSteering.MOD_NAME = g_currentModName

-- ---------------------------------------------------------------------------
-- Register specialization with the game
-- ---------------------------------------------------------------------------
if g_specializationManager:getSpecializationByName("SlowSteering") == nil then
    g_specializationManager:addSpecialization(
        "SlowSteering",
        "SlowSteering",
        Utils.getFilename("src/SlowSteering.lua", g_currentModDirectory),
        nil
    )
end

-- Add to every vehicle type that has Motorized + Drivable + Enterable
local types = g_vehicleTypeManager:getTypes()
if types ~= nil then
    for typeName, typeEntry in pairs(types) do
        if typeEntry ~= nil
           and SpecializationUtil.hasSpecialization(Motorized,  typeEntry.specializations)
           and SpecializationUtil.hasSpecialization(Drivable,   typeEntry.specializations)
           and SpecializationUtil.hasSpecialization(Enterable,  typeEntry.specializations)
           and not SpecializationUtil.hasSpecialization(SlowSteering, typeEntry.specializations) then
            g_vehicleTypeManager:addSpecialization(typeName, g_currentModName .. ".SlowSteering")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Map lifecycle + GUI event listener
-- ---------------------------------------------------------------------------
local SlowSteering_Listener = {}

function SlowSteering_Listener:loadMap(name)
    SlowSteering.loadConfig(true)
    print(string.format("--> SlowSteering v2.1.0.0 loaded  [active=%s | hud=%s | ref=%.0f km/h | reduction=%.0f%% | curve=%.1f | profile=%s]",
        tostring(SlowSteering.isActive),
        tostring(SlowSteering.showHud),
        SlowSteering.refSpeed,
        SlowSteering.steeringReductionAtRef * 100,
        SlowSteering.curveExponent,
        tostring(SlowSteering.activeProfile)))
    print("    Config: " .. SlowSteering.CONF_FILE)
end

function SlowSteering_Listener:deleteMap()
    SlowSteeringGui.close(false)
    SlowSteeringGui.destroy()
    SlowSteering.saveConfig()
end

function SlowSteering_Listener:keyEvent(unicode, sym, modifier, isDown)
    SlowSteeringGui.onKeyEvent(unicode, sym, modifier, isDown)
end

function SlowSteering_Listener:update(dt)
    SlowSteeringGui.onUpdate(dt)
end

function SlowSteering_Listener:draw()
    SlowSteeringGui.onDraw()
end

function SlowSteering_Listener:mouseEvent(posX, posY, isDown, isUp, button)
    SlowSteeringGui.onMouseEvent(posX, posY, isDown, isUp, button)
end

addModEventListener(SlowSteering_Listener)
