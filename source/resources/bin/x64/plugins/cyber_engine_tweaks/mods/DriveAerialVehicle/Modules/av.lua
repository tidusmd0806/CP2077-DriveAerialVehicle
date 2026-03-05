local Camera = require("Modules/camera.lua")
local Engine = require("Modules/engine.lua")
local Navigation = require("Modules/navigation.lua")
local Utils = require("Etc/utils.lua")
local AV = {}
AV.__index = AV

-- Attach navigation/autopilot methods from a dedicated module to keep this file smaller.
local navigation_obj = Navigation:New()
navigation_obj:Init(AV)

--- Constractor.
---@param core_obj any Core instance
---@return table instance av instance
function AV:New(core_obj)
	---instance---
	local obj = {}
	obj.core_obj = core_obj
	obj.all_models = core_obj.all_models
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
	-- autopilot
	obj.destination_range = 3
	obj.destination_z_offset = 10
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
	obj.collision_query_filter = nil
	obj.minimum_distance_to_ground = 1.2
	obj.spawn_time = 0
	-- av status
	obj.is_landed = false
	obj.is_leaving = false
	obj.is_auto_pilot = false
	obj.is_unmounting = false
	obj.is_spawning = false
	obj.is_combat = false
	-- autopilot
	obj.mappin_destination_position = Vector4.new(0, 0, 0, 1)
	obj.favorite_destination_position = Vector4.new(0, 0, 0, 1)
	obj.autopilot_speed = 1
	obj.autopilot_turn_speed = 0.01
	obj.autopilot_leaving_height = 100
	obj.autopilot_searching_range = 50         -- Detection range for obstacles
	obj.autopilot_searching_step = 2           -- Used for minimum search range validation
	obj.is_failture_auto_pilot = false
	obj.autopilot_horizontal_sign = 0
	obj.autopilot_vertical_sign = 0
	obj.auto_speed_reduce_rate = 1
	obj.search_range = 1
	obj.initial_destination_length = 1
	obj.dest_dir_vector_norm = 1
	obj.dest_remaining_to_final = 1
	obj.pre_speed_list = {x = 0, y = 0, z = 0}
	obj.autopilot_exception_area_list = {}
	obj.collision_check_side_distance = 2.5
	obj.collision_check_front_distance = 3.5
	obj.collision_check_rear_distance = 3.5
	obj.autopilot_leaving_deceleration_start_flag = false
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
	obj.eval_safety_margin_range = 10              -- Check +/-10 degrees around selected angle (adjusted for 5-degree steps)
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
	obj.deadend_score_threshold = 10               -- Threshold score to determine dead-end situation (lowered to prevent false positives)
	obj.deadend_emergency_threshold = 0            -- Emergency threshold: all directions blocked
	obj.deadend_vertical_escape_distance = 20     -- Distance to ascend when escaping dead-end (meters)
	obj.deadend_escape_check_interval = 3         -- Seconds between dead-end escape attempts
	obj.is_deadend_escape_active = false          -- Flag for dead-end escape mode
	obj.deadend_escape_target_z = nil             -- Target altitude for dead-end escape
	obj.deadend_last_check_time = 0               -- Last time dead-end was checked

	-- === NEW: Sector-Based Navigation System ===
	-- Global route planning (sector-based)
	obj.sector_size = 20                          -- Sector size: 20m x 20m x 20m
	obj.current_global_route = {}                 -- Current planned route (list of sector coordinates)
	obj.current_route_index = 1                   -- Current position in route
	obj.route_replan_interval = 10                -- Replan route every N seconds
	obj.last_route_plan_time = 0
	obj.astar_is_partial_route = false
	obj.astar_local_avoidance_recheck_time = 0       -- last time astar_local_avoidance recheck was performed    -- True when last A* hit iteration limit (partial route)

	-- Local avoidance (spherical raycast)
	obj.local_avoidance_enabled = true
	obj.local_ray_count = 32                      -- Number of rays for local avoidance
	obj.local_ray_distance = 25                   -- Ray detection distance for local avoidance (meters)
	obj.local_repulsion_strength = 35.0           -- Repulsion force multiplier (balanced for smooth avoidance)
	obj.local_attraction_strength = 0.15          -- Attraction to destination multiplier (increased to prevent stalling)
	obj.local_min_obstacle_distance = 35.0        -- Minimum safe distance from obstacles (increased for much safer margin)
	obj.local_ray_angles = {}                     -- Pre-calculated ray directions (unit vectors)
	
	-- === 3D Local Avoidance Navigation ===
	obj.local_avoidance_stuck_timer = 0           -- Accumulated seconds of receding from destination
	obj.local_avoidance_stuck_threshold = 5.0     -- Seconds receding from dest in BOUNDARY = stuck
	obj.local_avoidance_stuck_escape_time = 0     -- Timestamp when stuck-escape ascent started (0 = not escaping)
	obj.local_avoidance_net_check_dist = nil      -- Distance to dest at last stuck-check interval
	obj.local_avoidance_net_check_time = 0        -- Time of last stuck-check interval

	-- 3D Obstacle Map: records confirmed obstacle positions across flights
	obj.obstacle_map          = {}          -- key = "cx_cy_cz", value = true (obstacle) | "danger" (adjacent to obstacle) | false (clear) | nil (unknown)
	                                        --   Priority (high->low): true > "danger" > false > nil (never overwrite higher with lower)
	obj.obstacle_cell_size    = 10.0        -- Grid cell size in meters (~vehicle length)
	obj.obstacle_map_path     = "Data/obstacle_map.dat"  -- Legacy path (for migration)
	obj.obstacle_map_dir      = "Data/map"               -- Chunked storage directory
	obj.obstacle_map_chunk_cells = 50                     -- Cells per chunk side (50x10m = 500m)
	obj.obstacle_map_dirty_chunks = {}                    -- chunk_key -> true (needs saving)
	obj.obstacle_map_dirty_cells  = {}                    -- chunk_key -> {cell_key -> true} changed since last save
	obj.obstacle_map_chunk_index  = {}                    -- chunk_key -> {cell_key -> true}
	obj.obstacle_map_dir_ok    = false                    -- Directory existence verified
	obj.route_save_path       = "Data/last_route.json"  -- Last A* route for visualization

	-- Obstacle map recording (toggled from debug menu)
	obj.is_obstacle_map_recording  = false   -- When true, scan rays during ANY driving (not just autopilot)
	obj.obstacle_record_interval   = 0.2     -- Seconds between scan ticks during recording
	obj.obstacle_record_range      = 35.0    -- Raycast range during scan (m)

	-- Autopilot navigation phases
	-- "start_local" : start is in unknown sector -> local avoidance + scanning toward nearest known sector
	-- "astar"       : follow A* route directly (no local avoidance)
	-- "final_local" : destination was unknown -> local avoidance + scanning for final approach
	obj.autopilot_phase           = "astar"   -- current navigation phase
	obj.autopilot_local_target    = nil        -- intermediate target for start_local / final_local phases
	obj.autopilot_dest_is_unknown = false      -- true when final destination is in unknown sector
	obj.autopilot_exploring_mode  = false      -- legacy alias (kept for compatibility)
	obj.autopilot_scan_dirty_count    = 0      -- scan ticks since last batch save
	obj.autopilot_scan_dirty_threshold = 150   -- save every 150 ticks (~30s at 0.2s/tick)
	obj.autopilot_scan_save_interval  = 120.0  -- also force-save every 120 seconds
	obj.autopilot_scan_last_save_time = 0

	-- Yaw smoothing
	obj.yaw_target_smoothed = nil         -- Smoothed yaw target angle (degrees), nil = not initialized
	obj.yaw_smooth_alpha = 0.06           -- Low-pass coefficient (lower = smoother, slower response)
	obj.yaw_deadzone_deg = 4.0            -- Don't turn if yaw error is smaller than this (degrees)

	-- Collision recording
	obj.collision_detection_count = 0             -- Current session collision detections
	obj.last_collision_sector = nil               -- Last sector where collision was detected

	-- Smooth movement parameters
	obj.direction_continuity_bonus = 10        -- Bonus for keeping same direction (reduced oscillation)

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
	self:InitializeCollisionQueryFilter()

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

	-- Apply autopilot speed from user settings
	self:ApplyAutopilotSpeed()
	self.autopilot_exception_area_list = Utils:ReadJson(self.exception_area_path)
	self.collision_check_side_distance = self.all_models[index].collision_check_side_distance
	self.collision_check_front_distance = self.all_models[index].collision_check_front_distance or self.collision_check_side_distance
	self.collision_check_rear_distance = self.all_models[index].collision_check_rear_distance or self.collision_check_side_distance

	-- Initialize learning system (wrapped in pcall for safety)
	local success, error_msg = pcall(function()
		self:InitializeLearningSystem()
	end)
	
	if not success and self.log_obj then
		self.log_obj:Record(LogLevel.Warning, "Failed to initialize learning system in Init(): " .. tostring(error_msg))
	end
end

--- Build and cache a query filter using collision_filters.
function AV:InitializeCollisionQueryFilter()
	local query_filter = QueryFilter.new()
	for _, group_name in ipairs(self.collision_filters) do
		query_filter.mask2 = query_filter.mask2 + QueryFilter.AddGroup(CName.new(group_name)).mask2
	end
	self.collision_query_filter = query_filter
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
		return Vector4.new(0, 0, 0, 1.0)
	end
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
        return Vector4.new(0, 0, 0, 1.0)
    end
    return entity:GetWorldForward()
end

--- Get Vehicle Right Vector
---@return Vector4
function AV:GetRight()
	if self.entity_id == nil then
		return Vector4.new(0, 0, 0, 1.0)
	end
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
        return Vector4.new(0, 0, 0, 1.0)
    end
    return entity:GetWorldRight()
end

--- Get Vehicle Up Vector
---@return Vector4
function AV:GetUp()
	if self.entity_id == nil then
		return Vector4.new(0, 0, 0, 1.0)
	end
	local entity = Game.FindEntityByID(self.entity_id)
    if entity == nil then
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
	if self.collision_query_filter == nil then
		self:InitializeCollisionQueryFilter()
	end
    current_position.z = current_position.z + self.search_ground_offset
	local is_success, trace_result = Game.GetSpatialQueriesSystem():SyncRaycastByQueryFilter(
		current_position,
		Vector4.new(current_position.x, current_position.y, current_position.z - self.search_ground_distance, 1.0),
		self.collision_query_filter,
		false,
		false)
	if is_success then
		return trace_result.position.z
	end
    return current_position.z - self.search_ground_distance - 1
end

--- Get Height between ground and vehicle
---@return number height
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
		return false
	end
	if not entity:IsPlayerMounted() then
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
		return false
	end
	local entity = Game.FindEntityByID(self.entity_id)
	if entity == nil then
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
	self.spawn_time = os.clock()

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
				self.log_obj:Record(LogLevel.Trace, "Fluctuation Velocity")
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
			if not self.engine_obj:OnlyAngularRun(roll_idle, pitch_idle, yaw_idle) then
				self.log_obj:Record(LogLevel.Warning, "Failed to run angular velocity in DespawnFromGround")
			end
			if timer.tick == 1 then
				self.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
				self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 1))
				self.log_obj:Record(LogLevel.Info, "Initial Despawn Velocity: " .. self.engine_obj:GetDirectionVelocity().z)
			elseif timer.tick == 2 then
				self.engine_obj:SetFluctuationVelocityParams(1, math.abs(self.down_speed))
				self.log_obj:Record(LogLevel.Trace, "Fluctuation Velocity")
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
			self.log_obj:Record(LogLevel.Error, "Door event is not valid", "ChangeDoorState - door: " .. tostring(door_name) .. ", state: " .. tostring(door_state))
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

	-- Auto-start obstacle map recording if the setting is enabled
	if DAV.user_setting_table.is_enable_scan_during_autopilot then
		self:StartObstacleRecording()
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
				
				-- Stop obstacle recording and save on true unmount
				self:StopObstacleRecording()

				-- Consolidate learning data before unmounting
				if self.short_term_memory and 
				   self.short_term_memory.path_history and 
				   #self.short_term_memory.path_history > 0 then
					self:ConsolidateMemory()
				end
				
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
		if not self.engine_obj:Run(x_total, y_total, z_total, roll_total, pitch_total, yaw_total) then
			self.log_obj:Record(LogLevel.Warning, "Failed to run engine in Operate")
		end
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

--- Toggle radio ON or switch to next station.
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

--- Get exit position in world coordinates.
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

--- Initialize Learning System (stub - sector navigation handles all learning data)
function AV:InitializeLearningSystem()
	-- Old learning system no longer used
	-- Sector navigation system handles all learning data
	if self.log_obj then
		self.log_obj:Record(LogLevel.Debug, "Legacy learning system skipped (using sector navigation)")
	end
end

--- Consolidate short-term memory into long-term memory (call on flight end)
function AV:ConsolidateMemory()
	-- Save current in-memory map to disk.
	-- NOTE: do NOT stop recording here; recording runs for the entire time the
	-- player is in the vehicle (including after autopilot ends / is interrupted).
	-- StopObstacleRecording() is called exclusively from the Unmount handler.
	self:SaveObstacleMap()
	if self.log_obj then
		self.log_obj:Record(LogLevel.Info, "Flight completed, obstacle map saved")
	end
end

-- Local-avoidance navigation methods are defined in Modules/navigation.lua and attached to AV.

return AV

