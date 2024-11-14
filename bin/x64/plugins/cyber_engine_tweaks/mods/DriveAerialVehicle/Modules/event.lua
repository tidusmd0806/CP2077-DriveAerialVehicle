-- local Log = require("Tools/log.lua")
local GameUI = require('External/GameUI.lua')
local Hud = require("Modules/hud.lua")
local Sound = require("Modules/sound.lua")
local UI = require("Modules/ui.lua")
local Event = {}
Event.__index = Event

function Event:New()
    -- instance --
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Event")
    obj.av_obj = nil
    obj.hud_obj = Hud:New()
    obj.ui_obj = UI:New()
    obj.sound_obj = Sound:New()

    -- static --
    -- distance limit
    obj.distance_limit = 80
    obj.engine_audio_limit = 40
    -- projection
    obj.projection_max_height_offset = 4
    -- dynamic --
    obj.is_initial_load = false
    obj.current_situation = Def.Situation.Idle
    obj.is_in_menu = false
    obj.is_in_popup = false
    obj.is_in_photo = false
    obj.is_locked_operation = false
    obj.selected_seat_index = 1
    obj.is_keyboard_input_prev = false
    obj.is_enable_audio = true
    -- projection
    obj.is_landing_projection = false

    return setmetatable(obj, self)

end

function Event:Init(av_obj)

    self.av_obj = av_obj

    self.ui_obj:Init(self.av_obj)
    self.hud_obj:Init(self.av_obj)
    self.sound_obj:Init(self.av_obj)

    self.is_enable_audio = true

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
        self.current_situation = Def.Situation.Normal

    end)

    GameUI.Observe("SessionEnd", function()
        self.log_obj:Record(LogLevel.Info, "Session end detected")
        self.current_situation = Def.Situation.Idle
    end)

end

function Event:SetOverride()

    Override("VehicleComponentPS", "GetHasAnyDoorOpen", function(this, wrapped_method)
        if self:IsInVehicle() then
            return false
        else
            return wrapped_method()
        end
    end)

    Override("VehicleTransition", "IsUnmountDirectionClosest", function(this, state_context, unmount_direction, wrapped_method)
        if self:IsInVehicle() and not Game.GetPlayer():PSIsInDriverCombat() then
            self.av_obj:Unmount()
            return true
        else
            return wrapped_method(state_context, unmount_direction)
        end
    end)

    Override("VehicleTransition", "IsUnmountDirectionOpposite", function(this, state_context, unmount_direction, wrapped_method)
        if self:IsInVehicle() and not Game.GetPlayer():PSIsInDriverCombat() then
            return false
        else
            return wrapped_method(state_context, unmount_direction)
        end
    end)

end

function Event:SetSituation(situation)
    if self.current_situation == Def.Situation.Idle then
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
        self:CheckGarage()
    elseif self.current_situation == Def.Situation.Landing then
        self:CheckLanded()
        self:CheckHeight()
    elseif self.current_situation == Def.Situation.Waiting then
        self:CheckDespawn()
        self:CheckInEntryArea()
        self:CheckInAV()
        self:CheckDestroyed()
        self:CheckDistance()
        self:CheckHeight()
        self:CheckDoor()
    elseif self.current_situation == Def.Situation.InVehicle then
        self:CheckInAV()
        self:CheckAutoModeChange()
        self:CheckFailAutoPilot()
        self:CheckHUD()
        self:CheckDestroyed()
        self:CheckInput()
        self:CheckCombat()
        self:CheckHeight()
    elseif self.current_situation == Def.Situation.TalkingOff then
        self:CheckDespawn()
        self:CheckLockedSave()
        self:CheckHeight()
    end

end

function Event:CheckGarage()
    DAV.core_obj:UpdateGarageInfo(false)
end

function Event:CallVehicle()
    if self:IsNotSpawned() then
        self:SpawnVehicle()
    elseif self:IsWaiting() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle call detected in Waiting situation")
        self.av_obj:Despawn()
        DAV.core_obj:Reset()
        Cron.After(1.0, function()
            self:SpawnVehicle()
        end)
    end
end

function Event:SpawnVehicle()

    self.sound_obj:PlaySound("100_call_vehicle")
    self.sound_obj:PlaySound("210_landing")
    self.sound_obj:PlaySound(self.av_obj.engine_audio_name)
    self:SetSituation(Def.Situation.Landing)
    self.av_obj:SpawnToSky()

end

function Event:ReturnVehicle(is_leaving_sound)
    if self:IsWaiting() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle return detected in Waiting situation")
        if is_leaving_sound then
            self.sound_obj:PlaySound("240_leaving")
        end
        self.sound_obj:PlaySound("104_call_vehicle")
        self.sound_obj:ResetSoundResource()
        self:SetSituation(Def.Situation.TalkingOff)
        self.hud_obj:HideChoice()
        self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
        self.av_obj:DespawnFromGround()
    end
end

function Event:CheckLanded()
    if self.av_obj.position_obj:IsCollision() or self.av_obj.is_landed then
        self.log_obj:Record(LogLevel.Trace, "Landed detected")
        self.sound_obj:StopSound("210_landing")
        self.sound_obj:PlaySound("110_arrive_vehicle")
        self.sound_obj:ChangeSoundResource()
        self:SetSituation(Def.Situation.Waiting)
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
            self.hud_obj:ShowCustomHint()
            self.hud_obj:EnableManualMeter(false, self.av_obj.is_enable_manual_rpm_meter)
            self.is_keyboard_input_prev = DAV.is_keyboard_input
            Cron.After(1.5, function()
                self.hud_obj:ForceShowMeter()
                self.hud_obj:ShowLeftBottomHUD()
                self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
            end)
        end
    else
        -- when player take off from AV
        if self.current_situation == Def.Situation.InVehicle then
            self.log_obj:Record(LogLevel.Info, "Exit AV")
            self.hud_obj:HideLeftBottomHUD()
            self:SetSituation(Def.Situation.Waiting)
            self.hud_obj:HideCustomHint()
            self.hud_obj:EnableManualMeter(false, false)
            if self:IsAutoMode() then
                self.av_obj:InterruptAutoPilot()
            end
            SaveLocksManager.RequestSaveLockRemove(CName.new("DAV_IN_AV"))
        end
    end
end

function Event:CheckHUD()

    if self.hud_obj:IsVisibleConsumeItemSlot() then
        self.hud_obj:SetVisibleConsumeItemSlot(false)
    end
    local success, result = pcall(function()
        self.hud_obj:SetHPDisplay()
    end)
    if not success then
        self.log_obj:Record(LogLevel.Critical, result)
    end
    if self:IsAutoMode() then
        self.hud_obj:ToggleOriginalMPHDisplay(true)
        self.hud_obj:EnableManualMeter(true, true)
        local initial_length = math.floor(self.av_obj.initial_destination_length)
        local current_length = math.floor(self.av_obj.dest_dir_vector_norm)
        self.hud_obj:SetSpeedMeterValue(current_length)
        self.hud_obj:SetRPMMeterValue(math.floor(10 * (1 - current_length / initial_length) + 1))
    else
        self.hud_obj:ToggleOriginalMPHDisplay(false)
        self.hud_obj:EnableManualMeter(false, self.av_obj.is_enable_manual_rpm_meter)
        local rpm_count = self.av_obj.engine_obj:GetRPMCount()
        self.hud_obj:SetRPMMeterValue(math.abs(rpm_count))
    end

end

function Event:CheckDoor()

    local veh_door = EVehicleDoor.seat_front_left

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

function Event:CheckCombat()

    local is_combat = Game.GetPlayer():PSIsInDriverCombat()
    if is_combat ~= self.av_obj.is_combat then
        self.av_obj.is_combat = is_combat
        if is_combat then
            if self.av_obj.combat_door[1] ~= "None" then
                self.av_obj:ChangeDoorState(Def.DoorOperation.Open, self.av_obj.combat_door)
            end
        else
            if self.av_obj.combat_door[1] ~= "None" then
                self.av_obj:ChangeDoorState(Def.DoorOperation.Close, self.av_obj.combat_door)
            end
        end
    end

end

function Event:CheckDestroyed()
    if self.av_obj:IsDestroyed() then
        self.log_obj:Record(LogLevel.Info, "Destroyed detected")
        if self.current_situation == Def.Situation.InVehicle then
            self.hud_obj:HideCustomHint()
            self.av_obj:Unmount()
        end
        self.sound_obj:ResetSoundResource()
        self.sound_obj:Mute()
        self.av_obj:ProjectLandingWarning(false)
        self.av_obj:ToggleThruster(false)
        self.hud_obj:HideChoice()
        if self.av_obj.engine_obj.fly_av_system ~= nil then
            self.av_obj.engine_obj.fly_av_system:EnableGravity(true)
        end
        self.av_obj:SetDestroyAppearance()
        self:SetSituation(Def.Situation.Normal)
        DAV.core_obj:Reset()
    end
end

function Event:CheckDespawn()
    if self.av_obj:IsDespawned() then
        self.log_obj:Record(LogLevel.Info, "Despawn detected")
        self.sound_obj:Mute()
        self:SetSituation(Def.Situation.Normal)
        DAV.core_obj:Reset()
    end
end

function Event:CheckDistance()
    local player_pos = Game.GetPlayer():GetWorldPosition()
    local av_pos = self.av_obj.position_obj:GetPosition()
    local distance = Vector4.Distance(player_pos, av_pos)
    if distance > self.distance_limit then
        self:ReturnVehicle(false)
    elseif distance > self.engine_audio_limit then
        self.sound_obj:PartialMute(200, 400)
        self.is_enable_audio = false
    else
        if not self.is_enable_audio then
            self.sound_obj:PlaySound(self.av_obj.engine_audio_name)
        end
        self.is_enable_audio = true
    end
end

function Event:CheckHeight()

    local height = self.av_obj.position_obj:GetHeight()
    if height < self.projection_max_height_offset + self.av_obj.position_obj.minimum_distance_to_ground then
        local height_offset = - height + self.av_obj.projection_offset.z
        self.av_obj:SetLandingVFXPosition(Vector4.new(self.av_obj.projection_offset.x, self.av_obj.projection_offset.y, height_offset, 1))
        self.av_obj:ProjectLandingWarning(true)
    else
        self.av_obj:ProjectLandingWarning(false)
    end

end

function Event:CheckInput()

    if self.is_keyboard_input_prev ~= DAV.is_keyboard_input then
        self.is_keyboard_input_prev = DAV.is_keyboard_input
        self.hud_obj:HideCustomHint()
        self.hud_obj:ShowCustomHint()
    end

end

function Event:CheckAutoModeChange()
    if self:IsAutoMode() and not self.is_locked_operation then
        self.is_locked_operation = true
    elseif not self:IsAutoMode() and self.is_locked_operation then
        self.is_locked_operation = false
        self.hud_obj:ShowArrivalDisplay()
        self.sound_obj:PlaySound("110_arrive_vehicle")
    end

end

function Event:CheckFailAutoPilot()
    if self.av_obj:IsFailedAutoPilot() then
        self.hud_obj:ShowInterruptAutoPilotDisplay()
    end
end

function Event:CheckLockedSave()
    local res, _ = Game.IsSavingLocked()
    if res then
        self.log_obj:Record(LogLevel.Info, "Locked save detected. Remove lock")
        SaveLocksManager.RequestSaveLockRemove(CName.new("DAV_IN_AV"))
    end

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
    if self:IsInEntryArea() then
        self.av_obj:Mount()
    end
end

-- function Event:ExitVehicle()
--     if self:IsInVehicle() then
--         self.av_obj:Unmount()
--     end
-- end

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

function Event:ShowVehicleManagerPopup()
    if self.current_situation == Def.Situation.Normal or self.current_situation == Def.Situation.Waiting then
        self.hud_obj:ShowVehicleManagerPopup()
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
