-- mod info
CAV_mod = {
    ready = false
}

Util = require('util.lua')
Cron = require('Cron.lua')

function ChangeScanAppearanceTo(t, newAppearance)
	if t.archetype ~= "mech" then

		t.handle:PrefetchAppearanceChange(newAppearance)
		t.handle:ScheduleAppearanceChange(newAppearance)

		-- if self.activeCustomApps[t.hash] ~= nil and self.activeCustomApps[t.hash] ~= 'reverse' then
		-- 	self.activeCustomApps[t.hash] = nil
		-- end
	end
end

local _entitySystem
local function getEntitySystem()
	_entitySystem = _entitySystem or Game.GetDynamicEntitySystem()
	return _entitySystem
end

function SpawnVehicle(spawn)

	local entitySystem = getEntitySystem()

	spawn.entitySpec.recordID = spawn.path
	spawn.entitySpec.tags = { "AMM_CAR" }
	spawn.entitySpec.position = Util:GetPosition(5.5, 0.0)
	spawn.entitySpec.orientation = Util:GetOrientation(90.0)
	spawn.entityID = getEntitySystem():CreateEntity(spawn.entitySpec)

	local timerfunc = function(timer)
		local entity = Game.FindEntityByID(spawn.entityID)
		if entity then
			spawn.handle = entity
			spawn.hash = tostring(entity:GetEntityID().hash)

			-- Spawn.spawnedNPCs[spawn.uniqueName()] = spawn
			if spawn.id == "0xE09AAEB8, 26" then
				Game.GetGodModeSystem():AddGodMode(spawn.handle:GetEntityID(), 0, "")
			end

			if spawn.parameters ~= nil then
				ChangeScanAppearanceTo(spawn, spawn.parameters)
			end

			Util:UnlockVehicle(spawn.handle)
			Cron.Halt(timer)
		end
	end

	local timerfunc2 = function()
		local entity = Game.FindEntityByID(spawn.entityID)
		print("sfda")
		if entity then
			local getTargetPS = spawn.handle:GetVehiclePS()
			local state = getTargetPS:GetDoorState(1).value
			print(state)
			getTargetPS:OpenAllRegularVehDoors(false)
		end
	end
	Cron.After(5.0, timerfunc2)
	Cron.Every(0.3, timerfunc)

end


-- print on load
print('My Mod is loaded!')

-- onInit event
registerForEvent('onInit', function()

    -- set as ready
    CAV_mod.ready = true

    -- print on initialize
    print('My Mod is initialized!')

end)

registerHotkey('SpawnRandomVehicle', 'Spawn a vehicle', function()
    local spawn = {}
    spawn.path = "Vehicle.av_rayfield_excalibur"
	spawn.parameter = 0
	spawn.entitySpec = DynamicEntitySpec.new()
    SpawnVehicle(spawn)
end)

registerForEvent('onUpdate', function(delta)
    -- This is required for Cron to function
    Cron.Update(delta)
end)

-- return mod info 
-- for communication between mods
return CAV_mod