-- mod info
CAV_mod = {
    ready = false
}


function getNPCByTweakId(tweak)

    print("point 37")

    local entitieshash = dofile("entitieshash.lua")
	
	for k,v in pairs(entitieshash) do
		
		if v.entity_tweak == tweak then
			
			
			
			return v
		end
		
	end
end

function spawnVehicleV2(chara, appearance, tag, x, y ,z, spawnlevel, spawn_system ,isAV,from_behind,isMPplayer,wait_for_vehicule, scriptlevel, wait_for_vehicle_second,fakeav,despawntimer,persistState,persistSpawn,AlwaysSpawned,SpawnInView,dontregister,rotation)
    print("func enter")
    if (spawn_system ~= 4 and spawn_system ~= 1) then spawn_system = 4 end
    print("point 10")
    if (('string' == type(chara)) and (string.match(tostring(chara), "AMM_Vehicle.") == nil or (string.match(tostring(chara), "AMM_Vehicle.") ~= nil and AMM ~= nil)  )  )then

        print(spawn_system)

        isprevention = isprevention or false

        isAV = isAV or false
        local firstspawn = false
        local NPC = nil


        if despawntimer == nil then despawntimer = 0 end



        local player = Game.GetPlayer()
        local worldpos = player:GetWorldTransform()

        local postp = Vector4.new( x, y, z,1)

        worldpos:SetPosition(worldpos, postp)
        if(rotation ~= nil) then

            local rostp =  EulerAngles.new(rotation.roll,rotation.pitch,rotation.yaw)

            worldpos:SetOrientationEuler(worldpos, rostp)
            else
            rotation = EulerAngles.new(0,0,0)
        end

        local npcSpec =  DynamicEntitySpec.new()
        npcSpec.recordID = chara
        npcSpec.appearanceName = appearance
        npcSpec.position = postp
        npcSpec.orientation = EulerAngles.new(rotation.roll,rotation.pitch,rotation.yaw)
        npcSpec.persistState = persistState or false
        npcSpec.persistSpawn = persistSpawn or false
        npcSpec.alwaysSpawned = AlwaysSpawned or false
        npcSpec.spawnInView =  true
        CName.add("CyberScript")
        CName.add("CyberScript.Vehicle")
        CName.add("CyberScript.Vehicle."..tag)


        npcSpec.tags = {"CyberScript","CyberScript.Vehicle","CyberScript.Vehicle."..tag}
        if(Game.GetDynamicEntitySystem():IsPopulated("CyberScript.Vehicle."..tag) == true) then Game.GetDynamicEntitySystem():DeleteTagged("CyberScript.Vehicle."..tag) end
        print(chara)
        print(appearance)
        if(Game.GetDynamicEntitySystem():IsPopulated("CyberScript.Vehicle."..tag) == false) then
            print("dsdddd")
            NPC = Game.GetDynamicEntitySystem():CreateEntity(npcSpec)
            if dontregister == nil then dontregister = false end
            if(NPC ~= nil and dontregister == false) then
                local entity = {}
                print("test")
                entity.id = NPC
                entity.spawntimespan = os.time(os.date("!*t"))+0
                entity.despawntimespan = os.time(os.date("!*t"))+despawntimer
                entity.tag = tag
                entity.takenSeat = {}
                entity.driver = {}
                entity.isAV = isAV
                entity.fakeAV = fakeav
                entity.spawnlocation = postp
                entity.isitem = isitem
                entity.tweak = chara
                entity.isprevention = isprevention
                entity.iscodeware = true
                entity.persistState = persistState or false
                entity.persistSpawn = persistSpawn or false
                entity.alwaysSpawned = AlwaysSpawned or false
                entity.spawnInView = true
                if(scriptlevel == nil) then
                    entity.scriptlevel = 0
                    else
                    entity.scriptlevel = scriptlevel
                end
                entity.isMP = isMPplayer
                print("point 30")
                isitem = nil

                if(isitem == nil or isitem == false) then
                    print("point 35")
                    local npgc = getNPCByTweakId(chara)
                    if(npgc ~= nil) then
                        entity.name = npgc.Names
                        print("point 40")
                        else
                        entity.name = tag
                        print("point 50")
                    end
                    else

                    entity.name = tag

                end

                if(isMPplayer ~= nil and isMPplayer == true)then
                    entity.name = tag
                end
                cyberscript.EntityManager[tag]=entity
                cyberscript.EntityManager["last_spawned"].tag=tag


                -- Cron.After(0.5, function()


                -- if isprevention == true then
                -- local postp = Vector4.new( x, y, z,1)
                -- teleportTo(Game.FindEntityByID(NPC), postp, 1,false)
                -- end




                -- end)
            end

        else
        print("already spawsn")
        end
    end

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
    chara = "Vehicle.av_rayfield_excalibur" 
    appearance = ""
    tag = "taxi_delamain_av"
    x = -55
    y = 0
    z = 50
    spawnlevel = 36
    spawn_system = 4
    isAV = false
    from_behind = false
    isMPplayer = true
    wait_for_vehicule = false
    scriptlevel = 0
    wait_for_vehicle_second = false --check
    fakeav = "" --check
    despawntimer = 0
    persistState = false
    persistSpawn = false
    AlwaysSpawned = true
    SpawnInView = true
    dontregister = false
    rotation = nil --check

    spawnVehicleV2(chara, appearance, tag, x, y ,z, spawnlevel, spawn_system ,isAV,from_behind,isMPplayer,wait_for_vehicule, scriptlevel, wait_for_vehicle_second,fakeav,despawntimer,persistState,persistSpawn,AlwaysSpawned,SpawnInView,dontregister,rotation)
end)

-- return mod info 
-- for communication between mods
return CAV_mod