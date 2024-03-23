DAV = {
	description = "Drive an Aerial Vehicele",
	version = "0.0.1",
    ready = false,
    is_debug_mode = true,
    is_setting_menu = false,
    time_resolution = 0.01,
}

DAV.Cron = require('External/Cron.lua')
DAV.Core = require('Modules/core.lua')
DAV.Debug = require('Debug/debug.lua')

DAV.core_obj = DAV.Core:New()
DAV.debug_obj = DAV.Debug:New(DAV.core_obj)

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

    -- Observe("IMountingFacility", "Unmount", function(this, event)
    --     print("Unmount")
    --     print("delay: " .. event.delay)
    --     print("lowLevelMountingInfo")
    --     print("childId: " .. event.lowLevelMountingInfo.childId:GetHash())
    --     print("parentId: " .. event.lowLevelMountingInfo.parentId:GetHash())
    --     print("slotId: " .. event.lowLevelMountingInfo.slotId.id.value)
    --     print("mountData")
    --     print("allowFailsafeTeleport ")
    --     print(event.mountData.allowFailsafeTeleport)
    --     print("entryAnimName: " .. event.mountData.entryAnimName.value)
    --     print("entrySlotName: " .. event.mountData.entrySlotName.value)
    --     print("ignoreHLS")
    --     print(event.mountData.ignoreHLS)
    --     -- print("initialTransformLS: " .. event.mountData.initialTransformLS)
    --     print("isCarrying")
    --     print(event.mountData.isCarrying)
    --     print("isInstant")
    --     print(event.mountData.isInstant)
    --     print("isJustAttached")
    --     print(event.mountData.isJustAttached)
    --     -- print("mountEventOptions" .. event.mountData.mountEventOptions)
    --     print("mountParentEntityId: " .. event.mountData.mountParentEntityId:GetHash())
    --     print("removePitchRollRotationOnDismount")
    --     print(event.mountData.removePitchRollRotationOnDismount)
    --     print("setEntityVisibleWhenMountFinish")
    --     print(event.mountData.setEntityVisibleWhenMountFinish)
    --     print("slotName" .. event.mountData.slotName.value)
    --     print("switchRenderPlane")
    --     print(event.mountData.switchRenderPlane)
    -- end)

    DAV.ready = true
    print('Drive an Aerodyne Vehicle Mod is ready!')
end)

registerForEvent("onDraw", function()
    if DAV.is_debug_mode then
        DAV.debug_obj:ImGuiMain()
    end
    if DAV.is_setting_menu then
        DAV.core_obj.event_obj.ui_obj:ShowSettingMenu()
    end
end)

registerHotkey('Setting', 'Show Set Up Menu', function()
    if DAV.is_setting_menu then
        DAV.is_setting_menu = false
    else
        DAV.is_setting_menu = true
    end
end)

registerForEvent('onUpdate', function(delta)
    -- This is required for Cron to function
    DAV.Cron.Update(delta)
end)

return DAV