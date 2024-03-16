DAV = {
	description = "Drive an Aerodyne Vehicele",
	version = "0.1",
    ready = false,
    is_debug_mode = true,
    time_resolution = 0.01,
}

-- import modules
DAV.Cron = require('External/Cron.lua')
DAV.Core = require('Modules/core.lua')
DAV.Debug = require('Debug/debug.lua')

-- create instances
DAV.core_obj = DAV.Core:New()
DAV.debug_obj = DAV.Debug:New(DAV.core_obj)

registerForEvent('onInit', function()

    DAV.core_obj:Init()

    -- Observe player action
    Observe("PlayerPuppet", "OnAction", function(this, action)
        local action_name = Game.NameToString(action:GetName(action))
		local action_type = action:GetType(action).value
        local action_value = action:GetValue(action)

        if DAV.is_debug_mode then
            DAV.debug_obj:PrintActionCommand(action_name, action_type, action_value)
        end

        DAV.core_obj:StorePlayerAction(action_name, action_type, action_value)

    end)

    DAV.ready = true
    print('Drive an Aerodyne Vehicle Mod is ready!')
end)

-- Debug Window
registerForEvent("onDraw", function()
    if DAV.is_debug_mode then
        DAV.debug_obj:ImGuiMain()
    end
end)

registerHotkey('CallAerodyneVehicle', 'Call Aerodyne Vehicle', function()
    DAV.core_obj:CallAerodyneVehicle()
end)

registerHotkey('ChangeAerodyneDoor', 'Change Door (TMP)', function()
    DAV.core_obj:ChangeAerodyneDoor(1)
end)

registerHotkey('LockAerodyneDoor', 'Lock (TMP)', function()
    DAV.core_obj:LockAerodyneDoor()
end)

registerHotkey('UnlockAerodyneDoor', 'Unlock (TMP)', function()
    DAV.core_obj:UnlockAerodyneDoor()
end)

registerHotkey('Mount', 'Mount (TMP)', function()
    DAV.core_obj:Mount(3)
end)

registerHotkey('Unmount', 'Unmount (TMP)', function()
    DAV.core_obj:Unmount()
end)

registerForEvent('onUpdate', function(delta)
    -- This is required for Cron to function
    DAV.Cron.Update(delta)
end)

return DAV