RAV = {
	description = "RideAerodyneVehicele",
	version = "0.1",
    ready = false
}

-- import modules
RAV.Cron = require('External/Cron.lua')
RAV.Event = require('Modules/event.lua')
RAV.Core = require('Modules/core.lua')

-- create instances
RAV.event_obj = RAV.Event:new()
RAV.core_obj = RAV.Core:new(RAV.event_obj)

print('RAV is loaded!')

-- onInit event
registerForEvent('onInit', function()

    RAV.ready = true
    local callback = function()
        RAV.core_obj:operateAV()
    end
    RAV.Cron.Every(0.01, callback)


    -- print on initialize
    print('RAV is initialized!')

end)

registerHotkey('CallAerodyneVehicle', 'Call Aerodyne Vehicle', function()
    RAV.core_obj:callAerodyneVehicle()
end)

registerHotkey('ChangeAerodyneDoor', 'Change Door (TMP)', function()
    RAV.core_obj:changeAerodyneDoor()
end)

registerHotkey('LockAerodyneDoor', 'Lock (TMP)', function()
    RAV.core_obj:lockAerodyneDoor()
end)

registerHotkey('UnlockAerodyneDoor', 'Unlock (TMP)', function()
    RAV.core_obj:unlockAerodyneDoor()
end)

registerHotkey('Mount', 'Mount (TMP)', function()
    RAV.core_obj:mount()
end)

registerHotkey('Unmount', 'Unmount (TMP)', function()
    RAV.core_obj:unmount()
end)

registerForEvent('onUpdate', function(delta)
    -- This is required for Cron to function
    RAV.Cron.Update(delta)
    RAV.event_obj:checkInAV()
end)

-- for communication between mods
return RAV