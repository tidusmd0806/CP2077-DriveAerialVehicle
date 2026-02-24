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
	obj.spawn_time = 0
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
	obj.autopilot_searching_range = 50         -- Detection range for obstacles
	obj.autopilot_searching_step = 2           -- Used for minimum search range validation
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

	-- Local avoidance (spherical raycast)
	obj.local_avoidance_enabled = true
	obj.local_ray_count = 32                      -- Number of rays for local avoidance
	obj.local_ray_distance = 25                   -- Ray detection distance for local avoidance (meters)
	obj.local_repulsion_strength = 35.0           -- Repulsion force multiplier (balanced for smooth avoidance)
	obj.local_attraction_strength = 0.15          -- Attraction to destination multiplier (increased to prevent stalling)
	obj.local_min_obstacle_distance = 35.0        -- Minimum safe distance from obstacles (increased for much safer margin)
	obj.local_ray_angles = {}                     -- Pre-calculated ray directions (unit vectors)
	
	-- Repulsion-based route replanning
	obj.repulsion_threshold = 20.0                -- If repulsion magnitude exceeds this, trigger route replan
	obj.current_repulsion_direction = nil         -- Current repulsion direction (normalized Vector3)
	obj.repulsion_route_bias_enabled = false      -- Whether to bias A* costs toward repulsion direction
	obj.repulsion_cost_bonus = 0.5                -- Cost multiplier for sectors aligned with repulsion (lower = more favorable)
	obj.last_repulsion_replan_time = 0
	obj.repulsion_replan_cooldown = 0.5           -- Cooldown between repulsion-based route replans (seconds)
	obj.force_escape_threshold = 200.0            -- Repulsion magnitude to force emergency vertical escape

	-- === 3D Tangent Bug Navigation ===
	obj.tangent_mode = "DIRECT"           -- "DIRECT" = straight to goal, "BOUNDARY" = follow obstacle surface
	obj.tangent_detect_dist = 25.0        -- Forward detection range (m)
	obj.tangent_enter_dist = 18.0         -- Enter BOUNDARY when obstacle closer than this (m)
	obj.tangent_exit_dist = 28.0          -- Return to DIRECT when path clears beyond this (m) - hysteresis
	obj.tangent_obstacle_normal = nil     -- Estimated inward normal of detected obstacle face
	obj.tangent_boundary_dir = nil        -- Current best boundary-following direction
	obj.tangent_mode_start_time = 0       -- When BOUNDARY mode started (for timeout)
	obj.tangent_boundary_timeout = 30.0   -- Max seconds in BOUNDARY before reset to DIRECT
	obj.tangent_last_pos = nil            -- Position last tick (for stuck detection)
	obj.tangent_stuck_timer = 0           -- Accumulated seconds without significant movement
	obj.tangent_stuck_threshold = 5.0     -- Seconds without movement = stuck
	obj.tangent_stuck_escape_time = 0     -- Timestamp when stuck-escape ascent started (0 = not escaping)
	obj.tangent_stuck_escape_dur = 3.0    -- Seconds to ascend vertically during stuck escape
	obj.tangent_entry_pos = nil           -- Position where BOUNDARY mode was entered (for progress check)
	obj.tangent_direct_start_pos = nil    -- Position when DIRECT mode began (for cooldown after BOUNDARY)
	obj.tangent_direct_cooldown_dist = 20.0 -- Must travel this far in DIRECT before re-entering BOUNDARY

	-- 3D Obstacle Map: records confirmed obstacle positions across flights
	obj.obstacle_map          = {}          -- key = "cx_cy_cz", value = {count=N}
	obj.obstacle_cell_size    = 10.0        -- Grid cell size in meters (≈ vehicle length)
	obj.obstacle_map_path     = "Data/obstacle_map.dat"
	obj.obstacle_min_hits     = 1           -- Min hits before a cell is "known obstacle" (1 = any single hit counts)
	obj.route_save_path       = "Data/last_route.json"  -- Last A* route for visualization

	-- Obstacle map recording (toggled from debug menu)
	obj.is_obstacle_map_recording  = false   -- When true, scan rays during ANY driving (not just autopilot)
	obj.obstacle_record_interval   = 0.2     -- Seconds between scan ticks during recording
	obj.obstacle_record_range      = 35.0    -- Raycast range during scan (m)

	-- Yaw smoothing
	obj.yaw_target_smoothed = nil         -- Smoothed yaw target angle (degrees), nil = not initialized
	obj.yaw_smooth_alpha = 0.06           -- Low-pass coefficient (lower = smoother, slower response)
	obj.yaw_deadzone_deg = 4.0            -- Don't turn if yaw error is smaller than this (degrees)

	-- Scanning mode settings
	obj.scanning_mode = false                     -- When true, scanning sectors for danger map
	obj.scan_ray_count = 32                       -- Rays used for danger scanning
	obj.scan_ray_distance = 25                    -- Ray detection distance for scanning (meters)
	obj.scan_current_sector_index = 0             -- Current scanning progress
	obj.scan_total_sectors = 0                    -- Total sectors to scan
	obj.scan_sector_list = {}                     -- List of sectors to scan

	-- Collision recording
	obj.collision_detection_count = 0             -- Current session collision detections
	obj.last_collision_sector = nil               -- Last sector where collision was detected

	-- Smooth movement parameters
	obj.direction_continuity_bonus = 10        -- Bonus for keeping same direction (reduced oscillation)
	obj.last_selected_direction_name = nil     -- Track previous direction

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

	-- Initialize learning system (wrapped in pcall for safety)
	local success, error_msg = pcall(function()
		self:InitializeLearningSystem()
	end)
	
	if not success and self.log_obj then
		self.log_obj:Record(LogLevel.Warning, "Failed to initialize learning system in Init(): " .. tostring(error_msg))
	end
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
	if DAV.user_setting_table.autopilot_selected_index == 0 then
		if self.mappin_destination_position:IsZero() then
			self.log_obj:Record(LogLevel.Debug, "No Mappin Destination", "StartAutoPilot")
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

	-- Store target altitude for maintaining flight height
	local target_altitude
	if self.autopilot_is_only_horizontal then
		self:AutoLeaving(direction_vector, self.autopilot_leaving_height - current_position.z)
		target_altitude = self.autopilot_leaving_height
		self.log_obj:Record(LogLevel.Info, "Select Leaving Only Horizontal")
	else
		self:AutoLeaving(direction_vector, self.standard_leaving_height)
		target_altitude = current_position.z + self.standard_leaving_height
		self.log_obj:Record(LogLevel.Info, "Select Leaving Horizontal and Vertical")
	end

	-- Adjust destination altitude to match target flight altitude
	-- Use the HIGHER of flight altitude or actual destination altitude
	-- This prevents downward bias while maintaining safe flight altitude
	local adjusted_z = math.max(destination_position.z, target_altitude)
	
	local altitude_adjusted_destination = Vector4.new(
		destination_position.x,
		destination_position.y,
		adjusted_z,  -- Use higher altitude (either flight altitude or destination)
		1
	)
	self.target_flight_altitude = target_altitude
	
	self.log_obj:Record(LogLevel.Info, string.format(
		"Destination altitude adjusted: original=%.1f, flight_alt=%.1f, final=%.1f",
		destination_position.z, target_altitude, adjusted_z))
	
	-- Debug: Log sector keys for start and destination
	local start_sector = self:PositionToSectorKey(current_position)
	local dest_sector = self:PositionToSectorKey(altitude_adjusted_destination)
	self.log_obj:Record(LogLevel.Info, string.format(
		"Route planning: start_sector=%s (pos: %.1f, %.1f, %.1f), dest_sector=%s (pos: %.1f, %.1f, %.1f)",
		start_sector or "nil", current_position.x, current_position.y, current_position.z,
		dest_sector or "nil", altitude_adjusted_destination.x, altitude_adjusted_destination.y, altitude_adjusted_destination.z))

	-- autopilot parameter initialize
	self.autopilot_angle = 0
	self.autopilot_horizontal_sign = 0
	self.autopilot_vertical_sign = 0
	self.auto_speed_reduce_rate = 1
	self.pre_speed_list = {x = 0, y = 0, z = 0}
	-- Tangent Bug state reset
	self.tangent_mode = "DIRECT"
	self.tangent_obstacle_normal = nil
	self.tangent_boundary_dir = nil
	self.tangent_last_pos = nil
	self.tangent_stuck_timer = 0
	self.tangent_stuck_escape_time = 0
	self.tangent_entry_pos = nil
	self.tangent_direct_start_pos = nil
	-- Yaw smoothing reset
	self.yaw_target_smoothed = nil

	-- NEW: Initialize sector navigation system
	self:InitializeSectorSystem()
	
	-- NEW: Plan initial global route with altitude-adjusted destination
	self.current_global_route = self:PlanGlobalRoute(current_position, altitude_adjusted_destination)
	self.current_route_index = 1
	self.last_route_plan_time = os.clock()
	self.altitude_adjusted_destination = altitude_adjusted_destination
	-- Save route for external visualization
	self:SaveLastRoute(self.current_global_route, current_position, altitude_adjusted_destination)

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

		-- Distance to final destination.
		-- For arrival check, Z is clipped (being above target is OK):
		-- horizontal proximity is enough to trigger landing.
		local ddx = destination_position.x - current_position.x
		local ddy = destination_position.y - current_position.y
		local ddz = destination_position.z - current_position.z
		local horiz_to_final = math.sqrt(ddx*ddx + ddy*ddy)
		local dist_to_final_arr = math.sqrt(ddx*ddx + ddy*ddy + (ddz < 0 and 0 or ddz*ddz))

		-- === A* Route Waypoint Following ===
		-- Advance waypoint index when vehicle reaches current waypoint.
		-- This makes the vehicle actually fly along the A*-planned route
		-- instead of heading straight to the final destination.
		-- NOTE: advance threshold uses HORIZONTAL distance only, because dest_dir_vector.z
		-- is clipped to 0 when target is below → vehicle can't descend to waypoint Z,
		-- so 3D distance would never reach the threshold even when horizontally arrived.
		local nav_target = destination_position  -- fallback: aim at final dest
		if #self.current_global_route > 0 and horiz_to_final > self.sector_size * 1.5 then
			local advance_thr = self.sector_size * 0.9  -- ~18 m for sector_size=20
			while self.current_route_index <= #self.current_global_route do
				local wp_key = self.current_global_route[self.current_route_index]
				local wp_pos = self:SectorKeyToPosition(wp_key)
				if wp_pos then
					local wdx = current_position.x - wp_pos.x
					local wdy = current_position.y - wp_pos.y
					local horiz_to_wp = math.sqrt(wdx*wdx + wdy*wdy)  -- horizontal only
					if horiz_to_wp < advance_thr then
						self.log_obj:Record(LogLevel.Debug, string.format(
							"Route: waypoint %d/%d reached (%s), advancing",
							self.current_route_index, #self.current_global_route, wp_key))
						self.current_route_index = self.current_route_index + 1
					else
						nav_target = wp_pos  -- aim at this waypoint
						break
					end
				else
					self.current_route_index = self.current_route_index + 1
				end
			end
			-- All waypoints passed → aim directly at final destination
			if self.current_route_index > #self.current_global_route then
				nav_target = destination_position
			end
		end

		-- Calculate destination vector toward current nav target (A* waypoint or final dest)
		local dest_dir_vector = Vector4.new(
			nav_target.x - current_position.x,
			nav_target.y - current_position.y,
			nav_target.z - current_position.z, 1)
		if self.autopilot_is_only_horizontal then
			dest_dir_vector.z = 0
		elseif dest_dir_vector.z < 0 then
			dest_dir_vector.z = 0
		end
		-- dest_dir_vector_norm: distance to current nav target (waypoint or final dest)
		self.dest_dir_vector_norm = Vector4.Length(dest_dir_vector)

		-- Update exception area bypass status based on distance to destination
		self:UpdateExceptionAreaBypass()

		-- check destination: use horizontal + upward-only Z so that being above target
		-- at flight altitude doesn't prevent arrival detection
		if dist_to_final_arr < self.destination_range then
			self.log_obj:Record(LogLevel.Info, "Arrived at destination")
			self.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			self:AutoLanding(current_position.z - destination_position.z + self.destination_z_offset)
			Cron.Halt(timer)
			return
		end

		-- 3D Tangent Bug Navigation
		local current_time = os.clock()
		local navigation_vector = self:TangentBugNavigate(current_position, dest_dir_vector, current_time)

		-- Set direction vector for movement
		self.search_range = self.autopilot_searching_range
		if self.dest_dir_vector_norm < self.autopilot_searching_range then
			self.search_range = self.dest_dir_vector_norm + 0.1
		end

		local direction_vector = Vector4.new(
			navigation_vector.x * self.search_range,
			navigation_vector.y * self.search_range,
			navigation_vector.z * self.search_range,
			1
		)
		local direction_vector_norm = Vector4.Length(direction_vector)

		-- Automatic speed adjustment based on navigation vector orientation
		local navigation_angle = math.deg(math.acos(math.max(-1, math.min(1, 
			(navigation_vector.x * dest_dir_vector.x + navigation_vector.y * dest_dir_vector.y + navigation_vector.z * dest_dir_vector.z) /
			(Vector4.Length(navigation_vector) * Vector4.Length(dest_dir_vector))
		))))
		
		-- Base speed reduction based on deviation from destination
		local base_speed_rate = 0.7  -- Default normal speed
		if navigation_angle > 60 then
			base_speed_rate = 0.3  -- Slow down significantly for large deviations
		elseif navigation_angle > 30 then
			base_speed_rate = 0.5  -- Moderate slowdown
		end
		
		-- Combine with proximity-based speed from TangentBug (take the more conservative value)
		self.auto_speed_reduce_rate = math.min(base_speed_rate, self.auto_speed_reduce_rate)

		-- speed control
		if self.auto_speed_reduce_rate < self.autopilot_min_speed_rate then
			self.auto_speed_reduce_rate = self.autopilot_min_speed_rate
		elseif self.auto_speed_reduce_rate > 1 then
			self.auto_speed_reduce_rate = 1
		end

		local autopilot_speed = self.autopilot_speed * self.auto_speed_reduce_rate
		local fix_direction_vector = Vector4.new(autopilot_speed * direction_vector.x / direction_vector_norm, autopilot_speed * direction_vector.y / direction_vector_norm, autopilot_speed * direction_vector.z / direction_vector_norm, 1)

		-- yaw control
		local vehicle_angle = self:GetForward()
		local vehicle_angle_norm = Vector4.Length(vehicle_angle)
		local yaw_vehicle = math.atan2(vehicle_angle.y / vehicle_angle_norm, vehicle_angle.x / vehicle_angle_norm) * 180 / Pi()

		-- Compute raw yaw target from navigation vector
		local yaw_target_raw = yaw_vehicle
		local yaw_target_vector = navigation_vector
		local yaw_target_vector_norm = Vector4.Length(yaw_target_vector)
		if yaw_target_vector_norm > 0.001 then
			yaw_target_raw = math.atan2(yaw_target_vector.y / yaw_target_vector_norm, yaw_target_vector.x / yaw_target_vector_norm) * 180 / Pi()
		end

		-- Low-pass filter: initialize on first tick, then blend toward raw target
		if not self.yaw_target_smoothed then
			self.yaw_target_smoothed = yaw_target_raw
		end
		-- Shortest-path angular blend (handle 180° wrap)
		local yaw_delta_raw = yaw_target_raw - self.yaw_target_smoothed
		if yaw_delta_raw > 180 then yaw_delta_raw = yaw_delta_raw - 360
		elseif yaw_delta_raw < -180 then yaw_delta_raw = yaw_delta_raw + 360 end
		self.yaw_target_smoothed = self.yaw_target_smoothed + yaw_delta_raw * self.yaw_smooth_alpha

		-- Error between vehicle heading and smoothed target
		local yaw_diff = self.yaw_target_smoothed - yaw_vehicle
		if yaw_diff > 180 then yaw_diff = yaw_diff - 360
		elseif yaw_diff < -180 then yaw_diff = yaw_diff + 360 end

		-- Dead zone: suppress micro-corrections
		local yaw_diff_half = 0
		if math.abs(yaw_diff) > self.yaw_deadzone_deg then
			yaw_diff_half = yaw_diff * self.autopilot_turn_speed
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
			if not self.engine_obj:Run(adjust_x, adjust_y, adjust_z, roll, pitch, yaw) then
				self.log_obj:Record(LogLevel.Warning, "Failed to run engine in Autopilot (overshoot prevention)")
			end
			-- Restore original target after run
			self.engine_obj.target_velocity = original_target
		else
			if not self.engine_obj:Run(adjust_x, adjust_y, adjust_z, roll, pitch, yaw) then
				self.log_obj:Record(LogLevel.Warning, "Failed to run engine in Autopilot")
			end
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
		if not self.engine_obj:OnlyAngularRun(roll_idle, pitch_idle, yaw_idle) then
			self.log_obj:Record(LogLevel.Warning, "Failed to run angular velocity during takeoff")
		end

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

				if not self.engine_obj:Run(0.0, 0.0, 0.0, 0.0, 0.0, yaw_diff_half) then
					self.log_obj:Record(LogLevel.Warning, "Failed to run engine during leaving")
				end

				if math.abs(yaw_diff_half) < 0.1 then
					if not self.engine_obj:Run(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) then
						self.log_obj:Record(LogLevel.Warning, "Failed to run engine at leaving end")
					end
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
		if not self.engine_obj:OnlyAngularRun(roll_idle, pitch_idle, yaw_idle) then
			self.log_obj:Record(LogLevel.Warning, "Failed to run angular velocity during landing")
		end

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
	
	-- Consolidate learning data
	self:ConsolidateMemory()
end

--- Set AV.is_failture_auto_pilot and AV.is_auto_pilot when AutoPilot Failed.
function AV:InterruptAutoPilot()
	self.is_auto_pilot = false
	self.is_failture_auto_pilot = true
	
	-- Consolidate learning data (failures are important for learning)
	self:ConsolidateMemory()
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

	-- Save to cache
	self.iswall_cache[cache_key] = {
		result = false,
		search_vec = search_vec,
		timestamp = current_time,
		position = current_position
	}

    return false, search_vec
end

--- ============================================================================
--- NEW: Sector-Based Navigation System
--- ============================================================================

--- Initialize Sector Navigation System
function AV:InitializeSectorSystem()
	local success, error_msg = pcall(function()
		-- Initialize spherical ray pattern for local avoidance
		self:GenerateSphericalRayPattern()
		
		-- Load obstacle map
		self:LoadObstacleMap()
		
		self.log_obj:Record(LogLevel.Info, "Sector navigation system initialized")
	end)
	
	if not success then
		self.log_obj:Record(LogLevel.Error, "Failed to initialize sector system: " .. tostring(error_msg))
	end
end

--- Generate spherical ray pattern for local avoidance
function AV:GenerateSphericalRayPattern()
	self.local_ray_angles = {}
	
	-- Fibonacci sphere algorithm for even distribution
	local n = self.local_ray_count
	local golden_ratio = (1 + math.sqrt(5)) / 2
	
	for i = 0, n - 1 do
		local theta = 2 * math.pi * i / golden_ratio
		local phi = math.acos(1 - 2 * (i + 0.5) / n)
		
		local x = math.sin(phi) * math.cos(theta)
		local y = math.sin(phi) * math.sin(theta)
		local z = math.cos(phi)
		
		table.insert(self.local_ray_angles, {x = x, y = y, z = z})
	end
	
	self.log_obj:Record(LogLevel.Debug, string.format("Generated %d spherical rays for local avoidance", n))
end

--- Convert position to sector key
---@param position Vector4 Position in world space
---@return string|nil sector_key Format: "x_y_z", or nil if position is invalid
function AV:PositionToSectorKey(position)
	if not position then return nil end
	
	local sx = math.floor(position.x / self.sector_size)
	local sy = math.floor(position.y / self.sector_size)
	local sz = math.floor(position.z / self.sector_size)
	
	return string.format("%d_%d_%d", sx, sy, sz)
end

--- Get sector center position from key
---@param sector_key string Sector key "x_y_z"
---@return Vector4|nil Sector center position
function AV:SectorKeyToPosition(sector_key)
	if not sector_key then return nil end
	
	local sx, sy, sz = sector_key:match("([^_]+)_([^_]+)_([^_]+)")
	if not sx then return nil end
	
	sx, sy, sz = tonumber(sx), tonumber(sy), tonumber(sz)
	
	return Vector4.new(
		(sx + 0.5) * self.sector_size,
		(sy + 0.5) * self.sector_size,
		(sz + 0.5) * self.sector_size,
		1
	)
end

--- Scan sector for danger
--- NOTE: sector_database removed; function stubbed out. Use obstacle_map for route cost.
---@param sector_key string Sector key to scan
---@return number Always 0
function AV:ScanSectorDanger(sector_key)
	self.log_obj:Record(LogLevel.Info, "ScanSectorDanger: sector_database removed, use obstacle_map for cost")
	return 0
end

--- Get neighbor sector keys (26 directions: 6 cardinal + 12 edge + 8 corner)
---@param sector_key string Current sector key
---@return table List of neighbor sector keys
function AV:GetNeighborSectors(sector_key)
	if not sector_key then return {} end
	
	local sx, sy, sz = sector_key:match("([^_]+)_([^_]+)_([^_]+)")
	if not sx then return {} end
	
	sx, sy, sz = tonumber(sx), tonumber(sy), tonumber(sz)
	
	local neighbors = {}
	-- 6 cardinal directions only: all equal distance (1 sector = 25m)
	local offsets = {
		{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1},
	}
	
	for _, offset in ipairs(offsets) do
		local neighbor_key = string.format("%d_%d_%d", 
			sx + offset[1], sy + offset[2], sz + offset[3])
		table.insert(neighbors, neighbor_key)
	end
	
	return neighbors
end

--- Calculate heuristic (estimated cost) from sector to goal
---@param sector_key string Current sector key
---@param goal_key string Goal sector key
---@return number Estimated cost (weighted Euclidean distance)
function AV:CalculateHeuristic(sector_key, goal_key)
	if not sector_key or not goal_key then return 9999 end
	
	local sx, sy, sz = sector_key:match("([^_]+)_([^_]+)_([^_]+)")
	local gx, gy, gz = goal_key:match("([^_]+)_([^_]+)_([^_]+)")
	
	if not sx or not gx then return 9999 end
	
	sx, sy, sz = tonumber(sx), tonumber(sy), tonumber(sz)
	gx, gy, gz = tonumber(gx), tonumber(gy), tonumber(gz)
	
	local dx = gx - sx
	local dy = gy - sy
	local dz = gz - sz
	
	-- Manhattan distance: admissible heuristic for 6-direction grid
	-- Each step costs exactly 1.0, so Manhattan = minimum possible moves → finds optimal path
	return math.abs(dx) + math.abs(dy) + math.abs(dz)
end

--- Get movement cost between two adjacent sectors
---@param from_key string Source sector key
---@param to_key string Destination sector key
---@return number Movement cost (distance + accessibility penalty + connectivity check)
function AV:GetSectorMovementCost(from_key, to_key)
	-- Base cost is the distance between sectors
	local fx, fy, fz = from_key:match("([^_]+)_([^_]+)_([^_]+)")
	local tx, ty, tz = to_key:match("([^_]+)_([^_]+)_([^_]+)")
	
	if not fx or not tx then return 1.0 end
	
	fx, fy, fz = tonumber(fx), tonumber(fy), tonumber(fz)
	tx, ty, tz = tonumber(tx), tonumber(ty), tonumber(tz)
	
	local dx = tx - fx
	local dy = ty - fy
	local dz = tz - fz
	
	local base_cost = math.sqrt(dx*dx + dy*dy + dz*dz)
	
	-- CRITICAL: Block underground sectors (Z <= 0)
	if tz <= 0 then
		return base_cost * 10000000.0
	end

	-- Obstacle map penalty: check all obstacle cells that overlap this sector
	-- sector_size=20m, cell_size=10m → ~2×2×2 cells per sector; sample 8 quadrant points
	local obstacle_penalty = 1.0
	if next(self.obstacle_map) then
		local cs  = self.obstacle_cell_size
		local ss  = self.sector_size
		local max_hits = 0
		local clear_count   = 0   -- confirmed clear (count == 0)
		local unknown_count = 0   -- never scanned (nil)
		local total_sampled = 0
		for _, fx in ipairs({0.2, 0.5, 0.8}) do
			for _, fy in ipairs({0.2, 0.5, 0.8}) do
				for _, fz in ipairs({0.25, 0.75}) do
					local wx = (tx + fx) * ss
					local wy = (ty + fy) * ss
					local wz = (tz + fz) * ss
					local ckey = math.floor(wx/cs) .. "_" .. math.floor(wy/cs) .. "_" .. math.floor(wz/cs)
					local cell = self.obstacle_map[ckey]
					total_sampled = total_sampled + 1
					if cell then
						if cell.count > max_hits then max_hits = cell.count end
						if cell.count == 0 then clear_count = clear_count + 1 end
					else
						unknown_count = unknown_count + 1
					end
				end
			end
		end
		if max_hits >= self.obstacle_min_hits then
			-- Confirmed obstacle cells: increase cost
			obstacle_penalty = 1.0 + math.min(max_hits / 2.0, 5.0)  -- 1 hit → 1.5×, 12+ hits → 6×
		elseif clear_count > 0 then
			-- At least one confirmed-clear cell: cost reduction proportional to clear ratio.
			-- Mixed (some clear + some unknown) gets a partial discount only.
			local clear_ratio = clear_count / total_sampled
			obstacle_penalty = 1.0 - 0.2 * clear_ratio  -- 0.80 – 1.00 range
		elseif unknown_count > 0 then
			-- Fully unknown sector: penalize to prefer known-safe corridors.
			-- unknown_ratio=1.0 → 1.5×, partial unknown → 1.0–1.5×
			local unknown_ratio = unknown_count / total_sampled
			obstacle_penalty = 1.0 + 0.5 * unknown_ratio
		end
	end

	return base_cost * obstacle_penalty
end

--- Plan global route using A* algorithm
---@param start_pos Vector4 Start position
---@param end_pos Vector4 End position
---@return table Route as list of sector keys
function AV:PlanGlobalRoute(start_pos, end_pos)
	if not start_pos or not end_pos then
		return {}
	end
	
	local start_key = self:PositionToSectorKey(start_pos)
	local end_key = self:PositionToSectorKey(end_pos)
	
	if not start_key or not end_key then
		return {}
	end
	
	-- Same sector, no need for pathfinding
	if start_key == end_key then
		return {start_key}
	end
	
	-- A* Algorithm with optimized settings
	local open_set = {}  -- Nodes to be evaluated
	local closed_set = {}  -- Nodes already evaluated
	local came_from = {}  -- For path reconstruction
	local g_score = {}  -- Cost from start to node
	local f_score = {}  -- Estimated total cost (g + h)
	
	-- Initialize start node
	open_set[start_key] = true
	g_score[start_key] = 0
	f_score[start_key] = self:CalculateHeuristic(start_key, end_key)
	
	local max_iterations = 5000  -- Increased limit for larger maps
	local iterations = 0
	
	while next(open_set) ~= nil and iterations < max_iterations do
		iterations = iterations + 1
		
		-- Find node in open_set with lowest f_score
		local current = nil
		local lowest_f = math.huge
		for key, _ in pairs(open_set) do
			local f = f_score[key] or math.huge
			if f < lowest_f then
				lowest_f = f
				current = key
			end
		end
		
		if not current then
			break
		end
		
		-- Goal reached
		if current == end_key then
			-- Reconstruct path
			local route = {}
			local path_node = current
			while path_node do
				table.insert(route, 1, path_node)  -- Insert at beginning
				path_node = came_from[path_node]
			end
			
			self.log_obj:Record(LogLevel.Info, string.format(
				"A* route planned: %d sectors, %d iterations from %s to %s",
				#route, iterations, start_key, end_key))
			
			return route
		end
		
		-- Move current from open to closed
		open_set[current] = nil
		closed_set[current] = true
		
		-- Evaluate neighbors (6 cardinal directions: ±X, ±Y, ±Z)
		local neighbors = self:GetNeighborSectors(current)
		for _, neighbor in ipairs(neighbors) do
			if not closed_set[neighbor] then
				local tentative_g = (g_score[current] or math.huge) + 
					self:GetSectorMovementCost(current, neighbor)
				
				local existing_g = g_score[neighbor] or math.huge
				
				if tentative_g < existing_g then
					-- Found a better path to this neighbor
					came_from[neighbor] = current
					g_score[neighbor] = tentative_g
					f_score[neighbor] = tentative_g + self:CalculateHeuristic(neighbor, end_key)
					open_set[neighbor] = true
				end
			end
		end
	end
	
	-- No path found within iteration limit - return best partial path (local optimum)
	local open_count = 0
	local closed_count = 0
	for _ in pairs(open_set) do open_count = open_count + 1 end
	for _ in pairs(closed_set) do closed_count = closed_count + 1 end
	
	-- Find closest node to goal from explored nodes
	local best_node = nil
	local best_distance = math.huge
	for node_key, _ in pairs(closed_set) do
		local heuristic_distance = self:CalculateHeuristic(node_key, end_key)
		if heuristic_distance < best_distance then
			best_distance = heuristic_distance
			best_node = node_key
		end
	end
	
	-- If found a better node than start, reconstruct path to it (local optimum)
	if best_node and best_node ~= start_key then
		local partial_route = {}
		local path_node = best_node
		while path_node do
			table.insert(partial_route, 1, path_node)
			path_node = came_from[path_node]
		end
		
		self.log_obj:Record(LogLevel.Warning, string.format(
			"A* incomplete after %d iterations, using partial route to closest explored node: %d sectors (distance to goal: %.1f)",
			iterations, #partial_route, best_distance * self.sector_size))
		
		return partial_route
	end
	
	-- If no better path found, use straight line fallback
	self.log_obj:Record(LogLevel.Warning, string.format(
		"A* pathfinding failed after %d iterations, using straight line fallback (start=%s, end=%s, open=%d, closed=%d)",
		iterations, start_key, end_key, open_count, closed_count))
	
	return self:PlanStraightLineRoute(start_pos, end_pos)
end

--- Save the last planned A* route to JSON for external visualization.
---@param route table List of sector keys ("sx_sy_sz")
---@param start_pos Vector4 Actual start world position
---@param end_pos Vector4 Actual end world position
function AV:SaveLastRoute(route, start_pos, end_pos)
	if not route or #route == 0 then return end
	local ok, err = pcall(function()
		-- Build waypoint list: store both the key and the world-space centre
		local waypoints = {}
		for i, key in ipairs(route) do
			local wpos = self:SectorKeyToPosition(key)
			waypoints[i] = {
				key = key,
				wx  = wpos and wpos.x or 0,
				wy  = wpos and wpos.y or 0,
				wz  = wpos and wpos.z or 0,
			}
		end
		local data = {
			version     = 1,
			sector_size = self.sector_size,
			timestamp   = os.time(),
			start_pos   = {x = start_pos.x, y = start_pos.y, z = start_pos.z},
			end_pos     = {x = end_pos.x,   y = end_pos.y,   z = end_pos.z},
			waypoints   = waypoints,
		}
		local file = io.open(self.route_save_path, "w")
		if file then
			file:write(json.encode(data))
			file:close()
			self.log_obj:Record(LogLevel.Info, string.format(
				"Route saved: %d waypoints -> %s", #route, self.route_save_path))
		end
	end)
	if not ok then
		self.log_obj:Record(LogLevel.Warning, "SaveLastRoute failed: " .. tostring(err))
	end
end

--- Plan straight-line route as fallback
---@param start_pos Vector4 Start position
---@param end_pos Vector4 End position
---@return table Route as list of sector keys
function AV:PlanStraightLineRoute(start_pos, end_pos)
	local start_key = self:PositionToSectorKey(start_pos)
	local end_key = self:PositionToSectorKey(end_pos)
	
	local start_sector_pos = self:SectorKeyToPosition(start_key)
	local end_sector_pos = self:SectorKeyToPosition(end_key)
	
	if not start_sector_pos or not end_sector_pos then
		return {start_key or end_key}
	end
	
	local route = {}
	local direction = Vector4.new(
		end_sector_pos.x - start_sector_pos.x,
		end_sector_pos.y - start_sector_pos.y,
		end_sector_pos.z - start_sector_pos.z,
		1
	)
	local distance = Vector4.Length(direction)
	local step_count = math.ceil(distance / self.sector_size)
	
	if step_count > 0 then
		direction = Vector4.Normalize(direction)
		
		for i = 0, step_count do
			local t = i / step_count
			local intermediate_pos = Vector4.new(
				start_sector_pos.x + direction.x * distance * t,
				start_sector_pos.y + direction.y * distance * t,
				start_sector_pos.z + direction.z * distance * t,
				1
			)
			local sector_key = self:PositionToSectorKey(intermediate_pos)
			if sector_key then
				-- Avoid duplicate consecutive keys
				if #route == 0 or route[#route] ~= sector_key then
					table.insert(route, sector_key)
				end
			end
		end
	end
	
	if #route == 0 then
		table.insert(route, start_key)
		table.insert(route, end_key)
	end
	
	self.log_obj:Record(LogLevel.Info, string.format(
		"Fallback route generated: %d sectors", #route))
	
	return route
end

--- Calculate local repulsion vector using spherical raycast
---@param current_pos Vector4 Current position
---@param dest_dir Vector4 Normalized direction to destination
---@return Vector4 Combined navigation vector (repulsion + attraction)
---@return number Repulsion magnitude for speed control
---@return integer Number of rays that hit obstacles
---@return Vector4 Raw repulsion vector (unnormalized, for direction calculation)
function AV:CalculateLocalRepulsion(current_pos, dest_dir)
	if not current_pos or not dest_dir then
		self.log_obj:Record(LogLevel.Warning, "CalculateLocalRepulsion: Invalid input parameters")
		return Vector4.Zero(), 0, 0, Vector4.Zero(), math.huge
	end
	
	-- Ensure collision filters are initialized
	if not self.weak_collision_filters or #self.weak_collision_filters == 0 then
		self.weak_collision_filters = {"Static", "Terrain"}
		self.log_obj:Record(LogLevel.Warning, "Collision filters not initialized, using defaults")
	end
	
	local repulsion_vector = Vector4.Zero()
	local ray_hit_count = 0
	local min_obstacle_distance = math.huge
	
	-- Cast rays: forward hemisphere only
	-- Skip rays pointing more than 120 degrees backward (dot < -0.5)
	for _, ray_dir in ipairs(self.local_ray_angles) do
		-- Forward hemisphere filter: exclude rays pointing strongly backward
		local dot_fwd = ray_dir.x * dest_dir.x + ray_dir.y * dest_dir.y + ray_dir.z * dest_dir.z
		if dot_fwd < -0.5 then goto continue_ray end
		
		local target_pos = Vector4.new(
			current_pos.x + ray_dir.x * self.local_ray_distance,
			current_pos.y + ray_dir.y * self.local_ray_distance,
			current_pos.z + ray_dir.z * self.local_ray_distance,
			1
		)
		
		local is_collision = false
		local collision_distance = nil
		
		for _, filter in ipairs(self.weak_collision_filters) do
			local hit_success, hit_result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(
				current_pos, target_pos, filter, false, false)
			
			if hit_success then
				is_collision = true
				if hit_result and hit_result.position then
					local dx = hit_result.position.x - current_pos.x
					local dy = hit_result.position.y - current_pos.y
					local dz = hit_result.position.z - current_pos.z
					collision_distance = math.sqrt(dx*dx + dy*dy + dz*dz)
				else
					collision_distance = self.local_ray_distance * 0.9
				end
				break
			end
		end
		
		if is_collision and collision_distance then
			local distance = tonumber(collision_distance)
			if type(distance) ~= "number" then goto continue_ray end
			
			ray_hit_count = ray_hit_count + 1
			if distance < min_obstacle_distance then
				min_obstacle_distance = distance
			end
			
			-- Distance-based repulsion strength
			-- Calibrated so 12m zone is clearly maintained and 8m triggers retreat
			if distance < self.local_ray_distance then
				local strength = 0
				
				if distance < 3.0 then
					-- CRITICAL (<3m): extreme repulsion
					strength = self.local_repulsion_strength * 50.0 * math.pow(1.0 - distance / 3.0, 4.0)
				elseif distance < 8.0 then
					-- DANGER (3-8m): strong repulsion, steer away hard
					strength = self.local_repulsion_strength * 8.0 * math.pow(1.0 - distance / 8.0, 3.0)
				elseif distance < 12.0 then
					-- WARNING (8-12m): maintain safety zone, moderate push
					strength = self.local_repulsion_strength * 2.0 * math.pow(1.0 - distance / 12.0, 2.0)
				elseif distance < 20.0 then
					-- CAUTION (12-20m): gentle awareness
					strength = self.local_repulsion_strength * 0.4 * math.pow(1.0 - distance / 20.0, 2.0)
				else
					-- FAR (20-25m): very light early warning
					strength = self.local_repulsion_strength * 0.05 * (1.0 - distance / self.local_ray_distance)
				end
				
				repulsion_vector.x = repulsion_vector.x - ray_dir.x * strength
				repulsion_vector.y = repulsion_vector.y - ray_dir.y * strength
				repulsion_vector.z = repulsion_vector.z - ray_dir.z * strength
			end
		end
		
		::continue_ray::
	end
	
	local repulsion_magnitude = math.sqrt(
		repulsion_vector.x * repulsion_vector.x +
		repulsion_vector.y * repulsion_vector.y +
		repulsion_vector.z * repulsion_vector.z
	)
	
	-- Combine repulsion with attraction toward destination
	-- Reduce attraction as obstacles get closer
	local attraction_weight = self.local_attraction_strength
	if min_obstacle_distance < 8.0 then
		attraction_weight = 0.0  -- Near collision: pure repulsion
	elseif min_obstacle_distance < 12.0 then
		-- Scale down attraction in safety zone
		attraction_weight = attraction_weight * ((min_obstacle_distance - 8.0) / 4.0)
	end
	
	local attraction_vector = Vector4.new(
		dest_dir.x * attraction_weight,
		dest_dir.y * attraction_weight,
		dest_dir.z * attraction_weight,
		0
	)
	
	local combined_vector = Vector4.new(
		repulsion_vector.x + attraction_vector.x,
		repulsion_vector.y + attraction_vector.y,
		repulsion_vector.z + attraction_vector.z,
		1
	)
	
	if combined_vector:IsZero() then
		combined_vector = dest_dir
	else
		combined_vector = Vector4.Normalize(combined_vector)
	end
	
	return combined_vector, repulsion_magnitude, ray_hit_count, repulsion_vector, min_obstacle_distance
end

--- ============================================================================
--- Learning System Functions (DEPRECATED - Kept for compatibility)
--- ============================================================================

--- Initialize Learning System
--- Initialize Learning System
--- NOTE: This function is deprecated. Sector navigation system is initialized in InitializeSectorSystem().
function AV:InitializeLearningSystem()
	-- Old learning system no longer used
	-- Sector navigation system handles all learning data
	if self.log_obj then
		self.log_obj:Record(LogLevel.Debug, "Legacy learning system skipped (using sector navigation)")
	end
end

--- Convert position to grid key
---@param position Vector4
---@return string
function AV:PositionToGridKey(position)
	local grid_size = self.long_term_memory.grid_size
	local x = math.floor(position.x / grid_size)
	local y = math.floor(position.y / grid_size)
	local z = math.floor(position.z / grid_size)
	return string.format("%d_%d_%d", x, y, z)
end

--- Get or create cell data for a position
---@param position Vector4
---@return table cell_data
function AV:GetOrCreateCell(position)
	local key = self:PositionToGridKey(position)
	
	if not self.long_term_memory.cells[key] then
		self.long_term_memory.cells[key] = {
			visits = 0,
			success_pass = 0,
			collision = 0,
			deadend = 0,
			stuck = 0,
			avg_score = 0,
			min_score = 999,
			max_score = 0,
			total_score = 0,
			direction_stats = {
				forward = {success = 0, total = 0},
				left = {success = 0, total = 0},
				right = {success = 0, total = 0},
				up = {success = 0, total = 0},
				down = {success = 0, total = 0},
			},
			best_direction = nil,
			last_visit = 0,
			confidence = 0,
			danger_level = 0,
		}
	end
	
	return self.long_term_memory.cells[key]
end

--- Get number of cells in long-term memory
---@return number
function AV:GetCellCount()
	local count = 0
	for _ in pairs(self.long_term_memory.cells) do
		count = count + 1
	end
	return count
end

--- Calculate danger level for a cell
---@param position Vector4
---@return number danger_level (0-1)
function AV:GetCellDangerLevel(position)
	local cell = self:GetOrCreateCell(position)
	
	-- Unknown areas get medium danger level
	if cell.visits < self.learning_confidence_threshold then
		return 0.5
	end
	
	-- Calculate failure rate
	local failure_count = cell.collision + cell.deadend + cell.stuck
	local failure_rate = failure_count / cell.visits
	
	-- Consider average score
	local score_factor = 1.0
	if cell.avg_score < 50 then
		score_factor = 1.5
	elseif cell.avg_score < 100 then
		score_factor = 1.2
	end
	
	return math.min(failure_rate * score_factor, 1.0)
end

--- Update cell statistics
---@param position Vector4
---@param score number
---@param direction_name string|nil
---@param result string "success", "collision", "deadend", "stuck"
function AV:UpdateCellStatistics(position, score, direction_name, result)
	local cell = self:GetOrCreateCell(position)
	local current_time = os.clock()
	
	-- Update basic statistics
	cell.visits = cell.visits + 1
	cell.last_visit = current_time
	cell.total_score = cell.total_score + score
	cell.avg_score = cell.total_score / cell.visits
	cell.min_score = math.min(cell.min_score, score)
	cell.max_score = math.max(cell.max_score, score)
	
	-- Update result statistics
	if result == "success" then
		cell.success_pass = cell.success_pass + 1
	elseif result == "collision" then
		cell.collision = cell.collision + 1
	elseif result == "deadend" then
		cell.deadend = cell.deadend + 1
	elseif result == "stuck" then
		cell.stuck = cell.stuck + 1
	end
	
	-- Update direction statistics
	if direction_name then
		local dir_lower = direction_name:lower()
		if cell.direction_stats[dir_lower] then
			cell.direction_stats[dir_lower].total = cell.direction_stats[dir_lower].total + 1
			if result == "success" then
				cell.direction_stats[dir_lower].success = cell.direction_stats[dir_lower].success + 1
			end
		end
	end
	
	-- Update confidence (0-1 scale, based on visit count)
	cell.confidence = math.min(cell.visits / 10, 1.0)
	
	-- Recalculate danger level
	cell.danger_level = self:GetCellDangerLevel(position)
end

--- Record path history (short-term memory)
---@param position Vector4
---@param score number
---@param direction Vector4
function AV:RecordPathHistory(position, score, direction)
	if not self.learning_enabled or not self.short_term_memory then return end
	
	local success, error_msg = pcall(function()
		local current_time = os.clock()
		
		table.insert(self.short_term_memory.path_history, {
			position = {x = position.x, y = position.y, z = position.z},
			score = score,
			direction = direction,
			time = current_time,
		})
		
		-- Remove entries older than duration
		local duration = self.learning_path_history_duration or 30
		while #self.short_term_memory.path_history > 0 do
			local oldest = self.short_term_memory.path_history[1]
			if current_time - oldest.time > duration then
				table.remove(self.short_term_memory.path_history, 1)
			else
				break
			end
		end
		
		-- Also update long-term memory
		self:UpdateCellStatistics(position, score, nil, "success")
	end)
	
	if not success and self.log_obj then
		self.log_obj:Record(LogLevel.Debug, "Error recording path history: " .. tostring(error_msg))
	end
end

--- Record danger spot (short-term memory)
---@param position Vector4
---@param score number
---@param reason string
function AV:RecordDangerSpot(position, score, reason)
	if not self.learning_enabled or not self.short_term_memory or not self.short_term_memory.danger_spots then
		return
	end
	
	local success, error_msg = pcall(function()
		table.insert(self.short_term_memory.danger_spots, {
			pos = {x = position.x, y = position.y, z = position.z},
			score = score,
			reason = reason,
			time = os.clock(),
			radius = self.learning_danger_spot_radius or 20,
		})
		
		-- Update long-term memory
		local result = "collision"
		if reason == "deadend" then
			result = "deadend"
		elseif reason == "stuck" then
			result = "stuck"
		end
		self:UpdateCellStatistics(position, score, nil, result)
		
		if self.log_obj then
			self.log_obj:Record(LogLevel.Debug, string.format(
				"Danger spot recorded: reason=%s, score=%.1f at (%.1f, %.1f, %.1f)",
				reason, score, position.x, position.y, position.z))
		end
	end)
	
	if not success and self.log_obj then
		self.log_obj:Record(LogLevel.Debug, "Error recording danger spot: " .. tostring(error_msg))
	end
end

--- Check if near a danger spot (short-term memory)
---@param position Vector4
---@return boolean is_near
---@return number score
---@return string reason
function AV:IsNearDangerSpot(position)
	if not self.short_term_memory or not self.short_term_memory.danger_spots then
		return false, 0, ""
	end
	
	for _, spot in ipairs(self.short_term_memory.danger_spots) do
		local dist = math.sqrt(
			(position.x - spot.pos.x)^2 +
			(position.y - spot.pos.y)^2 +
			(position.z - spot.pos.z)^2)
		
		if dist < (spot.radius or 20) then
			return true, spot.score or 0, spot.reason or ""
		end
	end
	return false, 0, ""
end

--- Detect loop in path history
---@param current_position Vector4
---@return boolean is_loop
function AV:DetectLoop(current_position)
	if not self.short_term_memory or not self.short_term_memory.path_history then
		return false
	end
	
	local success, result = pcall(function()
		local history = self.short_term_memory.path_history
		local radius = self.short_term_memory.loop_check_radius or 20
		local window = self.short_term_memory.loop_check_window or 20
		local current_time = os.clock()
		local visit_count = 0
		
		-- Check how many times we've visited this area recently
		for i = #history, math.max(1, #history - 40), -1 do
			local hist = history[i]
			if current_time - hist.time <= window then
				local dist = math.sqrt(
					(current_position.x - hist.position.x)^2 +
					(current_position.y - hist.position.y)^2 +
					(current_position.z - hist.position.z)^2)
				
				if dist < radius then
					visit_count = visit_count + 1
				end
			end
		end
		
		-- Loop detected if visited same area 2+ times
		if visit_count >= 2 then
			if self.log_obj then
				self.log_obj:Record(LogLevel.Warning, 
					string.format("Loop detected! Visited same area %d times", visit_count))
			end
			
			-- Record as deadend in long-term memory
			self:UpdateCellStatistics(current_position, 0, nil, "deadend")
			
			return true
		end
		
		return false
	end)
	
	if not success then
		return false
	end
	
	return result
end

--- Detect if stuck
---@return boolean is_stuck
function AV:DetectStuck()
	if not self.short_term_memory then
		return false
	end
	
	local success, result = pcall(function()
		local current_pos = self:GetPosition()
		local current_time = os.clock()
		local speed = self:GetCurrentSpeed()
		
		-- Check if speed is below threshold
		if speed < (self.stuck_speed_threshold or 1.0) then
			if not self.stuck_start_time then
				self.stuck_start_time = current_time
				self.stuck_position = current_pos
			elseif current_time - self.stuck_start_time > (self.stuck_detection_time or 3) then
				-- Stuck for too long
				if self.short_term_memory.stuck_positions then
					table.insert(self.short_term_memory.stuck_positions, {
						pos = {x = current_pos.x, y = current_pos.y, z = current_pos.z},
						time = current_time,
					})
				end
				
				-- Record in long-term memory
				self:UpdateCellStatistics(current_pos, 0, nil, "stuck")
				
				if self.log_obj then
					self.log_obj:Record(LogLevel.Warning, "Stuck detected!")
				end
				return true
			end
		else
			self.stuck_start_time = nil
			self.stuck_position = nil
		end
		
		return false
	end)
	
	if not success then
		return false
	end
	
	return result
end

--- Find safe backtrack position from path history
---@param distance number
---@return Vector4|nil safe_position
function AV:FindSafeBacktrackPosition(distance)
	local history = self.short_term_memory.path_history
	local current_pos = self:GetPosition()
	
	-- Search from recent to old
	for i = #history, 1, -1 do
		local hist = history[i]
		local hist_pos = Vector4.new(hist.position.x, hist.position.y, hist.position.z, 1)
		
		local dist = Vector4.Length(Vector4.new(
			current_pos.x - hist_pos.x,
			current_pos.y - hist_pos.y,
			current_pos.z - hist_pos.z, 1))
		
		if dist >= distance then
			-- Check safety in long-term memory
			local danger = self:GetCellDangerLevel(hist_pos)
			
			if danger < 0.3 then  -- Low danger
				self.log_obj:Record(LogLevel.Info, string.format(
					"Safe backtrack position found: %.1fm away, danger=%.2f",
					dist, danger))
				return hist_pos
			end
		end
	end
	
	return nil
end

--- Execute backtrack maneuver
---@return Vector4|nil backtrack_position
function AV:ExecuteBacktrack()
	self.log_obj:Record(LogLevel.Info, "Executing backtrack maneuver")
	
	-- Try to find safe position in history
	local safe_position = self:FindSafeBacktrackPosition(self.backtrack_distance)
	
	if safe_position then
		self.short_term_memory.backtrack_count = 
			self.short_term_memory.backtrack_count + 1
		return safe_position
	end
	
	-- If no safe position found, go up
	local current_pos = self:GetPosition()
	self.log_obj:Record(LogLevel.Info, "No safe backtrack position, ascending instead")
	return Vector4.new(current_pos.x, current_pos.y, current_pos.z + 20, 1)
end

--- Predict path danger using learning data
---@param current_pos Vector4
---@param direction Vector4
---@param distance number
---@return number max_danger
---@return number avg_danger
function AV:PredictPathDanger(current_pos, direction, distance)
	local danger_levels = {}
	local steps = 3  -- Check 3 steps ahead
	
	for i = 1, steps do
		local check_pos = Vector4.new(
			current_pos.x + direction.x * (distance * i / steps),
			current_pos.y + direction.y * (distance * i / steps),
			current_pos.z + direction.z * (distance * i / steps), 1)
		
		local danger = self:GetCellDangerLevel(check_pos)
		table.insert(danger_levels, danger)
	end
	
	-- Calculate max and average danger
	local max_danger = 0
	local sum_danger = 0
	for _, d in ipairs(danger_levels) do
		max_danger = math.max(max_danger, d)
		sum_danger = sum_danger + d
	end
	local avg_danger = sum_danger / #danger_levels
	
	return max_danger, avg_danger
end

--- Get warning level based on score and predicted danger
---@param score number
---@param predicted_danger number
---@return number level (0-3)
---@return string description
function AV:GetWarningLevel(score, predicted_danger)
	-- Adjust score based on predicted danger
	local adjusted_score = score * (1 - predicted_danger * 0.5)
	
	if adjusted_score < self.warning_threshold_critical then
		return 3, "CRITICAL"  -- Force ascent
	elseif adjusted_score < self.warning_threshold_high then
		return 2, "HIGH"      -- Consider ascending
	elseif adjusted_score < self.warning_threshold_medium then
		return 1, "MEDIUM"    -- Prefer horizontal avoidance
	else
		return 0, "SAFE"
	end
end

--- Apply learning to direction score
---@param direction_name string
---@param position Vector4
---@param base_score number
---@return number adjusted_score
function AV:ApplyLearningToDirectionScore(direction_name, position, base_score)
	if not self.learning_enabled or not self.long_term_memory or not self.long_term_memory.cells then
		return base_score
	end
	
	local success, result = pcall(function()
		local cell = self:GetOrCreateCell(position)
		
		-- Don't apply learning if not enough data
		if cell.visits < (self.learning_confidence_threshold or 3) then
			return base_score
		end
		
		-- Get direction success rate
		local dir_lower = direction_name:lower()
		local dir_stat = cell.direction_stats and cell.direction_stats[dir_lower]
		
		if dir_stat and dir_stat.total > 0 then
			local success_rate = dir_stat.success / dir_stat.total
			
			-- Adjust score based on success rate
			if success_rate > 0.7 then
				base_score = base_score * (self.learning_score_bonus_multiplier or 1.3)
				if self.log_obj then
					self.log_obj:Record(LogLevel.Debug, string.format(
						"Learning bonus for %s: success_rate=%.2f, multiplier=%.2f",
						direction_name, success_rate, self.learning_score_bonus_multiplier or 1.3))
				end
			elseif success_rate < 0.3 then
				base_score = base_score * (self.learning_score_penalty_multiplier or 0.6)
				if self.log_obj then
					self.log_obj:Record(LogLevel.Debug, string.format(
						"Learning penalty for %s: success_rate=%.2f, multiplier=%.2f",
						direction_name, success_rate, self.learning_score_penalty_multiplier or 0.6))
				end
			end
		end
		
		return base_score
	end)
	
	if not success then
		return base_score
	end
	
	return result
end

--- Evaluate direction with lookahead (2-step prediction)
---@param direction table Direction data with score, vector, name
---@param current_pos Vector4
---@return number adjusted_score
function AV:EvaluateDirectionWithLookahead(direction, current_pos)
	local base_score = direction.score
	
	if not self.learning_enabled or not self.learning_lookahead_enabled or not self.long_term_memory or not self.long_term_memory.cells then
		return base_score
	end
	
	local success, result = pcall(function()
		-- Step 1 position
		local step1_pos = Vector4.new(
			current_pos.x + direction.vector.x * (self.search_range or 50),
			current_pos.y + direction.vector.y * (self.search_range or 50),
			current_pos.z + direction.vector.z * (self.search_range or 50), 1)
		
		-- Check step 1 danger
		local step1_cell = self:GetOrCreateCell(step1_pos)
		local step1_danger = self:GetCellDangerLevel(step1_pos)
		
		-- If step 1 has best_direction and enough data, check step 2
		local bonus = 0
		local penalty = 0
		
		if step1_cell.best_direction and step1_cell.visits >= 5 then
			local step2_pos = Vector4.new(
				step1_pos.x + step1_cell.best_direction.x * (self.search_range or 50),
				step1_pos.y + step1_cell.best_direction.y * (self.search_range or 50),
				step1_pos.z + step1_cell.best_direction.z * (self.search_range or 50), 1)
			
			local step2_danger = self:GetCellDangerLevel(step2_pos)
			
			-- Both steps safe = big bonus
			if step1_danger < 0.3 and step2_danger < 0.3 then
				bonus = base_score * (self.learning_lookahead_bonus or 0.5)
				if self.log_obj then
					self.log_obj:Record(LogLevel.Debug, string.format(
						"Lookahead bonus for %s: 2 steps clear, bonus=%.1f",
						direction.name or "unknown", bonus))
				end
			end
		end
		
		-- Step 1 dangerous = penalty
		if step1_danger > 0.6 then
			penalty = base_score * 0.3
			if self.log_obj then
				self.log_obj:Record(LogLevel.Debug, string.format(
					"Lookahead penalty for %s: danger ahead=%.2f, penalty=%.1f",
					direction.name or "unknown", step1_danger, penalty))
			end
		end
		
		return base_score + bonus - penalty
	end)
	
	if not success then
		return base_score
	end
	
	return result
end

--- Consolidate short-term memory into long-term memory (call on flight end)
--- NOTE: This function is deprecated. Sector navigation system handles persistence automatically.
function AV:ConsolidateMemory()
	-- Save obstacle map when flight ends
	self:SaveObstacleMap()
	
	if self.log_obj then
		self.log_obj:Record(LogLevel.Info, "Flight completed, obstacle map saved")
	end
end

--- 3D Tangent Bug: cast a fan of rays in a cone around center_dir
--- Returns min distance hit among all rays, and the averaged normal of blocked rays
--- half_angle_deg: cone half-angle in degrees, n_rings: 1=center only, 2=center+ring
function AV:RaycastFanMin(from_pos, center_dir, max_dist, half_angle_deg, n_extra)
	if not from_pos or not center_dir then return max_dist, nil end
	-- Build a small orthonormal basis around center_dir
	local ref
	if math.abs(center_dir.z) < 0.9 then
		ref = Vector4.new(0, 0, 1, 0)
	else
		ref = Vector4.new(1, 0, 0, 0)
	end
	local b1x = ref.y*center_dir.z - ref.z*center_dir.y
	local b1y = ref.z*center_dir.x - ref.x*center_dir.z
	local b1z = ref.x*center_dir.y - ref.y*center_dir.x
	local b1l = math.sqrt(b1x*b1x + b1y*b1y + b1z*b1z)
	if b1l < 0.001 then return self:RaycastDist(from_pos, center_dir, max_dist), nil end
	b1x, b1y, b1z = b1x/b1l, b1y/b1l, b1z/b1l
	local b2x = center_dir.y*b1z - center_dir.z*b1y
	local b2y = center_dir.z*b1x - center_dir.x*b1z
	local b2z = center_dir.x*b1y - center_dir.y*b1x
	-- Rays: center + n_extra evenly around the cone rim
	local angle_rad = math.rad(half_angle_deg)
	local sin_a, cos_a = math.sin(angle_rad), math.cos(angle_rad)
	local dirs = {center_dir}
	for i = 0, (n_extra or 4) - 1 do
		local phi = (2 * math.pi * i) / (n_extra or 4)
		local cp, sp = math.cos(phi), math.sin(phi)
		dirs[#dirs+1] = Vector4.new(
			cos_a*center_dir.x + sin_a*(cp*b1x + sp*b2x),
			cos_a*center_dir.y + sin_a*(cp*b1y + sp*b2y),
			cos_a*center_dir.z + sin_a*(cp*b1z + sp*b2z), 0)
	end
	local all_dists = {}
	local blocked_nx, blocked_ny, blocked_nz, blocked_count = 0, 0, 0, 0
	for _, d in ipairs(dirs) do
		local dist = self:RaycastDist(from_pos, d, max_dist)
		all_dists[#all_dists+1] = dist
		if dist < max_dist * 0.98 then
			-- Accumulate inward normals of hit rays
			blocked_nx = blocked_nx - d.x
			blocked_ny = blocked_ny - d.y
			blocked_nz = blocked_nz - d.z
			blocked_count = blocked_count + 1
		end
	end
	-- Use the 2nd-minimum distance: at least 2 rays must be blocked before
	-- reporting a short distance back to the caller.  A single ray clipping a
	-- thin pillar or building edge won't falsely shrink the returned distance.
	table.sort(all_dists)
	local effective_dist = all_dists[2] or all_dists[1] or max_dist
	local avg_normal = nil
	if blocked_count > 0 then
		local nl = math.sqrt(blocked_nx*blocked_nx + blocked_ny*blocked_ny + blocked_nz*blocked_nz)
		if nl > 0.001 then
			avg_normal = Vector4.new(blocked_nx/nl, blocked_ny/nl, blocked_nz/nl, 0)
		end
	end
	return effective_dist, avg_normal
end

--- 3D Tangent Bug: single directional raycast
--- Returns distance to first obstacle hit, or max_dist if clear
function AV:RaycastDist(from_pos, dir_normalized, max_dist)
	if not from_pos or not dir_normalized then return max_dist end
	local target = Vector4.new(
		from_pos.x + dir_normalized.x * max_dist,
		from_pos.y + dir_normalized.y * max_dist,
		from_pos.z + dir_normalized.z * max_dist, 1)
	for _, filter in ipairs(self.weak_collision_filters) do
		local hit, result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(
			from_pos, target, filter, false, false)
		if hit then
			if result and result.position then
				local dx = result.position.x - from_pos.x
				local dy = result.position.y - from_pos.y
				local dz = result.position.z - from_pos.z
				return math.sqrt(dx*dx + dy*dy + dz*dz), result.position
			else
				return max_dist * 0.9, nil
			end
		end
	end
	return max_dist, nil
end

--- 3D Tangent Bug: generate N directions evenly spaced in plane perpendicular to obstacle_normal
--- Returns list of normalized Vector4 directions
function AV:GeneratePerpDirs(obstacle_normal, n)
	-- Build two orthogonal basis vectors in the perpendicular plane
	local ref
	if math.abs(obstacle_normal.z) < 0.9 then
		ref = Vector4.new(0, 0, 1, 0)
	else
		ref = Vector4.new(1, 0, 0, 0)
	end
	-- basis1 = ref x normal (cross product, normalized)
	local b1x = ref.y * obstacle_normal.z - ref.z * obstacle_normal.y
	local b1y = ref.z * obstacle_normal.x - ref.x * obstacle_normal.z
	local b1z = ref.x * obstacle_normal.y - ref.y * obstacle_normal.x
	local b1len = math.sqrt(b1x*b1x + b1y*b1y + b1z*b1z)
	if b1len < 0.001 then return {} end
	b1x, b1y, b1z = b1x/b1len, b1y/b1len, b1z/b1len
	-- basis2 = normal x basis1
	local b2x = obstacle_normal.y * b1z - obstacle_normal.z * b1y
	local b2y = obstacle_normal.z * b1x - obstacle_normal.x * b1z
	local b2z = obstacle_normal.x * b1y - obstacle_normal.y * b1x
	local b2len = math.sqrt(b2x*b2x + b2y*b2y + b2z*b2z)
	if b2len < 0.001 then return {} end
	b2x, b2y, b2z = b2x/b2len, b2y/b2len, b2z/b2len
	-- Sample n directions evenly around the circle in the perpendicular plane
	local dirs = {}
	for i = 0, n - 1 do
		local angle = (2 * math.pi * i) / n
		local c, s = math.cos(angle), math.sin(angle)
		dirs[i + 1] = Vector4.new(
			c * b1x + s * b2x,
			c * b1y + s * b2y,
			c * b1z + s * b2z, 0)
	end
	return dirs
end

--- 3D Tangent Bug: find best passable direction to follow obstacle boundary toward goal
--- Candidates are in the plane perpendicular to obstacle_normal
--- Returns best normalized Vector4, or nil if all blocked
function AV:FindBestBoundaryDir(current_pos, dest_dir, obstacle_normal)
	local n = 16             -- candidate directions
	local ray_range = 35.0   -- raycast range for candidates
	local candidates = self:GeneratePerpDirs(obstacle_normal, n)

	-- Pre-compute blended directions: push AWAY from obstacle (+normal, not -normal)
	-- obstacle_normal points from obstacle toward vehicle (outward), so adding it
	-- nudges each candidate away from the wall to avoid hugging.
	local blended_dirs = {}
	for _, dir in ipairs(candidates) do
		local bx = dir.x + obstacle_normal.x * 0.3
		local by = dir.y + obstacle_normal.y * 0.3
		local bz = dir.z + obstacle_normal.z * 0.3
		local blen = math.sqrt(bx*bx + by*by + bz*bz)
		if blen > 0.001 then
			blended_dirs[#blended_dirs+1] = Vector4.new(bx/blen, by/blen, bz/blen, 0)
		else
			blended_dirs[#blended_dirs+1] = dir
		end
	end

	-- Try progressively relaxed clearance thresholds to avoid returning nil
	-- in tight spaces (narrow passages, concave geometry).
	local thresholds = {12.0, 8.0, 4.0}
	for _, min_clear in ipairs(thresholds) do
		local best_dir = nil
		local best_score = -math.huge
		for _, blended in ipairs(blended_dirs) do
			local dist = self:RaycastDist(current_pos, blended, ray_range)
			if dist >= min_clear then
				local goal_dot = blended.x * dest_dir.x + blended.y * dest_dir.y + blended.z * dest_dir.z
				local clearance_bonus = math.min(dist / ray_range, 1.0) * 0.2
				local density_penalty = self:GetObstacleDensityAlongRay(current_pos, blended, ray_range) * 0.3
				local score = goal_dot + clearance_bonus - density_penalty
				if score > best_score then
					best_score = score
					best_dir = blended
				end
			end
		end
		if best_dir then
			return best_dir
		end
	end
	return nil
end

--- ============================================================================
--- Obstacle Map Functions
--- ============================================================================

--- Record a confirmed obstacle hit position into the obstacle map grid
function AV:RecordObstacleHit(hit_pos, ray_dir)
	if not hit_pos then return end
	local cs = self.obstacle_cell_size
	local cx = math.floor(hit_pos.x / cs)
	local cy = math.floor(hit_pos.y / cs)
	local cz = math.floor(hit_pos.z / cs)
	-- Center cell: increment count normally
	local key = cx .. "_" .. cy .. "_" .. cz
	if not self.obstacle_map[key] then
		self.obstacle_map[key] = {count = 0}
	end
	self.obstacle_map[key].count = self.obstacle_map[key].count + 1
	-- Propagate count=1 to neighboring cells ONLY in the ray direction.
	-- For each of the 26 neighbors, compute dot(offset, ray_dir).
	-- If dot > 0 (neighbor is in the forward half of the ray), it may be
	-- inside the obstacle that was just hit → record as count=1.
	-- Rule: only write if existing count < 1 (never overwrite stronger evidence).
	if ray_dir then
		local rx = ray_dir.x or 0
		local ry = ray_dir.y or 0
		local rz = ray_dir.z or 0
		local rlen = math.sqrt(rx*rx + ry*ry + rz*rz)
		if rlen > 0.001 then
			rx, ry, rz = rx/rlen, ry/rlen, rz/rlen
			for dx = -1, 1 do
				for dy = -1, 1 do
					for dz = -1, 1 do
						if not (dx == 0 and dy == 0 and dz == 0) then
							-- Positive dot = offset is in the ray's forward direction
							local dot = dx*rx + dy*ry + dz*rz
							if dot > 0 then
								local nkey = (cx+dx) .. "_" .. (cy+dy) .. "_" .. (cz+dz)
								local existing = self.obstacle_map[nkey]
								if not existing then
									self.obstacle_map[nkey] = {count = 1}
								elseif existing.count < 1 then
									existing.count = 1
								end
							end
						end
					end
				end
			end
		end
	end
end

--- Get maximum obstacle cell hit count along a ray (normalized 0-1, 5 hits = 1.0)
function AV:GetObstacleDensityAlongRay(from_pos, dir, max_dist)
	local cs = self.obstacle_cell_size
	local steps = math.max(1, math.floor(max_dist / cs))
	local max_count = 0
	for i = 1, steps do
		local d = i * cs
		local key = math.floor((from_pos.x + dir.x*d)/cs) .. "_"
				 .. math.floor((from_pos.y + dir.y*d)/cs) .. "_"
				 .. math.floor((from_pos.z + dir.z*d)/cs)
		local cell = self.obstacle_map[key]
		if cell then
			if cell.count > max_count then max_count = cell.count end
		else
			-- Unrecorded cell: treat as moderate risk (count=1.5 equivalent).
			-- This nudges boundary direction selection toward known-safe paths.
			if 1.5 > max_count then max_count = 1.5 end
		end
	end
	return math.min(max_count / 5.0, 1.0)
end

--- Save obstacle map to compact text file (.dat).
--- Format: header line + one line per cell "cx cy cz count".
--- No count caps: all hit cells and clear cells are saved.
--- This is significantly faster than JSON for large maps.
function AV:SaveObstacleMap()
	local ok, err = pcall(function()
		-- Build lines table (much faster than string concatenation)
		local lines = {"DAV_OBMAP v2 cell_size=" .. tostring(self.obstacle_cell_size)}
		local n_hit, n_clear = 0, 0
		for k, v in pairs(self.obstacle_map) do
			-- k = "cx_cy_cz", replace underscores with spaces for compact storage
			lines[#lines+1] = k:gsub("_", " ") .. " " .. v.count
			if v.count == 0 then
				n_clear = n_clear + 1
			else
				n_hit = n_hit + 1
			end
		end
		local file = io.open(self.obstacle_map_path, "w")
		if file then
			file:write(table.concat(lines, "\n"))
			file:close()
			self.log_obj:Record(LogLevel.Info, string.format(
				"Obstacle map saved: %d hit cells, %d clear cells (total %d)",
				n_hit, n_clear, n_hit + n_clear))
		end
	end)
	if not ok then
		self.log_obj:Record(LogLevel.Warning, "SaveObstacleMap failed: " .. tostring(err))
	end
end

--- Load obstacle map from .dat file (compact text format).
function AV:LoadObstacleMap()
	local ok, err = pcall(function()
		local file = io.open(self.obstacle_map_path, "r")
		if not file then return end
		-- Read compact .dat format
		local raw = file:read("*all")
		file:close()
		if not raw or raw == "" then return end
		local cs = raw:match("^DAV_OBMAP v2 cell_size=([%d%.]+)")
		if not cs then
			self.log_obj:Record(LogLevel.Warning, "LoadObstacleMap: unrecognised .dat header")
			return
		end
		self.obstacle_cell_size = tonumber(cs) or 10.0
		self.obstacle_map = {}
		local n = 0
		-- Each data line: "cx cy cz count" (integer cell coords, may be negative)
		for cx, cy, cz, count in raw:gmatch("(-?%d+) (-?%d+) (-?%d+) (-?%d+)") do
			self.obstacle_map[cx .. "_" .. cy .. "_" .. cz] = {count = tonumber(count)}
			n = n + 1
		end
		self.log_obj:Record(LogLevel.Info, string.format("Obstacle map loaded: %d cells", n))
	end)
	if not ok then
		self.log_obj:Record(LogLevel.Warning, "LoadObstacleMap failed: " .. tostring(err))
	end
end

--- ============================================================================
--- Obstacle Map Recording (runs during any driving when enabled via debug menu)
--- ============================================================================

--- Cast rays in 16 fixed world-space directions and record hits in obstacle map.
--- Called by the recording Cron timer started via StartObstacleRecording().
function AV:RecordObstacleScan()
	if self.entity_id == nil then return end
	local pos = self:GetPosition()
	if pos == nil then return end

	-- 16 horizontal directions (every 22.5°) + up + down  = 18 rays per tick
	local range = self.obstacle_record_range
	local dirs = {}
	for i = 0, 7 do
		local a = math.rad(i * 45)
		dirs[#dirs+1] = {x = math.cos(a), y = math.sin(a), z =  0}
		dirs[#dirs+1] = {x = math.cos(a), y = math.sin(a), z =  0.5}  -- angled up
		dirs[#dirs+1] = {x = math.cos(a), y = math.sin(a), z = -0.3}  -- angled down
	end
	dirs[#dirs+1] = {x = 0, y = 0, z =  1}  -- straight up
	dirs[#dirs+1] = {x = 0, y = 0, z = -1}  -- straight down

	for _, d in ipairs(dirs) do
		local len = math.sqrt(d.x*d.x + d.y*d.y + d.z*d.z)
		if len > 0.001 then
			local nd = Vector4.new(d.x/len, d.y/len, d.z/len, 0)
			local dist, hit = self:RaycastDist(pos, nd, range)
			-- Only record if NOT at max range (i.e., something was actually hit)
			if dist < range - 0.5 and hit then
				self:RecordObstacleHit(hit, nd)
			else
				-- Ray cleared: mark traversed cells as confirmed clear (count = 0).
				-- Walk first 2 cell-widths along the ray; never overwrite a hit cell.
				local cs = self.obstacle_cell_size
				for step = 1, 2 do
					local d_val = step * cs
					if d_val < range - cs then
						local ck = math.floor((pos.x + nd.x*d_val)/cs) .. "_" ..
								   math.floor((pos.y + nd.y*d_val)/cs) .. "_" ..
								   math.floor((pos.z + nd.z*d_val)/cs)
						if not self.obstacle_map[ck] then
							self.obstacle_map[ck] = {count = 0}
						end
					end
				end
			end
		end
	end
	-- Also mark the cell the vehicle is currently occupying as confirmed clear.
	local cs = self.obstacle_cell_size
	local cur_key = math.floor(pos.x/cs) .. "_" .. math.floor(pos.y/cs) .. "_" .. math.floor(pos.z/cs)
	if not self.obstacle_map[cur_key] then
		self.obstacle_map[cur_key] = {count = 0}
	end
end

--- Start continuous obstacle recording (independent of autopilot).
--- Registers a Cron timer; subsequent calls while already running are no-ops.
function AV:StartObstacleRecording()
	if self.is_obstacle_map_recording then return end
	-- Merge with any previously saved data so new scans accumulate on top
	self:LoadObstacleMap()
	self.is_obstacle_map_recording = true
	self.log_obj:Record(LogLevel.Info, "Obstacle map recording STARTED (merged with saved map)")
	Cron.Every(self.obstacle_record_interval, function(timer)
		if not self.is_obstacle_map_recording then
			Cron.Halt(timer)
			return
		end
		self:RecordObstacleScan()
	end)
end

--- Stop continuous obstacle recording and persist the map.
function AV:StopObstacleRecording()
	if not self.is_obstacle_map_recording then return end
	self.is_obstacle_map_recording = false
	self:SaveObstacleMap()
	self.log_obj:Record(LogLevel.Info, "Obstacle map recording STOPPED and saved")
end

--- Get approximate rear-left and rear-right corner positions of the vehicle
--- Based on current heading. Used to detect rear corner clips during turns.
function AV:GetRearCornerPositions(current_pos)
	local veh_fwd = self:GetForward()
	local fwd_len = math.sqrt(veh_fwd.x^2 + veh_fwd.y^2)
	if fwd_len < 0.001 then
		return current_pos, current_pos
	end
	local fx = veh_fwd.x / fwd_len
	local fy = veh_fwd.y / fwd_len
	-- Right vector in XY plane (perpendicular to forward)
	local rx = -fy
	local ry =  fx
	local half_rear = self.collision_check_rear_distance   -- center to rear face
	local half_wid  = self.collision_check_side_distance   -- center to side face
	local rear_left = Vector4.new(
		current_pos.x - fx*half_rear - rx*half_wid,
		current_pos.y - fy*half_rear - ry*half_wid,
		current_pos.z, 1)
	local rear_right = Vector4.new(
		current_pos.x - fx*half_rear + rx*half_wid,
		current_pos.y - fy*half_rear + ry*half_wid,
		current_pos.z, 1)
	return rear_left, rear_right
end

--- Returns front-left and front-right corner positions (horizontal plane)
--- Uses collision_check_front_distance and collision_check_side_distance from model data
function AV:GetFrontCornerPositions(current_pos)
	local veh_fwd = self:GetForward()
	local fwd_len = math.sqrt(veh_fwd.x^2 + veh_fwd.y^2)
	if fwd_len < 0.001 then
		return current_pos, current_pos
	end
	local fx = veh_fwd.x / fwd_len
	local fy = veh_fwd.y / fwd_len
	-- Right vector in XY plane
	local rx = -fy
	local ry =  fx
	local half_fwd = self.collision_check_front_distance   -- center to front face
	local half_wid = self.collision_check_side_distance    -- center to side face
	local front_left = Vector4.new(
		current_pos.x + fx*half_fwd - rx*half_wid,
		current_pos.y + fy*half_fwd - ry*half_wid,
		current_pos.z, 1)
	local front_right = Vector4.new(
		current_pos.x + fx*half_fwd + rx*half_wid,
		current_pos.y + fy*half_fwd + ry*half_wid,
		current_pos.z, 1)
	return front_left, front_right
end

--- 3D Tangent Bug main navigation function
--- Returns normalized Vector4 movement direction for this tick
function AV:TangentBugNavigate(current_pos, dest_dir_vec, current_time)
	if not current_pos or not dest_dir_vec then
		return Vector4.new(1, 0, 0, 0)
	end

	-- Normalize destination direction
	local dest_len = math.sqrt(dest_dir_vec.x^2 + dest_dir_vec.y^2 + dest_dir_vec.z^2)
	if dest_len < 0.001 then return Vector4.new(1, 0, 0, 0) end
	local dest_dir = Vector4.new(
		dest_dir_vec.x / dest_len,
		dest_dir_vec.y / dest_len,
		dest_dir_vec.z / dest_len, 0)

	-- Stuck detection: accumulate time when not moving
	if self.tangent_last_pos then
		local moved = math.sqrt(
			(current_pos.x - self.tangent_last_pos.x)^2 +
			(current_pos.y - self.tangent_last_pos.y)^2 +
			(current_pos.z - self.tangent_last_pos.z)^2)
		if moved < 0.2 then
			self.tangent_stuck_timer = self.tangent_stuck_timer + DAV.time_resolution
		else
			self.tangent_stuck_timer = 0
			self.tangent_stuck_escape_time = 0  -- Reset escape if moving
		end
	end
	self.tangent_last_pos = Vector4.new(current_pos.x, current_pos.y, current_pos.z, 1)

	-- Stuck escape: ascend vertically for tangent_stuck_escape_dur seconds
	if self.tangent_stuck_timer >= self.tangent_stuck_threshold then
		if self.tangent_stuck_escape_time == 0 then
			self.tangent_stuck_escape_time = current_time
			self.log_obj:Record(LogLevel.Warning, string.format(
				"TangentBug: STUCK (%.1fs without movement) - ascending to escape",
				self.tangent_stuck_timer))
		end
		if current_time - self.tangent_stuck_escape_time < self.tangent_stuck_escape_dur then
			return Vector4.new(0, 0, 1, 0)  -- Pure upward escape
		else
			-- Escape finished: reset and resume DIRECT mode
			self.tangent_stuck_timer = 0
			self.tangent_stuck_escape_time = 0
			self.tangent_mode = "DIRECT"
			self.log_obj:Record(LogLevel.Info, "TangentBug: stuck escape complete, resuming DIRECT")
		end
	end

	-- Speed-proportional detection distance: faster = look further ahead
	-- At 10m/s → 20m, at 25m/s → 50m, at 48m/s → 96m
	local detect_dist = math.max(20.0, self.autopilot_speed * 2.0)
	-- enter_dist: trigger BOUNDARY when obstacle closer than this.
	-- Reduced to speed*0.6 (was *1.0) so A*-selected corridors are not
	-- prematurely blocked.  Still ≥10m minimum for low-speed safety.
	local enter_dist = math.max(10.0, self.autopilot_speed * 0.6)
	-- exit_dist: hysteresis = enter + 8m
	local exit_dist = enter_dist + 8.0

	-- Forward fan detection: 5 rays in a 20° cone around dest_dir
	-- This covers vehicle width and slight approach angles
	local fwd_dist, hit_normal = self:RaycastFanMin(current_pos, dest_dir, detect_dist, 20, 4)

	-- Check rear corners of the vehicle rectangle moving in dest_dir.
	-- Front corners are intentionally excluded from DIRECT triggering:
	-- they are already offset forward+sideways, so flying parallel to building walls
	-- always returns ~enter_dist from them, causing constant false BOUNDARY entries in corridors.
	-- Rear corners are still needed to catch tail-swing clips during turns.
	-- Front corners are only used later for BOUNDARY validation (see below).
	local rear_left,  rear_right  = self:GetRearCornerPositions(current_pos)
	local front_left, front_right = self:GetFrontCornerPositions(current_pos)
	local rear_left_dist  = self:RaycastDist(rear_left,  dest_dir, detect_dist)
	local rear_right_dist = self:RaycastDist(rear_right, dest_dir, detect_dist)
	-- For log reporting + body-clear check, record front corner distances too
	local front_left_dist  = self:RaycastDist(front_left,  dest_dir, detect_dist)
	local front_right_dist = self:RaycastDist(front_right, dest_dir, detect_dist)
	-- Effective forward distance: center fan + rear corners only
	local effective_fwd_dist = math.min(fwd_dist, rear_left_dist, rear_right_dist)

	-- Body-clear check: if ALL 4 corners are beyond enter_dist, the vehicle body can
	-- physically pass through even if the center fan ray clips something (e.g. a thin
	-- pillar, building edge, or terrain artifact only in the exact forward direction).
	-- In that case we skip BOUNDARY entry entirely to prevent false-positive stalls.
	local body_clear = (front_left_dist  > enter_dist and front_right_dist > enter_dist and
	                    rear_left_dist   > enter_dist and rear_right_dist  > enter_dist)

	-- Speed reduction based on proximity: slow down well before the obstacle.
	-- In BOUNDARY mode, use only fwd_dist (center fan in dest_dir) for speed control.
	-- Using effective_fwd_dist (which includes rear corners) in BOUNDARY mode causes
	-- permanent speed reduction because rear corners face the wall being followed.
	local speed_dist = (self.tangent_mode == "BOUNDARY") and fwd_dist or effective_fwd_dist
	local proximity_ratio = speed_dist / (enter_dist * 2.0)
	if not body_clear and proximity_ratio < 1.0 then
		self.auto_speed_reduce_rate = math.max(0.2, proximity_ratio * 0.6 + 0.2)
	else
		self.auto_speed_reduce_rate = 0.7  -- normal cruising rate
	end

	-- === DIRECT mode: fly straight toward goal ===
	if self.tangent_mode == "DIRECT" then
		-- Cooldown: after exiting BOUNDARY, require tangent_direct_cooldown_dist of travel
		-- before allowing BOUNDARY re-entry (prevents rapid oscillation on same obstacle).
		-- An emergency override skips cooldown only when imminent collision is detected.
		local direct_traveled = math.huge  -- infinity = no cooldown if start_pos not set
		if self.tangent_direct_start_pos then
			local dx = current_pos.x - self.tangent_direct_start_pos.x
			local dy = current_pos.y - self.tangent_direct_start_pos.y
			local dz = current_pos.z - self.tangent_direct_start_pos.z
			direct_traveled = math.sqrt(dx*dx + dy*dy + dz*dz)
		end
		local in_cooldown   = direct_traveled < self.tangent_direct_cooldown_dist
		local emergency_thr = enter_dist * 0.4  -- ~7-10 m: imminent collision threshold

		if effective_fwd_dist > enter_dist then
			-- Path is clear: continue straight
			return dest_dir
		elseif body_clear then
			-- Center fan clips something but all 4 corners are clear:
			-- the vehicle body can physically pass → ignore the false-positive hit.
			self.log_obj:Record(LogLevel.Debug, string.format(
				"TangentBug: DIRECT body-clear skip (fwd=%.1fm < enter=%.1fm but all corners OK)",
				fwd_dist, enter_dist))
			return dest_dir
		elseif in_cooldown and effective_fwd_dist > emergency_thr then
			-- Not an emergency and we just left BOUNDARY: suppress re-entry
			self.log_obj:Record(LogLevel.Debug, string.format(
				"TangentBug: DIRECT cooldown (trav=%.1fm/%.1fm, eff=%.1fm > emer=%.1fm)",
				direct_traveled, self.tangent_direct_cooldown_dist, effective_fwd_dist, emergency_thr))
			return dest_dir
		end
		-- Obstacle detected (or emergency): estimate face normal from hit rays
		if hit_normal then
			self.tangent_obstacle_normal = hit_normal
		else
			self.tangent_obstacle_normal = Vector4.new(-dest_dir.x, -dest_dir.y, -dest_dir.z, 0)
		end
		-- Record the estimated obstacle hit position in the 3D obstacle map
		self:RecordObstacleHit(Vector4.new(
			current_pos.x + dest_dir.x * effective_fwd_dist,
			current_pos.y + dest_dir.y * effective_fwd_dist,
			current_pos.z + dest_dir.z * effective_fwd_dist, 1), dest_dir)
		self.tangent_mode = "BOUNDARY"
		self.tangent_mode_start_time = current_time
		self.tangent_boundary_dir = nil
		self.tangent_entry_pos = Vector4.new(current_pos.x, current_pos.y, current_pos.z, 1)
		self.tangent_direct_start_pos = nil  -- cooldown resets; re-armed on BOUNDARY->DIRECT
		self.log_obj:Record(LogLevel.Info, string.format(
			"TangentBug: DIRECT->BOUNDARY (eff=%.1fm [fwd=%.1fm FL=%.1fm FR=%.1fm RL=%.1fm RR=%.1fm], enter=%.1fm, cooldown=%s)",
			effective_fwd_dist, fwd_dist, front_left_dist, front_right_dist, rear_left_dist, rear_right_dist, enter_dist,
			in_cooldown and "BYPASSED(emergency)" or "n/a"))
	end

	-- === BOUNDARY mode: follow obstacle surface ===
	-- Keep updating the obstacle normal from real-time ray data
	if hit_normal then
		self.tangent_obstacle_normal = hit_normal
	end

	-- Timeout guard: reset to DIRECT if stuck in boundary too long
	if current_time - self.tangent_mode_start_time > self.tangent_boundary_timeout then
		self.tangent_mode = "DIRECT"
		self.tangent_boundary_dir = nil
		self.log_obj:Record(LogLevel.Warning, string.format(
			"TangentBug: BOUNDARY timeout (%.0fs) -> DIRECT",
			self.tangent_boundary_timeout))
		return dest_dir
	end

	-- Exit condition: forward path is clear AND we have moved past the obstacle
	-- Requires both:
	--   1. fwd_dist > exit_dist  (obstacle no longer directly ahead)
	--   2. moved >= enter_dist   (have actually navigated around, not just turned sideways)
	-- Fallback: if moved a lot (>= enter_dist*3) and fwd is at least marginally clear
	-- (> enter_dist), exit regardless of exit_dist.  This handles large buildings where
	-- fwd_dist in dest_dir never reaches exit_dist even after a full boundary circuit.
	local moved_from_entry = 0
	if self.tangent_entry_pos then
		local dx = current_pos.x - self.tangent_entry_pos.x
		local dy = current_pos.y - self.tangent_entry_pos.y
		local dz = current_pos.z - self.tangent_entry_pos.z
		moved_from_entry = math.sqrt(dx*dx + dy*dy + dz*dz)
	end
	local normal_exit   = fwd_dist > exit_dist   and moved_from_entry >= enter_dist
	local fallback_exit = fwd_dist > enter_dist  and moved_from_entry >= enter_dist * 3
	if normal_exit or fallback_exit then
		self.tangent_mode = "DIRECT"
		self.tangent_entry_pos = nil
		-- Arm the re-entry cooldown from this position
		self.tangent_direct_start_pos = Vector4.new(current_pos.x, current_pos.y, current_pos.z, 1)
		self.log_obj:Record(LogLevel.Info, string.format(
			"TangentBug: BOUNDARY->DIRECT (%s, fwd=%.1fm, moved=%.1fm, cooldown armed)",
			fallback_exit and "fallback" or "normal", fwd_dist, moved_from_entry))
		return dest_dir
	else
		self.log_obj:Record(LogLevel.Debug, string.format(
			"TangentBug: still in BOUNDARY (fwd=%.1fm exit=%.1fm, moved=%.1fm/%.1fm)",
			fwd_dist, exit_dist, moved_from_entry, enter_dist))
	end

	-- Find best passable direction along obstacle boundary toward goal
	local best_dir = self:FindBestBoundaryDir(current_pos, dest_dir, self.tangent_obstacle_normal)
	if best_dir then
		-- Verify the chosen boundary direction is clear for center AND rear corners.
		-- Front corners are excluded: when hugging an obstacle they already sit beside
		-- the wall, so a side-ward boundary ray from them always returns a short dist.
		-- Rear corners catch the tail-swing hazard which is the real concern here.
		local boundary_clearance  = self:RaycastDist(current_pos, best_dir, 10.0)
		local rear_left_boundary  = self:RaycastDist(rear_left,   best_dir, 8.0)
		local rear_right_boundary = self:RaycastDist(rear_right,  best_dir, 8.0)
		local min_clearance = math.min(boundary_clearance, rear_left_boundary, rear_right_boundary)
		if min_clearance < 5.0 then
			self.log_obj:Record(LogLevel.Warning, string.format(
				"TangentBug: boundary dir blocked (ctr=%.1fm RL=%.1fm RR=%.1fm), seeking alternative",
				boundary_clearance, rear_left_boundary, rear_right_boundary))
			-- Fall through to keep previous or escape
		else
			self.tangent_boundary_dir = best_dir
			self.log_obj:Record(LogLevel.Debug, string.format(
				"TangentBug: BOUNDARY dir=(%.2f,%.2f,%.2f) fwd=%.1fm min_clear=%.1fm",
				best_dir.x, best_dir.y, best_dir.z, fwd_dist, min_clearance))
			return best_dir
		end
	end

	-- All boundary candidates blocked: keep previous direction or escape upward
	if self.tangent_boundary_dir then
		-- Verify previous dir is still safe
		local prev_clearance = self:RaycastDist(current_pos, self.tangent_boundary_dir, 8.0)
		if prev_clearance > 4.0 then
			self.log_obj:Record(LogLevel.Warning, "TangentBug: all new candidates blocked, keeping previous boundary dir")
			return self.tangent_boundary_dir
		end
	end

	-- Last resort: pure upward
	self.log_obj:Record(LogLevel.Warning, "TangentBug: no valid direction found, ascending")
	return Vector4.new(0, 0, 1, 0)
end

--- Save learning data to JSON file
--- NOTE: This function is deprecated.
function AV:SaveLearningData()
	-- Legacy function - no longer used
end

--- Load learning data from JSON file
--- NOTE: This function is deprecated.
function AV:LoadLearningData()
	-- Legacy function - no longer used
end

return AV