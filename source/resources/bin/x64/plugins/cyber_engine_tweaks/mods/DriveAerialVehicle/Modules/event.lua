local GameUI = require('External/GameUI.lua')
local Hud = require("Modules/hud.lua")
local Sound = require("Modules/sound.lua")
local UI = require("Modules/ui.lua")
local Event = {}
Event.__index = Event

--- Constractor
---@return table
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
    obj.is_locked_showing_meter = false
    obj.check_input_count = 0
    -- projection
    obj.is_landing_projection = false

    return setmetatable(obj, self)

end

--- Initialize
---@param av_obj any AV instance
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

--- Set Observe Functions
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

    -- Compatibility with LTBF
    Observe("vehicleBaseObject", "QueueEvent", function(_, event)
        if event:IsA(StringToName("VehicleFlightActivationEvent")) then
            if self:IsInVehicle() then
                self.hud_obj:SetDeleteWidgetFlag(true)
                self.av_obj:BlockOperation(true)
            end
        elseif event:IsA(StringToName("VehicleFlightDeactivationEvent")) then
            if self:IsInVehicle() then
                self.hud_obj:SetDeleteWidgetFlag(false)
                self.av_obj:BlockOperation(false)
            end
        end
    end)
end

--- Set Override Functions
function Event:SetOverride()
    -- To prevent the door from opening while driving
    Override("VehicleComponentPS", "GetHasAnyDoorOpen", function(this, wrapped_method)
        if self:IsInVehicle() then
            return false
        else
            return wrapped_method()
        end
    end)
    -- Depending on the position of the driver's seat, an animation will play in which the driver moves to the opposite door, just like in a normal car. This hook prevents this.
    Override("VehicleTransition", "IsUnmountDirectionClosest", function(this, state_context, unmount_direction, wrapped_method)
        if self:IsInVehicle() and not Game.GetPlayer():PSIsInDriverCombat() then
            self.av_obj:Unmount()
            return true
        else
            return wrapped_method(state_context, unmount_direction)
        end
    end)

    -- Depending on the position of the driver's seat, an animation will play in which the driver moves to the opposite door, just like in a normal car. This hook prevents this.
    Override("VehicleTransition", "IsUnmountDirectionOpposite", function(this, state_context, unmount_direction, wrapped_method)
        if self:IsInVehicle() and not Game.GetPlayer():PSIsInDriverCombat() then
            return false
        else
            return wrapped_method(state_context, unmount_direction)
        end
    end)
end

--- Get current situation.
---@return Def.Situation
function Event:GetSituation()
    return self.current_situation
end

--- Set new situation if it is possible.
---@param situation Def.Situation
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

--- Check events for current situation.
function Event:CheckAllEvents()
    if self:IsInMenuOrPopupOrPhoto() then
        self.log_obj:Record(LogLevel.Debug, "In Menu or Popup or Photo mode. Skip all checks")
    elseif self.current_situation == Def.Situation.Normal then
        self:CheckGarage()
    elseif self.current_situation == Def.Situation.Landing then
        self:CheckLanded()
        self:CheckHeight()
    elseif self.current_situation == Def.Situation.Waiting then
        self:CheckDespawn()
        self:CheckInEntryArea()
        self:CheckInAV()
        self:CheckDestroyed()
        self:CheckHeight()
        self:CheckDoor()
    elseif self.current_situation == Def.Situation.InVehicle then
        self:CheckInAV()
        self:CheckAutoModeChange()
        self:CheckFailAutoPilot()
        self:CheckHUD()
        self:CheckEngine()
        self:CheckDestroyed()
        self:CheckInput()
        self:CheckCombat()
        self:CheckHeight()
        self:CheckPerspective()
    elseif self.current_situation == Def.Situation.TalkingOff then
        self:CheckDespawn()
        self:CheckLockedSave()
        self:CheckHeight()
    end
end

--- Check vehicles user has.
function Event:CheckGarage()
    DAV.core_obj:UpdateGarageInfo(false)
end

--- Call vehicle.
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

--- Spawn vehicle.
function Event:SpawnVehicle()
    self.sound_obj:PlayGameSound("100_call_vehicle")
    -- self.sound_obj:PlayGameSound("210_landing")
    -- self.sound_obj:PlayGameSound(self.av_obj.engine_audio_name)
    self:SetSituation(Def.Situation.Landing)
    self.av_obj:SpawnToSky()
end

--- Return vehicle.
function Event:ReturnVehicle(is_leaving_sound)
    if self:IsWaiting() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle return detected in Waiting situation")
        if is_leaving_sound then
            -- self.sound_obj:PlayGameSound("240_leaving")
        end
        self.sound_obj:PlayGameSound("100_call_vehicle")
        self.sound_obj:ResetSoundResource()
        self:SetSituation(Def.Situation.TalkingOff)
        self.hud_obj:HideChoice()
        self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
        self.av_obj:DespawnFromGround()
    end
end

--- Check vehicle has landed.
function Event:CheckLanded()
    if self.av_obj:IsCollision() or self.av_obj.is_landed then
        self.log_obj:Record(LogLevel.Trace, "Landed detected")
        -- self.sound_obj:StopGameSound("210_landing")
        self.sound_obj:PlayGameSound("110_arrive_vehicle")
        self.sound_obj:ChangeSoundResource()
        self.av_obj.engine_obj:SetForce(Vector3.new(0, 0, 0))
        self.av_obj.engine_obj:SetTorque(Vector3.new(0, 0, 0))
        self:SetSituation(Def.Situation.Waiting)
    end
end

--- Check player is in entry area.
function Event:CheckInEntryArea()
    if self.av_obj:IsPlayerInEntryArea() then
        self.log_obj:Record(LogLevel.Trace, "InEntryArea detected")
        self.hud_obj:ShowChoice(self.selected_seat_index)
    else
        self.hud_obj:HideChoice()
    end
end

--- Check player is in AV.
function Event:CheckInAV()
    if self.av_obj:IsPlayerIn() then
        -- when player take on AV
        if self.current_situation == Def.Situation.Waiting then
            self.log_obj:Record(LogLevel.Info, "Enter In AV")
            SaveLocksManager.RequestSaveLockAdd(CName.new("DAV_IN_AV"))
            self:SetSituation(Def.Situation.InVehicle)
            self.hud_obj:HideChoice()
            self.hud_obj:EnableManualMeter(true, self.av_obj.is_enable_manual_rpm_meter)
            self.is_keyboard_input_prev = self.hud_obj.is_keyboard_input
            self.av_obj.engine_obj:EnableOriginalPhysics(false)
            self.av_obj.engine_obj:SetControlType(Def.EngineControlType.AddForce)
            Cron.After(1.5, function()
                self.hud_obj:ForceShowMeter()
                self.hud_obj:ShowLeftBottomHUD()
                self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
                Cron.After(1.5, function()
                    self.hud_obj:ShowCustomHint()
                end)
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
            self.av_obj.engine_obj:EnableOriginalPhysics(true)
            self.av_obj.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
            if self:IsAutoMode() then
                self.av_obj:InterruptAutoPilot()
            end
            SaveLocksManager.RequestSaveLockRemove(CName.new("DAV_IN_AV"))
        end
    end
end

--- Check HUD.
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
        self.hud_obj:EnableManualMeter(true, self.av_obj.is_enable_manual_rpm_meter)
        local current_speed = self.av_obj:GetCurrentSpeed()
        self.hud_obj:SetSpeedMeterValue(current_speed)
        local rpm_count = self.av_obj.engine_obj:GetRPMCount()
        self.hud_obj:SetRPMMeterValue(math.abs(rpm_count))
    end
end

--- Check engine status. If engine is off, turn it on.
function Event:CheckEngine()
    if not self.av_obj:IsEngineOn() then
        self.av_obj:TurnEngineOn(true)
    end
end

--- Check door status.
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

--- Check if player is in combat.
function Event:CheckCombat()
    local is_combat = Game.GetPlayer():PSIsInDriverCombat()
    if is_combat ~= self.av_obj.is_combat then
        self.av_obj.is_combat = is_combat
        if is_combat then
            if self.av_obj.combat_door[1] ~= "None" then
                self.av_obj:ChangeDoorState(Def.DoorOperation.Open, self.av_obj.combat_door)
            end
            self.hud_obj:DeleteInputHint("Exit")
        else
            if self.av_obj.combat_door[1] ~= "None" then
                self.av_obj:ChangeDoorState(Def.DoorOperation.Close, self.av_obj.combat_door)
            end
            self.hud_obj:AddInputHint("Exit", "Exit", "LocKey#36196", inkInputHintHoldIndicationType.Hold, true, 20)
        end
    end
end

--- Check if vehicle is destroyed.
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
            self.av_obj.engine_obj:EnableGravity(true)
        end
        self.av_obj:SetDestroyAppearance()
        self:SetSituation(Def.Situation.Normal)
        DAV.core_obj:Reset()
    end
end

--- Check if vehicle is despawned.
function Event:CheckDespawn()
    if self.av_obj:IsDespawned() then
        self.log_obj:Record(LogLevel.Info, "Despawn detected")
        self.sound_obj:Mute()
        self:SetSituation(Def.Situation.Normal)
        DAV.core_obj:Reset()
    end
end

--- Check height between AV and ground. if height is too low, show landing warning.
function Event:CheckHeight()
    local height = self.av_obj:GetHeight()
    if height < self.projection_max_height_offset + self.av_obj.minimum_distance_to_ground then
        local height_offset = - height + self.av_obj.projection_offset.z
        self.av_obj:SetLandingVFXPosition(Vector4.new(self.av_obj.projection_offset.x, self.av_obj.projection_offset.y, height_offset, 1))
        self.av_obj:ProjectLandingWarning(true)
    else
        self.av_obj:ProjectLandingWarning(false)
    end
end

--- Check player input. if or not keyboard input, show/hide custom hint.
function Event:CheckInput()
    self.check_input_count = self.check_input_count + 1
    if self.is_keyboard_input_prev ~= self.hud_obj.is_keyboard_input then
        self.is_keyboard_input_prev = self.hud_obj.is_keyboard_input
        self.hud_obj:HideCustomHint()
        self.hud_obj:ShowCustomHint()
        return
    end
    if self.check_input_count > math.floor(2 / DAV.time_resolution) then
        self.check_input_count = 0
        self.hud_obj:SetInputHintController()
        if not self.hud_obj:IsVisibleCustomInputHints() then
            self.hud_obj:ReconstructInputHint()
            self.log_obj:Record(LogLevel.Info, "ReconstructInputHint called")
            return
        end
    end
end

--- Check if auto mode is changed. if changed, lock operation.
function Event:CheckAutoModeChange()
    if self:IsAutoMode() and not self.is_locked_operation then
        self.is_locked_operation = true
    elseif not self:IsAutoMode() and self.is_locked_operation then
        self.is_locked_operation = false
        self.hud_obj:ShowArrivalDisplay()
        self.av_obj.engine_obj:SetControlType(Def.EngineControlType.AddForce)
        self.sound_obj:PlayGameSound("110_arrive_vehicle")
    end
end

--- Check if auto pilot is failed. if failed, show interrupt auto pilot display.
function Event:CheckFailAutoPilot()
    if self.av_obj:IsFailedAutoPilot() then
        self.hud_obj:ShowInterruptAutoPilotDisplay()
        self.av_obj.engine_obj:SetControlType(Def.EngineControlType.AddForce)
    end
end

--- Check if save is locked. if locked, remove lock.
function Event:CheckLockedSave()
    local res, _ = Game.IsSavingLocked()
    if res then
        self.log_obj:Record(LogLevel.Info, "Locked save detected. Remove lock")
        SaveLocksManager.RequestSaveLockRemove(CName.new("DAV_IN_AV"))
    end
end

--- Check if perspective is FPP.
function Event:CheckPerspective()
    if self:IsFPP() and not self.is_locked_showing_meter then
        self.hud_obj:ForceShowMeter()
        self.is_locked_showing_meter = true
    else
        self.is_locked_showing_meter = false
    end
end

--- Check if AV is spawned.
---@return boolean
function Event:IsNotSpawned()
    if self.current_situation == Def.Situation.Normal then
        return true
    else
        return false
    end
end

--- Check if AV is waiting.
---@return boolean
function Event:IsWaiting()
    if self.current_situation == Def.Situation.Waiting then
        return true
    else
        return false
    end
end

--- Check if player is in entry area.
---@return boolean
function Event:IsInEntryArea()
    if self.current_situation == Def.Situation.Waiting and self.av_obj:IsPlayerInEntryArea() then
        return true
    else
        return false

    end
end

--- Check if player is in vehicle.
---@return boolean
function Event:IsInVehicle()
    if self.current_situation == Def.Situation.InVehicle and self.av_obj:IsPlayerIn() then
        return true
    else
        return false
    end
end

--- Check if player is taking off.
---@return boolean
function Event:IsTakingOff()
    if self.current_situation == Def.Situation.TalkingOff then
        return true
    else
        return false
    end
end

--- Check if player is in auto mode.
---@return boolean
function Event:IsAutoMode()
    if self.av_obj.is_auto_pilot then
        return true
    else
        return false
    end
end

--- Check if player is in menu, popup or photo mode.
---@return boolean
function Event:IsInMenuOrPopupOrPhoto()
    if self.is_in_menu or self.is_in_popup or self.is_in_photo then
        return true
    else
        return false
    end
end

--- Check if entry is allowed.
---@return boolean
function Event:IsAllowedEntry()
    return self.is_allowed_entry
end

--- Check perspective is FPP.
---@return boolean
function Event:IsFPP()
    local veh_camera_perspective = self.av_obj.camera_obj:GetCurrentCameraDistanceLevel()
    if veh_camera_perspective == Def.CameraDistanceLevel.Fpp then
        return true
    else
        return false
    end
end

--- Change door state.
function Event:ChangeDoor()
    if self.current_situation == Def.Situation.InVehicle then
        self.av_obj:ChangeDoorState(Def.DoorOperation.Change)
    end
end

--- Enter vehicle.
function Event:EnterVehicle()
    if self:IsInEntryArea() then
        self.av_obj:Mount()
    end
end

--- Toggle auto mode.
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

--- Show radio popup.
function Event:ShowRadioPopup()
    if self:IsInVehicle() then
        self.hud_obj:ShowRadioPopup()
    end
end

--- Show vehicle manager popup.
function Event:ShowVehicleManagerPopup()
    if self.current_situation == Def.Situation.Normal or self.current_situation == Def.Situation.Waiting then
        self.hud_obj:ShowVehicleManagerPopup()
    end
end

--- Select choice.
---@param direction Def.ActionList
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
