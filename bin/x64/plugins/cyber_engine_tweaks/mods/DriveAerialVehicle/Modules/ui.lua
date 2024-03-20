local Log = require("Tools/log.lua")
local GameUI = require('External/GameUI.lua')
local Ui = {}
Ui.__index = Ui

function Ui:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Ui")

    obj.dummy_vehicle_record = "Vehicle.av_dav_dummy"
    obj.dummy_vehicle_record_path = "base\\vehicles\\special\\av_dav_dummy_99.ent"
    obj.dummy_logo_record = "UIIcon.av_davr_logo"

    -- set default value
    obj.dummy_vehicle_record_hash = nil
    obj.is_vehicle_call = false

    return setmetatable(obj, self)
end

function Ui:Init(display_name_lockey, logo_inkatlas_path, logo_inkatlas_part_name)
    self:SetTweekDB(display_name_lockey, logo_inkatlas_path, logo_inkatlas_part_name)
    self:SetOverride()

    GameUI.Observe("SessionStart", function()
        DAV.Cron.After(1, function()
            self:ActivateAVSummon(true)
        end)
    end)

    GameUI.Observe("SessionEnd", function()
        self:ActivateAVSummon(false)
    end)
end

function Ui:SetTweekDB(display_name_lockey, logo_inkatlas_path, logo_inkatlas_part_name)
    local lockey = display_name_lockey or "Story-base-gameplay-gui-quests-q103-q103_rogue-_localizationString47"

    TweakDB:CloneRecord(self.dummy_logo_record, "UIIcon.quadra_type66__bulleat")
    TweakDB:SetFlat(TweakDBID.new(self.dummy_logo_record .. ".atlasPartName"), logo_inkatlas_part_name)
    TweakDB:SetFlat(TweakDBID.new(self.dummy_logo_record .. ".atlasResourcePath"), logo_inkatlas_path)

    TweakDB:CloneRecord(self.dummy_vehicle_record, "Vehicle.v_sport2_quadra_type66_02_player")
    TweakDB:SetFlat(TweakDBID.new(self.dummy_vehicle_record .. ".entityTemplatePath"), self.dummy_vehicle_record)
    TweakDB:SetFlat(TweakDBID.new(self.dummy_vehicle_record .. ".displayName"), LocKey(lockey))
    TweakDB:SetFlat(TweakDBID.new(self.dummy_vehicle_record .. ".icon"), self.dummy_logo_record)

    local vehicle_list = TweakDB:GetFlat(TweakDBID.new('Vehicle.vehicle_list.list'))
    table.insert(vehicle_list, TweakDBID.new(self.dummy_vehicle_record))
    TweakDB:SetFlat(TweakDBID.new('Vehicle.vehicle_list.list'), vehicle_list)

    self.dummy_vehicle_record_hash = TweakDBID.new(self.dummy_vehicle_record).hash
end

function Ui:SetOverride()
    Override("VehicleSystem", "SpawnPlayerVehicle", function(this, arg_1, wrapped_method)

        local record_hash = this:GetActivePlayerVehicle().recordID.hash

        if record_hash == self.dummy_vehicle_record_hash then
            self.log_obj:Record(LogLevel.Trace, "Vehicle call detected")        
            self.is_vehicle_call = true
            return false
        else
            local res = false
            if arg_1 == nil then
                res = wrapped_method()
            else
                res = wrapped_method(arg_1)
            end
            self.is_vehicle_call = false
            return res
        end
    end)
end

function Ui:ActivateAVSummon(is_avtive)
    Game.GetVehicleSystem():EnablePlayerVehicle(self.dummy_vehicle_record, is_avtive, true)
end

function Ui:GetCallStatus()
    local call_status = self.is_vehicle_call
    self.is_vehicle_call = false
    return call_status
end

return Ui