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
	version = "2.3.3",
    -- system
    is_ready = false,
    time_resolution = 0.01,
    is_debug_mode = false,
    -- common
    user_setting_path = "Data/user_setting.json",
    language_path = "Language",
    -- vehicle record
    excalibur_record = "Vehicle.av_rayfield_excalibur_dav",
    manticore_record = "Vehicle.av_militech_manticore_dav",
    atlus_record = "Vehicle.av_zetatech_atlus_dav",
    surveyor_record = "Vehicle.av_zetatech_surveyor_dav",
    valgus_record = "Vehicle.q000_nomad_border_patrol_heli_dav",
    mayhem_record = "Vehicle.q000_nomad_border_patrol_heli_mayhem_dav",
    -- global index
    model_index = 1,
	model_type_index = 1,
    -- version check
    cet_required_version = 32.1, -- 1.32.1
    cet_recommended_version = 32.3, -- 1.32.3
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
    axis_dead_zone = 0.1,
    input_key_listener = nil,
    input_axis_listener = nil,
    is_keyboard_input = true,
    listening_keybind_widget = nil,
    default_keybind_table = {
        {name = "move_up", key = "IK_G", pad = "IK_Pad_X_SQUARE", is_hold = true},
        {name = "move_down", key = "IK_V", pad = "IK_Pad_A_CROSS", is_hold = true},
        {name = "move_left", key = "IK_Q", pad = "IK_Pad_DigitLeft", is_hold = true},
        {name = "move_right", key = "IK_E", pad = "IK_Pad_DigitRight", is_hold = true},
        {name = "lean_reset", key = "IK_B", pad = "IK_Pad_LeftShoulder", is_hold = true},
    },
    default_heli_keybind_table = {
        {name = "ascend", key = "IK_G", pad = "IK_Pad_X_SQUARE", is_hold = true},
        {name = "descend", key = "IK_V", pad = "IK_Pad_A_CROSS", is_hold = true},
        {name = "turn_left", key = "IK_Q", pad = "IK_Pad_LeftTrigger", is_hold = true},
        {name = "turn_right", key = "IK_E", pad = "IK_Pad_RightTrigger", is_hold = true},
        {name = "acceleration", key = "IK_RightMouse", pad = "IK_Pad_LeftShoulder", is_hold = true},
    },
    default_common_keybind_table = {
        {name = "toggle_autopilot", key = "IK_Space", pad = "IK_Pad_LeftThumb", is_hold = true},
        {name = "toggle_camera", key = "IK_1", pad = "IK_Pad_DigitDown", is_hold = false},
        {name = "toggle_radio", key = "IK_2", pad = "IK_Pad_DigitUp", is_hold = true},
        {name = "toggle_door", key = "IK_3", pad = "IK_None", is_hold = false},
        {name = "toggle_crystal_dome", key = "IK_4", pad = "IK_None", is_hold = false},
        {name = "toggle_appearance", key = "IK_5", pad = "IK_None", is_hold = false},
        {name = "open_vehicle_manager", key = "IK_None", pad = "IK_None", is_hold = false},
    }
}

-- initial settings
DAV.user_setting_table = {
    version = DAV.version,
    --- garage
    garage_info_list = {},
    --- autopilot
    mappin_history = {},
    autopilot_selected_index = 0,
    favorite_location_list = {
        {name = "Not Registered", pos = {x=0,y=0,z=0}, is_selected = false},
        {name = "Not Registered", pos = {x=0,y=0,z=0}, is_selected = false},
        {name = "Not Registered", pos = {x=0,y=0,z=0}, is_selected = false},
        {name = "Not Registered", pos = {x=0,y=0,z=0}, is_selected = false},
        {name = "Not Registered", pos = {x=0,y=0,z=0}, is_selected = false},
    },
    autopilot_speed_level = Def.AutopilotSpeedLevel.Normal,
    is_enable_history = true,
    --- general
    language_index = 1,
    is_enable_landing_vfx = true,
    --- input
    keybind_table = DAV.default_keybind_table,
    heli_keybind_table = DAV.default_heli_keybind_table,
    common_keybind_table = DAV.default_common_keybind_table,
    --- physics
    -- common
    horizontal_air_resistance_const = 0.01,
    vertical_air_resistance_const = 0.025,
    -- av
    acceleration = 1,
    vertical_acceleration = 0.8,
    left_right_acceleration = 0.5,
    roll_change_amount = 0.5,
    roll_restore_amount = 0.2,
    pitch_change_amount = 0.5,
    pitch_restore_amount = 0.2,
    yaw_change_amount = 1,
    rotate_roll_change_amount = 0.5,
    -- helicopter
    h_roll_change_amount = 0.8,
    h_roll_restore_amount = 0.2,
    h_pitch_change_amount = 0.8,
    h_pitch_restore_amount = 0.2,
    h_yaw_change_amount = 1,
    h_acceleration = 0.5,
    h_lift_idle_acceleration = 1.0,
    h_ascend_acceleration = 0.5,
    h_descend_acceleration = 0.5,
}

-- set custom vehicle record
registerForEvent("onTweak",function ()

    -- Vehicle weapons list
    local weapon_list = {TweakDBID.new("Vehicle.Vehicle_Power_Weapon_Left_A"), TweakDBID.new("Vehicle.Vehicle_Power_Weapon_Right_A"),
                        TweakDBID.new("Vehicle.Vehicle_Power_Weapon_Left_B"), TweakDBID.new("Vehicle.Vehicle_Power_Weapon_Right_B"),
                        TweakDBID.new("Vehicle.Vehicle_Power_Weapon_Left_C"), TweakDBID.new("Vehicle.Vehicle_Power_Weapon_Right_C"),
                        TweakDBID.new("Vehicle.Vehicle_Missile_Launcher_A"), TweakDBID.new("Vehicle.Vehicle_Missile_Launcher_B"), TweakDBID.new("Vehicle.Vehicle_Missile_Launcher_C")}

    -- Custom excalibur record
    TweakDB:CloneRecord(DAV.excalibur_record, "Vehicle.av_rayfield_excalibur")
    TweakDB:SetFlat(TweakDBID.new(DAV.excalibur_record .. ".entityTemplatePath"), "base\\dav\\excalibur\\av_rayfield_excalibur__basic_01_dav.ent")
    TweakDB:SetFlat(TweakDBID.new(DAV.excalibur_record .. ".player_audio_resource"), "v_av_basilisk_tank")
    TweakDB:CloneRecord("Vehicle.av_rayfield_excalibur_inline0_dav", "Vehicle.av_rayfield_excalibur_inline0")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.av_rayfield_excalibur_inline0_dav.exitDelay"), 2.3)
    TweakDB:SetFlat(TweakDBID.new(DAV.excalibur_record .. ".vehDataPackage"), "Vehicle.av_rayfield_excalibur_inline0_dav")

    -- Custom manticore record
    TweakDB:CloneRecord(DAV.manticore_record, "Vehicle.av_militech_manticore")
    TweakDB:SetFlat(TweakDBID.new(DAV.manticore_record .. ".entityTemplatePath"), "base\\dav\\manticore\\av_militech_manticore_basic_01_dav.ent")
    TweakDB:SetFlat(TweakDBID.new(DAV.manticore_record .. ".player_audio_resource"), "v_av_basilisk_tank")
    TweakDB:SetFlat(TweakDBID.new(DAV.manticore_record .. ".destroyedAppearance"), "burnt")
    TweakDB:SetFlat(TweakDBID.new(DAV.manticore_record .. ".isArmoredVehicle"), true)
    TweakDB:SetFlat(TweakDBID.new(DAV.manticore_record .. ".weapons"), weapon_list)
    TweakDB:CloneRecord("Vehicle.av_militech_manticore_inline0_dav", "Vehicle.av_militech_manticore_inline0")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.av_militech_manticore_inline0_dav.driverCombat"), "DriverCombatTypes.MountedWeapons")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.av_militech_manticore_inline0_dav.exitDelay"), 1.2)
    TweakDB:SetFlat(TweakDBID.new(DAV.manticore_record .. ".vehDataPackage"), "Vehicle.av_militech_manticore_inline0_dav")

    -- Custom atlus record
    TweakDB:CloneRecord(DAV.atlus_record, "Vehicle.av_zetatech_atlus")
    TweakDB:SetFlat(TweakDBID.new(DAV.atlus_record .. ".entityTemplatePath"), "base\\dav\\atlus\\av_zetatech_atlus_basic_02_dav.ent")
    TweakDB:SetFlat(TweakDBID.new(DAV.atlus_record .. ".player_audio_resource"), "v_av_basilisk_tank")
    TweakDB:SetFlat(TweakDBID.new(DAV.atlus_record .. ".isArmoredVehicle"), true)
    TweakDB:SetFlat(TweakDBID.new(DAV.atlus_record .. ".weapons"), weapon_list)
    TweakDB:CloneRecord("Vehicle.av_zetatech_atlus_inline0_dav", "Vehicle.av_zetatech_atlus_inline0")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.av_zetatech_atlus_inline0_dav.driverCombat"), "DriverCombatTypes.MountedWeapons")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.av_zetatech_atlus_inline0_dav.exitDelay"), 1.2)
    TweakDB:SetFlat(TweakDBID.new(DAV.atlus_record .. ".vehDataPackage"), "Vehicle.av_zetatech_atlus_inline0_dav")

     -- Custom surveyor record
    TweakDB:CloneRecord(DAV.surveyor_record, "Vehicle.av_zetatech_surveyor")
    TweakDB:SetFlat(TweakDBID.new(DAV.surveyor_record .. ".entityTemplatePath"), "base\\dav\\surveyor\\av_zetatech_surveyor_basic_01_ep1_dav.ent")
    TweakDB:SetFlat(TweakDBID.new(DAV.surveyor_record .. ".player_audio_resource"), "v_av_basilisk_tank")
    TweakDB:SetFlat(TweakDBID.new(DAV.surveyor_record .. ".isArmoredVehicle"), true)
    TweakDB:SetFlat(TweakDBID.new(DAV.surveyor_record .. ".weapons"), weapon_list)
    TweakDB:CloneRecord("Vehicle.av_zetatech_surveyor_inline0_dav", "Vehicle.av_zetatech_atlus_inline0")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.av_zetatech_surveyor_inline0_dav.driverCombat"), "DriverCombatTypes.MountedWeapons")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.av_zetatech_surveyor_inline0_dav.exitDelay"), 2.2)
    TweakDB:SetFlat(TweakDBID.new(DAV.surveyor_record .. ".vehDataPackage"), "Vehicle.av_zetatech_surveyor_inline0_dav")
    
    -- Custom valgus record
    TweakDB:CloneRecord(DAV.valgus_record, "Vehicle.q000_nomad_border_patrol_heli")
    TweakDB:SetFlat(TweakDBID.new(DAV.valgus_record .. ".entityTemplatePath"), "base\\dav\\valgus\\q000_border_patrol_heli_dav.ent")
    TweakDB:SetFlat(TweakDBID.new(DAV.valgus_record .. ".displayName"), LocKey(77966))
    TweakDB:SetFlat(TweakDBID.new(DAV.valgus_record .. ".manufacturer"), "Vehicle.Zetatech")
    TweakDB:SetFlat(TweakDBID.new(DAV.valgus_record .. ".player_audio_resource"), "v_av_basilisk_tank")
    TweakDB:SetFlat(TweakDBID.new(DAV.valgus_record .. ".destroyedAppearance"), "valgus_rusted")
    local valgus_tag_list = {CName.new("InteractiveTrunk")}
    TweakDB:SetFlat(TweakDBID.new(DAV.valgus_record .. ".tags"), valgus_tag_list)
    TweakDB:SetFlat(TweakDBID.new(DAV.valgus_record .. ".savable"), false)
    TweakDB:SetFlat(TweakDBID.new(DAV.valgus_record .. ".isHackable"), "Vehicle.Never")
    TweakDB:CloneRecord("Vehicle.av_zetatech_valgus_inline0_dav", "Vehicle.av_zetatech_valgus_inline0")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.av_zetatech_valgus_inline0_dav.exitDelay"), 0.8)
    TweakDB:SetFlat(TweakDBID.new(DAV.valgus_record .. ".vehDataPackage"), "Vehicle.av_zetatech_valgus_inline0_dav")

    -- Custom mayhem record
    TweakDB:CloneRecord(DAV.mayhem_record, "Vehicle.q000_nomad_border_patrol_heli")
    TweakDB:SetFlat(TweakDBID.new(DAV.mayhem_record .. ".entityTemplatePath"), "base\\dav\\mayhem\\q000_border_patrol_heli_mayhem_dav.ent")
    TweakDB:SetFlat(TweakDBID.new(DAV.mayhem_record .. ".displayName"), LocKey(88814))
    TweakDB:SetFlat(TweakDBID.new(DAV.mayhem_record .. ".manufacturer"), "Vehicle.Militech")
    TweakDB:SetFlat(TweakDBID.new(DAV.mayhem_record .. ".player_audio_resource"), "v_av_basilisk_tank")
    TweakDB:SetFlat(TweakDBID.new(DAV.mayhem_record .. ".destroyedAppearance"), "valgus_rusted")
    TweakDB:SetFlat(TweakDBID.new(DAV.mayhem_record .. ".tags"), valgus_tag_list)
    TweakDB:SetFlat(TweakDBID.new(DAV.mayhem_record .. ".savable"), false)
    TweakDB:SetFlat(TweakDBID.new(DAV.mayhem_record .. ".isHackable"), "Vehicle.Never")
    TweakDB:SetFlat(TweakDBID.new(DAV.mayhem_record .. ".isArmoredVehicle"), true)
    TweakDB:SetFlat(TweakDBID.new(DAV.mayhem_record .. ".weapons"), weapon_list)
    TweakDB:CloneRecord("Vehicle.av_zetatech_mayhem_inline0_dav", "Vehicle.av_zetatech_valgus_inline0")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.av_zetatech_mayhem_inline0_dav.driverCombat"), "DriverCombatTypes.MountedWeapons")
    TweakDB:SetFlat(TweakDBID.new("Vehicle.av_zetatech_mayhem_inline0_dav.exitDelay"), 0.8)
    TweakDB:SetFlat(TweakDBID.new(DAV.mayhem_record .. ".vehDataPackage"), "Vehicle.av_zetatech_mayhem_inline0_dav")

end)

registerForEvent("onHook", function()

    -- refer to Kiroshi Night Vision (https://www.nexusmods.com/cyberpunk2077/mods/8326)
    DAV.input_key_listener = NewProxy({
        OnKeyInput = {
            args = {'handle:KeyInputEvent'},
            callback = function(event)
                local key = event:GetKey().value
                local action = event:GetAction().value
                if key:find("IK_Pad") then
                    DAV.is_keyboard_input = false
                else
                    DAV.is_keyboard_input = true
                end
                if DAV.listening_keybind_widget and key:find("IK_Pad") and action == "IACT_Release" then -- OnKeyBindingEvent has to be called manually for gamepad inputs, while there is a keybind widget listening for input
                    DAV.listening_keybind_widget:OnKeyBindingEvent(KeyBindingEvent.new({keyName = key}))
                    DAV.listening_keybind_widget = nil
                elseif DAV.listening_keybind_widget and action == "IACT_Release" then -- Key was bound, by keyboard
                    DAV.listening_keybind_widget = nil
                end
                local current_situation = Def.Situation.Idle
                if DAV.core_obj ~= nil then
                    current_situation = DAV.core_obj.event_obj.current_situation or Def.Situation.Idle
                end
                if current_situation == Def.Situation.InVehicle or current_situation == Def.Situation.Waiting or current_situation == Def.Situation.Normal then
                    if action == "IACT_Press" then
                        DAV.core_obj:ConvertPressButtonAction(key)
                    elseif action == "IACT_Release" then
                        DAV.core_obj:ConvertHoldButtonAction(key)
                    end
                end
            end
        }
    })
    Game.GetCallbackSystem():RegisterCallback('Input/Key', DAV.input_key_listener:Target(), DAV.input_key_listener:Function("OnKeyInput"), true)

    Observe("SettingsSelectorControllerKeyBinding", "ListenForInput", function(this)
        DAV.listening_keybind_widget = this
    end)

    DAV.input_axis_listener = NewProxy({
        OnAxisInput = {
            args = {'handle:AxisInputEvent'},
            callback = function(event)
                local key = event:GetKey().value
                local value = event:GetValue()
                if key:find("IK_Pad") and math.abs(value) > DAV.axis_dead_zone then
                    DAV.is_keyboard_input = false
                else
                    DAV.is_keyboard_input = true
                end
            end
        }
    })
    Game.GetCallbackSystem():RegisterCallback('Input/Axis', DAV.input_axis_listener:Target(), DAV.input_axis_listener:Function("OnAxisInput"), true)

end)

registerForEvent('onInit', function()

    if not DAV:CheckDependencies() then
        print('[DAV][Error] Drive an Aerial Vehicle Mod failed to load due to missing dependencies.')
        return
    end

    DAV:CheckNativeSettings()

    DAV.core_obj = Core:New()
    DAV.debug_obj = Debug:New(DAV.core_obj)

    DAV.core_obj:Init()

    DAV.is_ready = true

    print('[DAV][Info] Finished initializing Drive an Aerial Vehicle Mod.')

end)

registerForEvent("onDraw", function()
    if DAV.is_debug_mode then
        DAV.debug_obj:ImGuiMain()
    end
end)

registerForEvent('onUpdate', function(delta)
    Cron.Update(delta)
end)

registerForEvent('onShutdown', function()
    Game.GetCallbackSystem():UnregisterCallback('Input/Key', DAV.input_key_listener:Target(), DAV.input_key_listener:Function("OnKeyInput"))
    Game.GetCallbackSystem():UnregisterCallback('Input/Axis', DAV.input_axis_listener:Target(), DAV.input_axis_listener:Function("OnAxisInput"))
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
        print("[DAV][Error] requires Cyber Engine Tweaks version 1." .. DAV.cet_required_version .. " or higher.")
        return false
    elseif DAV.codeware_version_num < DAV.codeware_required_version then
        print("[DAV][Error] requires CodeWare version 1." .. DAV.codeware_required_version .. " or higher.")
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
        print("[DAV][Error] requires Native Settings version " .. DAV.native_settings_required_version .. " or higher.")
        return
    end
    DAV.is_valid_native_settings = true

end

function DAV:Version()
    return DAV.version
end

return DAV