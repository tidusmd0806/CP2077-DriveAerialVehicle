-- local Log = require("Tools/log.lua")
local GameUI = require('External/GameUI.lua')
local Hud = require("Modules/hud.lua")
local Sound = require("Modules/sound.lua")
local Ui = require("Modules/ui.lua")
local Event = {}
Event.__index = Event

function Event:New()

    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Event")
    obj.av_obj = nil
    obj.hud_obj = Hud:New()
    obj.ui_obj = Ui:New()
    obj.sound_obj = Sound:New()

    -- set default parameters
    obj.is_initial_load = false
    obj.current_situation = Def.Situation.Idel
    obj.is_unlocked_dummy_av = false
    obj.is_in_menu = false
    obj.is_in_popup = false
    obj.is_in_photo = false
    obj.is_locked_operation = false
    obj.selected_seat_index = 1

    return setmetatable(obj, self)

end

function Event:Init(av_obj)

    self.av_obj = av_obj

    self.ui_obj:Init(self.av_obj)
    self.hud_obj:Init(self.av_obj)
    self.sound_obj:Init(self.av_obj)

    if not DAV.is_ready then
        self:SetObserve()
        self:SetOverride()
    end

end

function Event:SetObserve()

    GameUI.Observe("MenuOpen", function()
        self.is_in_menu = true
    end)

    GameUI.Observe("MenuClose", function()
        self.is_in_menu = false
    end)

    GameUI.Observe("PopupOpen", function()
        self.is_in_popup = true
    end)

    GameUI.Observe("PopupClose", function()
        self.is_in_popup = false
    end)

    GameUI.Observe("PhotoModeOpen", function()
        self.is_in_photo = true
    end)

    GameUI.Observe("PhotoModeClose", function()
        self.is_in_photo = false
    end)

    GameUI.Observe("SessionStart", function()

        if not self.is_initial_load then
            self.log_obj:Record(LogLevel.Info, "Initial Session start detected")
            self.is_initial_load = true
        else
            self.log_obj:Record(LogLevel.Info, "Session start detected")
            DAV.core_obj:Reset()
        end

        DAV.core_obj:SetFastTravelPosition()

        self.is_unlocked_dummy_av = Game.GetVehicleSystem():IsVehiclePlayerUnlocked(TweakDBID.new(self.ui_obj.dummy_vehicle_record))
        self.current_situation = Def.Situation.Normal

    end)

    GameUI.Observe("SessionEnd", function()
        self.log_obj:Record(LogLevel.Info, "Session end detected")
        self.current_situation = Def.Situation.Idel
    end)
end

function Event:SetOverride()
    Override("OpenVendorUI", "CreateInteraction", function(this, arg_1, arg_2, arg_3, wrapped_method)
        if this:GetActionName().value == "vehicle_door_quest_locked" and self:IsInEntryArea() then
            self.log_obj:Record(LogLevel.Trace, "Disappear vehicle door quest locked")
            return
        end
        wrapped_method(arg_1, arg_2, arg_3)
    end)
end

function Event:SetSituation(situation)
    if self.current_situation == Def.Situation.Idel then
        return false
    elseif self.current_situation == Def.Situation.Normal and situation == Def.Situation.Landing then
        self.log_obj:Record(LogLevel.Info, "Landing detected")
        self.current_situation = Def.Situation.Landing
        return true
    elseif self.current_situation == Def.Situation.Landing and situation == Def.Situation.Waiting then
        self.log_obj:Record(LogLevel.Info, "Waiting detected")
        self.current_situation = Def.Situation.Waiting
        return true
    elseif (self.current_situation == Def.Situation.Waiting and situation == Def.Situation.InVehicle) then
        self.log_obj:Record(LogLevel.Info, "InVehicle detected")
        self.current_situation = Def.Situation.InVehicle
        return true
    elseif (self.current_situation == Def.Situation.Waiting and situation == Def.Situation.TalkingOff) then
        self.log_obj:Record(LogLevel.Info, "TalkingOff detected")
        self.current_situation = Def.Situation.TalkingOff
        return true
    elseif (self.current_situation == Def.Situation.InVehicle and situation == Def.Situation.Waiting) then
        self.log_obj:Record(LogLevel.Info, "Waiting detected")
        self.current_situation = Def.Situation.Waiting
        return true
    elseif (self.current_situation == Def.Situation.TalkingOff and situation == Def.Situation.Normal) then
        self.log_obj:Record(LogLevel.Info, "Normal detected")
        self.current_situation = Def.Situation.Normal
        return true
    elseif situation == Def.Situation.Normal then
        self.log_obj:Record(LogLevel.Warning, "Force Reset to Normal situation")
        self.current_situation = Def.Situation.Normal
        return true
    else
        self.log_obj:Record(LogLevel.Critical, "Invalid translating situation")
        return false
    end
end

function Event:CheckAllEvents()

    if self.current_situation == Def.Situation.Normal then
        self:CheckCallPurchasedVehicle()
        self:CheckGarage()
    elseif self.current_situation == Def.Situation.Landing then
        self:CheckLanded()
    elseif self.current_situation == Def.Situation.Waiting then
        self:CheckDespawn()
        self:CheckInEntryArea()
        self:CheckInAV()
        self:CheckReturnPurchasedVehicle()
        self:CheckDestroyed()
        self:CheckDoor()
    elseif self.current_situation == Def.Situation.InVehicle then
        self:CheckInAV()
        self:CheckAutoModeChange()
        self:CheckFailAutoPilot()
        self:CheckCustomMappinPosition()
        self:CheckHUD()
        self:CheckDestroyed()
    elseif self.current_situation == Def.Situation.TalkingOff then
        self:CheckDespawn()
        self:CheckLockedSave()
    end

end


function Event:CheckGarage()
    DAV.core_obj:UpdateGarageInfo(false)
end

function Event:CheckCallPurchasedVehicle()
    if DAV.core_obj:GetPurchasedCallStatus() and not self.av_obj:IsSpawning() then
        self.log_obj:Record(LogLevel.Trace, "Purchased vehicle call detected")
        self.sound_obj:PlaySound("100_call_vehicle")
        self.sound_obj:PlaySound("210_landing")
        self:SetSituation(Def.Situation.Landing)
        self.av_obj:SpawnToSky()
    end
end

function Event:CheckLanded()
    if self.av_obj.position_obj:IsCollision() or self.av_obj.is_landed then
        self.log_obj:Record(LogLevel.Trace, "Landed detected")
        self.sound_obj:StopSound("210_landing")
        self.sound_obj:PlaySound("110_arrive_vehicle")
        self.sound_obj:ChangeSoundResource()
        self:SetSituation(Def.Situation.Waiting)
        -- self.av_obj:ChangeDoorState(Def.DoorOperation.Open)
    end
end

function Event:CheckInEntryArea()
    if self.av_obj.position_obj:IsPlayerInEntryArea() then
        self.log_obj:Record(LogLevel.Trace, "InEntryArea detected")
        self.hud_obj:ShowChoice(self.selected_seat_index)
    else
        self.hud_obj:HideChoice()
    end
end

function Event:CheckInAV()
    if self.av_obj:IsPlayerIn() then
        -- when player take on AV
        if self.current_situation == Def.Situation.Waiting then
            self.log_obj:Record(LogLevel.Info, "Enter In AV")
            SaveLocksManager.RequestSaveLockAdd(CName.new("DAV_IN_AV"))
            self:SetSituation(Def.Situation.InVehicle)
            self.hud_obj:HideChoice()
            self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
            self.hud_obj:ShowCustomHint()
            Cron.After(1.5, function()
                self.hud_obj:ShowLeftBottomHUD()
            end)
        end
    else
        -- when player take off from AV
        if self.current_situation == Def.Situation.InVehicle then
            self.log_obj:Record(LogLevel.Info, "Exit AV")
            self.hud_obj:HideLeftBottomHUD()
            self:SetSituation(Def.Situation.Waiting)
            self.hud_obj:HideCustomHint()
            self:UnsetMappin()
            SaveLocksManager.RequestSaveLockRemove(CName.new("DAV_IN_AV"))
        end
    end
end

function Event:CheckHUD()
    if self.hud_obj:IsVisibleConsumeItemSlot() then
        self.hud_obj:SetVisibleConsumeItemSlot(false)
    end
    -- if self.hud_obj:IsVisiblePhoneSlot() then
    --     self.hud_obj:SetVisiblePhoneSlot(false)
    -- end
    local success, result = pcall(function()
        -- always show car mete
        -- if not self.hud_obj.hud_car_controller.moduleShown thenr
        -- self.hud_obj.hud_car_controller:ShowRequest()
        -- self.hud_obj.hud_car_controller:OnCameraModeChanged(true)
        self.hud_obj:SetHPDisplay()
        -- end
     end)
     if not success then
        self.log_obj:Record(LogLevel.Critical, result)
     end
end

function Event:CheckDoor()

    local veh_door = EVehicleDoor.seat_front_left
    if self.av_obj.vehicle_model_tweakdb_id == DAV.surveyor_record then
        veh_door = EVehicleDoor.trunk
    end

    if self:IsInEntryArea() then
        if self.av_obj:GetDoorState(veh_door) == VehicleDoorState.Closed then
            self.av_obj:ChangeDoorState(Def.DoorOperation.Open)
        end
    else
        if self.av_obj:GetDoorState(veh_door) == VehicleDoorState.Open then
            self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
        end
    end

end

function Event:CheckDestroyed()
    if self.av_obj:IsDestroyed() then
        self.log_obj:Record(LogLevel.Trace, "Destroyed detected")
        self.sound_obj:ResetSoundResource()
        self.hud_obj:HideChoice()
        self.av_obj.engine_obj.fly_av_system:EnableGravity(true)
        self:SetSituation(Def.Situation.Normal)
        DAV.core_obj:Reset()
    end
end

function Event:CheckReturnPurchasedVehicle()
    if DAV.core_obj:GetPurchasedCallStatus() then
        self.log_obj:Record(LogLevel.Trace, "Purchased vehicle return detected")
        self.sound_obj:PlaySound("240_leaving")
        self.sound_obj:PlaySound("104_call_vehicle")
        self.sound_obj:ResetSoundResource()
        self:SetSituation(Def.Situation.TalkingOff)
        self.hud_obj:HideChoice()
        self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
        self.av_obj:DespawnFromGround()
    end
end

function Event:CheckDespawn()
    if self.av_obj:IsDespawned() then
        self.log_obj:Record(LogLevel.Trace, "Despawn detected")
        self.sound_obj:StopSound("240_leaving")
        self:SetSituation(Def.Situation.Normal)
        DAV.core_obj:Reset()
    end
end

function Event:CheckAutoModeChange()
    if self:IsAutoMode() and not self.is_locked_operation then
        self.is_locked_operation = true
    elseif not self:IsAutoMode() and self.is_locked_operation then
        self.is_locked_operation = false
        self.hud_obj:ShowArrivalDisplay()
    end

end

function Event:CheckFailAutoPilot()
    if self.av_obj:IsFailedAutoPilot() then
        self.hud_obj:ShowInterruptAutoPilotDisplay()
    end
end

function Event:CheckCustomMappinPosition()

    if self.av_obj.is_auto_pilot then
        return
    end
    local success, mappin = pcall(function() return DAV.core_obj.mappin_controller:GetMappin() end)
    if not success then
        self.log_obj:Record(LogLevel.Debug, "Mappin is not found")
        DAV.core_obj.is_custom_mappin = false
        if self.stored_mappin_pos == nil then
            return
        end
    else
        DAV.core_obj.is_custom_mappin = true
    end
    local mappin_pos = mappin:GetWorldPosition()
    if Vector4.Distance(DAV.core_obj.current_custom_mappin_position, mappin_pos) ~= 0 then
        DAV.core_obj:SetCustomMappin(mappin)
    end

end

function Event:CheckLockedSave()
    local res, reason = Game.IsSavingLocked()
    if res then
        self.log_obj:Record(LogLevel.Info, "Locked save detected. Remove lock")
        SaveLocksManager.RequestSaveLockRemove(CName.new("DAV_IN_AV"))
    end

end

function Event:UnsetMappin()
    DAV.core_obj.is_custom_mappin = false
    DAV.core_obj:RemoveFavoriteMappin()
end

function Event:IsNotSpawned()
    if self.current_situation == Def.Situation.Normal then
        return true
    else
        return false
    end
end

function Event:IsWaiting()
    if self.current_situation == Def.Situation.Waiting then
        return true
    else
        return false
    end
end

function Event:IsInEntryArea()
    if self.current_situation == Def.Situation.Waiting and self.av_obj.position_obj:IsPlayerInEntryArea() then
        return true
    else
        return false

    end
end

function Event:IsInVehicle()
    if self.current_situation == Def.Situation.InVehicle and self.av_obj:IsPlayerIn() then
        return true
    else
        return false
    end
end

function Event:IsTakingOff()
    if self.current_situation == Def.Situation.TalkingOff then
        return true
    else
        return false
    end
end

function Event:IsAutoMode()
    if self.av_obj.is_auto_pilot then
        return true
    else
        return false
    end
end

function Event:IsInMenuOrPopupOrPhoto()
    if self.is_in_menu or self.is_in_popup or self.is_in_photo then
        return true
    else
        return false
    end
end

function Event:IsAllowedEntry()
    return self.is_allowed_entry
end

function Event:ChangeDoor()
    if self.current_situation == Def.Situation.InVehicle then
        self.av_obj:ChangeDoorState(Def.DoorOperation.Change)
    end
end

function Event:EnterVehicle()
    if self:IsInEntryArea()then
        self.av_obj:Mount()
    end
end

function Event:ExitVehicle()
    if self:IsInVehicle() then
        self.av_obj:Unmount()
    end
end

function Event:ToggleAutoMode()
    if self:IsInVehicle() then
        if not self.av_obj.is_auto_pilot then
            self.hud_obj:ShowAutoModeDisplay()
            self.is_locked_operation = true
            self.av_obj:AutoPilot()
        elseif not self.av_obj.is_leaving then
            self.hud_obj:ShowDriveModeDisplay()
            self.is_locked_operation = false
            self.av_obj:InterruptAutoPilot()
        end
    end
end

function Event:ShowRadioPopup()
    if self:IsInVehicle() then
        self.hud_obj:ShowRadioPopup()
    end
end

function Event:SelectChoice(direction)
    local max_seat_index = #self.av_obj.all_models[DAV.model_index].actual_allocated_seat
    if self:IsInEntryArea() then
        if direction == Def.ActionList.SelectUp then
            self.selected_seat_index = self.selected_seat_index - 1
            if self.selected_seat_index < 1 then
                self.selected_seat_index = max_seat_index

            end
        elseif direction == Def.ActionList.SelectDown then
            self.selected_seat_index = self.selected_seat_index + 1
            if self.selected_seat_index > max_seat_index then
                self.selected_seat_index = 1
            end
        else
            self.log_obj:Record(LogLevel.Critical, "Invalid direction detected")
            return
        end
        self.av_obj.seat_index = self.selected_seat_index
    end
end

return Event
