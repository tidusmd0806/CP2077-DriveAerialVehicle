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
    input_unlock_time = 0.5,
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
DAV.Utils = require('Tools/utils.lua')

DAV.core_obj = DAV.Core:New()
DAV.debug_obj = DAV.Debug:New(DAV.core_obj)

registerForEvent("onOverlayOpen",function ()
	DAV.is_opening_overlay = true
end)

registerForEvent("onOverlayClose",function ()
	DAV.is_opening_overlay = false
end)

registerForEvent('onInit', function()

    DAV.is_debug_mode = true

    DAV.core_obj:Init()

    local exception_list = DAV.Utils:ReadJson("Data/essential_default_input.json")

    Observe("PlayerPuppet", "OnAction", function(this, action, consumer)
        local action_name = action:GetName(action).value
		local action_type = action:GetType(action).value
        local action_value = action:GetValue(action)

        if DAV.core_obj.event_obj:IsInVehicle() and not DAV.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
            for _, exception in pairs(exception_list) do
                if action_name ~= exception and DAV.is_locked_input then
                    consumer:ConsumeSingleAction()
                else
                    DAV.is_locked_input = false
                    DAV.Cron.After(DAV.input_unlock_time, function()
                        DAV.is_locked_input = true
                    end)
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

registerHotkey("DAV_1", "1", function()
    local spawnTransform = Game.GetPlayer():GetWorldTransform()

    local heading = Game.GetPlayer():GetWorldForward()
    local pos = Game.GetPlayer():GetWorldPosition()
    pos = Vector4.new(pos.x + heading.x, pos.y + heading.y, pos.z + 1.5, pos.w) -- in front of the player

    spawnTransform:SetPosition(pos)

    local entityID = exEntitySpawner.Spawn("base\\entities\\cameras\\simple_free_camera.ent", spawnTransform, '')

    DAV.Cron.Every(0.1, {tick = 1}, function(timer)
        local entity = Game.FindEntityByID(entityID)
        timer.tick = timer.tick + 1
        if entity then
            DAV.component = entity:FindComponentByName("camera")

            DAV.Cron.Halt(timer)
        elseif timer.tick > 20 then
            DAV.Cron.Halt(timer)
        end
    end)

end)

registerHotkey("DAV_2", "2", function()
    DAV.core_obj.camera_obj.cam_component:Activate(0, false)
end)

registerHotkey("DAV_3", "3", function()
    Game.GetPlayer():GetFPPCameraComponent():Activate(0, false)
end)

registerHotkey("DAV_4", "4", function()
    DAV.core_obj.player_obj:ActivateTPPHead(true)
end)

registerHotkey("DAV_5", "5", function()
    local pos = Game.GetPlayer():GetWorldPosition()
    pos.x = pos.x + 10
    local angle = Game.GetPlayer():GetWorldOrientation():ToEulerAngles()
    Game.GetTeleportationFacility():Teleport(DAV.enti, pos, angle)
end)

registerForEvent('onUpdate', function(delta)
    -- This is required for Cron to function
    DAV.Cron.Update(delta)
end)

return DAV