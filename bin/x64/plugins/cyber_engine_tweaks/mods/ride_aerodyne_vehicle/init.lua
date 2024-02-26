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
RAV.event_obj = RAV.Event:New()
RAV.core_obj = RAV.Core:New(RAV.event_obj)

print('RAV is loaded!')

-- onInit event
registerForEvent('onInit', function()

    RAV.ready = true
    local callback = function()
        RAV.core_obj:CheckAction()
    end
    RAV.Cron.Every(0.01, callback)


    -- print on initialize
    print('RAV is initialized!')

end)

registerHotkey('CallAerodyneVehicle', 'Call Aerodyne Vehicle', function()
    RAV.core_obj:CallAerodyneVehicle()
end)

registerHotkey('ChangeAerodyneDoor', 'Change Door (TMP)', function()
    RAV.core_obj:ChangeAerodyneDoor()
end)

registerHotkey('LockAerodyneDoor', 'Lock (TMP)', function()
    RAV.core_obj:LockAerodyneDoor()
end)

registerHotkey('UnlockAerodyneDoor', 'Unlock (TMP)', function()
    RAV.core_obj:UnlockAerodyneDoor()
end)

registerHotkey('Mount', 'Mount (TMP)', function()
    RAV.core_obj:Mount()
end)

registerHotkey('Unmount', 'Unmount (TMP)', function()
    RAV.core_obj:Unmount()
end)

registerInput('Forword', 'Forword', function(keypress)
    if keypress then
        RAV.core_obj:SetAction(ActionCommandList.Foword)
    else
        RAV.core_obj:SetAction(ActionCommandList.Nothing)
    end
end)

registerInput('Backward', 'Backward', function(keypress)
    if keypress then
        RAV.core_obj:SetAction(ActionCommandList.Backward)
    else
        RAV.core_obj:SetAction(ActionCommandList.Nothing)
    end
end)

registerInput('Left', 'Left', function(keypress)
    if keypress then
        RAV.core_obj:SetAction(ActionCommandList.Left)
    else
        RAV.core_obj:SetAction(ActionCommandList.Nothing)
    end
end)

registerInput('Right', 'Right', function(keypress)
    if keypress then
        RAV.core_obj:SetAction(ActionCommandList.Right)
    else
        RAV.core_obj:SetAction(ActionCommandList.Nothing)
    end
end)

registerInput('Up', 'Up', function(keypress)
    if keypress then
        RAV.core_obj:SetAction(ActionCommandList.Up)
    else
        RAV.core_obj:SetAction(ActionCommandList.Nothing)
    end
end)

registerInput('Down', 'Down', function(keypress)
    if keypress then
        RAV.core_obj:SetAction(ActionCommandList.Down)
    else
        RAV.core_obj:SetAction(ActionCommandList.Nothing)
    end
end)

registerForEvent('onUpdate', function(delta)
    -- This is required for Cron to function
    RAV.Cron.Update(delta)
    RAV.event_obj:CheckInAV()
end)

-- for communication between mods
return RAV