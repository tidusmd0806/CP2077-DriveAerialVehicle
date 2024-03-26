--------------------------------------------------------
-- CopyRight (C) 2024, tidusmd. All rights reserved.
-- This mod is under the MIT License.
-- https://opensource.org/licenses/mit-license.php
--------------------------------------------------------

DAV = {
	description = "Drive an Aerial Vehicele",
	version = "0.1.0",
    ready = false,
    is_debug_mode = false,
    is_opening_overlay = false,
    time_resolution = 0.01,
	model_index = 1,
	model_type_index = 3,
	open_door_index = 1,
	seat_index = 3,
    horizenal_boost_ratio = 1.2
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

registerForEvent('onInit', function()

    DAV.core_obj:Init()

    Observe("PlayerPuppet", "OnAction", function(this, action, consumer)
        local action_name = action:GetName(action).value
		local action_type = action:GetType(action).value
        local action_value = action:GetValue(action)

        if DAV.core_obj.event_obj:IsInVehicle() then
            if string.find(action_name, "Exit") then
                consumer:Consume()
            elseif string.find(action_name, "VisionHold") then
                consumer:Consume()
            end
        end

        if DAV.is_debug_mode then
            DAV.debug_obj:PrintActionCommand(action_name, action_type, action_value)
        end

        DAV.core_obj:StorePlayerAction(action_name, action_type, action_value)

    end)

    Observe("CommunitySystem", "EnableDynamicCrowdNullArea", function(this)
        print('EnableDynamicCrowdNullArea')
    end)

    DAV.ready = true
    print('Drive an Aerodyne Vehicle Mod is ready!')
end)

registerForEvent("onDraw", function()
    if DAV.is_debug_mode then
        DAV.debug_obj:ImGuiMain()
    end
    if DAV.is_opening_overlay then
        DAV.core_obj.event_obj.ui_obj:ShowSettingMenu()
    end
end)

-- registerHotkey("DAV_1", "1", function()
--     Game.GetGodModeSystem():AddGodMode(GetPlayer():GetEntityID(), gameGodModeType.Invulnerable, 'FastTravel')
--     GetPlayer():SetInvisible(true)
-- end)

-- registerHotkey("DAV_2", "2", function()
--     GetPlayer():SetInvisible(false)
--     Game.GetGodModeSystem():RemoveGodMode(GetPlayer():GetEntityID(), gameGodModeType.Invulnerable, 'FastTravel')
-- end)

registerForEvent('onUpdate', function(delta)
    -- This is required for Cron to function
    DAV.Cron.Update(delta)
end)

return DAV