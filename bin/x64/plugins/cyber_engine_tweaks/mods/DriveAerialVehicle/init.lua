--------------------------------------------------------
-- CopyRight (C) 2024, tidusmd. All rights reserved.
-- This mod is under the MIT License.
-- https://opensource.org/licenses/mit-license.php
--------------------------------------------------------

Cron = require('External/Cron.lua')
Def = require("Tools/def.lua")
Log = require("Tools/log.lua")

local Core = require('Modules/core.lua')
local Debug = require('Debug/debug.lua')

DAV = {
	description = "Drive an Aerial Vehicele",
	version = "1.7.0",
    -- system
    is_ready = false,
    time_resolution = 0.01,
    is_debug_mode = false,
    is_opening_overlay = false,
    -- common
    user_setting_path = "Data/user_setting.json",
    language_path = "Language",
    -- grobal index
    model_index = 1,
	model_type_index = 1,
    -- version check
    cet_required_version = 32.1, -- 1.32.1
    cet_recommended_version = 32.2, -- 1.32.2
    codeware_required_version = 8.2, -- 1.8.2
    codeware_recommended_version = 9.2, -- 1.9.2
    native_settings_required_version = 1.96,
    cet_version_num = 0,
    codeware_version_num = 0,
    native_settings_version_num = 0,
    -- setting
    is_valid_native_settings = false,
    NativeSettings = nil,
    -- input
    input_listener = nil,
    listening_keybind_widget = nil,
    default_keybind_table = {
        {name = "toggle_autopilot", key = "IK_T", pad = "IK_Pad_DigitRight"},
        {name = "toggle_camera", key = "IK_V", pad = "IK_Pad_DigitDown"},
        {name = "toggle_door", key = "IK_G", pad = "IK_Pad_DigitLeft"},
        {name = "toggle_radio", key = "IK_R", pad = "IK_Pad_DigitUp"},
        {name = "toggle_crystal_dome", key = "IK_C", pad = "IK_Pad_Y_TRIANGLE"},
    }
}

-- initial settings
DAV.user_setting_table = {
    version = DAV.version,
    --- garage
    garage_info_list = {},
    --- free summon mode
    is_free_summon_mode = true,
    model_index_in_free = 1,
    model_type_index_in_free = 1,
    --- autopilot
    mappin_history = {},
    favorite_location_list = {
        {name = "Unselected", pos = {x=0,y=0,z=0}, is_selected = true},
        {name = "Not Registered", pos = {x=0,y=0,z=0}, is_selected = false},
        {name = "Not Registered", pos = {x=0,y=0,z=0}, is_selected = false},
        {name = "Not Registered", pos = {x=0,y=0,z=0}, is_selected = false},
        {name = "Not Registered", pos = {x=0,y=0,z=0}, is_selected = false},
        {name = "Not Registered", pos = {x=0,y=0,z=0}, is_selected = false},
    },
    autopilot_speed_level = Def.AutopilotSpeedLevel.Normal,
    is_autopilot_info_panel = true,
    is_enable_history = true,
    --- control
    flight_mode = Def.FlightMode.Spinner,
    heli_horizenal_boost_ratio = 5.0,
    is_disable_spinner_roll_tilt = false,
    --- environment
    is_enable_community_spawn = true,
    max_speed_for_freezing = 150,
    max_spawn_frequency = 20,
    min_spawn_frequency = 10,
    is_mute_all = false,
    is_mute_flight = false,
    --- general
    language_index = 1,
    is_unit_km_per_hour = false,
    --- input
    keybind_table = DAV.default_keybind_table
}

registerForEvent("onOverlayOpen",function ()
	DAV.is_opening_overlay = true
end)

registerForEvent("onOverlayClose",function ()
	DAV.is_opening_overlay = false
end)

-- set custom vehicle record
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
    TweakDB:SetFlat(TweakDBID.new("Vehicle.q000_nomad_border_patrol_heli_dav.displayName"), LocKey(77966))
    TweakDB:SetFlat(TweakDBID.new("Vehicle.q000_nomad_border_patrol_heli_dav.manufacturer"), "Vehicle.Zetatech")

end)

registerForEvent("onHook", function ()

    -- refer to https://www.nexusmods.com/cyberpunk2077/mods/8326
    DAV.input_listener = NewProxy({
        OnKeyInput = {
            args = {'handle:KeyInputEvent'},
            callback = function(event)
                local key = event:GetKey().value
                local action = event:GetAction().value
                if DAV.listening_keybind_widget and key:find("IK_Pad") and action == "IACT_Release" then -- OnKeyBindingEvent has to be called manually for gamepad inputs, while there is a keybind widget listening for input
                    DAV.listening_keybind_widget:OnKeyBindingEvent(KeyBindingEvent.new({keyName = key}))
                    DAV.listening_keybind_widget = nil
                elseif DAV.listening_keybind_widget and action == "IACT_Release" then -- Key was bound, by keyboard
                    DAV.listening_keybind_widget = nil
                end
                if DAV.core_obj.event_obj.current_situation == Def.Situation.InVehicle then
                    if action == "IACT_Press" then
                        DAV.core_obj:ConvertPressButtonAction(key)
                    elseif action == "IACT_Release" then
                        DAV.core_obj:ConvertHoldButtonAction(key)
                    end
                end
            end
        }
    })
    Game.GetCallbackSystem():RegisterCallback('Input/Key', DAV.input_listener:Target(), DAV.input_listener:Function("OnKeyInput"), true)
    Observe("SettingsSelectorControllerKeyBinding", "ListenForInput", function(this)
        DAV.listening_keybind_widget = this
    end)

end)

registerForEvent('onInit', function()

    if not DAV:CheckDependencies() then
        print('[Error] Drive an Aerial Vehicle Mod failed to load due to missing dependencies.')
        return
    end

    DAV:CheckNativeSettings()

    DAV.core_obj = Core:New()
    DAV.debug_obj = Debug:New(DAV.core_obj)

    DAV.core_obj:Init()

    DAV.is_ready = true

    print('Drive an Aerial Vehicle Mod is ready!')

end)

registerForEvent("onDraw", function()

    if DAV.is_debug_mode then
        DAV.debug_obj:ImGuiMain()
    end
    if DAV.is_opening_overlay then
        if DAV.core_obj == nil or DAV.core_obj.event_obj == nil or DAV.core_obj.event_obj.ui_obj == nil then
            return
        end
        DAV.core_obj.event_obj.ui_obj:ShowSettingMenu()
    end
    DAV.core_obj.event_obj.hud_obj:ShowAutoPilotInfo()

end)

registerForEvent('onUpdate', function(delta)
    Cron.Update(delta)
end)

registerForEvent('onShutdown', function()
    Game.GetCallbackSystem():UnregisterCallback('Input/Key', DAV.input_listener:Target(), DAV.input_listener:Function("OnKeyInput"))
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

function DAV:CheckNativeSettings()

    DAV.NativeSettings = GetMod("nativeSettings")
    if DAV.NativeSettings == nil then
		DAV.is_valid_native_settings = false
        return
	end
    DAV.native_settings_version_num = DAV.NativeSettings.version
    if DAV.NativeSettings.version < DAV.native_settings_required_version then
        DAV.is_valid_native_settings = false
        return
    end
    DAV.is_valid_native_settings = true
    return

end

function DAV:Version()
    return DAV.version
end

return DAV