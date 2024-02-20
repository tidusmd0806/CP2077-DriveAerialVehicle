RAV = {
	description = "RideAerodyneVehicele",
	version = "0.1",
    ready = false
}

-- import modules
Cron = require('External/Cron.lua')
Event = require('Modules/event.lua')
Core = require('Modules/core.lua')

-- create instances
RAV.event_obj = Event:new()
RAV.core_obj = Core:new(RAV.event_obj)

print('RAV is loaded!')

-- onInit event
registerForEvent('onInit', function()

    RAV.ready = true

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
    Cron.Update(delta)
    RAV.event_obj:checkInAV()
end)

-- for communication between mods
return RAV