local Camera = require("Modules/camera.lua")
local Position = require("Modules/position.lua")
local Engine = require("Modules/engine.lua")
local Utils = require("Etc/utils.lua")
local AV = {}
AV.__index = AV

--- Constractor.
---@param core_obj any Core instance
---@return table instance av instance
function AV:New(core_obj)
	---instance---
	local obj = {}
	obj.core_obj = core_obj
	obj.all_models = core_obj.all_models
	-- obj.position_obj = Position:New(core_obj.all_models)
	obj.engine_obj = Engine:New(obj)
	obj.camera_obj = Camera:New(core_obj.all_models)
	obj.log_obj = Log:New()
	obj.log_obj:SetLevel(LogLevel.Info, "AV")
	---static---
	-- door
	obj.duration_zero_wait = 0.5
	-- summon
	obj.spawn_distance = 5.5
	obj.spawn_height = 20
	obj.down_timeout = 5 -- s
	obj.up_timeout = 350
	obj.down_speed = -5.0
	-- autopiolt
	obj.profile_path = "Data/autopilot_profile.json"
	obj.destination_range = 3
	obj.destination_z_offset = 10
	obj.autopilot_angle_restore_rate = 0.005
	obj.autopilot_landing_angle_restore_rate = 0.005
	obj.standard_leaving_height = 20
	obj.exception_area_path = "Data/autopilot_exception_area.json"
	obj.check_cell_distance = 5.0 -- check cell distance when leaving
	-- thruster
	obj.thruster_angle_step = 0.6
	obj.thruster_angle_restore = 0.3
	---dynamic---
	-- common
	obj.entity_id = nil
	obj.is_blocking_operation = false
	-- door
	obj.combat_door = nil
	obj.door_input_lock_list = {seat_front_left = false, seat_front_right = false, seat_back_left = false, seat_back_right = false, trunk = false, hood = false}
	-- summon
	obj.vehicle_model_tweakdb_id = nil
	obj.vehicle_model_type = nil
	obj.active_seat = nil
	obj.active_door = nil
	obj.seat_index = 1
	obj.is_crystal_dome = false
	obj.search_ground_offset = 2
	obj.search_ground_distance = 100
	obj.collision_filters =  {"Static", "Terrain", "Water"}
	obj.weak_collision_filters = {"Static", "Terrain"}
	obj.minimum_distance_to_ground = 1.2
	-- av status
	obj.is_landed = false
	obj.is_leaving = false
	obj.is_auto_pilot = false
	obj.is_unmounting = false
	obj.is_spawning = false
	obj.is_combat = false
	-- autopiolt
	obj.autopilot_profile = nil
	obj.mappin_destination_position = Vector4.new(0, 0, 0, 1)
	obj.favorite_destination_position = Vector4.new(0, 0, 0, 1)
	obj.autopilot_speed = 1
	obj.autopilot_turn_speed = 0.01
	obj.autopilot_leaving_height = 100
	obj.autopilot_searching_range = 50
	obj.autopilot_searching_step = 5
	obj.is_failture_auto_pilot = false
	obj.autopilot_horizontal_sign = 0
	obj.autopilot_vertical_sign = 0
	obj.auto_speed_reduce_rate = 1
	obj.search_range = 1
	obj.is_search_start_swing_reverse = false
	obj.initial_destination_length = 1
	obj.dest_dir_vector_norm = 1
	obj.pre_speed_list = {x = 0, y = 0, z = 0}
	obj.autopilot_exception_area_list = {}
	obj.collision_check_side_distance = 2.5
	obj.collision_check_front_distance = 3.5
	obj.collision_check_rear_distance = 3.5
	obj.autopilot_leaving_deceleration_start_flag = false
	obj.autopilot_landing_deceleration_start_flag = false
	-- Exception area bypass parameters
	obj.exception_area_bypass_distance = 200  -- Disable exception check when within this distance to destination
	obj.is_exception_area_bypassed = false   -- Flag to track bypass status
	-- 9-direction evaluation system debug info
	obj.last_direction_evaluations = {}
	obj.last_selected_direction = nil
	obj.last_best_score = 0
	obj.last_evaluation_timestamp = 0

	-- === 5-Direction Evaluation System Parameters ===
	-- Direction priorities (lower value = higher priority)
	obj.eval_priority_forward = 1          -- Forward direction priority
	obj.eval_priority_horizontal = 1.5     -- Left/Right direction priority - Improved for better avoidance
	obj.eval_priority_up = 2.0              -- Up direction priority
	obj.eval_priority_down = 5.0            -- Down direction priority (lower priority than up)

	-- Maximum angle settings for each direction
	obj.eval_max_angle_horizontal = 90      -- Max angle for left/right directions
	obj.eval_max_angle_up = 110             -- Max angle for up direction (extended range)
	obj.eval_max_angle_down = 90            -- Max angle for down direction (standard range)

	-- Scoring parameters
	obj.eval_collision_penalty_multiplier = 8      -- Penalty per collision (increased for more conservative approach)
	obj.eval_safety_bonus_multiplier = 250         -- Safety rate bonus (safety_rate * this) - Further increased
	obj.eval_angle_efficiency_multiplier = 3       -- Angle efficiency score ((90 - |angle|) * this) - Increased for angle preference
	obj.eval_base_safety_score = 400               -- Base safety score for all directions - Further increased for safety

	-- Direction bonuses and penalties
	obj.eval_forward_bonus_multiplier = 1.2        -- Forward direction bonus (reduced for balanced competition)
	-- Safety thresholds and penalties
	obj.eval_safety_threshold_low = 0.3            -- Below this: 30% score reduction
	obj.eval_safety_threshold_medium = 0.5         -- Below this: 15% score reduction
	obj.eval_safety_penalty_low = 0.7              -- Penalty multiplier for low safety
	obj.eval_safety_penalty_medium = 0.85          -- Penalty multiplier for medium safety

	-- Safety margin evaluation system
	obj.eval_safety_margin_enabled = true          -- Enable adjacent angle safety evaluation
	obj.eval_safety_margin_range = 10              -- Check ±10 degrees around selected angle (adjusted for 5-degree steps)
	obj.eval_safety_margin_step = 5                -- Step size for safety margin evaluation (unified to 5 degrees)
	obj.eval_safety_margin_bonus_multiplier = 50   -- Bonus for good safety margins
	obj.eval_safety_margin_penalty_multiplier = 100 -- Penalty for poor safety margins

	-- Angle evaluation parameters
	obj.eval_angle_step = 5                        -- Angle evaluation step (degrees) - Unified 5-degree step for all angles

	-- Low-angle collision penalty system
	obj.eval_low_angle_penalty_enabled = true      -- Enable low-angle collision penalty
	obj.eval_low_angle_threshold = 15              -- Angles <= this get extra penalty - Expanded range
	obj.eval_low_angle_penalty_multiplier = 2.5    -- Extra penalty multiplier for low angles - Increased for stronger avoidance

	-- High-angle collision penalty system
	obj.eval_high_angle_threshold = 60             -- Angles >= this get moderate penalty
	obj.eval_high_angle_penalty_multiplier = 1.3   -- Moderate penalty multiplier for high angles - Reduced for balance

	-- Dead-end avoidance system
	obj.deadend_score_threshold = 50               -- Threshold score to determine dead-end situation
	obj.deadend_vertical_escape_distance = 20     -- Distance to ascend when escaping dead-end (meters)
	obj.deadend_escape_check_interval = 3         -- Seconds between dead-end escape attempts
	obj.is_deadend_escape_active = false          -- Flag for dead-end escape mode
	obj.deadend_escape_target_z = nil             -- Target altitude for dead-end escape
	obj.deadend_last_check_time = 0               -- Last time dead-end was checked

	-- appearance
	obj.is_enable_crystal_dome = false
	obj.is_enable_landing_vfx = false
	obj.landing_vfx_component = nil
	obj.is_landing_projection = false
	obj.destroy_app = nil
	-- audio
	obj.engine_audio_name = nil
	obj.is_acceleration_sound = false
	obj.is_thruster_sound = false
	-- truster
	obj.is_available_thruster = false
	obj.engine_component_name_list = {}
	obj.engine_offset_list = {}
	obj.thruster_fx_name_list = {}
	obj.thruster_offset_list = {}
	obj.engine_components = {}
	obj.thruster_fxs = {}
	obj.thruster_angle = 0
	obj.thruster_angle_max = 0
	-- enter and exit
	obj.enter_point = {}
	obj.entry_area_radius = 0
	obj.exit_point = {}
	-- landing
	obj.minimum_distance_to_ground = 1.2
	return setmetatable(obj, self)
end

--- Initialize
function AV:Init()
	self.camera_obj:Init()

	local index = DAV.model_index
	local type_number = DAV.model_type_index

	self.vehicle_model_tweakdb_id = self.all_models[index].tweakdb_id
	self.vehicle_model_type = self.all_models[index].type[type_number]
	self.active_seat = self.all_models[index].actual_allocated_seat
	self.active_door = self.all_models[index].actual_allocated_door
	self.exit_duration = self.all_models[index].exit_duration
	self.combat_door = self.all_models[index].combat_door
	self.is_enable_crystal_dome = self.all_models[index].crystal_dome
	self.is_enable_landing_vfx = self.all_models[index].landing_vfx
	self.projection_offset = self.all_models[index].projection_offset
	self.engine_audio_name = self.all_models[index].engine_audio_name
	self.is_enable_manual_speed_meter = self.all_models[index].manual_speed_meter
	self.is_enable_manual_rpm_meter = self.all_models[index].manual_rpm_meter
	self.is_armed = self.all_models[index].armed
	self.engine_component_name_list = self.all_models[index].engine_component_name
	self.engine_offset_list = self.all_models[index].engine_component_offset
	self.thruster_fx_name_list = self.all_models[index].thruster_fx_name
	self.thruster_offset_list = self.all_models[index].thruster_fx_offset
	self.thruster_angle_max = self.all_models[index].thruster_angle_max
	self.destroy_app = self.all_models[index].destroy_app
	self.entry_point = { x = self.all_models[index].entry_point.x, y = self.all_models[index].entry_point.y, z = self.all_models[index].entry_point.z }
    self.entry_area_radius = self.all_models[index].entry_area_radius
	self.exit_point = {x = self.all_models[index].exit_point.x, y = self.all_models[index].exit_point.y, z = self.all_models[index].exit_point.z}
	self.minimum_distance_to_ground = self.all_models[index].minimum_distance_to_ground
	self.flight_mode = self.all_models[DAV.model_index].flight_mode

	-- read autopilot profile
	local speed_level = DAV.user_setting_table.autopilot_speed_level
	self.autopilot_profile = Utils:ReadJson(self.profile_path)
	self.autopilot_speed = self.autopilot_profile[speed_level].speed
	self.autopilot_acceleration = self.autopilot_profile[speed_level].acceleration
	self.autopilot_turn_speed = self.autopilot_profile[speed_level].turn_speed
	self.autopilot_leaving_height = self.autopilot_profile[speed_level].leaving_height
	self.autopilot_searching_range = self.autopilot_profile[speed_level].searching_range
	self.autopilot_searching_step = self.autopilot_profile[speed_level].searching_step
	self.autopilot_min_speed_rate = self.autopilot_profile[speed_level].min_speed_rate
	self.autopilot_is_only_horizontal = self.autopilot_profile[speed_level].is_only_horizontal
	self.autopilot_exception_area_list = Utils:ReadJson(self.exception_area_path)
	self.collision_check_side_distance = self.all_models[index].collision_check_side_distance
	self.collision_check_front_distance = self.all_models[index].collision_check_front_distance or self.collision_check_side_distance
	self.collision_check_rear_distance = self.all_models[index].collision_check_rear_distance or self.collision_check_side_distance
end

--- Check if player is mounted.
---@return boolean
function AV:IsPlayerIn()
	if self.entity_id == nil then
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		return false
	end
	return entity:IsPlayerMounted()
end

--- Check if AV is spawning.
---@return boolean
function AV:IsSpawning()
	return self.is_spawning
end

--- Check if AV is destroyed.
---@return boolean
function AV:IsDestroyed()
	if self.entity_id == nil then
		return true
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		return true
	end
	return entity:IsDestroyed()
end

--- Check if AV is despawned.
---@return boolean
function AV:IsDespawned()
	if self.entity_id == nil then
		return true
	end
	if Game.FindEntityByID(self.entity_id) == nil then
		return true
	else
		return false
	end
end

--- Get AV position.
---@return Vector4
function AV:GetPosition()
	if self.entity_id == nil then
		return Vector4.Zero()
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		return Vector4.Zero()
	end
	return entity:GetWorldPosition()
end

--- Get Vehicle Forward Vector
---@return Vector4
function AV:GetForward()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No vehicle entity id for GetForward")
		return Vector4.new(0, 0, 0, 1.0)
	end
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetForward")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return entity:GetWorldForward()
end

--- Get Vehicle Right Vector
---@return Vector4
function AV:GetRight()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No vehicle entity id for GetRight")
		return Vector4.new(0, 0, 0, 1.0)
	end
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetRight")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return entity:GetWorldRight()
end

--- Get Vehicle Up Vector
---@return Vector4
function AV:GetUp()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No vehicle entity id for GetUp")
		return Vector4.new(0, 0, 0, 1.0)
	end
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetUp")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return entity:GetWorldUp()
end

--- Get Vehicle Quaternion
---@return Quaternion
function AV:GetQuaternion()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No vehicle entity id for GetQuaternion")
		return Quaternion.new(0, 0, 0, 1.0)
	end
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetQuaternion")
        return Quaternion.new(0, 0, 0, 1.0)
    end
    return entity:GetWorldOrientation()
end

--- Get Vehicle EulerAngles
---@return EulerAngles
function AV:GetEulerAngles()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No vehicle entity id for GetEulerAngles")
		return EulerAngles.new(0, 0, 0)
	end
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetEulerAngles")
        return EulerAngles.new(0, 0, 0)
    end
    return entity:GetWorldOrientation():ToEulerAngles()
end

--- Get Ground Position
---@return number z
function AV:GetGroundPosition()
    local current_position = self:GetPosition()
	if current_position == nil then
		self.log_obj:Record(LogLevel.Warning, "No position to get ground position")
		return 0
	end
    current_position.z = current_position.z + self.search_ground_offset
    for _, filter in ipairs(self.collision_filters) do
        local is_success, trace_result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_position, Vector4.new(current_position.x, current_position.y, current_position.z - self.search_ground_distance, 1.0), filter, false, false)
        if is_success then
            return trace_result.position.z
        end
    end
    return current_position.z - self.search_ground_distance - 1
end

--- Get Height between ground and vehicle
---@return number height
function AV:GetHeight()
    return self:GetPosition().z - self:GetGroundPosition()
end

function AV:GetCurrentSpeed()
	local vel_vec3, _ = self.engine_obj:GetDirectionAndAngularVelocity()
	local vel_vec4 = Vector4.Vector3To4(vel_vec3)
	return vel_vec4:Length()
end

--- Check if player is mounted combat seat.
---@return boolean
function AV:IsMountedCombatSeat()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity id to check combat seat")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to check combat seat")
		return false
	end
	if not entity:IsPlayerMounted() then
		self.log_obj:Record(LogLevel.Trace, "Check Combat Seat: No player mounted")
		return false
	end
	if self.is_armed and self.active_seat[self.seat_index] == "seat_front_left" then
		return true
	else
		return false
	end
end

--- Check if engine is on.
---@return boolean
function AV:IsEngineOn()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity id to check engine")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to check engine")
		return false
	end
	return entity:IsEngineTurnedOn()
end

--- Spawn AV.
---@return boolean
function AV:Spawn(position, angle)
	if self.entity_id ~= nil then
		self.log_obj:Record(LogLevel.Info, "Entity already spawned")
		return false
	end

	self.is_spawning = true

	local entity_system = Game.GetDynamicEntitySystem()
	local entity_spec = DynamicEntitySpec.new()

	entity_spec.recordID = self.vehicle_model_tweakdb_id
	entity_spec.appearanceName = self.vehicle_model_type
	entity_spec.position = position
	entity_spec.orientation = angle
	entity_spec.persistState = false
	entity_spec.persistSpawn = false
	self.entity_id = entity_system:CreateEntity(entity_spec)

	-- set entity id to position object
	Cron.Every(0.1, {tick = 1}, function(timer)
		local entity = Game.FindEntityByID(self.entity_id)
		if entity ~= nil then
			self.landing_vfx_component = entity:FindComponentByName("LandingVFXSlot")
			self.engine_obj:Init(self.entity_id)
			self.engine_obj:UnsetPhysicsState()
			self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
			self.engine_obj:EnableGravity(false)
			self.is_spawning = false
			Cron.After(0.5, function()
				self.core_obj.event_obj.sound_obj:StartEngineSound(self.flight_mode, 1.5)
				if self:SetThrusterComponent() then
					self.is_available_thruster = true
				else
					self.is_available_thruster = false
				end
			end)
			Cron.Halt(timer)
		end
	end)

	return true
end

--- Spawn AV at sky.
function AV:SpawnToSky()
	local position = self:GetSpawnPosition(self.spawn_distance, 0.0)
	position.z = position.z + self.spawn_height
	local angle = self:GetSpawnOrientation(90.0)
	self:Spawn(position, angle)
	Cron.Every(DAV.time_resolution, { tick = 1 }, function(timer)
		if not self.core_obj.event_obj:IsInMenuOrPopupOrPhoto() and not self.is_spawning then
			local height = self:GetHeight()
			self.log_obj:Record(LogLevel.Trace, "Current Height In Spawning: " .. height)
			if timer.tick == 1 then
				self:DisableAllDoorInteractions()
				self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, self.down_speed))
				self.log_obj:Record(LogLevel.Info, "Initial Spawn Velocity: " .. self.engine_obj:GetDirectionVelocity().z)
			elseif height < self.minimum_distance_to_ground or timer.tick > (self.down_timeout / DAV.time_resolution) or self.core_obj.event_obj:GetSituation() ~= Def.Situation.Landing then
				self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
				self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
				self.is_landed = true
				self.log_obj:Record(LogLevel.Info, "Spawn to sky success")
				Cron.Halt(timer)
			elseif height < 10 and self.engine_obj:GetControlType() ~= Def.EngineControlType.FluctuationVelocity then
				self.engine_obj:SetFluctuationVelocityParams(-2, 1)
				self.log_obj:Record(LogLevel.Info, "Fluctuation Velocity")
			end
			timer.tick = timer.tick + 1
		end
	end)
end

--- Despawn AV.
---@return boolean
function AV:Despawn()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to despawn")
		return false
	end
	local entity_system = Game.GetDynamicEntitySystem()
	entity_system:DeleteEntity(self.entity_id)
	self.entity_id = nil
	return true
end

--- Despawn AV when it is on ground.
function AV:DespawnFromGround()
	Cron.Every(0.01, { tick = 1 }, function(timer)
		if not self.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
			local _, _, _, roll_idle, pitch_idle, yaw_idle = self.engine_obj:CalculateAddVelocity({Def.ActionList.Idle, 1})
			self.engine_obj:OnlyAngularRun(roll_idle, pitch_idle, yaw_idle)
			if timer.tick == 1 then
				self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
				self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 1))
				self.log_obj:Record(LogLevel.Info, "Initial Despawn Velocity: " .. self.engine_obj:GetDirectionVelocity().z)
			elseif timer.tick == 2 then
				self.engine_obj:SetFluctuationVelocityParams(1, math.abs(self.down_speed))
				self.log_obj:Record(LogLevel.Info, "Fluctuation Velocity")
			elseif timer.tick >= self.up_timeout then
				self.log_obj:Record(LogLevel.Info, "Despawn Timeout")
				self.core_obj.event_obj.sound_obj:StopEngineSound(self.flight_mode, 1.5)
				Cron.After(1.5, function()
					self:Despawn()
				end)
				Cron.Halt(timer)
			end
			timer.tick = timer.tick + 1
		end
	end)
end

--- Toggle crystal dome ON/OFF.
---@return boolean
function AV:ToggleCrystalDome()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity id to change crystal dome")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local effect_name
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change crystal dome")
		return false
	elseif not self.is_enable_crystal_dome then
		self.log_obj:Record(LogLevel.Trace, "This vehicle does not have a crystal dome")
		return false
	end
	if not self.is_crystal_dome then
		effect_name = CName.new("crystal_dome_start")
		self.is_crystal_dome = true
	else
		effect_name = CName.new("crystal_dome_stop")
		self.is_crystal_dome = false
	end
	GameObjectEffectHelper.StartEffectEvent(entity, effect_name, false)
	return true
end

--- (Unused) Unlock all doors.
---@return boolean
function AV:UnlockDoor()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:UnlockAllVehDoors()
	return true
end

--- (Unused) Lock all doors.
---@return boolean
function AV:LockDoor()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity id to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:QuestLockAllVehDoors()
	return true
end

--- Disable all door interactions for preventing unexpected mounting.
---@return boolean
function AV:DisableAllDoorInteractions()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity id to change door lock")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local vehicle_ps = entity:GetVehiclePS()
	vehicle_ps:DisableAllVehInteractions()
	return true
end

--- Get door state.
---@param e_veh_door EVehicleDoor
---@return VehicleDoorState | nil
function AV:GetDoorState(e_veh_door)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Trace, "No entity id to get door state")
		return nil
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Trace, "No entity to get door state")
		return nil
	end
	local vehicle_ps = entity:GetVehiclePS()
	return vehicle_ps:GetDoorState(e_veh_door)
end

--- Change door state.
---@param door_state Def.DoorOperation
---@return boolean
function AV:ChangeDoorState(door_state, door_name_list)
	for _, input_lock in pairs(self.door_input_lock_list) do
		if input_lock then
			self.log_obj:Record(LogLevel.Info, "Door input is locked")
			return false
		end
	end

	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to get door state")
		return false
	end

	-- local vehicle_ps = self.position_obj.entity:GetVehiclePS()
	local vehicle_ps = Game.FindEntityByID(self.entity_id):GetVehiclePS()

	if door_name_list == nil then
		door_name_list = self.active_door
	end

	for _, door_name in ipairs(door_name_list) do
		local e_veh_door = EVehicleDoor.seat_front_left
		if door_name == "seat_front_left" then
			e_veh_door = EVehicleDoor.seat_front_left
		elseif door_name == "seat_front_right" then
			e_veh_door = EVehicleDoor.seat_front_right
		elseif door_name == "seat_back_left" then
			e_veh_door = EVehicleDoor.seat_back_left
		elseif door_name == "seat_back_right" then
			e_veh_door = EVehicleDoor.seat_back_right
		elseif door_name == "trunk" then
			e_veh_door = EVehicleDoor.trunk
		elseif door_name == "hood" then
			e_veh_door = EVehicleDoor.hood
		end

		local door_event = nil
		if door_state == Def.DoorOperation.Open then
			door_event = VehicleDoorOpen.new()
		elseif door_state == Def.DoorOperation.Close then
			door_event = VehicleDoorClose.new()
		elseif door_state == Def.DoorOperation.Change then
			if self:GetDoorState(e_veh_door) == VehicleDoorState.Closed then
				door_event = VehicleDoorOpen.new()
			elseif self:GetDoorState(e_veh_door) == VehicleDoorState.Open then
				door_event = VehicleDoorClose.new()
			end
		end
		if door_event == nil then
			self.log_obj:Record(LogLevel.Error, "Door event is not valid")
			return false
		end

		self.log_obj:Record(LogLevel.Info, "Change Door State : " .. door_name .. " : " .. door_state)

		door_event.slotID = CName.new(door_name)
        door_event.forceScene = false
		vehicle_ps:QueuePSEvent(vehicle_ps, door_event)

	end
	return true
end

--- Toggle crystal dome ON/OFF.
function AV:ControlCrystalDome()
	local e_veh_door = EVehicleDoor.seat_front_left
	if not self.is_crystal_dome then
		Cron.Every(1, {tick = 1}, function(timer)
			if self:GetDoorState(e_veh_door) == VehicleDoorState.Closed then
				if self.vehicle_model_tweakdb_id == DAV.excalibur_record then
					Cron.After(3.0, function()
						self:ToggleCrystalDome()
					end)
				else
					self:ToggleCrystalDome()
				end
				Cron.Halt(timer)
			end
		end)
	elseif self.is_crystal_dome then
		self:ToggleCrystalDome()
	end
end

--- Mount AV.
---@return boolean
function AV:Mount()
	self.is_landed = false
	self.camera_obj:SetPerspective(self.seat_index)

	local seat_number = self.seat_index

	self.log_obj:Record(LogLevel.Debug, "Mount Aerial Vehicle : " .. seat_number)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to mount")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	local player = Game.GetPlayer()
	local ent_id = entity:GetEntityID()
	local seat = self.active_seat[seat_number]

	local mount_data = MountEventData.new()
	mount_data.isInstant = false
	mount_data.slotName = seat
	mount_data.mountParentEntityId = ent_id

	local slot_id = MountingSlotId.new()
	slot_id.id = seat

	local mounting_info = MountingInfo.new()
	mounting_info.childId = player:GetEntityID()
	mounting_info.parentId = ent_id
	mounting_info.slotId = slot_id

	local mounting_request = MountingRequest.new()
	mounting_request.lowLevelMountingInfo = mounting_info
	mounting_request.mountData = mount_data

	Game.GetMountingFacility():Mount(mounting_request)

	if self.active_seat[seat_number] ~= "seat_front_left" and not self.is_crystal_dome then
		self:ToggleCrystalDome()
	else
		self.is_crystal_dome = true
	end

	return true
end

--- Unmount AV.
---@return boolean
function AV:Unmount()
	if self.is_unmounting then
		return false
	end

	self.is_unmounting = true

	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to unmount")
		self.is_unmounting = false
		return false
	end

	if self.is_crystal_dome then
		self:ControlCrystalDome()
	end

	self:ChangeDoorState(Def.DoorOperation.Open)

	local unmount_wait_time = self.exit_duration
	if unmount_wait_time == 0 then
		unmount_wait_time = self.duration_zero_wait
	end

	Cron.After(unmount_wait_time, function()

		self.log_obj:Record(LogLevel.Trace, "Unmount Aerial Vehicle : " .. self.seat_index)

		-- set entity id to position object
		Cron.Every(0.01, {tick = 1}, function(timer)
			timer.tick = timer.tick + 1
			if not self:IsPlayerIn() then
				self.log_obj:Record(LogLevel.Info, "Unmounted")
				local player = Game.GetPlayer()
				local entity = Game.FindEntityByID(self.entity_id)
				local vehicle_angle = entity:GetWorldOrientation():ToEulerAngles()
				local teleport_angle = EulerAngles.new(vehicle_angle.roll, vehicle_angle.pitch, vehicle_angle.yaw + 90)
				local position = self:GetExitPosition()
				Game.GetTeleportationFacility():Teleport(player, Vector4.new(position.x, position.y, position.z, 1.0), teleport_angle)
				self.is_unmounting = false
				Cron.Halt(timer)
			elseif timer.tick > 350 then
				self.log_obj:Record(LogLevel.Error, "Unmount failed")
				self:ChangeDoorState(Def.DoorOperation.Close)
				self.is_unmounting = false
				Cron.Halt(timer)
			end
		end)
	end)
	return true
end

---@param on boolean
function AV:BlockOperation(on)
	if on then
		self.is_blocking_operation = true
		self.engine_obj:SetControlType(Def.EngineControlType.Blocking)
		self.engine_obj:EnableOriginalPhysics(true)
		self.engine_obj:EnableGravity(true)
	else
		self.is_blocking_operation = false
		if self:IsPlayerIn() then
			self.engine_obj:SetControlType(Def.EngineControlType.AddForce)
		else
			self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
		end
		self.engine_obj:EnableOriginalPhysics(false)
		self.engine_obj:EnableGravity(false)
	end
end

--- Execute action commands.
---@param action_command_lists table
function AV:Operate(action_command_lists)
	local x_total, y_total, z_total, roll_total, pitch_total, yaw_total = 0, 0, 0, 0, 0, 0
	-- self.log_obj:Record(LogLevel.Debug, "Operation Count:" .. #action_command_lists)
	for _, action_command_list in ipairs(action_command_lists) do
		if action_command_list[1] >= Def.ActionList.Enter then
			self.log_obj:Record(LogLevel.Critical, "Invalid Event Command:" .. action_command_list[1])
			return false
		end
		if action_command_list[1] == Def.ActionList.Idle then
			self.engine_obj:SetIdle(true)
		else
			self.engine_obj:SetIdle(false)
		end
		if not self.is_auto_pilot then
			local x, y, z, roll, pitch, yaw = self.engine_obj:CalculateAddVelocity(action_command_list)
			x = x * action_command_list[2]
			y = y * action_command_list[2]
			z = z * action_command_list[2]
			roll = roll * action_command_list[2]
			pitch = pitch * action_command_list[2]
			yaw = yaw * action_command_list[2]
			x_total = x_total + x
			y_total = y_total + y
			z_total = z_total + z
			roll_total = roll_total + roll
			pitch_total = pitch_total + pitch
			yaw_total = yaw_total + yaw
		end
	end

	if not self.is_auto_pilot then
		self.engine_obj:Run(x_total, y_total, z_total, roll_total, pitch_total, yaw_total)
		self:MoveThruster(action_command_lists)
		self:ControlSound(action_command_lists)
	end

	return true
end

--- Control sound.
---@param action_command_lists table
---@return boolean
function AV:ControlSound(action_command_lists)
	local is_acceleration_sound = false
	local is_thruster_sound = false
	for _, action_command_list in ipairs(action_command_lists) do
		if action_command_list[1] >= Def.ActionList.Enter then
			self.log_obj:Record(LogLevel.Trace, "Invalid Sound Command:" .. action_command_list[1])
			return false
		end
		for _, acceleration_command in pairs(Def.AccelerationActionList) do
			if action_command_list[1] == acceleration_command then
				is_acceleration_sound = true
				break
			end
		end
		for _, thruster_command in pairs(Def.ThrusterActionList) do
			if action_command_list[1] == thruster_command then
				is_thruster_sound = true
				break
			end
		end
		if is_acceleration_sound or is_thruster_sound then
			break
		end
	end

	if not self.is_acceleration_sound and is_acceleration_sound then
		self.log_obj:Record(LogLevel.Trace, "Start Acceleration Sound")
		self.core_obj.event_obj.sound_obj:StartAccelerationSound(self.flight_mode, 1.5)
		self.is_acceleration_sound = true
		return true
	elseif self.is_acceleration_sound and not is_acceleration_sound then
		self.log_obj:Record(LogLevel.Trace, "Stop Acceleration Sound")
		self.core_obj.event_obj.sound_obj:StopAccelerationSound(self.flight_mode, 1.5)
		self.is_acceleration_sound = false
		return true
	elseif not self.is_thruster_sound and is_thruster_sound then
		self.log_obj:Record(LogLevel.Trace, "Start Thruster Sound")
		self.core_obj.event_obj.sound_obj:StartThrusterSound(self.flight_mode, 1.5)
		self.is_thruster_sound = true
		return true
	elseif self.is_thruster_sound and not is_thruster_sound then
		self.log_obj:Record(LogLevel.Trace, "Stop Thruster Sound")
		self.core_obj.event_obj.sound_obj:StopThrusterSound(self.flight_mode, 1.5)
		self.is_thruster_sound = false
		return true
	end
	return true

end

--- Set destination by mappin.
---@param position Vector4
function AV:SetMappinDestination(position)
	self.mappin_destination_position = position
end

--- Set registered favorite destination.
---@param position Vector4
function AV:SetFavoriteDestination(position)
	self.favorite_destination_position = position
end

--- Excute Auto Pilot.
---@return boolean
function AV:AutoPilot()
	self.log_obj:Record(LogLevel.Info, "AutoPilot Start")
	self.is_auto_pilot = true
	local destination_position = Vector4.new(0, 0, 0, 1)
	local relay_position = nil
	if DAV.user_setting_table.autopilot_selected_index == 0 then
		if self.mappin_destination_position:IsZero() then
			self.log_obj:Record(LogLevel.Warning, "No Mappin Destination")
			self:InterruptAutoPilot()
			return false
		end
		destination_position = self.mappin_destination_position
		self.log_obj:Record(LogLevel.Info, "AutoPilot to Mappin Destination")
	else
		destination_position = self.favorite_destination_position
		self.log_obj:Record(LogLevel.Info, "AutoPilot to Favorite Destination")
	end

	destination_position.z = destination_position.z + self.destination_z_offset

	local current_position = self:GetPosition()

	local direction_vector = Vector4.new(destination_position.x - current_position.x, destination_position.y - current_position.y, destination_position.z - current_position.z, 1)
	self.initial_destination_length = Vector4.Length(direction_vector)

	if self.autopilot_is_only_horizontal then
		self:AutoLeaving(direction_vector, self.autopilot_leaving_height - current_position.z)
		self.log_obj:Record(LogLevel.Info, "Select Leaving Only Horizontal")
	else
		self:AutoLeaving(direction_vector, self.standard_leaving_height)
		self.log_obj:Record(LogLevel.Info, "Select Leaving Horizontal and Vertical")
	end

	-- autopilot parameter initialize
	self.autopilot_angle = 0
	self.autopilot_horizontal_sign = 0
	self.autopilot_vertical_sign = 0
	self.auto_speed_reduce_rate = 1
	self.pre_speed_list = {x = 0, y = 0, z = 0}

	-- autopilot loop
	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1

		if self.is_leaving or self.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
			return
		end

		if not self.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
			Cron.Halt(timer)
			return
		elseif self:IsCollision() then
			self.log_obj:Record(LogLevel.Info, "Collision Detected")
			self:InterruptAutoPilot()
			Cron.Halt(timer)
			return
		end

		-- set destination vector
		current_position = self:GetPosition()
		local dest_dir_vector = Vector4.new(destination_position.x - current_position.x, destination_position.y - current_position.y, destination_position.z - current_position.z, 1)
		if self.autopilot_is_only_horizontal then
			dest_dir_vector.z = 0
		elseif dest_dir_vector.z < 0 then
			dest_dir_vector.z = 0
		end
		self.dest_dir_vector_norm = Vector4.Length2D(dest_dir_vector)

		-- Update exception area bypass status based on distance to destination
		self:UpdateExceptionAreaBypass()

		-- check destination
		if self.dest_dir_vector_norm < self.destination_range then
			self.log_obj:Record(LogLevel.Info, "Arrived at destination")
			self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			self:AutoLanding(current_position.z - destination_position.z + self.destination_z_offset)
			Cron.Halt(timer)
			return
		end

		-- set direction vector
		if relay_position ~= nil then
			direction_vector = Vector4.new(relay_position.x - current_position.x, relay_position.y - current_position.y, relay_position.z - current_position.z, 1)
		end
		local direction_vector_norm = Vector4.Length(direction_vector)

		-- check destination
		if relay_position ~= nil and direction_vector_norm < self.destination_range then
			relay_position = nil
		end

		-- decide relay position
		if relay_position == nil then
			local dest_dir_2d = Vector4.new(dest_dir_vector.x, dest_dir_vector.y, 0, 1)
			local search_vec = Vector4.Zero()
			local is_wall = true

			self.search_range = self.autopilot_searching_range
			if self.dest_dir_vector_norm < self.autopilot_searching_range then
				self.search_range = self.dest_dir_vector_norm + 0.1
			end

			if self.search_range < self.autopilot_searching_step then
				self.search_range = self.autopilot_searching_step
			end

			-- Path finding logic execution flag
			local path_found = false

				-- 5-direction evaluation system: 5 primary directions only
				local directions = {
					{name = "Forward", vector = dest_dir_2d, base_angle = 0, swing_dir = "Horizontal", priority = self.eval_priority_forward},
					{name = "Left", vector = dest_dir_2d, base_angle = 0, swing_dir = "Horizontal", priority = self.eval_priority_horizontal, direction_sign = 1},
					{name = "Right", vector = dest_dir_2d, base_angle = 0, swing_dir = "Horizontal", priority = self.eval_priority_horizontal, direction_sign = -1},
					{name = "Up", vector = dest_dir_vector, base_angle = 0, swing_dir = "Vertical", priority = self.eval_priority_up, direction_sign = 1},
					{name = "Down", vector = dest_dir_vector, base_angle = 0, swing_dir = "Vertical", priority = self.eval_priority_down, direction_sign = -1}
				}

				local best_direction = nil
				local best_score = -1
				local best_vec = Vector4.Zero()
				local best_angle = 0

				-- Evaluate safety for each direction
				for _, dir in ipairs(directions) do
					local direction_best_score = -1
					local direction_best_angle = 0
					local direction_best_vec = Vector4.Zero()
					local direction_best_safety_margin = 0  -- Store best safety margin score
					local collision_count = 0          -- Actual collision count (for display)
					local collision_penalty_score = 0  -- Weighted penalty score (for calculation)
						local total_tests = 0
						local safe_angles = {}

						-- Dynamic angle test: evaluate appropriate angle ranges for each direction
						local angle_step = self.eval_angle_step  -- Parameterized angle evaluation step
						local start_angle = 0
						local max_test_angle = 90

						-- Set maximum test angle based on direction
						if dir.name == "Up" then
							max_test_angle = self.eval_max_angle_up         -- 110 degrees for up direction
						elseif dir.name == "Down" then
							max_test_angle = self.eval_max_angle_down       -- 90 degrees for down direction
						elseif dir.name == "Left" or dir.name == "Right" then
							max_test_angle = self.eval_max_angle_horizontal -- 90 degrees for horizontal directions
						end

						-- Set starting angle for each direction (avoid Forward duplication)
						if dir.name == "Forward" then
							-- Forward direction: only test 0 degrees directly, no loop needed
							local actual_angle = 0
							total_tests = 1
							local is_check_exception = true
							local res, vec = self:IsWall(dir.vector, self.search_range, actual_angle, dir.swing_dir, is_check_exception, "advanced")

							if not res then
								-- No collision: record as a safe angle
								table.insert(safe_angles, {angle = actual_angle, vec = vec})
							else
								-- Collision: count as penalty
								collision_count = 1  -- Actual collision count
								collision_penalty_score = 1  -- Base penalty
								-- Low angle penalty (0 degrees is always low angle)
								if self.eval_low_angle_penalty_enabled then
									collision_penalty_score = collision_penalty_score + (self.eval_low_angle_penalty_multiplier - 1)
								end
							end
						else
							-- Other directions: use loop with unified 5-degree step evaluation
							start_angle = angle_step  -- Left/Right/Up/Down start from angle_step degrees

							for test_angle = start_angle, max_test_angle, angle_step do
								local actual_angle = test_angle
								if dir.direction_sign then
									actual_angle = test_angle * dir.direction_sign
								end

								-- Angle range restriction: use direction-specific max angles
								local min_angle, max_angle = -90, 90  -- Default range
								if dir.name == "Up" then
									max_angle = self.eval_max_angle_up      -- 110 degrees for up direction
								elseif dir.name == "Down" then
									max_angle = self.eval_max_angle_down    -- 90 degrees for down direction
								elseif dir.name == "Left" or dir.name == "Right" then
									max_angle = self.eval_max_angle_horizontal  -- 90 degrees for horizontal directions
								end

								if actual_angle >= min_angle and actual_angle <= max_angle then
									total_tests = total_tests + 1
									local is_check_exception = true
									if dir.swing_dir == "Vertical" and math.abs(actual_angle) >= max_angle then
										is_check_exception = false
									end

									local res, vec = self:IsWall(dir.vector, self.search_range, actual_angle, dir.swing_dir, is_check_exception, "advanced")

									if not res then
										-- No collision: record as a safe angle
										table.insert(safe_angles, {angle = actual_angle, vec = vec})
									else
										-- Collision: count as penalty with angle-based multiplier
										collision_count = collision_count + 1  -- Actual collision count
										collision_penalty_score = collision_penalty_score + 1  -- Base penalty

										-- Apply graduated penalty based on angle (low angle = most dangerous, high angle = moderately dangerous)
										local angle_abs = math.abs(actual_angle)
										if self.eval_low_angle_penalty_enabled and angle_abs <= self.eval_low_angle_threshold then
											-- Low angle: most dangerous (e.g., 0-10 degrees)
											collision_penalty_score = collision_penalty_score + (self.eval_low_angle_penalty_multiplier - 1)
										elseif angle_abs >= self.eval_high_angle_threshold then
											-- High angle: moderately dangerous (e.g., 60-90 degrees)
											collision_penalty_score = collision_penalty_score + (self.eval_high_angle_penalty_multiplier - 1)
										end
										-- Medium angles (11-59 degrees) get standard penalty (no extra multiplier)
									end
								end
							end
						end

					-- Evaluate overall safety for the direction
					local safety_rate = 0
					if total_tests > 0 then
						safety_rate = (#safe_angles) / total_tests
					end

					-- Collision penalty: more collisions result in a significant score reduction
					local collision_penalty = collision_penalty_score * self.eval_collision_penalty_multiplier

					-- Safety bonus: higher safety rate yields higher score
					local safety_bonus = safety_rate * self.eval_safety_bonus_multiplier

					-- Calculate score for each safe angle
					for _, safe_angle_data in ipairs(safe_angles) do
						local actual_angle = safe_angle_data.angle
						local vec = safe_angle_data.vec

						-- Angle efficiency score: optimized for effective avoidance
						local angle_abs = math.abs(actual_angle)
						local angle_efficiency_score
						if angle_abs <= 5 then
							-- Very small angles: moderate score
							angle_efficiency_score = (90 - angle_abs) * self.eval_angle_efficiency_multiplier
						elseif angle_abs <= 30 then
							-- Optimal avoidance range: bonus score
							angle_efficiency_score = (90 - angle_abs) * self.eval_angle_efficiency_multiplier * 1.3
						elseif angle_abs <= 60 then
							-- Good avoidance range: standard score
							angle_efficiency_score = (90 - angle_abs) * self.eval_angle_efficiency_multiplier
						else
							-- Large angles: reduced but still viable
							angle_efficiency_score = (90 - angle_abs) * self.eval_angle_efficiency_multiplier * 0.8
						end

						-- Base safety score
						local base_safety_score = self.eval_base_safety_score

						-- Safety margin evaluation: check adjacent angles for safer routes
						local safety_margin_score = 0
						if self.eval_safety_margin_enabled and dir.name ~= "Forward" then
							local margin_safe_count = 0
							local margin_total_count = 0
							local margin_range = self.eval_safety_margin_range

							-- Check angles around the selected angle for safety margin
							for margin_offset = -margin_range, margin_range, 5 do
								if margin_offset ~= 0 then  -- Skip the current angle itself
									local margin_test_angle = actual_angle + margin_offset
									-- Keep within reasonable bounds
									if margin_test_angle >= -90 and margin_test_angle <= 90 then
										margin_total_count = margin_total_count + 1
										local is_check_exception = true
										if dir.swing_dir == "Vertical" and math.abs(margin_test_angle) >= 90 then
											is_check_exception = false
										end

										local res, _ = self:IsWall(dir.vector, self.search_range, margin_test_angle, dir.swing_dir, is_check_exception, "advanced")
										if not res then
											margin_safe_count = margin_safe_count + 1
										end
									end
								end
							end

							-- Calculate safety margin score
							if margin_total_count > 0 then
								local margin_safety_rate = margin_safe_count / margin_total_count
								if margin_safety_rate >= 0.8 then
									-- Excellent safety margin: significant bonus
									safety_margin_score = self.eval_safety_margin_bonus_multiplier * 1.5
								elseif margin_safety_rate >= 0.6 then
									-- Good safety margin: standard bonus
									safety_margin_score = self.eval_safety_margin_bonus_multiplier
								elseif margin_safety_rate >= 0.4 then
									-- Moderate safety margin: small bonus
									safety_margin_score = self.eval_safety_margin_bonus_multiplier * 0.5
								elseif margin_safety_rate < 0.2 then
									-- Poor safety margin: penalty for risky routes
									safety_margin_score = -self.eval_safety_margin_penalty_multiplier
								end
								-- 0.2-0.4 range: neutral (no bonus or penalty)
							end
						end

						-- Total score calculation including safety margin
						local total_score = base_safety_score + angle_efficiency_score + safety_bonus + safety_margin_score - collision_penalty

						-- Bonus for forward direction (directness to destination)
						if dir.name == "Forward" then
							total_score = total_score * self.eval_forward_bonus_multiplier
						end

						-- Consider direction priority
						total_score = total_score / dir.priority

						-- Additional penalty if overall safety is low
						if safety_rate < self.eval_safety_threshold_low then
							total_score = total_score * self.eval_safety_penalty_low
						elseif safety_rate < self.eval_safety_threshold_medium then
							total_score = total_score * self.eval_safety_penalty_medium
						end

						-- Update best score for this direction
						if total_score > direction_best_score then
							direction_best_score = total_score
							direction_best_angle = actual_angle
							direction_best_vec = vec
							direction_best_safety_margin = safety_margin_score  -- Store safety margin for debug
						end
					end

					-- Compare with overall best score
					if direction_best_score > best_score then
						best_score = direction_best_score
						best_direction = dir
						best_vec = direction_best_vec
						best_angle = direction_best_angle
					end

					-- Store evaluation result for debug display
					self.last_direction_evaluations[dir.name] = {
						score = direction_best_score,
						angle = direction_best_angle,
						safety_rate = safety_rate or 0,
						collision_count = collision_count,
						collision_penalty_score = collision_penalty_score,
						safety_margin_score = direction_best_safety_margin,  -- Add safety margin info
						is_interpolated = false
					}

					-- Enhanced debug log: always show evaluation results for each direction
					local max_angle_used = dir.name == "Up" and self.eval_max_angle_up or
					                       dir.name == "Down" and self.eval_max_angle_down or
					                       self.eval_max_angle_horizontal
					self.log_obj:Record(LogLevel.Info, string.format("Direction %s: safety=%.2f, collisions=%d (penalty=%.1f), angle=%d, score=%.1f, max_angle=%d°, current_best=%.1f",
						dir.name, safety_rate or 0, collision_count, collision_penalty_score, direction_best_angle, direction_best_score, max_angle_used, best_score))
				end -- End of direction loop

				-- Dead-end detection and escape logic
				local current_time = Game.GetTimeSystem():GetGameTimeStamp()

				-- Check if we're in a dead-end situation (all directions have low scores)
				if best_score <= self.deadend_score_threshold and
				   not self.is_deadend_escape_active and
				   (current_time - self.deadend_last_check_time) >= self.deadend_escape_check_interval then

					self.log_obj:Record(LogLevel.Info, string.format("Dead-end detected! Best score: %.1f (threshold: %.1f), activating vertical escape",
						best_score, self.deadend_score_threshold))

					-- Activate dead-end escape mode
					self.is_deadend_escape_active = true
					local current_pos = Game.GetPlayer():GetWorldPosition()
					self.deadend_escape_target_z = current_pos.z + self.deadend_vertical_escape_distance
					self.deadend_last_check_time = current_time
				end

				-- Handle dead-end escape mode
				if self.is_deadend_escape_active then
					local current_pos = Game.GetPlayer():GetWorldPosition()

					-- Check if we've reached the escape altitude or can proceed forward
					if current_pos.z >= self.deadend_escape_target_z then
						-- Test if forward direction is now clear
						local forward_clear, _ = self:IsWall(dest_dir_2d, self.search_range, 0, "Horizontal", true, "advanced")

						if not forward_clear then
							-- Forward is clear, exit escape mode
							self.log_obj:Record(LogLevel.Info, "Dead-end escape successful, forward path is now clear")
							self.is_deadend_escape_active = false
							self.deadend_escape_target_z = nil

							-- Don't set direction here, let normal evaluation handle it
							-- Reset flags and continue with normal evaluation
							self.log_obj:Record(LogLevel.Info, "Resuming normal direction evaluation after escape")
						else
							-- Continue ascending
							self.log_obj:Record(LogLevel.Trace, string.format("Dead-end escape: ascending to %.1fm (current: %.1fm)",
								self.deadend_escape_target_z, current_pos.z))
							is_wall = false
							search_vec = Vector4.new(0, 0, 1, 0) -- Pure upward movement
							self.autopilot_angle = 90
						end
					else
						-- Continue ascending to target altitude
						self.log_obj:Record(LogLevel.Trace, string.format("Dead-end escape: ascending to %.1fm (current: %.1fm)",
							self.deadend_escape_target_z, current_pos.z))
						is_wall = false
						search_vec = Vector4.new(0, 0, 1, 0) -- Pure upward movement
						self.autopilot_angle = 90
					end

					-- Only force relay position for active escape mode
					if self.is_deadend_escape_active then
						-- Force relay position for dead-end escape (override any other logic)
						if not search_vec:IsZero() then
							relay_position = Vector4.new(
								current_position.x + self.autopilot_searching_step * search_vec.x,
								current_position.y + self.autopilot_searching_step * search_vec.y,
								current_position.z + self.autopilot_searching_step * search_vec.z,
								1
							)
							self.log_obj:Record(LogLevel.Info, string.format("Dead-end escape relay set: x=%.1f, y=%.1f, z=%.1f",
								relay_position.x, relay_position.y, relay_position.z))
						end
						-- Mark path as found to exit path finding logic
						path_found = true
					end
					-- If escape mode was just exited, continue to normal evaluation below
				end

				-- Normal path selection (executed when not in escape mode, or after escape mode ends)
				-- If the optimal direction is found
				if not path_found and best_direction ~= nil and best_score > 0 then
					is_wall = false
					search_vec = best_vec
					self.autopilot_angle = best_angle

					-- Calculate the actual vector for the optimal direction
					local avoidance_vector = Vector4.Zero()
					if best_direction.swing_dir == "Horizontal" then
						-- Avoidance vector for horizontal direction
						-- Corrected rotation: positive angle = left, negative angle = right
						local rad = math.rad(best_angle)
						local cos_angle = math.cos(rad)
						local sin_angle = math.sin(rad)
						avoidance_vector = Vector4.new(
							dest_dir_2d.x * cos_angle - dest_dir_2d.y * sin_angle,
							dest_dir_2d.x * sin_angle + dest_dir_2d.y * cos_angle,
							0,
							1
						)
					elseif best_direction.swing_dir == "Vertical" then
						-- Avoidance vector for vertical direction
						local rad = math.rad(best_angle)
						local cos_angle = math.cos(rad)
						local sin_angle = math.sin(rad)
						local horizontal_length = Vector4.Length(Vector4.new(dest_dir_vector.x, dest_dir_vector.y, 0, 1))
						avoidance_vector = Vector4.new(
							dest_dir_vector.x * cos_angle,
							dest_dir_vector.y * cos_angle,
							horizontal_length * sin_angle,
							1
						)
					end

					-- Normalize and adjust to search range
					if not avoidance_vector:IsZero() then
						avoidance_vector = Vector4.Normalize(avoidance_vector)
						search_vec = Vector4.new(
							avoidance_vector.x,
							avoidance_vector.y,
							avoidance_vector.z,
							1
						)
					end

					-- Update direction record
					if best_direction.swing_dir == "Horizontal" then
						local sign = best_angle < 0 and -1 or 1
						if self.autopilot_horizontal_sign * sign <= 0 then
							self.autopilot_horizontal_sign = sign
						end
					elseif best_direction.swing_dir == "Vertical" then
						if best_angle > 0 and self.autopilot_vertical_sign <= 0 then
							self.autopilot_vertical_sign = 1
						elseif best_angle < 0 and self.autopilot_vertical_sign >= 0 then
							self.autopilot_vertical_sign = -1
						end
					end

					-- Thruster control
					local angle_abs = math.abs(best_angle)
					if angle_abs < 30 then
						self:MoveThruster({{Def.ActionList.Forward, 1}})
					else
						self:MoveThruster({{Def.ActionList.Nothing, 1}})
					end

					-- Dynamic speed adjustment
					local base_speed_reduction = (90 - angle_abs) / 90
					self.auto_speed_reduce_rate = base_speed_reduction * 0.6
					if self.auto_speed_reduce_rate < self.autopilot_min_speed_rate then
						self.auto_speed_reduce_rate = self.autopilot_min_speed_rate
					end

					-- Safety-focused speed adjustment according to avoidance angle
					if angle_abs > 45 then
						self.auto_speed_reduce_rate = self.auto_speed_reduce_rate * 0.3  -- Very cautious for steep angles
					elseif angle_abs > 15 then
						self.auto_speed_reduce_rate = self.auto_speed_reduce_rate * 0.5  -- Cautious for moderate angles
					end

					if angle_abs == 90 then
						self.auto_speed_reduce_rate = 1  -- Stop
					end

					self.log_obj:Record(LogLevel.Info, "5-Direction System: Selected " .. best_direction.name .. " direction, angle: " .. best_angle .. ", score: " .. string.format("%.1f", best_score))
					self.log_obj:Record(LogLevel.Debug, "Avoidance vector: x=" .. string.format("%.3f", search_vec.x) .. ", y=" .. string.format("%.3f", search_vec.y) .. ", z=" .. string.format("%.3f", search_vec.z))

					-- Store final selection for debug display
					self.last_selected_direction = best_direction.name
					self.last_best_score = best_score
					self.last_evaluation_timestamp = Game.GetTimeSystem():GetGameTimeStamp()

					-- Use avoidance vector to directly set relay_position
					if not search_vec:IsZero() then
						local pos = relay_position or current_position
						-- Dynamic step size based on avoidance angle for stronger evasion
						local angle_abs = math.abs(best_angle)
						local step_multiplier = 1.0
						if angle_abs >= 15 and angle_abs <= 45 then
							step_multiplier = 1.5  -- Stronger avoidance for optimal angles
						elseif angle_abs > 45 then
							step_multiplier = 1.3  -- Moderate boost for large angles
						end

						local effective_step = self.autopilot_searching_step * step_multiplier
						relay_position = Vector4.new(
							pos.x + effective_step * search_vec.x,
							pos.y + effective_step * search_vec.y,
							pos.z + effective_step * search_vec.z,
							1
						)
						self.log_obj:Record(LogLevel.Debug, "New relay position: x=" .. relay_position.x .. ", y=" .. relay_position.y .. ", z=" .. relay_position.z .. " (step multiplier: " .. step_multiplier .. ")")
					end
					-- Mark path as found
					path_found = true
				end  -- End if best_direction ~= nil

				-- Fallback: emergency handling if new logic cannot resolve
				if not path_found then
					if self.autopilot_angle == 0 then
						-- reset search angle
						self.autopilot_horizontal_sign = 0
						self.autopilot_vertical_sign = 0
					end

					if not is_wall then
						if relay_position ~= nil then
							self.log_obj:Record(LogLevel.Trace, "Relay Position : " .. relay_position.x .. ", " .. relay_position.y .. ", " .. relay_position.z)
						else
							self.log_obj:Record(LogLevel.Critical, "Relay Position : nil")
						end
					else
						-- Final fallback for unresolved wall situations
						if self.autopilot_vertical_sign <= 0 then
							self.autopilot_vertical_sign = 1
						else
							self.log_obj:Record(LogLevel.Info, "AutoPilot Move Interrupted")
							self:InterruptAutoPilot()
							Cron.Halt(timer)
							return
						end
					end
				end
		end

		-- recheck relay position
		if relay_position ~= nil then
			direction_vector = Vector4.new(relay_position.x - current_position.x, relay_position.y - current_position.y, relay_position.z - current_position.z, 1)
		end
		direction_vector_norm = Vector4.Length(direction_vector)

		-- speed control
		if self.auto_speed_reduce_rate < self.autopilot_min_speed_rate then
			self.auto_speed_reduce_rate = self.autopilot_min_speed_rate
		elseif self.auto_speed_reduce_rate > 1 then
			self.auto_speed_reduce_rate = 1
		end

		-- Override speed control for dead-end escape mode
		if self.is_deadend_escape_active then
			self.auto_speed_reduce_rate = 0.8  -- Use moderate speed for escape
			self.log_obj:Record(LogLevel.Trace, "Dead-end escape: using escape speed rate 0.8")
		end

		local autopilot_speed = self.autopilot_speed * self.auto_speed_reduce_rate
		local fix_direction_vector = Vector4.new(autopilot_speed * direction_vector.x / direction_vector_norm, autopilot_speed * direction_vector.y / direction_vector_norm, autopilot_speed * direction_vector.z / direction_vector_norm, 1)

		-- yaw control
		local vehicle_angle = self:GetForward()
		local vehicle_angle_norm = Vector4.Length(vehicle_angle)
		local yaw_vehicle = math.atan2(vehicle_angle.y / vehicle_angle_norm, vehicle_angle.x / vehicle_angle_norm) * 180 / Pi()
		local yaw_dist = yaw_vehicle
		if self.dest_dir_vector_norm ~= 0 then
			yaw_dist = math.atan2(dest_dir_vector.y / self.dest_dir_vector_norm, dest_dir_vector.x / self.dest_dir_vector_norm) * 180 / Pi()
		end
		local yaw_diff = yaw_dist - yaw_vehicle
		if yaw_diff > 180 then
			yaw_diff = yaw_diff - 360
		elseif yaw_diff < -180 then
			yaw_diff = yaw_diff + 360
		end
		local yaw_diff_half = yaw_diff * self.autopilot_turn_speed
		if math.abs(yaw_diff_half) < 0.1 then
			yaw_diff_half = yaw_diff
		end

		-- Override yaw control for dead-end escape mode (minimize rotation during escape)
		if self.is_deadend_escape_active then
			yaw_diff_half = yaw_diff_half * 0.1  -- Minimal yaw movement during escape
			self.log_obj:Record(LogLevel.Trace, "Dead-end escape: minimal yaw control applied")
		end

		-- -- restore angle
		local current_angle = self:GetEulerAngles()
		local roll_diff = 0
		local pitch_diff = 0
		local forward = Vector4.new(vehicle_angle.x, vehicle_angle.y, 0, 1) -- Use only x and y components for forward vector to avoid z-axis influence on roll and pitch control
		local dir = Vector4.new(direction_vector.x, direction_vector.y, 0, 1)
		local forward_base_vec = Vector4.Normalize(forward)
		local direction_base_vec = Vector4.Normalize(dir)
		local between_angle = 0
		if not direction_base_vec:IsXYZZero() then
			between_angle = Vector4.GetAngleDegAroundAxis(forward_base_vec, direction_base_vec, Vector4.new(0, 0, 1, 1))
		end
		local between_angle_rad = math.rad(between_angle)
		local left_right_value = 0
		local forward_value = 0
		if self.engine_obj.flight_mode == Def.FlightMode.Helicopter then
			forward_value = math.cos(between_angle_rad)
			local _, _, _, roll_diff_forward, pitch_diff_forward, _ = self.engine_obj:CalculateAddVelocity({Def.ActionList.HLeanForward, forward_value})
			left_right_value = math.sin(between_angle_rad)
			local roll_control = {}
			if left_right_value >= 0 then
				roll_control = {Def.ActionList.HLeanLeft, left_right_value}
			else
				roll_control = {Def.ActionList.HLeanRight, -left_right_value}
			end
			local _, _, _, roll_diff_left_right, pitch_diff_left_right, _ = self.engine_obj:CalculateAddVelocity(roll_control)
			roll_diff = roll_diff_forward * forward_value + roll_diff_left_right * math.abs(left_right_value)
			pitch_diff = pitch_diff_forward * forward_value + pitch_diff_left_right * math.abs(left_right_value)
		else
			left_right_value = math.sin(between_angle_rad)
			local roll_control = {}
			if left_right_value >= 0 then
				roll_control = {Def.ActionList.Left, left_right_value}
			else
				roll_control = {Def.ActionList.Right, -left_right_value}
			end
			local _, _, _, roll_diff_left_right, pitch_diff_left_right, _ = self.engine_obj:CalculateAddVelocity(roll_control)
			roll_diff = roll_diff_left_right * math.abs(left_right_value)
			pitch_diff = pitch_diff_left_right * math.abs(left_right_value)
		end

		self.log_obj:Record(LogLevel.Debug, "AutoPilot Move : " .. fix_direction_vector.x .. ", " .. fix_direction_vector.y .. ", " .. fix_direction_vector.z .. ", " .. roll_diff .. ", " .. pitch_diff .. ", " .. yaw_diff_half)

		-- Clean speed-dependent stability system with natural ranges
		local speed_ranges = {
			{max = 10.0, inertia = 0.3, blend = 0.75},   -- Low speed: responsive
			{max = 20.0, inertia = 0.18, blend = 0.8},   -- Medium-low speed
			{max = 30.0, inertia = 0.08, blend = 0.85},  -- Medium speed
			{max = 45.0, inertia = 0.04, blend = 0.9},   -- Medium-high speed
			{max = 60.0, inertia = 0.02, blend = 0.96}, -- High speed: ultra strong damping for 50m/s
			{max = 80.0, inertia = 0.01, blend = 0.96}, -- Very high speed
			{max = math.huge, inertia = 0.01, blend = 0.98} -- Extreme speed: maximum stability
		}

		-- Find appropriate parameters for current speed
		local inertia_scale, blend_factor = 0.18, 0.8  -- defaults
		for _, range in ipairs(speed_ranges) do
			if autopilot_speed <= range.max then
				inertia_scale = range.inertia
				blend_factor = range.blend
				break
			end
		end

		-- Apply smooth transition between ranges to avoid sudden changes
		local prev_inertia = self.prev_inertia_scale or inertia_scale
		local prev_blend = self.prev_blend_factor or blend_factor
		local transition_rate = 0.15  -- Balanced transition rate

		inertia_scale = prev_inertia + (inertia_scale - prev_inertia) * transition_rate
		blend_factor = prev_blend + (blend_factor - prev_blend) * transition_rate

		-- Store for next frame
		self.prev_inertia_scale = inertia_scale
		self.prev_blend_factor = blend_factor

		local dummy_inertia = Utils:ScaleListValues(self.pre_speed_list, inertia_scale)

		local x, y, z, roll, pitch, yaw = fix_direction_vector.x, fix_direction_vector.y, fix_direction_vector.z, roll_diff, pitch_diff, yaw_diff_half
		local new_x, new_y, new_z = x + dummy_inertia.x, y + dummy_inertia.y, z + dummy_inertia.z

		-- Dynamic velocity transition with speed-dependent smoothing
		local current_norm = math.sqrt(new_x * new_x + new_y * new_y + new_z * new_z)
		local target_norm = Vector4.Length(Vector4.new(fix_direction_vector.x, fix_direction_vector.y, fix_direction_vector.z, 1))

		local adjust_x, adjust_y, adjust_z
		if current_norm > 0.001 then
			local smooth_norm = target_norm * blend_factor + current_norm * (1.0 - blend_factor)
			adjust_x = new_x * smooth_norm / current_norm
			adjust_y = new_y * smooth_norm / current_norm
			adjust_z = new_z * smooth_norm / current_norm
		else
			adjust_x, adjust_y, adjust_z = fix_direction_vector.x, fix_direction_vector.y, fix_direction_vector.z
		end

		self.pre_speed_list = {x = adjust_x, y = adjust_y, z = adjust_z}

		if self.is_deadend_escape_active then
			_, _, _, roll ,pitch ,yaw = self.engine_obj:CalculateAddVelocity({Def.ActionList.Idle, 1})
		end

		-- limit
		if current_angle.roll > self.engine_obj.max_roll or current_angle.roll < -self.engine_obj.max_roll then
			roll = 0
		end
		if current_angle.pitch > self.engine_obj.max_pitch or current_angle.pitch < -self.engine_obj.max_pitch then
			pitch = 0
		end

		-- Prevent FluctuationVelocity oscillation at target speed during movement
		-- Temporarily increase target velocity margin to avoid 50m/s oscillation
		local current_velocity = Vector4.Vector3To4(self.engine_obj.direction_velocity):Length()
		if math.abs(current_velocity - self.autopilot_speed) < 1.0 then  -- Near target speed
			local original_target = self.engine_obj.target_velocity
			-- Temporarily set higher target to prevent oscillation
			self.engine_obj.target_velocity = self.autopilot_speed * 1.05
			self.engine_obj:Run(adjust_x, adjust_y, adjust_z, roll, pitch, yaw)
			-- Restore original target after run
			self.engine_obj.target_velocity = original_target
		else
			self.engine_obj:Run(adjust_x, adjust_y, adjust_z, roll, pitch, yaw)
		end
	end)
	return true
end

--- Excute Leaving when auto pilot is on.
---@param dist_vector Vector4 vector to destination position
---@param height number | nil height to end leaving
function AV:AutoLeaving(dist_vector, height)
	self.is_leaving = true

	local res, _, area_height = self:IsInExceptionArea(self:GetPosition())
	if res then
		height = area_height + 10
	end

	local current_position = self:GetPosition()
	local leaving_height = height or self.autopilot_leaving_height - current_position.z
	local leaving_position = Vector4.new(current_position.x, current_position.y, current_position.z + leaving_height, 1)
	self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0.5))
	self.engine_obj:SetAngularVelocity(Vector3.new(0, 0, 0))
	self.engine_obj:SetFluctuationVelocityParams(self.autopilot_acceleration, self.autopilot_speed)
	self.autopilot_leaving_deceleration_start_flag = false
	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1
		if not self.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
			self.is_leaving = false
			Cron.Halt(timer)
			return
		elseif self:IsCollision() then
			self.log_obj:Record(LogLevel.Info, "Collision Detected")
			self:InterruptAutoPilot()
			self.is_leaving = false
			Cron.Halt(timer)
			return
		end

		-- Stabilize roll and pitch during takeoff
		local _, _, _, roll_idle ,pitch_idle ,yaw_idle = self.engine_obj:CalculateAddVelocity({Def.ActionList.Idle, 1})
		self.engine_obj:OnlyAngularRun(roll_idle, pitch_idle, yaw_idle)

		local is_detected_celling, search_vector = self:IsWall(Vector4.new(0, 0, 1, 1), self.check_cell_distance, 0, "Vertical", true, "simple")
		if is_detected_celling then
			self.log_obj:Record(LogLevel.Info, "Detected Ceiling, Search Vector:" .. search_vector.x .. ", " .. search_vector.y .. ", " .. search_vector.z)
		end
		local current_position_in_leaving = self:GetPosition()

		if current_position_in_leaving.z > leaving_position.z or is_detected_celling then
			self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
			self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			self.engine_obj:SetAngularVelocity(Vector3.new(0, 0, 0))
			Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
				timer.tick = timer.tick + 1
				if not self.is_auto_pilot then
					self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted by Canceling")
					self.is_leaving = false
					Cron.Halt(timer)
					return
				elseif self:IsCollision() then
					self.log_obj:Record(LogLevel.Info, "Collision Detected")
					self:InterruptAutoPilot()
					self.is_leaving = false
					Cron.Halt(timer)
					return
				end

				-- yaw control
				local vehicle_angle = self:GetForward()
				local vehicle_angle_norm = Vector4.Length(vehicle_angle)
				local yaw_vehicle = math.atan2(vehicle_angle.y / vehicle_angle_norm, vehicle_angle.x / vehicle_angle_norm) * 180 / Pi()
				local yaw_dist = yaw_vehicle
				local dist_vector_norm = dist_vector:Length2D()
				if dist_vector_norm ~= 0 then
					yaw_dist = math.atan2(dist_vector.y / dist_vector_norm, dist_vector.x / dist_vector_norm) * 180 / Pi()
				end
				local yaw_diff = yaw_dist - yaw_vehicle
				if yaw_diff > 180 then
					yaw_diff = yaw_diff - 360
				elseif yaw_diff < -180 then
					yaw_diff = yaw_diff + 360
				end
				local yaw_diff_half = yaw_diff * self.autopilot_turn_speed
				if math.abs(yaw_diff_half) < 0.1 then
					yaw_diff_half = yaw_diff
				end

				self.engine_obj:Run(0.0, 0.0, 0.0, 0.0, 0.0, yaw_diff_half)

				if math.abs(yaw_diff_half) < 0.1 then
					self.engine_obj:Run(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
					self.is_leaving = false
					Cron.Halt(timer)
				end
			end)
			Cron.Halt(timer)
		elseif current_position_in_leaving.z > leaving_position.z - (leaving_height * 0.3) and not self.autopilot_leaving_deceleration_start_flag then
			self.autopilot_leaving_deceleration_start_flag = true
			self.engine_obj:SetFluctuationVelocityParams(-self.autopilot_acceleration, self.autopilot_speed * 0.2)
		end
		self:MoveThruster({{Def.ActionList.Nothing, 1}})
	end)
end

--- Excute Landing when auto pilot is on.
--- @param height number height to start landing
function AV:AutoLanding(height)
	local down_time_count = ((height / self.autopilot_speed) / DAV.time_resolution) * 1.8
	self.log_obj:Record(LogLevel.Info, "AutoPilot Landing Start :" .. tostring(down_time_count) .. "s, " .. tostring(height) .. "m")
	self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
	self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, -0.5))
	self.engine_obj:SetAngularVelocity(Vector3.new(0, 0, 0))
	self.autopilot_leaving_deceleration_start_flag = false
	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		if not self.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted by Canceling")
			Cron.Halt(timer)
			return
		end

		local deceleration_height = height * 0.5
		local deceleration_rate = 1
		if deceleration_height > 80 then
			deceleration_height = 80
			deceleration_rate = 3
		end

		-- restore angle 
		local _, _, _, roll_idle ,pitch_idle ,yaw_idle = self.engine_obj:CalculateAddVelocity({Def.ActionList.Idle, 1})
		self.engine_obj:OnlyAngularRun(roll_idle, pitch_idle, yaw_idle)

		local is_detected_ground, search_vector = self:IsWall(Vector4.new(0, 0, -1, 1), self.minimum_distance_to_ground - 0.2, 0, "Vertical", false, "simple")
		if is_detected_ground then
			self.log_obj:Record(LogLevel.Info, "Detected Ground, Search Vector:" .. search_vector.x .. ", " .. search_vector.y .. ", " .. search_vector.z)
		end

		if timer.tick == 1 then
			self.engine_obj:SetFluctuationVelocityParams(self.autopilot_acceleration, self.autopilot_speed)
		elseif timer.tick > down_time_count then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Success for timeout")
			self.is_landed = true
			self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
			self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			self:SuccessAutoPilot()
			Cron.Halt(timer)
		elseif self:GetHeight() < self.minimum_distance_to_ground then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Success for minimum_height")
			self.is_landed = true
			self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
			self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			self:SuccessAutoPilot()
			Cron.Halt(timer)
		elseif self:IsCollision() or is_detected_ground then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Success for Collision or Ground Detection")
			self.is_landed = true
			self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
			self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			self:SuccessAutoPilot()
			Cron.Halt(timer)
		elseif self:GetHeight() <= deceleration_height and not self.autopilot_leaving_deceleration_start_flag then
			self.autopilot_leaving_deceleration_start_flag = true
			self.engine_obj:SetFluctuationVelocityParams(-self.autopilot_acceleration * deceleration_rate, self.autopilot_speed * 0.2)
		end

		self:MoveThruster({{Def.ActionList.Nothing, 1}})

		timer.tick = timer.tick + 1
	end)
end

--- Set AV.is_failture_auto_pilot and AV.is_auto_pilot when AutoPilot Success.
function AV:SuccessAutoPilot()
	self.is_auto_pilot = false
	self.is_failture_auto_pilot = false
	self.core_obj:SetAutoPilotHistory()
end

--- Set AV.is_failture_auto_pilot and AV.is_auto_pilot when AutoPilot Failed.
function AV:InterruptAutoPilot()
	self.is_auto_pilot = false
	self.is_failture_auto_pilot = true
end

--- Set AV.is_failture_auto_pilot and get Failture AutoPilot Flag.
---@return boolean
function AV:IsFailedAutoPilot()
	local is_failture_auto_pilot = self.is_failture_auto_pilot
	self.is_failture_auto_pilot = false
	return is_failture_auto_pilot
end

--- Reload Autopilot Profile from settings file.
function AV:ReloadAutopilotProfile()
	local speed_level = DAV.user_setting_table.autopilot_speed_level
	self.autopilot_speed = self.autopilot_profile[speed_level].speed
	self.autopilot_acceleration = self.autopilot_profile[speed_level].acceleration
	self.autopilot_turn_speed = self.autopilot_profile[speed_level].turn_speed
	self.autopilot_leaving_height = self.autopilot_profile[speed_level].leaving_height
	self.autopilot_searching_range = self.autopilot_profile[speed_level].searching_range
	self.autopilot_searching_step = self.autopilot_profile[speed_level].searching_step
	self.autopilot_min_speed_rate = self.autopilot_profile[speed_level].min_speed_rate
	self.autopilot_is_only_horizontal = self.autopilot_profile[speed_level].is_only_horizontal
end

--- Toggle radio ON or next radioStation.
function AV:ToggleRadio()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change radio")
		return
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change radio")
		return
	end
	if entity:IsRadioReceiverActive() then
		entity:NextRadioReceiverStation()
	else
		entity:ToggleRadioReceiver(true)
	end
end

--- Change appearance.
---@param type string appearance name
function AV:ChangeAppearance(type)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change appearance")
		return
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change appearance")
		return
	end
	entity:ScheduleAppearanceChange(type)
	Cron.After(0.1, function()
		if self:SetThrusterComponent() then
			self.is_available_thruster = true
		else
			self.is_available_thruster = false
		end
	end)
end

--- Set landing vfx position.
---@param position Vector4 offset center position
function AV:SetLandingVFXPosition(position)
	if self.is_enable_landing_vfx and DAV.user_setting_table.is_enable_landing_vfx then
		self.landing_vfx_component:SetLocalPosition(position)
	end
end

--- Toggle landing warning ON/OFF.
---@param on boolean
function AV:ProjectLandingWarning(on)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Trace, "No entity to project landing warning")
		return
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Trace, "No entity to project landing warning")
		return
	end
	if self.is_enable_landing_vfx and DAV.user_setting_table.is_enable_landing_vfx then
		if on and not self.is_landing_projection then
			GameObjectEffectHelper.StartEffectEvent(entity, CName.new("landingWarning"), false)
			GameObjectEffectHelper.StartEffectEvent(entity, CName.new("projectorVFX"), false)
			self.is_landing_projection = true
		elseif not on and self.is_landing_projection then
			GameObjectEffectHelper.StopEffectEvent(entity, CName.new("landingWarning"))
			GameObjectEffectHelper.StopEffectEvent(entity, CName.new("projectorVFX"))
			self.is_landing_projection = false
		end
	end
end

--- Set thruster component to move its angle.
---@return boolean
function AV:SetThrusterComponent()
	if self.engine_obj.flight_mode == Def.FlightMode.Helicopter then
		return false
	end

	self.engine_components = {}
	self.thruster_fxs = {}

	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set thruster")
		return false
	end

	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set thruster")
		return false
	end

	if self.engine_component_name_list ~= nil then
		for pos, component_name in pairs(self.engine_component_name_list) do
			self.engine_components[pos] = entity:FindComponentByName(component_name)
			if self.engine_components[pos] == nil then
				self.log_obj:Record(LogLevel.Warning, "No thruster component : " .. component_name)
				return false
			end
			self.engine_components[pos]:SetLocalPosition(Vector4.new(self.engine_offset_list[pos].x, self.engine_offset_list[pos].y, self.engine_offset_list[pos].z, 1))
		end
	end

	if self.thruster_fx_name_list ~= nil then
		for pos, thruster_name in pairs(self.thruster_fx_name_list) do
			self.thruster_fxs[pos] = entity:FindComponentByName(thruster_name)
			if self.thruster_fxs[pos] == nil then
				self.log_obj:Record(LogLevel.Warning, "No thruster fx : " .. thruster_name)
				return false
			end
			self.thruster_fxs[pos]:SetLocalPosition(Vector4.new(self.thruster_offset_list[pos].x, self.thruster_offset_list[pos].y, self.thruster_offset_list[pos].z, 1))
		end
	else
		return false
	end
	return true
end

--- Change thruster angle by action commands.
---@param action_command_lists table
---@return boolean
function AV:MoveThruster(action_command_lists)
	if self.thruster_angle > self.thruster_angle_restore then
		self.thruster_angle = self.thruster_angle - self.thruster_angle_restore
	elseif self.thruster_angle < -self.thruster_angle_restore then
		self.thruster_angle = self.thruster_angle + self.thruster_angle_restore
	else
		self.thruster_angle = 0
	end

	if not self.is_available_thruster then
		return false
	end

	for _, action_command_list in ipairs(action_command_lists) do
		if action_command_list[1] == Def.ActionList.Forward then
			self.thruster_angle = self.thruster_angle - self.thruster_angle_step
		elseif action_command_list[1] == Def.ActionList.Backward then
			self.thruster_angle = self.thruster_angle + self.thruster_angle_step
		end
	end

	if self.thruster_angle > self.thruster_angle_max then
		self.thruster_angle = self.thruster_angle_max
	elseif self.thruster_angle < -self.thruster_angle_max then
		self.thruster_angle = -self.thruster_angle_max
	end

	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set thruster")
		return false
	end

	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set thruster")
		return false
	end

	local angle = EulerAngles.new(0, self.thruster_angle, 0)

	for _, component in pairs(self.engine_components) do
		component:SetLocalOrientation(angle:ToQuat())
	end

	for _, thruster in pairs(self.thruster_fxs) do
		thruster:SetLocalOrientation(angle:ToQuat())
	end
	return true
end

--- Toggle thruster ON/OFF.
---@param on boolean
---@return boolean
function AV:ToggleThruster(on)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set thruster")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set thruster")
		return false
	end
	if not self.is_available_thruster then
		return false
	end

	if on then
		GameObjectEffectHelper.StartEffectEvent(entity, CName.new("thrusters"))
	else
		GameObjectEffectHelper.StopEffectEvent(entity, CName.new("thrusters"))
	end
	return true
end

--- Toggle helicopter thruster ON/OFF.
---@param on boolean
---@return boolean
function AV:ToggleHeliThruster(on)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set thruster")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set thruster")
		return false
	end
	if self.engine_obj.flight_mode ~= Def.FlightMode.Helicopter then
		return false
	end

	if on then
		GameObjectEffectHelper.StartEffectEvent(entity, CName.new("thruster"))
	else
		GameObjectEffectHelper.StopEffectEvent(entity, CName.new("thruster"))
	end
	return true
end

--- Set destroy appearance.
---@return boolean
function AV:SetDestroyAppearance()
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set destroy appearance")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to set destroy appearance")
		return false
	end

	if self.destroy_app == nil then
		self.log_obj:Record(LogLevel.Warning, "No destroy appearance")
		return false
	end

	self:ChangeAppearance(self.destroy_app)
	return true
end

--- Change engine status.
---@param on boolean
---@return boolean
function AV:TurnEngineOn(on)
	if self.entity_id == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change engine status")
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
		self.log_obj:Record(LogLevel.Warning, "No entity to change engine status")
		return false
	end
	entity:TurnEngineOn(on)
	return true
end

--- Get Player Around Direction (for spawn position)
---@param angle number
function AV:GetPlayerAroundDirection(angle)
    local player = Game.GetPlayer()
    if player == nil then
        self.log_obj:Record(LogLevel.Warning, "Player is nil in GetPlayerAroundDirection")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return Vector4.RotateAxis(player:GetWorldForward(), Vector4.new(0, 0, 1, 0), angle / 180.0 * Pi())
end

--- Get Spawn Position Vector
---@param distance number
---@param angle number
---@return Vector4
function AV:GetSpawnPosition(distance, angle)
    local pos = Game.GetPlayer():GetWorldPosition()
    local heading = self:GetPlayerAroundDirection(angle)
    return Vector4.new(pos.x + (heading.x * distance), pos.y + (heading.y * distance), pos.z + heading.z, pos.w + heading.w)
end

--- Get Spawn Orientation Quaternion
---@param angle number
---@return Quaternion
function AV:GetSpawnOrientation(angle)
    return EulerAngles.ToQuat(Vector4.ToRotation(self:GetPlayerAroundDirection(angle)))
end

--- Check Player in Exception Area
---@param position Vector4
---@return boolean is_in_area If or not in exception area
---@return string tag Tag
---@return number z max height of exception area
function AV:IsInExceptionArea(position)
    for _, area in ipairs(self.autopilot_exception_area_list) do
        if position.x >= area.min_x and position.x <= area.max_x and position.y >= area.min_y and position.y <= area.max_y and position.z >= area.min_z and position.z <= area.max_z then
            return true, area.tag, area.max_z
        end
    end
    return false, "None", 0
end

--- Get Exit Position Vector
---@return Vector4
function AV:GetExitPosition()
    local basic_vector = self:GetPosition()
    return self:ChangeWorldCordinate(basic_vector, {self.exit_point})[1]
end

--- Check Player in Entry Area
---@return boolean
function AV:IsPlayerInEntryArea()
    local basic_vector = self:GetPosition()
    if basic_vector:IsZero() then
        return false
    end
    local world_entry_point = self:ChangeWorldCordinate(basic_vector, {self.entry_point})
    local player = Game.GetPlayer()
    if player == nil then
        return false
    end
    local player_pos = player:GetWorldPosition()
    if player_pos == nil then
        return false
    end
    local player_vector = {x = player_pos.x, y = player_pos.y, z = player_pos.z}

    local norm = math.sqrt((player_vector.x - world_entry_point[1].x) * (player_vector.x - world_entry_point[1].x) + (player_vector.y - world_entry_point[1].y) * (player_vector.y - world_entry_point[1].y) + (player_vector.z - world_entry_point[1].z) * (player_vector.z - world_entry_point[1].z))
    if norm <= self.entry_area_radius then
        return true
    else
        return false
    end
end

--- Change World Cordinate
---@param basic_vector Vector4
---@param point_list Vector4[]
---@return Vector4[]
function AV:ChangeWorldCordinate(basic_vector, point_list)
    local quaternion = self:GetQuaternion()
    local result_list = {}
    for i, corner in ipairs(point_list) do
        local rotated = Utils:RotateVectorByQuaternion(corner, quaternion)
        result_list[i] = {x = rotated.x + basic_vector.x, y = rotated.y + basic_vector.y, z = rotated.z + basic_vector.z}
    end
    return result_list
end

--- This function returns collision status.
---@return boolean
function AV:IsCollision()
    return self.engine_obj:IsOnGround()
end

-- Update exception area bypass status based on distance to destination
function AV:UpdateExceptionAreaBypass()
	-- Check if autopilot is active and we have a destination
	if self.is_auto_pilot and self.dest_dir_vector_norm then
		-- Debug log for troubleshooting
		self.log_obj:Record(LogLevel.Debug, string.format("Checking exception bypass: distance=%.1f, threshold=%.1f, current_bypass=%s",
			self.dest_dir_vector_norm, self.exception_area_bypass_distance, tostring(self.is_exception_area_bypassed)))

		-- Enable bypass when close to destination
		if self.dest_dir_vector_norm <= self.exception_area_bypass_distance then
			if not self.is_exception_area_bypassed then
				self.is_exception_area_bypassed = true
				self.log_obj:Record(LogLevel.Info, "Exception area bypass enabled: distance = " .. tostring(self.dest_dir_vector_norm))
			end
		else
			-- Disable bypass when far from destination
			if self.is_exception_area_bypassed then
				self.is_exception_area_bypassed = false
				self.log_obj:Record(LogLevel.Info, "Exception area bypass disabled: distance = " .. tostring(self.dest_dir_vector_norm))
			end
		end
	else
		-- Reset bypass when autopilot is not active
		if self.is_exception_area_bypassed then
			self.is_exception_area_bypassed = false
			self.log_obj:Record(LogLevel.Debug, "Exception area bypass reset: autopilot inactive")
		end
	end
end

--- Check Wall
---@param dir_vec Vector4 direction vector
---@param distance number distance
---@param angle number angle
---@param swing_direction string "Vertical" or "Horizontal"
---@param is_check_exception_area boolean
---@param collision_mode string "advanced" for front plane + rear point, "simple" for front/center/rear points
---@return boolean
---@return Vector4
function AV:IsWall(dir_vec, distance, angle, swing_direction, is_check_exception_area, collision_mode)
	-- Cache system: greatly reduces computation when no obstacle is present
	local current_time = Game.GetTimeSystem():GetGameTimeStamp()
	local current_position = self:GetPosition()

	-- Generate cache key
	local cache_key = string.format("%.1f_%.1f_%.1f_%d_%s",
		math.floor(current_position.x), math.floor(current_position.y), math.floor(current_position.z),
		math.floor(angle), swing_direction)

	-- Initialize cache
	if not self.iswall_cache then
		self.iswall_cache = {}
		self.safe_streak_count = 0
		self.last_cache_time = current_time
	end

	-- Cache hit check
	local cached_result = self.iswall_cache[cache_key]
	if cached_result and (current_time - cached_result.timestamp) < 200 then  -- within 200ms
		-- Position change check
		local pos_diff = Vector4.Length(Vector4.new(
			current_position.x - cached_result.position.x,
			current_position.y - cached_result.position.y,
			current_position.z - cached_result.position.z, 0))

		if pos_diff < 3.0 then  -- within 3m change
			self.log_obj:Record(LogLevel.Trace, "IsWall cache hit: " .. cache_key)
			return cached_result.result, cached_result.search_vec
		end
	end

	-- Adaptive check frequency: simplify checks when safety continues
	local should_do_full_check = true
	if self.safe_streak_count > 15 then  -- safe for 15 consecutive times
		-- Only do full check once every 3 frames
		should_do_full_check = (self.safe_streak_count % 3 == 0)
	elseif self.safe_streak_count > 8 then  -- safe for 8 consecutive times
		-- Only do full check every 2 frames
		should_do_full_check = (self.safe_streak_count % 2 == 0)
	end

	local dir_base_vec = Vector4.Normalize(dir_vec)
	local up_vec = Vector4.new(0, 0, 1, 1)
	local right_vec = Vector4.Cross(dir_base_vec, up_vec)
	local search_vec
	if swing_direction == "Vertical" then
		search_vec = Vector4.RotateAxis(dir_base_vec, right_vec, angle / 180 * Pi())
	else
		search_vec = Vector4.RotateAxis(dir_base_vec, up_vec, angle / 180 * Pi())
	end

	-- Simple check: only center point when safety streak is high
	if not should_do_full_check then
		-- Ground proximity protection for simple check
		local raycast_start_pos = current_position
		if swing_direction == "Vertical" and angle >= 0 then  -- Upward vertical check
			-- Ensure raycast doesn't start below a reasonable ground level
			raycast_start_pos = Vector4.new(current_position.x, current_position.y,
				math.max(current_position.z, current_position.z), 1.0)
		end

		local adaptive_distance = distance * (1 + math.min(Vector4.Vector3To4(self.engine_obj.direction_velocity):Length() / 20.0, 2.0) * 0.4)
		local target_pos = Vector4.new(
			raycast_start_pos.x + adaptive_distance * search_vec.x,
			raycast_start_pos.y + adaptive_distance * search_vec.y,
			raycast_start_pos.z + adaptive_distance * search_vec.z,
			1.0
		)

		for _, filter in ipairs(self.weak_collision_filters) do
			local is_success, _ = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(raycast_start_pos, target_pos, filter, false, false)
			if is_success then
				self.safe_streak_count = 0  -- Reset
				self.log_obj:Record(LogLevel.Trace, "Simple check - Wall Detected: " .. filter)
				-- Save to cache
				self.iswall_cache[cache_key] = {
					result = true,
					search_vec = search_vec,
					timestamp = current_time,
					position = current_position
				}
				return true, search_vec
			end
		end

		self.safe_streak_count = self.safe_streak_count + 1
		self.log_obj:Record(LogLevel.Trace, "Simple check - Safe (streak: " .. self.safe_streak_count .. ")")
		-- Save to cache
		self.iswall_cache[cache_key] = {
			result = false,
			search_vec = search_vec,
			timestamp = current_time,
			position = current_position
		}
		return false, search_vec
	end

	-- Optimized detection with balanced performance and coverage
	local current_speed = Vector4.Vector3To4(self.engine_obj.direction_velocity):Length()
	local speed_factor = math.min(current_speed / 20.0, 2.0)

	local detection_step = self.collision_check_side_distance

	-- Stepwise grid detection system: 3D positioning with right, forward, and up offsets
	local function check_collision_at_point(offset_right, offset_forward, offset_up)
		offset_up = offset_up or 0  -- Default to 0 if not provided for backward compatibility
		local current_position = self:GetPosition()

		-- Calculate position offset: right_vec for left-right, dir_base_vec for front-back, up_vec for up-down
        current_position.x = current_position.x + right_vec.x * offset_right + dir_base_vec.x * offset_forward + up_vec.x * offset_up
        current_position.y = current_position.y + right_vec.y * offset_right + dir_base_vec.y * offset_forward + up_vec.y * offset_up
        current_position.z = current_position.z + right_vec.z * offset_right + dir_base_vec.z * offset_forward + up_vec.z * offset_up

        -- Ground proximity protection: Prevent raycast start points from going below ground during upward checks
        -- if swing_direction == "Vertical" and angle >= 0 then  -- Upward vertical check
        --     local base_position = self:GetPosition()  -- Original vehicle position
        --     local min_ground_clearance = 1.0  -- Minimum 1m above ground
        --     if current_position.z < base_position.z - min_ground_clearance then
        --         -- Raycast start point would be too low, clamp to minimum ground clearance
        --         current_position.z = base_position.z - min_ground_clearance
        --         self.log_obj:Record(LogLevel.Trace, "Raycast start point clamped to prevent ground false positive")
        --     end
        -- end

        local adaptive_distance = distance * (1 + speed_factor * 0.4)
        local target_pos = Vector4.new(
            current_position.x + adaptive_distance * search_vec.x,
            current_position.y + adaptive_distance * search_vec.y,
            current_position.z + adaptive_distance * search_vec.z,
            1.0
        )

        for _, filter in ipairs(self.weak_collision_filters) do
            local is_success, _ = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_position, target_pos, filter, false, false)
            if is_success then
                self.log_obj:Record(LogLevel.Trace, "Wall Detected: " .. filter)
                return true
            end
        end

        -- check exception area (with bypass for destination approach)
        if is_check_exception_area then
            local is_exception, tag, _ = self:IsInExceptionArea(target_pos)
            self.log_obj:Record(LogLevel.Trace, "IsWall Check - Exception Area: " .. tostring(is_exception) ..
                                               ", Tag: " .. (tag or "nil") ..
                                               ", Bypassed: " .. tostring(self.is_exception_area_bypassed))
            if is_exception and not self.is_exception_area_bypassed then
                self.log_obj:Record(LogLevel.Trace, "Exception Area Blocked: " .. tag)
                return true
            end
        end

        self.log_obj:Record(LogLevel.Trace, "IsWall - No obstacles detected")
        return false
    end

	-- New collision detection modes based on vehicle geometry
	collision_mode = collision_mode or "advanced"  -- Default to advanced mode

	if collision_mode == "simple" then
		-- Simple mode: 3 points - front, center, rear along vehicle axis
		local front_distance = self.collision_check_front_distance
		local rear_distance = self.collision_check_rear_distance

		-- Front point (along vehicle's forward direction)
		if check_collision_at_point(0, front_distance) then
			return true, search_vec
		end

		-- Center point (vehicle position)
		if check_collision_at_point(0, 0) then
			return true, search_vec
		end

		-- Rear point (along vehicle's backward direction)  
		if check_collision_at_point(0, -rear_distance) then
			self.safe_streak_count = 0
			self.iswall_cache[cache_key] = {
				result = true,
				search_vec = search_vec,
				timestamp = current_time,
				position = current_position
			}
			return true, search_vec
		end
	else
		-- Advanced mode: 7 points - vehicle center + front plane (5 points) + rear point
		-- Front plane: 5-point grid at vehicle front position (perpendicular to search direction)
		local front_distance = self.collision_check_front_distance
		local rear_distance = self.collision_check_rear_distance

		-- Phase 1: Check vehicle center point first (most important)
		if check_collision_at_point(0, 0, 0) then
			return true, search_vec
		end

		-- Phase 2: Front plane points: center + 4 corners at front position (square grid)
		local front_points = {
			{0, front_distance, 0},                        -- center front
			{-detection_step, front_distance, detection_step},   -- left upper front
			{detection_step, front_distance, detection_step},    -- right upper front
			{-detection_step, front_distance, -detection_step},  -- left lower front
			{detection_step, front_distance, -detection_step},   -- right lower front
		}

		-- Check front plane points
		for _, point in ipairs(front_points) do
			if check_collision_at_point(point[1], point[2], point[3]) then
				self.safe_streak_count = 0
				self.iswall_cache[cache_key] = {
					result = true,
					search_vec = search_vec,
					timestamp = current_time,
					position = current_position
				}
				return true, search_vec
			end
		end

		-- Phase 3: Rear point check
		if check_collision_at_point(0, -rear_distance, 0) then
			self.safe_streak_count = 0
			self.iswall_cache[cache_key] = {
				result = true,
				search_vec = search_vec,
				timestamp = current_time,
				position = current_position
			}
			return true, search_vec
		end
	end

	-- Check exception area here (with bypass for destination approach)
	if is_check_exception_area and not self.is_exception_area_bypassed then
		local is_exception, tag, _ = self:IsInExceptionArea(self:GetPosition())
		if is_exception then
			self.safe_streak_count = 0  -- Reset streak on exception area detection
			self.log_obj:Record(LogLevel.Trace, "Here is Exception Area: " .. tag)
			-- Save to cache
			self.iswall_cache[cache_key] = {
				result = true,
				search_vec = search_vec,
				timestamp = current_time,
				position = current_position
			}
			return true, search_vec
		end
	end

	-- Safe: increase streak and save to cache
	self.safe_streak_count = self.safe_streak_count + 1
	self.log_obj:Record(LogLevel.Trace, "Full check - Safe (streak: " .. self.safe_streak_count .. ")")

	-- Save to cache
	self.iswall_cache[cache_key] = {
		result = false,
		search_vec = search_vec,
		timestamp = current_time,
		position = current_position
	}

    return false, search_vec
end

return AV