--------------------------------------------------------
-- CopyRight (C) 2024, tidusmd. All rights reserved.
-- This mod is under the MIT License.
-- https://opensource.org/licenses/mit-license.php
--------------------------------------------------------

DAV = {
	description = "Drive an Aerial Vehicele",
	version = "0.2.0",
    ready = false,
    is_debug_mode = false,
    is_opening_overlay = false,
    is_locked_input = true,
    input_unlock_time = 1.5,
    time_resolution = 0.01,
	model_index = 1,
	model_type_index = 1,
	open_door_index = 1,
	seat_index = 1,
    horizenal_boost_ratio = 2.0
}

DAV.Cron = require('External/Cron.lua')
DAV.Core = require('Modules/core.lua')
DAV.Debug = require('Debug/debug.lua')
DAV.Utils = require('Tools/utils.lua')

DAV.core_obj = DAV.Core:New()
DAV.debug_obj = DAV.Debug:New(DAV.core_obj)

registerForEvent("onOverlayOpen",function ()
	DAV.is_opening_overlay = true
end)

registerForEvent("onOverlayClose",function ()
	DAV.is_opening_overlay = false
end)

registerForEvent("onTweak",function ()
    -- original surveyor record
    TweakDB:CloneRecord("Vehicle.av_zetatech_surveyor_dav", "Vehicle.av_zetatech_surveyor")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.av_zetatech_surveyor_dav.entityTemplatePath"), "base\\dav\\av_zetatech_surveyor_basic_01_ep1_dav.ent")
    -- original valgus record
    TweakDB:CloneRecord("Vehicle.q000_nomad_border_patrol_heli_dav", "Vehicle.q000_nomad_border_patrol_heli")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.q000_nomad_border_patrol_heli_dav.entityTemplatePath"), "base\\dav\\q000_border_patrol_heli_dav.ent")
end)

registerForEvent('onInit', function()

    -- DAV.is_debug_mode = true

    DAV.core_obj:Init()

    local exception_list = DAV.Utils:ReadJson("Data/exception_input.json")

    Observe("PlayerPuppet", "OnAction", function(this, action, consumer)
        local action_name = action:GetName(action).value
		local action_type = action:GetType(action).value
        local action_value = action:GetValue(action)

        if DAV.core_obj.event_obj:IsInVehicle() and not DAV.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
            for _, exception in pairs(exception_list) do
                if string.find(action_name, exception) then
                    consumer:ConsumeSingleAction()
                    return
                end
            end
        end

        if DAV.is_debug_mode then
            DAV.debug_obj:PrintActionCommand(action_name, action_type, action_value)
        end

        DAV.core_obj:StorePlayerAction(action_name, action_type, action_value)

    end)

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

registerForEvent('onUpdate', function(delta)
    -- This is required for Cron to function
    DAV.Cron.Update(delta)
end)

return DAV