local GameUI = require('External/GameUI.lua')
local Hud = require("Modules/hud.lua")
local Sound = require("Modules/sound.lua")
local UI = require("Modules/ui.lua")
-- PROBE: per-situation cost ledger (see Event.EnableSituationLedger at the
-- bottom of this file). Remove with that function.
local Prof = require("Modules/profprobe.lua")
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

    -- static --
    -- projection
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
    obj.is_locked_showing_meter = false
    obj.check_input_count = 0
    obj.is_ltbf_flight_active = false

    -- Entry-area choice hub state (see CheckInEntryArea).
    -- ShowChoice() rebuilds every seat caption, re-resolves localisation and
    -- re-activates the hub: ~40 C# transitions per call. It used to run on
    -- every 100 Hz tick for as long as the player stood near the parked AV,
    -- i.e. ~4000 transitions/second to re-display an unchanged dialog.
    obj.shown_seat_index = nil
    obj.choice_last_shown_time = 0
    -- Safety net only. The InteractionUIBase overrides keep the hub injected
    -- while the player is in range, so this mostly never fires; it exists so a
    -- hub the game dropped on its own is recovered within a second.
    obj.choice_keepalive_interval = 1.0

    -- Checks whose answer only changes on a human timescale. They were wired to
    -- the 100 Hz situation loop because that was the loop available, not
    -- because they need 100 Hz.
    obj.distance_check_interval = 0.5
    obj.last_distance_check_time = 0
    obj.locked_save_check_interval = 0.1
    obj.last_locked_save_check_time = 0
    obj.last_landing_vfx_height = nil

    -- Ground probe cadence (see CheckHeight).
    -- Navigation:GetHeight() bottoms out in SyncRaycastByQueryFilter, a
    -- *synchronous* physics query. One of those costs as much as a few dozen
    -- plain C# getters, and it was being paid every single tick in every
    -- situation that had a live AV -- including a parked one, where the answer
    -- cannot change at all.
    --
    -- The probe feeds exactly two things: the landing warning VFX (a boolean
    -- thresholded at projection_max_height_offset + minimum_distance_to_ground,
    -- ~5 m) and that VFX's slot offset. Neither needs 100 Hz, so the next
    -- interval is predicted from the previous measurement -- the height cannot
    -- move far in one interval:
    --
    --   far   -- nobody is close enough to see the projection at all
    --   still -- no vertical motion, so the height is fixed
    --   slow  -- high up: even at maximum sink rate the warning cannot reach
    --           its threshold inside the slow interval
    --   fast  -- low and moving: probe every tick, as before
    --
    -- Measured effect is not claimed here; the arithmetic is: a parked craft
    -- goes from 100 probes/s to 4/s, and a cruising one from 100/s to 10/s,
    -- while low-altitude flight keeps the original rate.
    obj.height_check_interval_fast = 0.0
    obj.height_check_interval_slow = 0.1
    obj.height_check_interval_still = 0.25
    obj.height_check_interval_far = 0.5
    obj.height_slow_threshold = 20.0
    obj.height_still_speed = 0.5
    obj.height_skip_distance = 60.0
    obj.next_height_check_time = 0
    obj.last_height = nil

    -- Shared cache for the player -> AV distance.
    -- CheckDistance polls it for the 30 m engine-audio threshold and CheckHeight
    -- polls it to decide whether anyone can see the landing projection.
    -- Uncached, every caller pays four transitions: GetPlayer, GetWorldPosition,
    -- GetPosition, Vector4.Distance.
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

    -- A new AV (or a new session) must not inherit the previous one's probe
    -- cadence or distance: the first probe after this runs immediately and
    -- re-predicts from fresh data.
    self.last_height = nil
    self.next_height_check_time = 0
    self.cached_player_distance = nil
    self.last_player_distance_time = 0
    self.is_locked_showing_meter = false

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

        -- The player exists now, so the resident obstacle-map cache can order
        -- chunks by distance from where we actually are. Previously this ran from
        -- Core:Init() (before the save was loaded) and pulled the whole 300MB map
        -- into the Lua heap for the rest of the session.
        DAV.core_obj:StartObstacleMapSessionPreload()
        -- Refresh the garage once immediately so the very first summon sees the
        -- right vehicles; afterwards the 1s throttle takes over.
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

    -- Compatibility for LTBF
    if DAV.is_valid_ltbf then
        Cron.Every(0.1, {tick=1}, function(timer)
            if self:IsInVehicle() then
                local is_ltbf_flight_active = fs().ctlr.active
                if is_ltbf_flight_active and is_ltbf_flight_active ~= self.is_ltbf_flight_active then
                    self.is_ltbf_flight_active = is_ltbf_flight_active
                    self.hud_obj:SetDeleteWidgetFlag(true)
                    self.av_obj:BlockOperation(true)
                    -- This poll runs on its own 0.1 s period, not on the control
                    -- loop, so the tick budget is derived from that period rather
                    -- than from TimeScale. Named so the 1 s intent survives.
                    local ltbf_poll_period = 0.1
                    local ltbf_timeout_ticks = math.ceil(1.0 / ltbf_poll_period)
                    Cron.Every(ltbf_poll_period, {tick=1}, function(timer)
                        timer.tick = timer.tick + 1
                        if timer.tick > ltbf_timeout_ticks then
                            self.log_obj:Record(LogLevel.Info, "Thruster check timed out")
                            Cron.Halt(timer)
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
                elseif is_ltbf_flight_active ~= self.is_ltbf_flight_active then
                    self.is_ltbf_flight_active = is_ltbf_flight_active
                    self.hud_obj:SetDeleteWidgetFlag(false)
                    self.av_obj:BlockOperation(false)
                end
            end
        end)
    end

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
    -- To prevent the door from opening while driving.
    --
    -- This wraps the door query of EVERY vehicle in Night City, not just the
    -- AV's.  IsInVehicle() answers through two C# calls (FindEntityByID +
    -- IsPlayerMounted), but its first condition is a plain Lua field read --
    -- so read that first and hand the call straight back for every vehicle
    -- that is not ours.  Equivalent to IsInVehicle(): nothing runs between
    -- the two checks that could move current_situation.
    Override("VehicleComponentPS", "GetHasAnyDoorOpen", function(this, wrapped_method)
        if self.current_situation ~= Def.Situation.InVehicle then
            return wrapped_method()
        end
        if self.av_obj ~= nil and self.av_obj:IsPlayerIn() then
            return false
        else
            return wrapped_method()
        end
    end)
    -- Depending on the position of the driver's seat, an animation will play in which the driver moves to the opposite door, just like in a normal car. This hook prevents this.
    --
    -- Same shape as above: the situation check is free, the player lookup is
    -- not, and this fires on every unmount transition of every vehicle.
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

    -- Depending on the position of the driver's seat, an animation will play in which the driver moves to the opposite door, just like in a normal car. This hook prevents this.
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
    if self.av_obj:IsPlayerInEntryArea() then
        self.log_obj:Record(LogLevel.Trace, "InEntryArea detected")
        -- interaction_hub is the HUD's own record of what it pushed; nil means
        -- nothing is shown. Reading it here instead of keeping a second flag
        -- means a HideChoice() from anywhere else is noticed and re-shown.
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
            -- Drop any armed movement holds on exit so they cannot leak into the next ride
            if DAV.core_obj ~= nil then
                DAV.core_obj:StopAllButtonHolds()
            end
            self.hud_obj:HideCustomHint()
            self.hud_obj:EnableManualMeter(false, false)
            -- CheckHUD stops running once the situation leaves InVehicle, so put
            -- the normal speed unit label back here or it stays on the autopilot
            -- distance unit after you get out.
            self.hud_obj:ToggleOriginalMPHDisplay(false)
            self.av_obj.engine_obj:EnableOriginalPhysics(true)
            self.av_obj.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
            if self:IsAutoMode() then
                self.av_obj.navigation_obj:InterruptAutoPilot()
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
    -- Called directly. This used to be wrapped in pcall(function() ... end) at
    -- the loop rate, which allocated a closure every tick to guard a function
    -- that now guards its own only throwing statement.
    self.hud_obj:SetHPDisplay()
    -- The game repaints the speedometer unit label on its own, continuously, so
    -- swapping it to a distance unit during autopilot just fights the HUD and
    -- flickers. Show the real speed in both modes and let the RPM dial carry the
    -- autopilot progress instead.
    self.hud_obj:ToggleOriginalMPHDisplay(false)
    local current_speed = self.av_obj:GetCurrentSpeed()

    if self:IsAutoMode() then
        self.hud_obj:EnableManualMeter(true, true)
        self.hud_obj:SetSpeedMeterValue(current_speed)
        local nav_obj = self.av_obj.navigation_obj
        local initial_length = math.floor(tonumber(nav_obj and nav_obj.initial_destination_length) or 1)
        local current_length = math.floor(tonumber(nav_obj and nav_obj.dest_remaining_to_final) or 0)
        if initial_length < 1 then
            initial_length = 1
        end
        -- RPM is the autopilot progress gauge: 1 at departure, 11 on arrival.
        self.hud_obj:SetRPMMeterValue(math.floor(10 * (1 - current_length / initial_length) + 1))
    else
        self.hud_obj:EnableManualMeter(true, self.av_obj.is_enable_manual_rpm_meter)
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

--- Distance from the player to the AV, cached for `player_distance_cache_time`.
--- Returns nil when the player cannot be resolved. Callers must treat nil as
--- "unknown" rather than "far", so a missing player never suppresses a check
--- that would otherwise have run.
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

--- Check distance between player and AV.
--- The only effect is turning the engine sound on/off across a 30 m threshold,
--- so a half-second resolution is invisible. At 100 Hz this was four C#
--- transitions per tick (GetPlayer, GetWorldPosition, GetPosition, Distance).
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
--- The prediction runs off the previous probe: the height cannot move far in
--- one interval, so what we saw last time bounds what we can miss next time.
--- Cost of this function is paid once per probe, not once per tick -- between
--- probes CheckHeight returns on a single clock comparison.
---@return number interval in seconds
function Event:PickHeightInterval()
    -- Nobody close enough to see the projection. 60 m matches the range the
    -- landing VFX is meant to cover.
    local distance = self:GetPlayerDistanceToAV()
    if distance ~= nil and distance > self.height_skip_distance then
        return self.height_check_interval_far
    end

    -- First probe after a reset: no basis to delay anything.
    local last_height = self.last_height
    if last_height == nil then
        return self.height_check_interval_fast
    end

    -- No vertical motion -> the height is not going to change under us.
    -- 0.5 m/s is well above the jitter of a pinned craft and well below any
    -- descent a player would call "flying".
    local engine_obj = self.av_obj.engine_obj
    if engine_obj ~= nil then
        local velocity = engine_obj:GetVelocity()
        if velocity ~= nil and math.abs(velocity.z) <= self.height_still_speed then
            return self.height_check_interval_still
        end
    end

    -- High up: the warning threshold is far enough away that 10 Hz cannot
    -- step over it. At 20 m above the ~5 m threshold, even a 20 m/s sink
    -- leaves 0.75 s of margin -- seven slow intervals.
    if last_height > self.height_slow_threshold then
        return self.height_check_interval_slow
    end

    return self.height_check_interval_fast
end

--- Check height between AV and ground. if height is too low, show landing warning.
---
--- Cadence-adaptive on purpose; see `height_check_interval_*` in New() and
--- PickHeightInterval(). The measurement ends in a synchronous physics query
--- and used to run at the full loop rate even when the craft was parked and
--- the answer was fixed.
function Event:CheckHeight()
    local now = os.clock()
    if now < self.next_height_check_time then
        return
    end
    self.next_height_check_time = now + self:PickHeightInterval()

    local height = self.av_obj.navigation_obj:GetHeight()
    self.last_height = height
    if height < self.projection_max_height_offset + self.av_obj.minimum_distance_to_ground then
        -- The VFX offset only needs writing when the measured height moved.
        -- A parked AV reports the same height 100 times a second.
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
    if self.av_obj.navigation_obj:IsFailedAutoPilot() then
        self.hud_obj:ShowInterruptAutoPilotDisplay()
        self.av_obj.engine_obj:SetControlType(Def.EngineControlType.AddForce)
    end
end

--- Check if save is locked. if locked, remove lock.
function Event:CheckLockedSave()
    -- TalkingOff lasts a few seconds; the save-lock state does not need to be
    -- polled at 100 Hz while it does.
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

--- Check if perspective is FPP.
---
--- The lock has to stay latched for as long as FPP lasts. It used to be written
--- `if FPP and not locked then show; lock = true else lock = false end`, which
--- means that while sitting in FPP the flag flipped true/false on alternate
--- ticks and ForceShowMeter() -- ShowRequest() plus OnCameraModeChanged(), two
--- C# calls and a pcall closure each -- fired at half the loop rate, ~50 times
--- a second, to re-force a meter that was already forced.
function Event:CheckPerspective()
    if self:IsFPP() then
        if not self.is_locked_showing_meter then
            self.hud_obj:ForceShowMeter()
            self.is_locked_showing_meter = true
        end
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
            self.is_locked_operation = true
            self.av_obj.navigation_obj:AutoPilot()
        else
            self.hud_obj:ShowDriveModeDisplay()
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

-- PROBE: per-situation cost ledger (opt-in).
--
-- Turns the aggregate in the log into "<situation>/<method>", which is what
-- answers "is Waiting really more expensive than InVehicle, and which check is
-- paying for it?".  Enable with DAV.is_debug_situation_ledger = true (init.lua)
-- before the mod loads; the table prints every Prof.summary_every seconds.
--
-- To remove the probe entirely: delete this block, the require of
-- Modules/profprobe.lua at the top, and the call in init.lua.

--- Enable the ledger. Idempotent.
---@param core_class table|nil Core class table (init.lua passes it; Core is not
---        reachable from here otherwise)
---@return boolean started
function Event.EnableSituationLedger(core_class)
    if Event._situation_ledger_on then
        return false
    end
    Event._situation_ledger_on = true
    Prof.situation_enabled = true

    local function label(self)
        local ev = self
        if ev ~= nil and ev.event_obj ~= nil then
            ev = ev.event_obj
        end
        local s = ev ~= nil and ev.current_situation or nil
        return (Def.SituationName and Def.SituationName[s]) or tostring(s)
    end

    local function label_from_global()
        local core = DAV.core_obj
        local ev = core ~= nil and core.event_obj or nil
        local s = ev ~= nil and ev.current_situation or nil
        return (Def.SituationName and Def.SituationName[s]) or tostring(s)
    end

    Prof.wrap_by_situation(Event, {
        "CheckAllEvents",
        "CheckGarage",
        "CheckLanded",
        "CheckInEntryArea",
        "CheckInAV",
        "CheckHUD",
        "CheckEngine",
        "CheckDoor",
        "CheckCombat",
        "CheckDestroyed",
        "CheckDespawn",
        "CheckDistance",
        "CheckHeight",
        "CheckInput",
        "CheckAutoModeChange",
        "CheckFailAutoPilot",
        "CheckLockedSave",
        "CheckPerspective",
    }, label)

    Prof.wrap_by_situation(AV, {
        "Operate",
        "GetEulerAngles",
        "IsPlayerInEntryArea",
        "MoveThruster",
        "GetGroundPosition",
    }, label_from_global)

    Prof.wrap_by_situation(Engine, {
        "Update",
        "Run",
        "CalculateAddVelocity",
        "CalculateIdleMode",
        "ChangeVelocity",
        "AddForce",
    }, label_from_global)

    if core_class ~= nil then
        Prof.wrap_by_situation(core_class, {
            "GetActions",
            "OperateAerialVehicle",
        }, label_from_global)
    end

    return true
end

return Event
