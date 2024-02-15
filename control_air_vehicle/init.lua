-- mod info
CAV_mod = {
    ready = false
}

-- print on load
print('My Mod is loaded!')

-- onInit event
registerForEvent('onInit', function() 
    
    -- set as ready
    CAV_mod.ready = true

    TweakDB:SetFlat("Shooter.DefaultPlayerControllerData.maxHealth", 15.0)
    TweakDB:SetFlat("Shooter.DefaultPlayerControllerData.defaultWeapon", "MISSILE")
    TweakDB:SetFlat("Shooter.MissileData.interval", 0.1)
    TweakDB:SetFlat("Shooter.MissileData.cooldown", 0.0)
    TweakDB:SetFlat("Shooter.MissileData.rounds", 50.0)
    TweakDB:SetFlat("Shooter.MissileData.value", 1000.0)


    
    -- print on initialize
    print('My Mod is initialized!')
    
end)

-- return mod info 
-- for communication between mods
return CAV_mod