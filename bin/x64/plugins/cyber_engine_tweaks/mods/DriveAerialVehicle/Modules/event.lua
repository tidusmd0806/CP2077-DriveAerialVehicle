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
    else
        self.log_obj:Record(LogLevel.Critical, "Invalid translating situation")
        return false
    end
end

function Event:CheckAllEvents()
    if self.current_situation == Def.Situation.Normal then
        self:CheckCallPurchasedVehicle()
        self:CheckCallVehicle()
        self:CheckGarage()
        self:CheckAvailableFreeCall()
    elseif self.current_situation == Def.Situation.Landing then
        self:CheckLanded()
    elseif self.current_situation == Def.Situation.Waiting then
        self:CheckInEntryArea()
        self:CheckInAV()
        self:CheckReturnPurchasedVehicle()
        self:CheckReturnVehicle()
    elseif self.current_situation == Def.Situation.InVehicle then
        self:CheckInAV()
        self:CheckCollision()
        self:CheckAutoModeChange()
        self:CheckFailAutoPilot()
    elseif self.current_situation == Def.Situation.TalkingOff then
        self:CheckDespawn()
    end
end

function Event:CheckGarage()
    DAV.core_obj:UpdateGarageInfo(false)
end

function Event:CheckAvailableFreeCall()

    if self:IsAvailableFreeCall() and not self.is_unlocked_dummy_av then
        self.log_obj:Record(LogLevel.Info, "Unlock dummy vehicle for free call")
        self.is_unlocked_dummy_av = true
        DAV.core_obj:ActivateDummySummon(true)
    elseif not self:IsAvailableFreeCall() and self.is_unlocked_dummy_av then
        self.log_obj:Record(LogLevel.Info, "Lock dummy vehicle for free call")
        self.is_unlocked_dummy_av = false
        DAV.core_obj:ActivateDummySummon(false)
    end
end

function Event:CheckCallVehicle()
    if DAV.core_obj:GetCallStatus() and not self.av_obj:IsSpawning() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle call detected")
        self.sound_obj:PlaySound("101_call_vehicle")
        self.sound_obj:PlaySound("211_landing")
        self:SetSituation(Def.Situation.Landing)
        self.av_obj:SpawnToSky()
    end
end

function Event:CheckCallPurchasedVehicle()
    if DAV.core_obj:GetPurchasedCallStatus() and not self.av_obj:IsSpawning() then
        self.log_obj:Record(LogLevel.Trace, "Purchased vehicle call detected")
        self.sound_obj:PlaySound("101_call_vehicle")
        self.sound_obj:PlaySound("211_landing")
        self:SetSituation(Def.Situation.Landing)
        self.av_obj:SpawnToSky()
    end
end

function Event:CheckLanded()
    if self.av_obj.position_obj:IsCollision() or self.av_obj.is_landed then
        self.log_obj:Record(LogLevel.Trace, "Landed detected")
        self.sound_obj:StopSound("211_landing")
        self.sound_obj:PlaySound("131_arrive_vehicle")
        self:SetSituation(Def.Situation.Waiting)
        self.av_obj:ChangeDoorState(Def.DoorOperation.Open)
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
            self.sound_obj:PlaySound("232_fly_loop")
            self:SetSituation(Def.Situation.InVehicle)
            self.hud_obj:HideChoice()
            self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
            self.hud_obj:ShowMeter()
            self.hud_obj:ShowCustomHint()
            self.hud_obj:HideActionButtons()
        end
    else
        -- when player take off from AV
        if self.current_situation == Def.Situation.InVehicle then
            self.log_obj:Record(LogLevel.Info, "Exit AV")
            self.sound_obj:StopSound("232_fly_loop")
            self:SetSituation(Def.Situation.Waiting)
            self.hud_obj:HideMeter()
            self.hud_obj:HideCustomHint()
            self.hud_obj:ShowActionButtons()
            SaveLocksManager.RequestSaveLockRemove(CName.new("DAV_IN_AV"))
        end
    end
end

function Event:CheckCollision()
    if self.av_obj.is_collision then
        self.log_obj:Record(LogLevel.Debug, "Collision detected")
        if not self.av_obj.engine_obj:IsInFalling() then
            self.sound_obj:PlaySound("233_crash")
        end
    end
end

function Event:CheckReturnVehicle()
    if DAV.core_obj:GetCallStatus() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle return detected")
        self.sound_obj:PlaySound("243_leaving")
        self.sound_obj:PlaySound("104_call_vehicle")
        self:SetSituation(Def.Situation.TalkingOff)
        self.hud_obj:HideChoice()
        self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
        self.av_obj:DespawnFromGround()
    end
end

function Event:CheckReturnPurchasedVehicle()
    if DAV.core_obj:GetPurchasedCallStatus() then
        self.log_obj:Record(LogLevel.Trace, "Purchased vehicle return detected")
        self.sound_obj:PlaySound("243_leaving")
        self.sound_obj:PlaySound("104_call_vehicle")
        self:SetSituation(Def.Situation.TalkingOff)
        self.hud_obj:HideChoice()
        self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
        self.av_obj:DespawnFromGround()
    end
end

function Event:CheckDespawn()
    if self.av_obj:IsDespawned() then
        self.log_obj:Record(LogLevel.Trace, "Despawn detected")
        self.sound_obj:StopSound("243_leaving")
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

function Event:IsAvailableFreeCall()
    return DAV.is_free_summon_mode
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
