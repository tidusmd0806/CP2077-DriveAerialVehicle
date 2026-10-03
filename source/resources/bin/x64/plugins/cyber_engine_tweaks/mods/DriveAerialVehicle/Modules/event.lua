local GameUI = require('External/GameUI.lua')
local Hud = require("Modules/hud.lua")
local Sound = require("Modules/sound.lua")
local UI = require("Modules/ui.lua")
local AV = require("Modules/av.lua")
local Engine = require("Modules/engine.lua")
local Event = {}
Event.__index = Event

--- Constructor
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

    -- static -- projection
    obj.projection_max_height_offset = 4
    -- distance limit
    obj.engine_audio_limit = 30
    -- dynamic --
    obj.is_initial_load = true
    obj.current_situation = Def.Situation.Idle
    obj.is_in_menu = false
    obj.is_in_popup = false
    obj.is_in_photo = false
    obj.is_locked_operation = false
    obj.selected_seat_index = 1
    obj.is_keyboard_input_prev = false
    obj.is_enable_audio = true
    obj.check_input_count = 0
    obj.is_ltbf_flight_active = false

    -- Entry-area choice hub state: ShowChoice() costs ~40 C# transitions, so it runs only on change.
    obj.shown_seat_index = nil
    obj.choice_last_shown_time = 0
    -- Safety net: recovers a hub the game dropped on its own within a second.
    obj.choice_keepalive_interval = 1.0
    -- Door event drivers: last edge seen from the read-path record / entry-area check (nil = unknown).
    obj.last_recorded_door_open = nil
    obj.last_in_entry_area = nil

    -- Checks that change only on a human timescale; they do not need the full loop rate.
    obj.distance_check_interval = 0.5
    obj.last_distance_check_time = 0
    obj.locked_save_check_interval = 0.1
    obj.last_locked_save_check_time = 0
    obj.last_landing_vfx_height = nil

    -- Slow-changing checks paced via Event:DueNow instead of the full-rate situation loop.
    -- Mount/unmount/destroy/meters/door are pure event-driven (no polling): see the
    -- observers in SetObserve and the overrides in SetOverride.
    obj.engine_check_interval = 0.2          --  5 Hz: the engine only dies on destruction
    obj.combat_check_interval = 0.2          --  5 Hz: driver-combat state changes rarely

    -- Ground probe cadence: synchronous raycast, so the next interval is predicted from the last measurement.
    obj.height_check_interval_fast = 0.0
    obj.height_check_interval_slow = 0.1
    obj.height_check_interval_still = 0.25
    obj.height_check_interval_far = 0.5
    obj.height_slow_threshold = 20.0
    obj.height_still_speed = 0.5
    obj.height_skip_distance = 60.0
    obj.next_height_check_time = 0
    obj.last_height = nil

    -- Shared cache for the player -> AV distance (CheckDistance and CheckHeight poll the same value).
    obj.player_distance_cache_time = 0.5
    obj.last_player_distance_time = 0
    obj.cached_player_distance = nil

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

    -- A new AV/session resets probe cadence and distance: the first probe runs immediately on fresh data.
    self.last_height = nil
    self.next_height_check_time = 0
    self.cached_player_distance = nil
    self.last_player_distance_time = 0
    -- Forget door edges from the previous AV so the fresh state is re-synced.
    self.last_recorded_door_open = nil
    self.last_in_entry_area = nil

    -- A fresh AV/session must not inherit an LTBF poll still running against the previous instance.
    self:StopLTBFCompatPoll()

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
        if self.is_initial_load then
            self.log_obj:Record(LogLevel.Info, "Initial Session start detected")
            self.is_initial_load = false
        else
            self.log_obj:Record(LogLevel.Info, "Session start detected")
            DAV.core_obj:Reset()
        end

        DAV.core_obj:SetFastTravelPosition()
        self.current_situation = Def.Situation.Normal

        -- Resident cache starts here, once the player exists and chunks can be ordered by real distance.
        DAV.core_obj:StartObstacleMapSessionPreload()
        -- Refresh the garage immediately so the first summon is correct; the 1s throttle takes over after.
        DAV.core_obj:UpdateGarageInfo(true)

    end)

    GameUI.Observe("SessionEnd", function()
        self.log_obj:Record(LogLevel.Info, "Session end detected")
        self.current_situation = Def.Situation.Idle
        -- Drop any armed movement holds so they cannot survive the session change
        if DAV.core_obj ~= nil then
            DAV.core_obj:StopAllButtonHolds()
        end
    end)

    -- LTBF compatibility: the poll is registered only during boarding, not for the whole session.
    if DAV.is_valid_ltbf then
        self.ltbf_poll_period = 0.1
    end

    -- Pure event-driven boarding/leaving: the HUD's mount events run the transition directly.
    -- Situation guards make double or out-of-order events harmless.
    Observe("hudCarController", "OnMountingEvent", function(this)
        self:OnPlayerMounted()
    end)

    Observe("hudCarController", "OnUnmountingEvent", function(this)
        self:OnPlayerUnmounted()
    end)

    -- Pure event-driven destruction: run the cleanup directly when our AV dies.
    -- NOTE: Entity has no DestroyRequest function (verified in NativeDB 2.13); the game
    -- dispatches death to the vehicle's script component instead — same class as the HP observer.
    ObserveAfter("VehicleComponent", "OnDeath", function(this, deathEvent)
        if self.av_obj == nil or self.av_obj.entity_id == nil then
            return
        end
        if this:GetEntity():GetEntityID().hash == self.av_obj.entity_id.hash then
            self:OnAVDestroyed()
        end
    end)

    -- Observe appearance changes to reapply thruster positions
    ObserveAfter("Entity", "ScheduleAppearanceChange", function(this, newAppearanceName)
        if DAV.core_obj == nil or DAV.core_obj.av_obj == nil then
            return
        end
        local av_obj = DAV.core_obj.av_obj
        if av_obj.entity_id == nil then
            return
        end
        if this:GetEntityID().hash == av_obj.entity_id.hash then
            DAV.core_obj.log_obj:Record(LogLevel.Debug, "Appearance change detected on AV entity")
            Cron.After(0.1, function()
                if av_obj:SetThrusterComponent() then
                    av_obj.is_available_thruster = true
                else
                    av_obj.is_available_thruster = false
                end
            end)
        end
    end)
end

--- Set Override Functions
function Event:SetOverride()
    -- Door guard: check the Lua-only situation field first; return early for non-AV vehicles before C# round trips.
    Override("VehicleComponentPS", "GetHasAnyDoorOpen", function(this, wrapped_method)
        if self.current_situation ~= Def.Situation.InVehicle then
            -- Piggyback on the game's own read: record the real door state and let a *change*
            -- drive the follow logic, so no separate polling of GetDoorState is needed.
            local open = wrapped_method()
            if open ~= self.last_recorded_door_open then
                self.last_recorded_door_open = open
                if self.current_situation == Def.Situation.Waiting then
                    self:SyncEntryDoor()
                end
            end
            return open
        end
        if self.av_obj ~= nil and self.av_obj:IsPlayerIn() then
            return false
        else
            return wrapped_method()
        end
    end)
    -- Prevent the driver-seat swap animation on unmount; situation check first, player lookup after.
    Override("VehicleTransition", "IsUnmountDirectionClosest", function(this, state_context, unmount_direction, wrapped_method)
        if self.current_situation ~= Def.Situation.InVehicle then
            return wrapped_method(state_context, unmount_direction)
        end
        local player = Game.GetPlayer()
        if player == nil then
            self.log_obj:Record(LogLevel.Warning, "No Player detected")
            return wrapped_method(state_context, unmount_direction)
        end
        if self:IsInVehicle() and not player:PSIsInDriverCombat() then
            self.av_obj:Unmount()
            return true
        else
            return wrapped_method(state_context, unmount_direction)
        end
    end)

    -- Prevents the driver-swap-to-opposite-door animation of normal cars
    Override("VehicleTransition", "IsUnmountDirectionOpposite", function(this, state_context, unmount_direction, wrapped_method)
        if self.current_situation ~= Def.Situation.InVehicle then
            return wrapped_method(state_context, unmount_direction)
        end
        local player = Game.GetPlayer()
        if player == nil then
            self.log_obj:Record(LogLevel.Warning, "No Player detected")
            return wrapped_method(state_context, unmount_direction)
        end
        if self:IsInVehicle() and not player:PSIsInDriverCombat() then
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

--- Throttle helper: returns true when the caller should run now, and books the next slot.
--- os.clock() is CPU time, so every cadence backs off when the process is CPU-bound.
---@param field string instance field holding the next allowed run time
---@param interval number seconds between runs
---@return boolean true when the check should run
function Event:DueNow(field, interval)
    local now = os.clock()
    local next_time = self[field]
    if next_time ~= nil and now < next_time then
        return false
    end
    self[field] = now + interval
    return true
end

--- Check events for current situation.
function Event:CheckAllEvents()
    if self:IsInMenuOrPopupOrPhoto() then
        self.log_obj:Record(LogLevel.Debug, "In Menu or Popup or Photo mode. Skip all checks")
    elseif self.current_situation == Def.Situation.Normal then
        self:CheckGarage()
    elseif self.current_situation == Def.Situation.Landing then
        self:CheckLanded()
        -- Only check height if vehicle entity exists and is not currently spawning
        if not self.av_obj:IsSpawning() and not self.av_obj:IsDespawned() then
            self:CheckHeight()
        end
    elseif self.current_situation == Def.Situation.Waiting then
        self:CheckDespawn()
        self:CheckInEntryArea()
        self:CheckDistance()
        self:CheckHeight()
    elseif self.current_situation == Def.Situation.InVehicle then
        self:CheckEngine()
        self:CheckInput()
        self:CheckCombat()
        self:CheckHeight()
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
        -- Wait longer to ensure complete cleanup before spawning new vehicle
        Cron.After(1.5, function()
            -- Double-check that previous vehicle is completely removed
            if self.av_obj:IsDespawned() then
                self:SpawnVehicle()
            else
                self.log_obj:Record(LogLevel.Warning, "Previous vehicle not fully despawned, retrying...")
                Cron.After(0.5, function()
                    self:SpawnVehicle()
                end)
            end
        end)
    end
end

--- Spawn vehicle.
function Event:SpawnVehicle()
    self.sound_obj:PlayGameSound("100_call_vehicle")
    if not DAV.is_valid_audioware then
        self.sound_obj:PlayGameSound("210_landing")
        self.sound_obj:PlayGameSound(self.av_obj.engine_audio_name)
    end
    self:SetSituation(Def.Situation.Landing)
    self.av_obj:SpawnToSky()
end

--- Return vehicle.
function Event:ReturnVehicle()
    if self:IsWaiting() then
        self.log_obj:Record(LogLevel.Trace, "Vehicle return detected in Waiting situation")
        if not DAV.is_valid_audioware then
            self.sound_obj:PlayGameSound("240_leaving")
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
    if self.av_obj.navigation_obj:IsCollision() or self.av_obj.is_landed then
        self.log_obj:Record(LogLevel.Trace, "Landed detected")
        if not DAV.is_valid_audioware then
            self.sound_obj:StopGameSound("210_landing")
        end
        self.sound_obj:PlayGameSound("110_arrive_vehicle")
        self.sound_obj:ChangeSoundResource()
        self.av_obj.engine_obj:SetForce(Vector3.new(0, 0, 0))
        self.av_obj.engine_obj:SetTorque(Vector3.new(0, 0, 0))
        self:SetSituation(Def.Situation.Waiting)
    end
end

--- Check player is in entry area.
--- Edge-triggered: the hub is pushed when the player enters the area, when the
--- selected seat changes, or when the keep-alive is due -- not every tick.
function Event:CheckInEntryArea()
    local in_entry = self.av_obj:IsPlayerInEntryArea()
    -- Door follows the entry-area edge immediately (human-visible); no separate door poll needed.
    if in_entry ~= self.last_in_entry_area then
        self.last_in_entry_area = in_entry
        self:SyncEntryDoor()
    end
    if in_entry then
        self.log_obj:Record(LogLevel.Trace, "InEntryArea detected")
        -- interaction_hub is the HUD's own record; nil means nothing is shown, so re-show it.
        local shown = (self.hud_obj.interaction_hub ~= nil)
        local now = os.clock()
        if not shown
            or self.shown_seat_index ~= self.selected_seat_index
            or (self.choice_keepalive_interval > 0
                and (now - self.choice_last_shown_time) >= self.choice_keepalive_interval) then
            self.hud_obj:ShowChoice(self.selected_seat_index)
            self.shown_seat_index = self.selected_seat_index
            self.choice_last_shown_time = now
        end
    elseif self.hud_obj.interaction_hub ~= nil then
        self.hud_obj:HideChoice()
        self.shown_seat_index = nil
    end
end

--- Start the LTBF compatibility poll. Only ever runs while the player is aboard the AV.
---@return boolean true when the poll was actually started
function Event:StartLTBFCompatPoll()
    if not DAV.is_valid_ltbf then
        return false
    end
    if self.ltbf_poll_timer ~= nil then
        return false
    end

    local period = self.ltbf_poll_period or 0.1
    self.ltbf_poll_timer = Cron.Every(period, {tick = 1}, function(timer)
        local is_ltbf_flight_active = fs().ctlr.active
        if is_ltbf_flight_active and is_ltbf_flight_active ~= self.is_ltbf_flight_active then
            self.is_ltbf_flight_active = is_ltbf_flight_active
            self.hud_obj:SetDeleteWidgetFlag(true)
            self.av_obj:BlockOperation(true)
            self:StartLTBFThrusterCheck(period)
        elseif is_ltbf_flight_active ~= self.is_ltbf_flight_active then
            self.is_ltbf_flight_active = is_ltbf_flight_active
            self.hud_obj:SetDeleteWidgetFlag(false)
            self.av_obj:BlockOperation(false)
        end
    end)

    return true
end

--- Stop the LTBF compatibility poll and any thruster check it spawned.
--- Also unwinds an active LTBF takeover: the old always-on poll simply stopped
--- acting once the player left, which left BlockOperation(true) behind.
function Event:StopLTBFCompatPoll()
    self:StopLTBFThrusterCheck()
    if self.ltbf_poll_timer ~= nil then
        Cron.Halt(self.ltbf_poll_timer)
        self.ltbf_poll_timer = nil
    end
    if self.is_ltbf_flight_active then
        self.is_ltbf_flight_active = false
        self.hud_obj:SetDeleteWidgetFlag(false)
        if self.av_obj ~= nil then
            self.av_obj:BlockOperation(false)
        end
    end
    return true
end

--- Suppress LTBF thruster meshes/effects for ~1 s after LTBF flight kicks in.
--- The period is passed in so the 1 s budget stays tied to the poll period that
--- started it rather than to the control-loop resolution.
---@param period number poll period in seconds
---@return boolean true when the check was actually started
function Event:StartLTBFThrusterCheck(period)
    if self.ltbf_thruster_timer ~= nil then
        return false
    end

    period = period or self.ltbf_poll_period or 0.1
    local ltbf_timeout_ticks = math.ceil(1.0 / period)
    self.ltbf_thruster_timer = Cron.Every(period, {tick = 1}, function(timer)
        timer.tick = timer.tick + 1
        if timer.tick > ltbf_timeout_ticks then
            self.log_obj:Record(LogLevel.Info, "Thruster check timed out")
            self:StopLTBFThrusterCheck()
            return
        end
        if self.av_obj == nil or self.av_obj.entity_id == nil then
            self.log_obj:Record(LogLevel.Warning, "No vehicle entity id for Thruster check")
            return
        end
        local entity = self.av_obj:GetEntity()
        local mesh_fl = entity:FindComponentByName("ThrusterFL")
        local mesh_fr = entity:FindComponentByName("ThrusterFR")
        local mesh_bl = entity:FindComponentByName("ThrusterBL")
        local mesh_br = entity:FindComponentByName("ThrusterBR")
        if mesh_fl then mesh_fl:Toggle(false) end
        if mesh_fr then mesh_fr:Toggle(false) end
        if mesh_bl then mesh_bl:Toggle(false) end
        if mesh_br then mesh_br:Toggle(false) end
        if fs().playerComponent.configuration.thrusters then
            fs().playerComponent.configuration.thrusters[1]:Stop()
            fs().playerComponent.configuration.thrusters[2]:Stop()
            fs().playerComponent.configuration.thrusters[3]:Stop()
            fs().playerComponent.configuration.thrusters[4]:Stop()
        end
    end)

    return true
end

function Event:StopLTBFThrusterCheck()
    if self.ltbf_thruster_timer ~= nil then
        Cron.Halt(self.ltbf_thruster_timer)
        self.ltbf_thruster_timer = nil
    end
    return true
end

--- Event handler: player boarded the AV (fired by hudCarController.OnMountingEvent).
--- Situation + entity guards: the event fires for any vehicle, so verify our AV holds the player.
function Event:OnPlayerMounted()
    if self.current_situation ~= Def.Situation.Waiting then
        return
    end
    if self.av_obj == nil or not self.av_obj:IsPlayerIn() then
        return
    end
    self.log_obj:Record(LogLevel.Info, "Enter In AV")
    SaveLocksManager.RequestSaveLockAdd(CName.new("DAV_IN_AV"))
    self:SetSituation(Def.Situation.InVehicle)
    self.hud_obj:HideChoice()
    self.hud_obj:EnableManualMeter(true, self.av_obj.is_enable_manual_rpm_meter)
    self.is_keyboard_input_prev = self.hud_obj.is_keyboard_input
    self.av_obj.engine_obj:EnableOriginalPhysics(false)
    self.av_obj.engine_obj:SetControlType(Def.EngineControlType.AddForce)
    -- LTBF compatibility only matters while aboard (B-3).
    self:StartLTBFCompatPoll()
    Cron.After(1.5, function()
        self.hud_obj:ForceShowMeter()
        self.hud_obj:ShowLeftBottomHUD()
        self.av_obj:ChangeDoorState(Def.DoorOperation.Close)
        Cron.After(1.5, function()
            self.hud_obj:ShowCustomHint()
        end)
    end)
end

--- Event handler: player left the AV (fired by hudCarController.OnUnmountingEvent).
--- Situation guard: only InVehicle owns the exit cleanup; duplicates after the transition are no-ops.
function Event:OnPlayerUnmounted()
    if self.current_situation ~= Def.Situation.InVehicle then
        return
    end
    if self.av_obj == nil then
        return
    end
    self.log_obj:Record(LogLevel.Info, "Exit AV")
    -- LTBF compatibility has nothing to watch from outside the AV (B-3).
    self:StopLTBFCompatPoll()
    self.hud_obj:HideLeftBottomHUD()
    self:SetSituation(Def.Situation.Waiting)
    -- Drop any armed movement holds on exit so they cannot leak into the next ride
    if DAV.core_obj ~= nil then
        DAV.core_obj:StopAllButtonHolds()
    end
    self.hud_obj:HideCustomHint()
    self.hud_obj:EnableManualMeter(false, false)
    -- Restore the normal speed unit label on exit, or it stays on the autopilot distance unit.
    self.hud_obj:ToggleOriginalMPHDisplay(false)
    self.av_obj.engine_obj:EnableOriginalPhysics(true)
    self.av_obj.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
    if self:IsAutoMode() then
        self.av_obj.navigation_obj:InterruptAutoPilot()
    end
    SaveLocksManager.RequestSaveLockRemove(CName.new("DAV_IN_AV"))
end

--- Event handler: the AV entity was destroyed (fired by VehicleComponent.OnDeath, hash-matched).
--- Guarded by situation: a second destroy event after the reset must not re-run cleanup.
function Event:OnAVDestroyed()
    if self.current_situation == Def.Situation.Normal or self.current_situation == Def.Situation.Idle then
        return
    end
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

--- RPM meter display value, shared by the OnRpmValueChanged override and the boarding flow.
---@return number
function Event:ComputeRPMDisplayValue()
    if self:IsAutoMode() then
        local nav_obj = self.av_obj.navigation_obj
        local initial_length = math.floor(tonumber(nav_obj and nav_obj.initial_destination_length) or 1)
        local current_length = math.floor(tonumber(nav_obj and nav_obj.dest_remaining_to_final) or 0)
        if initial_length < 1 then
            initial_length = 1
        end
        -- RPM is the autopilot progress gauge: 1 at departure, 11 on arrival.
        return math.floor(10 * (1 - current_length / initial_length) + 1)
    end
    return math.abs(self.av_obj.engine_obj:GetRPMCount())
end

--- Check engine status. If engine is off, turn it on.
function Event:CheckEngine()
    -- 5 Hz: the engine dies only on destruction/scripted events; the body fires on a transition.
    if not self:DueNow("last_engine_check_time", self.engine_check_interval) then
        return
    end
    if not self.av_obj:IsEngineOn() then
        self.av_obj:TurnEngineOn(true)
    end
end

--- Bring the driver door in line with the entry area (idempotent; safe to call from any driver).
--- Drivers: the entry-area edge in CheckInEntryArea and the read-path change record
--- in the GetHasAnyDoorOpen override. No polling.
function Event:SyncEntryDoor()
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
    -- 5 Hz: driver-combat state changes on encounter timescales; the body fires on a transition.
    if not self:DueNow("last_combat_check_time", self.combat_check_interval) then
        return
    end
    local player = Game.GetPlayer()
    if player == nil then
        self.log_obj:Record(LogLevel.Warning, "No Player detected")
        return
    end
    local is_combat = player:PSIsInDriverCombat()
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

--- Check if vehicle is despawned.
function Event:CheckDespawn()
    if self.av_obj:IsDespawned() then
        self.log_obj:Record(LogLevel.Info, "Despawn detected")
        self.sound_obj:Mute()
        self:SetSituation(Def.Situation.Normal)
        DAV.core_obj:Reset()
    end
end

--- Distance from the player to the AV, cached for `player_distance_cache_time`.
--- Returns nil when the player cannot be resolved; callers must treat nil as "unknown", not "far".
---@return number|nil
function Event:GetPlayerDistanceToAV()
    local now = os.clock()
    if self.cached_player_distance ~= nil
            and (now - self.last_player_distance_time) < self.player_distance_cache_time then
        return self.cached_player_distance
    end
    local player = Game.GetPlayer()
    if player == nil then
        return nil
    end
    local distance = Vector4.Distance(player:GetWorldPosition(), self.av_obj:GetPosition())
    self.cached_player_distance = distance
    self.last_player_distance_time = now
    return distance
end

--- Check distance between player and AV (engine sound on/off across a 30 m threshold).
--- Half-second resolution is invisible; uncached this was four C# transitions per tick.
function Event:CheckDistance()
    local now = os.clock()
    if (now - self.last_distance_check_time) < self.distance_check_interval then
        return
    end
    self.last_distance_check_time = now
    local distance = self:GetPlayerDistanceToAV()
    if distance == nil then
        return
    end
    if distance > self.engine_audio_limit then
        self.sound_obj:StopGameSound(self.av_obj.engine_audio_name)
        self.is_enable_audio = false
    else
        if not self.is_enable_audio then
            self.sound_obj:PlayGameSound(self.av_obj.engine_audio_name)
        end
        self.is_enable_audio = true
    end
end

--- Choose how long the next ground probe may be delayed.
--- The previous probe bounds what the next can miss; cost is per probe, not per tick.
---@return number interval in seconds
function Event:PickHeightInterval()
    -- Nobody close enough to see the projection (60 m matches the landing VFX range).
    local distance = self:GetPlayerDistanceToAV()
    if distance ~= nil and distance > self.height_skip_distance then
        return self.height_check_interval_far
    end

    -- First probe after a reset: no basis to delay anything.
    local last_height = self.last_height
    if last_height == nil then
        return self.height_check_interval_fast
    end

    -- No vertical motion: 0.5 m/s is above pinned-craft jitter, below real descent.
    local engine_obj = self.av_obj.engine_obj
    if engine_obj ~= nil then
        local velocity = engine_obj:GetVelocity()
        if velocity ~= nil and math.abs(velocity.z) <= self.height_still_speed then
            return self.height_check_interval_still
        end
    end

    -- High up: 10 Hz cannot step over the ~5 m warning threshold (plenty of margin).
    if last_height > self.height_slow_threshold then
        return self.height_check_interval_slow
    end

    return self.height_check_interval_fast
end

--- Check height between AV and ground. if height is too low, show landing warning.
--- Cadence-adaptive on purpose: the measurement is a synchronous physics query.
function Event:CheckHeight()
    local now = os.clock()
    if now < self.next_height_check_time then
        return
    end
    self.next_height_check_time = now + self:PickHeightInterval()

    local height = self.av_obj.navigation_obj:GetHeight()
    self.last_height = height
    if height < self.projection_max_height_offset + self.av_obj.minimum_distance_to_ground then
        -- Write the VFX offset only when the measured height actually moved.
        if self.last_landing_vfx_height ~= height then
            self.last_landing_vfx_height = height
            local height_offset = - height + self.av_obj.projection_offset.z
            self.av_obj:SetLandingVFXPosition(Vector4.new(self.av_obj.projection_offset.x, self.av_obj.projection_offset.y, height_offset, 1))
        end
        self.av_obj:ProjectLandingWarning(true)
    else
        self.last_landing_vfx_height = nil
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
    if self.check_input_count > TimeScale:Ticks(2) then
        self.check_input_count = 0
        self.hud_obj:SetInputHintController()
        if not self.hud_obj:IsVisibleCustomInputHints() then
            self.hud_obj:ReconstructInputHint()
            self.log_obj:Record(LogLevel.Trace, "ReconstructInputHint called")
            return
        end
    end
end

--- Event hook: autopilot ended (success or interrupt); restore manual control.
--- Replaces the per-tick CheckAutoModeChange poll; called from Navigation on the state flip.
function Event:NotifyAutoModeEnded()
    -- Old poll only ran while InVehicle; keep that scope (unmount must not show the arrival display).
    if self.current_situation ~= Def.Situation.InVehicle then
        self.is_locked_operation = false
        return
    end
    if not self.is_locked_operation then
        return
    end
    self.is_locked_operation = false
    -- Hand the RPM gauge back from the progress bar to the manual setting (was CheckHUD's job).
    self.hud_obj:EnableManualMeter(true, self.av_obj.is_enable_manual_rpm_meter)
    self.hud_obj:ShowArrivalDisplay()
    self.av_obj.engine_obj:SetControlType(Def.EngineControlType.AddForce)
    self.sound_obj:PlayGameSound("110_arrive_vehicle")
end

--- Event hook: autopilot failed; show the interrupt display.
--- Replaces the per-tick CheckFailAutoPilot poll; called from Navigation:InterruptAutoPilot.
function Event:NotifyAutoPilotFailed()
    -- Old poll only ran while InVehicle; keep that scope.
    if self.current_situation ~= Def.Situation.InVehicle then
        return
    end
    self.hud_obj:ShowInterruptAutoPilotDisplay()
    self.av_obj.engine_obj:SetControlType(Def.EngineControlType.AddForce)
end

--- Check if save is locked. if locked, remove lock.
function Event:CheckLockedSave()
    -- TalkingOff lasts seconds; the save-lock state does not need full-rate polling while it does.
    local now = os.clock()
    if (now - self.last_locked_save_check_time) < self.locked_save_check_interval then
        return
    end
    self.last_locked_save_check_time = now
    local res, _ = Game.IsSavingLocked()
    if res then
        self.log_obj:Record(LogLevel.Info, "Locked save detected. Remove lock")
        SaveLocksManager.RequestSaveLockRemove(CName.new("DAV_IN_AV"))
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
--- Situation check with no C# round trip. The meter overrides fire on every speed
--- and rpm change event, so they must not depend on IsPlayerMounted().
function Event:IsInAVSituation()
    return self.current_situation == Def.Situation.InVehicle
end

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
            -- Auto mode drives the RPM gauge as a progress bar: take it over now (was CheckHUD's job).
            self.hud_obj:EnableManualMeter(true, true)
            self.is_locked_operation = true
            self.av_obj.navigation_obj:AutoPilot()
        else
            self.hud_obj:ShowDriveModeDisplay()
            -- Hand the RPM gauge back to the manual setting.
            self.hud_obj:EnableManualMeter(true, self.av_obj.is_enable_manual_rpm_meter)
            self.is_locked_operation = false
            self.av_obj.navigation_obj:InterruptAutoPilot()
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
