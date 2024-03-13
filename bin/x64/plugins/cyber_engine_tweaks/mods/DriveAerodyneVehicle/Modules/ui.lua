local Log = require("Tools/log.lua")
local Ui = {}
Ui.__index = Ui

function Ui:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Ui")

    obj.dummy_vehicle = "Vehicle.av_dav_dummy"

    -- set default value
    obj.dummy_vehicle_record_hash = nil
    obj.is_vehicle_call = false

    return setmetatable(obj, self)
end

function Ui:Init()
    self:SetTweekDB()
    self:SetOverrideFunc()
end

function Ui:SetTweekDB()

    TweakDB:CloneRecord("UIIcon.dav_av_rayfield_logos", "UIIcon.quadra_type66__bulleat")
    TweakDB:SetFlat(TweakDBID.new("UIIcon.dav_av_rayfield_logos.atlasPartName"), "rayfield")
    TweakDB:SetFlat(TweakDBID.new("UIIcon.dav_av_rayfield_logos.atlasResourcePath"), "base\\gameplay\\gui\\common\\icons\\weapon_manufacturers.inkatlas")

    TweakDB:CloneRecord(self.dummy_vehicle, "Vehicle.v_sport2_quadra_type66_02_player")
    TweakDB:SetFlat(TweakDBID.new(self.dummy_vehicle .. ".entityTemplatePath"), "base\\vehicles\\special\\av_dav_dummy_99.ent")
    TweakDB:SetFlat(TweakDBID.new(self.dummy_vehicle .. ".displayName"), LocKey(77051))
    TweakDB:SetFlat(TweakDBID.new(self.dummy_vehicle .. ".icon"), "UIIcon.dav_av_rayfield_logos")
    TweakDB:SetFlat(TweakDBID.new(self.dummy_vehicle .. ".model"), "Vehicle.RayfieldExcalibur")

    local vehicle_list = TweakDB:GetFlat(TweakDBID.new('Vehicle.vehicle_list.list'))
    table.insert(vehicle_list, TweakDBID.new(self.dummy_vehicle))
    TweakDB:SetFlat(TweakDBID.new('Vehicle.vehicle_list.list'), vehicle_list)
    self.dummy_vehicle_record_hash = TweakDBID.new(self.dummy_vehicle).hash

end

function Ui:SetOverrideFunc()
    Override("VehicleSystem", "SpawnPlayerVehicle", function(self, arg_1, wrapped_method)

        local record_hash = self:GetActivePlayerVehicle().recordID.hash

        if record_hash == self.dummy_vehicle_record_hash then
            self.log_obj:record(LogLevel.Trace, "Vehicle call detected")
            self.is_vehicle_call = true
            return true
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
    Game.GetVehicleSystem():EnablePlayerVehicle(self.dummy_vehicle, is_avtive, false)
end

function Ui:GetCallStatus()
    local call_status = self.is_vehicle_call
    self.is_vehicle_call = false
    return call_status
end

return Ui