--------------------------------------------------------
-- CopyRight (C) 2024, tidusmd. All rights reserved.
-- This mod is under the MIT License.
-- https://opensource.org/licenses/mit-license.php
--------------------------------------------------------

DAV = {
	description = "Drive an Aerial Vehicele",
	version = "1.1.0",
    ready = false,
    is_debug_mode = false,
    is_opening_overlay = false,
    time_resolution = 0.01,
    user_setting_path = "Data/user_setting.json",
    language_path = "Language",
    is_free_summon_mode = true,
	model_index = 1,
	model_type_index = 1,
    garage_info_list = {},
    language_index = 1,
    horizenal_boost_ratio = 2.0,
    cet_required_version = 32.1, -- 1.32.1
    cet_recommended_version = 32.2, -- 1.32.2
    codeware_required_version = 8.2, -- 1.8.2
    codeware_recommended_version = 8.2, -- 1.8.2
    cet_version_num = 0,
    codeware_version_num = 0
}

DAV.Cron = require('External/Cron.lua')
DAV.Core = require('Modules/core.lua')
DAV.Debug = require('Debug/debug.lua')
DAV.Utils = require('Tools/utils.lua')

DAV.core_obj = DAV.Core:New()
DAV.debug_obj = DAV.Debug:New(DAV.core_obj)

DAV.user_setting_table = {
    version = DAV.version,
    model_index = DAV.model_index,
    model_type_index = DAV.model_type_index,
    garage_info_list = DAV.garage_info_list,
    is_free_summon_mode = DAV.is_free_summon_mode,
    language_index = DAV.language_index,
    horizenal_boost_ratio = DAV.horizenal_boost_ratio
}

registerForEvent("onOverlayOpen",function ()
	DAV.is_opening_overlay = true
end)

registerForEvent("onOverlayClose",function ()
	DAV.is_opening_overlay = false
end)

registerForEvent("onTweak",function ()

     -- Custom excalibur record
     TweakDB:CloneRecord("Vehicle.av_rayfield_excalibur_dav", "Vehicle.av_rayfield_excalibur")
     TweakDB:SetFlat(TweakDBID.new("Vehicle.av_rayfield_excalibur_dav.entityTemplatePath"), "base\\dav\\av_rayfield_excalibur__basic_01_dav.ent")

     -- Custom manticore record
     TweakDB:CloneRecord("Vehicle.av_militech_manticore_dav", "Vehicle.av_militech_manticore")
     TweakDB:SetFlat(TweakDBID.new("Vehicle.av_militech_manticore_dav.entityTemplatePath"), "base\\dav\\av_militech_manticore_basic_01_dav.ent")

     -- Custom manticore record
     TweakDB:CloneRecord("Vehicle.av_zetatech_atlus_dav", "Vehicle.av_zetatech_atlus")
     TweakDB:SetFlat(TweakDBID.new("Vehicle.av_zetatech_atlus_dav.entityTemplatePath"), "base\\dav\\av_zetatech_atlus_basic_02_dav.ent")

     -- Custom surveyor record
     TweakDB:CloneRecord("Vehicle.av_zetatech_surveyor_dav", "Vehicle.av_zetatech_surveyor")
     TweakDB:SetFlat(TweakDBID.new("Vehicle.av_zetatech_surveyor_dav.entityTemplatePath"), "base\\dav\\av_zetatech_surveyor_basic_01_ep1_dav.ent")

     -- Custom valgus record
     TweakDB:CloneRecord("Vehicle.q000_nomad_border_patrol_heli_dav", "Vehicle.q000_nomad_border_patrol_heli")
     TweakDB:SetFlat(TweakDBID.new("Vehicle.q000_nomad_border_patrol_heli_dav.entityTemplatePath"), "base\\dav\\q000_border_patrol_heli_dav.ent")

     -- Custom valgus record(door close)
    TweakDB:CloneRecord("Vehicle.q000_nomad_border_patrol_heli_dav_closed", "Vehicle.q000_nomad_border_patrol_heli")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.q000_nomad_border_patrol_heli_dav_closed.entityTemplatePath"), "base\\dav\\q000_border_patrol_heli_dav_closed.ent")

end)

registerForEvent('onInit', function()

    if not DAV:CheckDependencies() then
        print('Drive an Aerial Vehicle Mod failed to load due to missing dependencies.')
        return
    end
    
    DAV.core_obj:Init()

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

registerForEvent('onUpdate', function(delta)
    -- This is required for Cron to function
    DAV.Cron.Update(delta)
end)

function DAV:CheckDependencies()

    -- Check Cyber Engine Tweaks Version
    local cet_version_str = GetVersion()
    local cet_version_major, cet_version_minor = cet_version_str:match("1.(%d+)%.*(%d*)")
    DAV.cet_version_num = tonumber(cet_version_major .. "." .. cet_version_minor)

    -- Check CodeWare Version
    local code_version_str = Codeware.Version()
    local code_version_major, code_version_minor = code_version_str:match("1.(%d+)%.*(%d*)")
    DAV.codeware_version_num = tonumber(code_version_major .. "." .. code_version_minor)

    if DAV.cet_version_num < DAV.cet_required_version then
        print("Drive an Aerial Vehicle Mod requires Cyber Engine Tweaks version 1." .. DAV.cet_required_version .. " or higher.")
        return false
    elseif DAV.codeware_version_num < DAV.codeware_required_version then
        print("Drive an Aerial Vehicle Mod requires CodeWare version 1." .. DAV.codeware_required_version .. " or higher.")
        return false
    end

    return true

end

function DAV:Version()
    return DAV.version
end

return DAV