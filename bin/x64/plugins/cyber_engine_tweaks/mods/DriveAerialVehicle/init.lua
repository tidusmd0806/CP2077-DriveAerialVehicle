--------------------------------------------------------
-- CopyRight (C) 2024, tidusmd. All rights reserved.
-- This mod is under the MIT License.
-- https://opensource.org/licenses/mit-license.php
--------------------------------------------------------

DAV = {
	description = "Drive an Aerial Vehicele",
	version = "1.0.0",
    ready = false,
    is_debug_mode = false,
    is_opening_overlay = false,
    time_resolution = 0.01,
	model_index = 1,
	model_type_index = 1,
	seat_index = 1,
    horizenal_boost_ratio = 2.0,
    cet_required_version = 32.1, -- 1.32.1
    codeware_required_version = 8.2, -- 1.8.2
    cet_version_num = 0,
    codeware_version_num = 0
}

DAV.Cron = require('External/Cron.lua')
DAV.Core = require('Modules/core.lua')
DAV.Debug = require('Debug/debug.lua')

DAV.core_obj = DAV.Core:New()
DAV.debug_obj = DAV.Debug:New(DAV.core_obj)

registerForEvent("onOverlayOpen",function ()
	DAV.is_opening_overlay = true
end)

registerForEvent("onOverlayClose",function ()
	DAV.is_opening_overlay = false
end)

registerForEvent("onTweak",function ()
    -- Custom surveyor record
    TweakDB:CloneRecord("Vehicle.av_zetatech_surveyor_dav", "Vehicle.av_zetatech_surveyor")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.av_zetatech_surveyor_dav.entityTemplatePath"), "base\\dav\\av_zetatech_surveyor_basic_01_ep1_dav.ent")
    -- Custom valgus record
    TweakDB:CloneRecord("Vehicle.q000_nomad_border_patrol_heli_dav", "Vehicle.q000_nomad_border_patrol_heli")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.q000_nomad_border_patrol_heli_dav.entityTemplatePath"), "base\\dav\\q000_border_patrol_heli_dav.ent")
end)

registerForEvent('onInit', function()

    if not DAV:CheckDependencies() then
        print('Drive an Aerial Vehicle Mod failed to load due to missing dependencies.')
        return
    end

    DAV.core_obj:Init()

    DAV.ready = true

    print('Drive an Aerial Vehicle Mod is ready!')

end)

registerForEvent("onDraw", function()
    if DAV.is_debug_mode then
        DAV.debug_obj:ImGuiMain()
    end
    if DAV.is_opening_overlay then
        DAV.core_obj.event_obj.ui_obj:ShowSettingMenu()
    end
end)

registerHotkey("DAV_ToggleDebug", "Toggle Debug Mode", function()
    local player = Game.GetPlayer()
    local eve = vehicleRequestCameraPerspectiveEvent.new()
    eve.cameraPerspective = vehicleCameraPerspective.FPP
    player:QueueEvent(eve)

end)

registerHotkey("DAV_ToggleDebug2", "Toggle Debug Mode2", function()
    local player = Game.GetPlayer()
    local eve = vehicleRequestCameraPerspectiveEvent.new()
    eve.cameraPerspective = vehicleCameraPerspective.TPPFar
    player:QueueEvent(eve)

end)

registerHotkey("DAV_ToggleDebug3", "Toggle Debug Mode3", function()
    local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
    local door_event = VehicleDoorOpen.new()
	door_event.slotID = CName.new("trunk")
	door_event.forceScene = false
	vehicle_ps:QueuePSEvent(vehicle_ps, door_event)

end)

registerHotkey("DAV_ToggleDebug4", "Toggle Debug Mode4", function()
    local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
    local door_event = VehicleDoorClose.new()
	door_event.slotID = CName.new("trunk")
	door_event.forceScene = false
	vehicle_ps:QueuePSEvent(vehicle_ps, door_event)

end)

registerForEvent('onUpdate', function(delta)
    -- This is required for Cron to function
    DAV.Cron.Update(delta)
end)

function DAV:CheckDependencies()

    -- Check Cyber Engine Tweaks Version
    local cet_version_str = GetVersion()
    local cet_version_major, cet_version_minor = cet_version_str:match("1.(%d+)%.*(%d*)")
    DAV.cet_version_num = tonumber(cet_version_major .. "." .. cet_version_minor)

    -- Check CodeWare Version
    local code_version_str = Codeware.Version()
    local code_version_major, code_version_minor = code_version_str:match("1.(%d+)%.*(%d*)")
    DAV.codeware_version_num = tonumber(code_version_major .. "." .. code_version_minor)

    if DAV.cet_version_num < DAV.cet_required_version then
        print("Drive an Aerial Vehicle Mod requires Cyber Engine Tweaks version 1." .. DAV.cet_required_version .. " or higher.")
        return false
    elseif DAV.codeware_version_num < DAV.codeware_required_version then
        print("Drive an Aerial Vehicle Mod requires CodeWare version 1." .. DAV.codeware_required_version .. " or higher.")
        return false
    end

    return true

end

function DAV:Version()
    return DAV.version
end

return DAV