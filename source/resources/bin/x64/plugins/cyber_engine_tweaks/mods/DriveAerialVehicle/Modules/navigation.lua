local Navigation = {}
Navigation.__index = Navigation
local Utils = require("Etc/utils.lua")

---@diagnostic disable: undefined-global, undefined-field

--- Constructor
---@param av_obj table AV instance
---@return table
function Navigation:New(av_obj)
	local obj = {}
	obj.av_obj = av_obj
	obj.log_obj = Log:New()
	obj.log_obj:SetLevel(LogLevel.Info, "Navigation")

	-- Initialize navigation-owned runtime state on bound AV instance.
	-- Destination and autopilot runtime values
	obj.mappin_destination_position = Vector4.new(0, 0, 0, 1)
	obj.favorite_destination_position = Vector4.new(0, 0, 0, 1)
	obj.autopilot_speed = 1
	obj.autopilot_turn_speed = 0.01
	obj.autopilot_leaving_height = 100
	obj.autopilot_searching_range = 50
	obj.autopilot_searching_step = 2
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
	obj.exception_area_bypass_distance = 200
	obj.is_exception_area_bypassed = false

	-- Route / A* state
	obj.sector_size = 20
	obj.current_global_route = {}
	obj.current_route_index = 1
	obj.last_route_plan_time = 0
	obj.astar_is_partial_route = false
	obj.astar_local_avoidance_recheck_time = 0

	-- Local avoidance state
	obj.is_deadend_escape_active = false
	obj.local_ray_count = 32
	obj.local_ray_angles = {}
	obj.local_avoidance_stuck_timer = 0
	obj.local_avoidance_stuck_threshold = 5.0
	obj.local_avoidance_stuck_escape_time = 0
	obj.local_avoidance_net_check_dist = nil
	obj.local_avoidance_net_check_time = 0

	-- Obstacle map and scan state
	obj.obstacle_map = {}
	obj.obstacle_cell_size = 10.0
	obj.obstacle_map_path = "Data/obstacle_map.dat"
	obj.obstacle_map_dir = "Data/map"
	obj.obstacle_map_chunk_cells = 50
	obj.obstacle_map_dirty_chunks = {}
	obj.obstacle_map_dirty_cells = {}
	obj.obstacle_map_chunk_index = {}
	obj.obstacle_map_dir_ok = false
	obj.route_save_path = "Data/last_route.json"
	obj.is_obstacle_map_recording = false
	obj.obstacle_record_interval = 0.2
	obj.obstacle_record_range = 60.0

	-- Navigation phase state
	obj.autopilot_phase = "astar"
	obj.autopilot_local_target = nil
	obj.autopilot_dest_is_unknown = false
	obj.autopilot_scan_dirty_count = 0
	obj.autopilot_scan_dirty_threshold = 150
	obj.autopilot_scan_last_save_time = 0

	-- Yaw smoothing state
	obj.yaw_target_smoothed = nil
	obj.yaw_smooth_alpha = 0.06
	obj.yaw_deadzone_deg = 4.0

	return setmetatable(obj, self)
end

--- Convert position to sector key
---@param position Vector4 Position in world space
---@return string|nil sector_key Format: "x_y_z", or nil if position is invalid
function Navigation:PositionToSectorKey(position)
	if not position then return nil end

	local sx = math.floor(position.x / self.sector_size)
	local sy = math.floor(position.y / self.sector_size)
	local sz = math.floor(position.z / self.sector_size)

	return string.format("%d_%d_%d", sx, sy, sz)
end

--- Parse sector key "sx_sy_sz" to integer coordinates.
--- Uses self.astar_coord_cache when available (populated during A* run) to avoid
--- repeated regex parsing of the same keys within a single pathfinding call.
---@param key string Sector key
---@return number|nil sx
---@return number|nil sy
---@return number|nil sz
function Navigation:ParseSectorKey(key)
	if self.astar_coord_cache then
		local c = self.astar_coord_cache[key]
		if c then return c[1], c[2], c[3] end
	end
	local sx, sy, sz = key:match("([^_]+)_([^_]+)_([^_]+)")
	if not sx then return nil, nil, nil end
	sx, sy, sz = tonumber(sx), tonumber(sy), tonumber(sz)
	if self.astar_coord_cache then
		self.astar_coord_cache[key] = {sx, sy, sz}
	end
	return sx, sy, sz
end

--- Get sector center position from key
---@param sector_key string Sector key "x_y_z"
---@return Vector4|nil Sector center position
function Navigation:SectorKeyToPosition(sector_key)
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

--- Get neighbor sector keys (26 directions: 6 cardinal + 12 edge + 8 corner)
---@param sector_key string Current sector key
---@return table List of neighbor sector keys
function Navigation:GetNeighborSectors(sector_key)
	if not sector_key then return {} end

	local sx, sy, sz = self:ParseSectorKey(sector_key)
	if not sx then return {} end

	local neighbors = {}
	-- 6 cardinal directions + 4 horizontal (XY) diagonals
	-- Diagonal base cost = sqrt(2) ~= 1.414 via GetSectorMovementCost Euclidean formula
	local offsets = {
		-- Cardinal
		{ 1,  0,  0}, {-1,  0,  0},
		{ 0,  1,  0}, { 0, -1,  0},
		{ 0,  0,  1}, { 0,  0, -1},
		-- Horizontal diagonals (XY plane)
		{ 1,  1,  0}, { 1, -1,  0},
		{-1,  1,  0}, {-1, -1,  0},
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
---@return number Estimated cost (3D Euclidean distance)
function Navigation:CalculateHeuristic(sector_key, goal_key)
	if not sector_key or not goal_key then return 9999 end

	local sx, sy, sz = self:ParseSectorKey(sector_key)
	local gx, gy, gz = self:ParseSectorKey(goal_key)

	if not sx or not gx then return 9999 end

	local dx = gx - sx
	local dy = gy - sy
	local dz = gz - sz

	-- 3D Euclidean distance: admissible heuristic for 10-direction grid
	-- (6 cardinal + 4 XY diagonals). Each cardinal costs 1.0, each diagonal costs sqrt(2),
	-- so 3D Euclidean never overestimates -> A* finds optimal path.
	return math.sqrt(dx*dx + dy*dy + dz*dz)
end

---@param from_key string Source sector key
---@param to_key string Destination sector key
---@return number Movement cost (distance + accessibility penalty + connectivity check)
function Navigation:GetSectorMovementCost(from_key, to_key)
	-- Base cost depends only on the direction offset (from->to), not sector content.
	-- Penalty depends only on the destination sector (to_key), so we cache it.
	local fx, fy, fz = self:ParseSectorKey(from_key)
	local tx, ty, tz = self:ParseSectorKey(to_key)

	if not fx or not tx then return 1.0 end

	local dx = tx - fx
	local dy = ty - fy
	local dz = tz - fz
	local base_cost = math.sqrt(dx*dx + dy*dy + dz*dz)

	-- Penalty cache: computed once per unique destination sector per A* run.
	-- Cache is initialised in PlanGlobalRoute and cleared afterwards.
	if self.sector_penalty_cache then
		local cached = self.sector_penalty_cache[to_key]
		if cached then
			return base_cost * cached
		end
	end

	-- ==== Penalty computation (runs once per unique to_key) ====

	-- CRITICAL: Block underground sectors (Z <= 0)
	if tz <= 0 then
		if self.sector_penalty_cache then self.sector_penalty_cache[to_key] = 10000000.0 end
		return base_cost * 10000000.0
	end

	local cs = self.obstacle_cell_size
	local ss = self.sector_size

	-- Obstacle map penalty (ternary): sample 18 cells overlapping this sector.
	-- sector_size=20m, cell_size=10m -> ~2x2x2 cells per sector.
	-- Values: true=obstacle, "danger"=adjacent-to-obstacle, false=clear, nil=unknown
	local obstacle_count = 0
	local danger_count   = 0
	local clear_count    = 0
	local unknown_count  = 0
	local total_sampled  = 0
	for _, sfx in ipairs({0.2, 0.5, 0.8}) do
		for _, sfy in ipairs({0.2, 0.5, 0.8}) do
			for _, sfz in ipairs({0.25, 0.75}) do
				local wx = (tx + sfx) * ss
				local wy = (ty + sfy) * ss
				local wz = (tz + sfz) * ss
				local ckey = math.floor(wx/cs) .. "_" .. math.floor(wy/cs) .. "_" .. math.floor(wz/cs)
				local cell = self.obstacle_map[ckey]
				total_sampled = total_sampled + 1
				if cell == true then
					obstacle_count = obstacle_count + 1
				elseif cell == "danger" then
					danger_count = danger_count + 1
				elseif cell == false then
					clear_count = clear_count + 1
				else
					unknown_count = unknown_count + 1
				end
			end
		end
	end

	local obstacle_penalty
	if obstacle_count > 0 then
		-- Obstacle cells present: high penalty proportional to density (max 501)
		obstacle_penalty = 1.0 + (obstacle_count / total_sampled) * 500.0
	elseif unknown_count > 0 then
		-- Unknown cells present: prefer danger over unknown, so unknown carries a
		-- higher base penalty. Danger cells in the same sector soften it slightly
		-- because they represent known information about the area.
		--   all unknown  -> 1.0 + 1.0 * 4.0           = 5.0
		--   half unknown + half danger -> 1.0 + 0.5*4.0 + 0.5*1.5 = 3.75
		local unknown_ratio = unknown_count / total_sampled
		local danger_ratio  = danger_count  / total_sampled
		obstacle_penalty = 1.0 + unknown_ratio * 4.0 + danger_ratio * 1.5
	elseif danger_count > 0 then
		-- Only danger cells (no obstacle, no unknown): medium penalty (max 2.5)
		-- Lower than unknown -> A* prefers known-danger over unknown territory
		obstacle_penalty = 1.0 + (danger_count / total_sampled) * 1.5
	else
		-- All cells confirmed clear: slight bonus for known-safe corridors
		obstacle_penalty = 0.8
	end

	-- Store in cache for reuse within this A* run
	if self.sector_penalty_cache then
		self.sector_penalty_cache[to_key] = obstacle_penalty
	end

	return base_cost * obstacle_penalty
end

--- Plan global route using A* algorithm
---@param start_pos Vector4 Start position
---@param end_pos Vector4 End position
---@return table Route as list of sector keys
function Navigation:PlanGlobalRoute(start_pos, end_pos)
	if not start_pos or not end_pos then
		return {}
	end

	-- Initialize per-run caches.
	-- sector_penalty_cache: avoids repeated obstacle_map lookups for the same destination sector.
	-- astar_coord_cache: avoids repeated regex parsing of the same sector key strings.
	self.sector_penalty_cache = {}
	self.astar_coord_cache    = {}

	local start_key = self:PositionToSectorKey(start_pos)
	local end_key   = self:PositionToSectorKey(end_pos)

	if not start_key or not end_key then
		return {}
	end

	-- Same sector, no need for pathfinding
	if start_key == end_key then
		return {start_key}
	end

	-- A* with min-heap open set (O(n log n) vs O(n^2) linear scan)
	-- and per-run coord cache (O(1) key parsing vs O(n) regex each call).
	-- Lazy-deletion heap: duplicate entries are pushed on f-score improvement;
	-- stale pops (already closed, or superseded) are skipped without counting
	-- against the iteration budget.
	local heap_keys   = {}
	local heap_scores = {}
	local heap_size   = 0

	local function heap_push(key, score)
		heap_size = heap_size + 1
		heap_keys[heap_size]   = key
		heap_scores[heap_size] = score
		local i = heap_size
		while i > 1 do
			local p = math.floor(i / 2)
			if heap_scores[p] > heap_scores[i] then
				heap_keys[i],   heap_keys[p]   = heap_keys[p],   heap_keys[i]
				heap_scores[i], heap_scores[p] = heap_scores[p], heap_scores[i]
				i = p
			else break end
		end
	end

	local function heap_pop()
		if heap_size == 0 then return nil, math.huge end
		local tk, ts = heap_keys[1], heap_scores[1]
		heap_keys[1]          = heap_keys[heap_size]
		heap_scores[1]        = heap_scores[heap_size]
		heap_keys[heap_size]  = nil
		heap_scores[heap_size]= nil
		heap_size = heap_size - 1
		local i = 1
		while true do
			local s = i
			local l, r = 2*i, 2*i+1
			if l <= heap_size and heap_scores[l] < heap_scores[s] then s = l end
			if r <= heap_size and heap_scores[r] < heap_scores[s] then s = r end
			if s == i then break end
			heap_keys[i], heap_keys[s]     = heap_keys[s],     heap_keys[i]
			heap_scores[i], heap_scores[s] = heap_scores[s], heap_scores[i]
			i = s
		end
		return tk, ts
	end

	local closed_set = {}
	local came_from  = {}
	local g_score    = {}
	local f_score    = {}

	-- Track best-explored node inline to avoid a second pass through closed_set on failure
	local best_partial_node = nil
	local best_partial_dist = math.huge

	-- Initialize start node
	g_score[start_key] = 0
	local start_h = self:CalculateHeuristic(start_key, end_key)
	f_score[start_key] = start_h
	heap_push(start_key, start_h)

	local precision = math.max(1, math.min(100, DAV.user_setting_table.astar_calculation_precision or 67))
	local max_iterations = math.floor(200 + ((precision - 1) / 99) * (30000 - 200) + 0.5)
	local iterations = 0

	while heap_size > 0 and iterations < max_iterations do
		local current, popped_f = heap_pop()
		if not current then break end

		-- Skip stale heap entries (lazy deletion):
		-- a node is stale if already closed, or if a better path was found
		-- after this entry was pushed (f_score decreased).
		if closed_set[current] or popped_f > (f_score[current] or math.huge) + 0.001 then
			-- stale: do not count against iteration budget
		else
			iterations = iterations + 1

			-- Goal reached
			if current == end_key then
				local route = {}
				local path_node = current
				while path_node do
					table.insert(route, 1, path_node)
					path_node = came_from[path_node]
				end
				self.astar_is_partial_route = false
				self.log_obj:Record(LogLevel.Info, string.format(
					"A* route planned: %d sectors, %d iterations from %s to %s (penalty_cache=%d coord_cache=%d)",
					#route, iterations, start_key, end_key,
					(function() local n=0; for _ in pairs(self.sector_penalty_cache) do n=n+1 end; return n end)(),
					(function() local n=0; for _ in pairs(self.astar_coord_cache) do n=n+1 end; return n end)()))
				self.sector_penalty_cache = nil
				self.astar_coord_cache    = nil
				return route
			end

			closed_set[current] = true

			-- Update best partial node (closest to goal among explored nodes)
			local h_cur = self:CalculateHeuristic(current, end_key)
			if h_cur < best_partial_dist then
				best_partial_dist = h_cur
				best_partial_node = current
			end

			-- Evaluate neighbors
			local neighbors = self:GetNeighborSectors(current)
			for _, neighbor in ipairs(neighbors) do
				if not closed_set[neighbor] then
					local move_cost = self:GetSectorMovementCost(current, neighbor)
					-- Skip impassable sectors (underground / exception area).
					-- Impassable returns base_cost * 1e7; max legitimate cost ~= 709, so 1e5 is safe.
					if move_cost < 1e5 then
						local tentative_g = (g_score[current] or math.huge) + move_cost
						if tentative_g < (g_score[neighbor] or math.huge) then
							came_from[neighbor] = current
							g_score[neighbor]   = tentative_g
							local new_f = tentative_g + self:CalculateHeuristic(neighbor, end_key)
							f_score[neighbor] = new_f
							heap_push(neighbor, new_f)
						end
					end
				end
			end
		end
	end

	-- No path found within iteration limit.
	local open_count   = heap_size
	local closed_count = 0
	for _ in pairs(closed_set) do closed_count = closed_count + 1 end

	if best_partial_node and best_partial_node ~= start_key then
		local partial_route = {}
		local path_node = best_partial_node
		while path_node do
			table.insert(partial_route, 1, path_node)
			path_node = came_from[path_node]
		end
		self.astar_is_partial_route = true
		self.log_obj:Record(LogLevel.Warning, string.format(
			"A* incomplete after %d iterations, using partial route to closest explored node: %d sectors (distance to goal: %.1f)",
			iterations, #partial_route, best_partial_dist * self.sector_size))
		self.sector_penalty_cache = nil
		self.astar_coord_cache    = nil
		return partial_route
	end

	-- No valid path found through known sectors.
	self.astar_is_partial_route = true
	self.log_obj:Record(LogLevel.Warning, string.format(
		"A* pathfinding failed after %d iterations - no path through known sectors (start=%s, end=%s, open=%d, closed=%d)",
		iterations, start_key, end_key, open_count, closed_count))
	self.sector_penalty_cache = nil
	self.astar_coord_cache    = nil
	return {}
end

--- Save the last planned A* route to JSON for external visualization.
---@param route table List of sector keys ("sx_sy_sz")
---@param start_pos Vector4 Actual start world position
---@param end_pos Vector4 Actual end world position
function Navigation:SaveLastRoute(route, start_pos, end_pos)
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

--- Priority-aware cell write helper.
--- Priority order: true(obstacle)=3 > "danger"=2 > false(clear)=1 > nil(unknown)=0
--- A cell is only updated when the new value has strictly higher priority.
---@param value any true | "danger" | false
---@return integer
function Navigation:GetObstacleCellPriority(value)
	if value == true then
		return 3
	elseif value == "danger" then
		return 2
	elseif value == false then
		return 1
	end
	return 0
end

---@param key string Cell key "cx_cy_cz"
---@param value any true | "danger" | false
---@return boolean updated
function Navigation:SetObstacleCellNoDirty(key, value)
	if self:GetObstacleCellPriority(value) > self:GetObstacleCellPriority(self.obstacle_map[key]) then
		self.obstacle_map[key] = value
		return true
	end
	return false
end

---@param key string Cell key "cx_cy_cz"
---@param value any true | "danger" | false
---@return boolean true if the cell was actually updated
function Navigation:SetObstacleCell(key, value)
	if self:GetObstacleCellPriority(value) > self:GetObstacleCellPriority(self.obstacle_map[key]) then
		self.obstacle_map[key] = value
		self:MarkCellDirty(key)
		return true
	end
	return false
end

--- Record a confirmed obstacle hit position into the obstacle map grid.
--- Marks the exact hit cell as obstacle (true), then marks all 26 face/edge/corner
--- neighbors as "danger" -- but never downgrades a cell to a lower-priority state.
function Navigation:RecordObstacleHit(hit_pos)
	if not hit_pos then return end
	local cs = self.obstacle_cell_size
	local cx = math.floor(hit_pos.x / cs)
	local cy = math.floor(hit_pos.y / cs)
	local cz = math.floor(hit_pos.z / cs)
	-- Mark the exact hit cell as obstacle
	self:SetObstacleCell(cx .. "_" .. cy .. "_" .. cz, true)
	-- Mark all 26 neighbors as danger (priority check inside SetObstacleCell)
	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				if not (dx == 0 and dy == 0 and dz == 0) then
					self:SetObstacleCell((cx+dx) .. "_" .. (cy+dy) .. "_" .. (cz+dz), "danger")
				end
			end
		end
	end
end

--- Record a PHYSICAL collision (IsCollision() == true) into the obstacle map.
--- Marks the vehicle's current cell as obstacle, then marks the 26 neighbors as danger.
function Navigation:RecordDirectCollision()
	local pos = self.av_obj:GetPosition()
	if not pos then return end
	local cs = self.obstacle_cell_size
	local cx = math.floor(pos.x / cs)
	local cy = math.floor(pos.y / cs)
	local cz = math.floor(pos.z / cs)
	local key = cx .. "_" .. cy .. "_" .. cz
	if self:SetObstacleCell(key, true) then
		self.log_obj:Record(LogLevel.Info, string.format(
			"Direct collision recorded at cell (%d,%d,%d) pos=(%.1f,%.1f,%.1f)",
			cx, cy, cz, pos.x, pos.y, pos.z))
	end
	-- Mark neighbors as danger
	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				if not (dx == 0 and dy == 0 and dz == 0) then
					self:SetObstacleCell((cx+dx) .. "_" .. (cy+dy) .. "_" .. (cz+dz), "danger")
				end
			end
		end
	end
end

--- Create a convex hexahedron obstacle volume from 8 recorded sector points.
--- Point order is free (unordered). The function extracts hull planes from points.
---@param points table Array of 8 entries. Each entry accepts { key = "sx_sy_sz" } or { pos = Vector4 } or Vector4.
---@return boolean ok
---@return string message
function Navigation:CreateObstacleConvexHexahedronFromPoints(points)
	if type(points) ~= "table" then
		return false, "points is not a table"
	end

	local verts = {}
	for i = 1, 8 do
		local p = points[i]
		if not p then
			return false, string.format("point %d is missing", i)
		end

		local sx, sy, sz = nil, nil, nil
		if type(p) == "table" and p.key then
			sx, sy, sz = self:ParseSectorKey(p.key)
		elseif type(p) == "table" and p.pos then
			local skey = self:PositionToSectorKey(p.pos)
			if skey then sx, sy, sz = self:ParseSectorKey(skey) end
		elseif type(p) == "userdata" or (type(p) == "table" and p.x and p.y and p.z) then
			local skey = self:PositionToSectorKey(p)
			if skey then sx, sy, sz = self:ParseSectorKey(skey) end
		end

		if not sx or not sy or not sz then
			return false, string.format("point %d is invalid", i)
		end

		local c = self:SectorKeyToPosition(string.format("%d_%d_%d", sx, sy, sz))
		if not c then
			return false, string.format("point %d center resolution failed", i)
		end
		verts[i] = {x = c.x, y = c.y, z = c.z}
	end

	local function vsub(a, b)
		return {x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}
	end
	local function dot(a, b)
		return a.x * b.x + a.y * b.y + a.z * b.z
	end
	local function cross(a, b)
		return {
			x = a.y * b.z - a.z * b.y,
			y = a.z * b.x - a.x * b.z,
			z = a.x * b.y - a.y * b.x
		}
	end
	local function flip(v)
		return {x = -v.x, y = -v.y, z = -v.z}
	end
	local function quantize(v)
		if v >= 0 then
			return math.floor(v * 1000 + 0.5) / 1000
		else
			return math.ceil(v * 1000 - 0.5) / 1000
		end
	end

	local centroid = {x = 0, y = 0, z = 0}
	for i = 1, 8 do
		centroid.x = centroid.x + verts[i].x
		centroid.y = centroid.y + verts[i].y
		centroid.z = centroid.z + verts[i].z
	end
	centroid.x = centroid.x / 8
	centroid.y = centroid.y / 8
	centroid.z = centroid.z / 8

	local eps = 1e-4
	local plane_set = {}
	local planes = {}

	-- Build supporting planes from all non-collinear point triplets.
	-- A valid hull plane has all other points on one side (or on the plane).
	for i = 1, 6 do
		for j = i + 1, 7 do
			for k = j + 1, 8 do
				local a, b, c = verts[i], verts[j], verts[k]
				local n = cross(vsub(b, a), vsub(c, a))
				local n_len_sq = n.x * n.x + n.y * n.y + n.z * n.z
				if n_len_sq > 1e-8 then
					local has_pos = false
					local has_neg = false
					for m = 1, 8 do
						if m ~= i and m ~= j and m ~= k then
							local d = dot(n, vsub(verts[m], a))
							if d > eps then
								has_pos = true
							elseif d < -eps then
								has_neg = true
							end
							if has_pos and has_neg then break end
						end
					end

					if not (has_pos and has_neg) then
						local n_len = math.sqrt(n_len_sq)
						local nu = {x = n.x / n_len, y = n.y / n_len, z = n.z / n_len}
						local pu = dot(nu, a)

						-- Canonical orientation for dedupe.
						if (nu.x < -eps)
							or (math.abs(nu.x) <= eps and nu.y < -eps)
							or (math.abs(nu.x) <= eps and math.abs(nu.y) <= eps and nu.z < -eps) then
							nu = flip(nu)
							pu = -pu
						end

						local key = string.format("%.3f_%.3f_%.3f_%.3f",
							quantize(nu.x), quantize(nu.y), quantize(nu.z), quantize(pu))
						if not plane_set[key] then
							plane_set[key] = true
							planes[#planes + 1] = {n = nu, p = a}
						end
					end
				end
			end
		end
	end

	if #planes < 4 then
		return false, "failed to build convex hull planes from points"
	end

	-- Orient normals outward using centroid.
	for _, pl in ipairs(planes) do
		if dot(pl.n, vsub(centroid, pl.p)) > 0 then
			pl.n = flip(pl.n)
		end
	end

	-- Validate convexity: every vertex must lie on or inside all face half-spaces.
	for _, pl in ipairs(planes) do
		for i = 1, 8 do
			local v = vsub(verts[i], pl.p)
			if dot(pl.n, v) > eps then
				return false, "points do not form a valid convex hexahedron"
			end
		end
	end

	local min_x, max_x = verts[1].x, verts[1].x
	local min_y, max_y = verts[1].y, verts[1].y
	local min_z, max_z = verts[1].z, verts[1].z
	for i = 2, 8 do
		if verts[i].x < min_x then min_x = verts[i].x end
		if verts[i].x > max_x then max_x = verts[i].x end
		if verts[i].y < min_y then min_y = verts[i].y end
		if verts[i].y > max_y then max_y = verts[i].y end
		if verts[i].z < min_z then min_z = verts[i].z end
		if verts[i].z > max_z then max_z = verts[i].z end
	end

	local cs = self.obstacle_cell_size
	local cx0 = math.floor(min_x / cs)
	local cx1 = math.floor(max_x / cs)
	local cy0 = math.floor(min_y / cs)
	local cy1 = math.floor(max_y / cs)
	local cz0 = math.floor(min_z / cs)
	local cz1 = math.floor(max_z / cs)

	local function is_inside(point)
		for _, pl in ipairs(planes) do
			local v = vsub(point, pl.p)
			if dot(pl.n, v) > eps then
				return false
			end
		end
		return true
	end

	local updated_cells = 0
	for cx = cx0, cx1 do
		for cy = cy0, cy1 do
			for cz = cz0, cz1 do
				local center = {
					x = (cx + 0.5) * cs,
					y = (cy + 0.5) * cs,
					z = (cz + 0.5) * cs,
				}
				if is_inside(center) then
					if self:SetObstacleCell(string.format("%d_%d_%d", cx, cy, cz), true) then
						updated_cells = updated_cells + 1
					end
				end
			end
		end
	end

	if updated_cells == 0 then
		return false, "no cells were updated (check point order and shape volume)"
	end

	self:SaveObstacleMap()
	self.log_obj:Record(LogLevel.Info, string.format(
		"Manual obstacle convex-hexahedron created: updated_cells=%d, bbox=(%.1f..%.1f, %.1f..%.1f, %.1f..%.1f)",
		updated_cells, min_x, max_x, min_y, max_y, min_z, max_z))

	return true, string.format("updated_cells=%d", updated_cells)
end

--- Convert cell key "cx_cy_cz" to chunk key "chunkX_chunkY" (XY-based 500m chunks).
---@param cell_key string Cell key in format "cx_cy_cz"
---@return string|nil chunk_key e.g. "-4_2" (500m region in world space)
function Navigation:CellKeyToChunkKey(cell_key)
	local cx, cy = cell_key:match("^(-?%d+)_(-?%d+)")
	if not cx then return nil end
	local cc = self.obstacle_map_chunk_cells
	return math.floor(tonumber(cx) / cc) .. "_" .. math.floor(tonumber(cy) / cc)
end

--- Mark the chunk containing a cell as dirty (needs saving on next SaveObstacleMap).
--- Also registers the cell in the chunk index for efficient per-chunk iteration.
---@param cell_key string Cell key "cx_cy_cz"
function Navigation:MarkCellDirty(cell_key)
	local ck = self:CellKeyToChunkKey(cell_key)
	if not ck then return end
	self.obstacle_map_dirty_chunks[ck] = true
	if not self.obstacle_map_dirty_cells[ck] then
		self.obstacle_map_dirty_cells[ck] = {}
	end
	self.obstacle_map_dirty_cells[ck][cell_key] = true
	if not self.obstacle_map_chunk_index[ck] then
		self.obstacle_map_chunk_index[ck] = {}
	end
	self.obstacle_map_chunk_index[ck][cell_key] = true
end

--- Register a cell in the chunk index WITHOUT marking dirty (used during load).
---@param cell_key string Cell key "cx_cy_cz"
function Navigation:RegisterCellInChunkIndex(cell_key)
	local ck = self:CellKeyToChunkKey(cell_key)
	if not ck then return end
	if not self.obstacle_map_chunk_index[ck] then
		self.obstacle_map_chunk_index[ck] = {}
	end
	self.obstacle_map_chunk_index[ck][cell_key] = true
end

--- Ensure the Data/map directory exists for chunked storage.
---@return boolean success
function Navigation:EnsureMapDirectory()
	if self.obstacle_map_dir_ok then return true end
	-- Try writing a test file to check if directory exists
	local test_path = self.obstacle_map_dir .. "/.dirtest"
	local f = io.open(test_path, "w")
	if f then
		f:close()
		os.remove(test_path)
		self.obstacle_map_dir_ok = true
		return true
	end
	-- Attempt to create the directory
	local dir_win = self.obstacle_map_dir:gsub("/", "\\")
	os.execute('mkdir "' .. dir_win .. '" 2>nul')
	f = io.open(test_path, "w")
	if f then
		f:close()
		os.remove(test_path)
		self.obstacle_map_dir_ok = true
		self.log_obj:Record(LogLevel.Info, "Created map directory: " .. self.obstacle_map_dir)
		return true
	end
	self.log_obj:Record(LogLevel.Error, "Failed to create map directory: " .. self.obstacle_map_dir)
	return false
end

--- Migrate legacy single-file obstacle_map.dat to chunked format in Data/map/.
--- Called automatically by LoadObstacleMap on first load.
function Navigation:MigrateOldObstacleMap()
	local old_path = self.obstacle_map_path
	local file = io.open(old_path, "r")
	if not file then
		-- Also try .bak
		file = io.open(old_path .. ".bak", "r")
		if not file then return false end
		self.log_obj:Record(LogLevel.Info, "Migrating from backup obstacle_map.dat.bak")
	end

	self.log_obj:Record(LogLevel.Info, "Migrating legacy obstacle_map.dat to chunked format...")
	local raw = file:read("*all")
	file:close()
	if not raw or raw == "" then return false end

	local cs = raw:match("^DAV_OBMAP v2 cell_size=([%d%.]+)")
	if not cs then
		self.log_obj:Record(LogLevel.Warning, "MigrateOldObstacleMap: unrecognized header, skipping")
		return false
	end
	self.obstacle_cell_size = tonumber(cs) or 10.0

	local n = 0
	for cx, cy, cz, count in raw:gmatch("(-?%d+) (-?%d+) (-?%d+) (-?%d+)") do
		local key = cx .. "_" .. cy .. "_" .. cz
		local cnt = tonumber(count)
		self.obstacle_map[key] = {count = cnt}
		-- Build chunk index and mark all chunks dirty for initial save
		self:MarkCellDirty(key)
		n = n + 1
	end

	-- Save all chunks in new format
	self:SaveObstacleMap()

	-- Rename old files so they won't be re-migrated
	os.rename(old_path, old_path .. ".migrated")
	os.rename(old_path .. ".bak", old_path .. ".bak.migrated")

	self.log_obj:Record(LogLevel.Info, string.format(
		"Migration complete: %d cells -> chunked files in %s. Old file renamed to .migrated",
		n, self.obstacle_map_dir))
	return true
end

--- Save obstacle map using complete differential persistence.
--- Only cells changed since the previous save are appended to chunk diff logs.
--- File naming: chunk_{chunkX}_{chunkY}.diff (append-only delta stream).
function Navigation:SaveObstacleMap()
	if next(self.obstacle_map) == nil then
		self.log_obj:Record(LogLevel.Debug, "SaveObstacleMap skipped: in-memory map is empty")
		return
	end
	if next(self.obstacle_map_dirty_cells) == nil then
		self.log_obj:Record(LogLevel.Debug, "SaveObstacleMap skipped: no dirty cells")
		return
	end
	if not self:EnsureMapDirectory() then return end

	local ok, err = pcall(function()
		local n_saved = 0
		local n_cells = 0
		for ck, cell_set in pairs(self.obstacle_map_dirty_cells) do
			local lines = {"DAV_OBMAP_DIFF v1 cell_size=" .. tostring(self.obstacle_cell_size)}
			local count = 0
			for cell_key, _ in pairs(cell_set) do
				local v = self.obstacle_map[cell_key]
				if v ~= nil then
					local vnum = (v == true) and 2 or (v == "danger" and 1 or 0)
					lines[#lines + 1] = cell_key:gsub("_", " ") .. " " .. vnum
					count = count + 1
				end
			end
			if count > 0 then
				local path = self.obstacle_map_dir .. "/chunk_" .. ck .. ".diff"
				local file = io.open(path, "a")
				if file then
					file:write(table.concat(lines, "\n"))
					file:write("\n")
					file:close()
					n_saved = n_saved + 1
					n_cells = n_cells + count
				end
			end
		end
		self.obstacle_map_dirty_chunks = {}
		self.obstacle_map_dirty_cells = {}
		if n_saved > 0 then
			self.log_obj:Record(LogLevel.Info, string.format(
				"Obstacle map saved (diff): %d chunks, %d cells written", n_saved, n_cells))
		end
	end)
	if not ok then
		self.log_obj:Record(LogLevel.Warning, "SaveObstacleMap failed: " .. tostring(err))
	end
end

--- Integrate append-only diff logs into base chunk files.
--- Rewrites chunk_*.dat from current in-memory map and removes chunk_*.diff.
---@return boolean success
function Navigation:IntegrateObstacleMapDiff()
	if next(self.obstacle_map) == nil then
		self.log_obj:Record(LogLevel.Debug, "IntegrateObstacleMapDiff skipped: in-memory map is empty")
		return false
	end
	if not self:EnsureMapDirectory() then
		return false
	end

	local ok, err = pcall(function()
		local n_dat = 0
		local n_diff_removed = 0
		local n_cells = 0

		for ck, cell_set in pairs(self.obstacle_map_chunk_index) do
			local lines = {"DAV_OBMAP v3 cell_size=" .. tostring(self.obstacle_cell_size)}
			local count = 0
			for cell_key, _ in pairs(cell_set) do
				local v = self.obstacle_map[cell_key]
				if v ~= nil then
					local vnum = (v == true) and 2 or (v == "danger" and 1 or 0)
					lines[#lines + 1] = cell_key:gsub("_", " ") .. " " .. vnum
					count = count + 1
				end
			end

			if count > 0 then
				local dat_path = self.obstacle_map_dir .. "/chunk_" .. ck .. ".dat"
				local dat_file = io.open(dat_path, "w")
				if dat_file then
					dat_file:write(table.concat(lines, "\n"))
					dat_file:close()
					n_dat = n_dat + 1
					n_cells = n_cells + count
				end
			end

			local diff_path = self.obstacle_map_dir .. "/chunk_" .. ck .. ".diff"
			if os.remove(diff_path) then
				n_diff_removed = n_diff_removed + 1
			end
		end

		self.obstacle_map_dirty_chunks = {}
		self.obstacle_map_dirty_cells = {}

		self.log_obj:Record(LogLevel.Info, string.format(
			"Obstacle map diff integrated: %d base chunks rewritten, %d cells, %d diff files removed",
			n_dat, n_cells, n_diff_removed))
	end)

	if not ok then
		self.log_obj:Record(LogLevel.Warning, "IntegrateObstacleMapDiff failed: " .. tostring(err))
		return false
	end
	return true
end

--- Load obstacle map from chunked files in Data/map/.
--- On first call, migrates legacy obstacle_map.dat if present.
--- Uses directory enumeration (dir /b) to discover only existing chunk files,
--- avoiding the overhead of probing all coordinate combinations.
--- MERGE mode: existing in-memory entries are kept; disk entries that don't
--- exist in memory yet are added.
function Navigation:LoadObstacleMap()
	-- First, try to migrate legacy single-file format
	self:MigrateOldObstacleMap()
	self.obstacle_map_dirty_chunks = {}
	self.obstacle_map_dirty_cells = {}

	-- Shared helper: parse and load one chunk file into obstacle_map.
	-- Returns number of cells loaded (0 if file missing or invalid).
	local function load_chunk_file(path)
		local file = io.open(path, "r")
		if not file then return 0 end
		local raw = file:read("*all")
		file:close()
		if not raw or raw == "" then return 0 end
		local cs = raw:match("^DAV_OBMAP v3 cell_size=([%d%.]+)")
		if not cs then return 0 end
		self.obstacle_cell_size = tonumber(cs) or 10.0
		local n = 0
		for cellx, celly, cellz, val in raw:gmatch("(-?%d+) (-?%d+) (-?%d+) (-?%d+)") do
			local key = cellx .. "_" .. celly .. "_" .. cellz
			local ival = tonumber(val) or 0
			-- 2=obstacle(true), 1=danger("danger"), 0=clear(false)
			-- Also accept legacy 1=obstacle for old files (val==1 that meant obstacle)
			local new_val
			if ival >= 2 then
				new_val = true
			elseif ival == 1 then
				new_val = "danger"
			else
				new_val = false
			end
			-- Merge load into memory without creating dirty-save entries.
			self:SetObstacleCellNoDirty(key, new_val)
			self:RegisterCellInChunkIndex(key)
			n = n + 1
		end
		return n
	end

	local function load_chunk_diff_file(path)
		local file = io.open(path, "r")
		if not file then return 0 end
		local raw = file:read("*all")
		file:close()
		if not raw or raw == "" then return 0 end
		local n = 0
		for cellx, celly, cellz, val in raw:gmatch("(-?%d+) (-?%d+) (-?%d+) (-?%d+)") do
			local key = cellx .. "_" .. celly .. "_" .. cellz
			local ival = tonumber(val) or 0
			local new_val
			if ival >= 2 then
				new_val = true
			elseif ival == 1 then
				new_val = "danger"
			else
				new_val = false
			end
			self:SetObstacleCellNoDirty(key, new_val)
			self:RegisterCellInChunkIndex(key)
			n = n + 1
		end
		return n
	end

	local ok, err = pcall(function()
		local total_cells  = 0
		local total_chunks = 0
		local total_diff_cells = 0
		local used_enum    = false

		-- ==== Primary: enumerate via dir /b (no coordinate probing) ====
		-- Lists only files that actually exist -> zero wasted io.open() calls.
		if io.popen then
			local dir_win = self.obstacle_map_dir:gsub("/", "\\")
			local pipe = io.popen('dir /b "' .. dir_win .. '\\chunk_*.dat" 2>nul')
			if pipe then
				for filename in pipe:lines() do
					local cx, cy = filename:match("^chunk_(-?%d+)_(-?%d+)%.dat$")
					if cx and cy then
						local path = self.obstacle_map_dir .. "/chunk_" .. cx .. "_" .. cy .. ".dat"
						local n = load_chunk_file(path)
						if n > 0 then
							total_cells  = total_cells  + n
							total_chunks = total_chunks + 1
						end
					end
				end
				pipe:close()
				used_enum = true
			end

			local diff_pipe = io.popen('dir /b "' .. dir_win .. '\\chunk_*.diff" 2>nul')
			if diff_pipe then
				for filename in diff_pipe:lines() do
					local cx, cy = filename:match("^chunk_(-?%d+)_(-?%d+)%.diff$")
					if cx and cy then
						local path = self.obstacle_map_dir .. "/chunk_" .. cx .. "_" .. cy .. ".diff"
						local n = load_chunk_diff_file(path)
						if n > 0 then
							total_diff_cells = total_diff_cells + n
						end
					end
				end
				diff_pipe:close()
			end
		end

		-- ==== Fallback: coordinate probe loop (if io.popen unavailable) ====
		-- Night City fits within [-10, 10]; 441 probes vs the old 1681.
		if not used_enum then
			for cx = -10, 10 do
				for cy = -10, 10 do
					local path = self.obstacle_map_dir .. "/chunk_" .. cx .. "_" .. cy .. ".dat"
					local n = load_chunk_file(path)
					if n > 0 then
						total_cells  = total_cells  + n
						total_chunks = total_chunks + 1
					end
					local diff_path = self.obstacle_map_dir .. "/chunk_" .. cx .. "_" .. cy .. ".diff"
					local dn = load_chunk_diff_file(diff_path)
					if dn > 0 then
						total_diff_cells = total_diff_cells + dn
					end
				end
			end
		end

		self.obstacle_map_dirty_chunks = {}
		self.obstacle_map_dirty_cells = {}

		if total_cells > 0 or total_diff_cells > 0 then
			self.log_obj:Record(LogLevel.Info, string.format(
				"Obstacle map loaded: %d base cells + %d diff cells from %d chunk files (%s)",
				total_cells, total_diff_cells, total_chunks, used_enum and "enum" or "probe"))
		end
	end)
	if not ok then
		self.log_obj:Record(LogLevel.Warning, "LoadObstacleMap failed: " .. tostring(err))
	end
end

--- Cast rays using the same Fibonacci sphere pattern as local avoidance (N=32).
--- Called by the recording Cron timer started via StartObstacleRecording().
function Navigation:RecordObstacleScan()
	if self.av_obj.entity_id == nil then return end
	local pos = self.av_obj:GetPosition()
	if pos == nil then return end

	if not self.local_ray_angles or #self.local_ray_angles ~= 32 then
		self.local_ray_count = 32
		self:GenerateSphericalRayPattern()
	end

	local range = self.obstacle_record_range

	for _, dir in ipairs(self.local_ray_angles) do
		local nd = Vector4.new(dir.x, dir.y, dir.z, 0)
		local dist, hit = self:RaycastDist(pos, nd, range)
		local cs = self.obstacle_cell_size

		if dist < range - 0.5 and hit then
			-- 1. Record obstacle + 26 danger neighbors first
			self:RecordObstacleHit(hit)
			-- 2. Mark cells along the ray UP TO (not including) the obstacle cell as clear.
			local max_d = dist - cs
			local step_d = cs
			while step_d <= max_d do
				local ck = math.floor((pos.x + nd.x * step_d) / cs) .. "_" ..
							math.floor((pos.y + nd.y * step_d) / cs) .. "_" ..
							math.floor((pos.z + nd.z * step_d) / cs)
				self:SetObstacleCell(ck, false)
				step_d = step_d + cs
			end
		else
			-- Ray cleared: mark ALL traversed cells as clear.
			local max_d = range - cs
			local step_d = cs
			while step_d <= max_d do
				local ck = math.floor((pos.x + nd.x * step_d) / cs) .. "_" ..
							math.floor((pos.y + nd.y * step_d) / cs) .. "_" ..
							math.floor((pos.z + nd.z * step_d) / cs)
				self:SetObstacleCell(ck, false)
				step_d = step_d + cs
			end
		end
	end
	-- Also mark the cell the vehicle is currently occupying as confirmed clear.
	local cs = self.obstacle_cell_size
	local cur_key = math.floor(pos.x/cs) .. "_" .. math.floor(pos.y/cs) .. "_" .. math.floor(pos.z/cs)
	self:SetObstacleCell(cur_key, false)
end

--- Start continuous obstacle recording (independent of autopilot).
--- Registers a Cron timer; subsequent calls while already running are no-ops.
function Navigation:StartObstacleRecording()
	if self.is_obstacle_map_recording then return end
	-- Merge with any previously saved data so new scans accumulate on top
	self:LoadObstacleMap()
	self.is_obstacle_map_recording = true
	self.log_obj:Record(LogLevel.Info, "Obstacle map recording STARTED (merged with saved map)")
	local scan_count = 0
	Cron.Every(self.obstacle_record_interval, function(timer)
		if not self.is_obstacle_map_recording then
			Cron.Halt(timer)
			return
		end
		-- Poll physical collision on every scan tick.
		-- IsOnGround() (= IsCollision()) is not an event; it must be called actively.
		-- This is the only always-running Cron while the player is in the vehicle,
		-- so it is the authoritative place to catch collisions regardless of autopilot phase.
		if self:IsCollision() then
			self:RecordDirectCollision()
		end
		self:RecordObstacleScan()
		scan_count = scan_count + 1
		-- Periodic save every ~30 s (150 ticks x 0.2 s) to protect against crashes.
		-- Skipped during autopilot: I/O stutter could affect A* route decisions.
		-- Data is saved on flight end via ConsolidateMemory().
		if scan_count >= self.autopilot_scan_dirty_threshold then
			scan_count = 0
			if not self.av_obj.is_auto_pilot then
				self:SaveObstacleMap()
				self.log_obj:Record(LogLevel.Info, "Obstacle map periodic save during recording")
			else
				self.log_obj:Record(LogLevel.Debug, "Obstacle map periodic save skipped (autopilot active)")
			end
		end
	end)
end

--- Stop continuous obstacle recording and persist the map.
function Navigation:StopObstacleRecording()
	if not self.is_obstacle_map_recording then return end
	self.is_obstacle_map_recording = false
	self:SaveObstacleMap()
	self.log_obj:Record(LogLevel.Info, "Obstacle map recording STOPPED and saved")
end

--- Get Height between ground and vehicle
---@return number height
function Navigation:GetHeight()
	return self.av_obj:GetPosition().z - self.av_obj:GetGroundPosition()
end


--- Set destination by mappin.
---@param position Vector4
function Navigation:SetMappinDestination(position)
	self.mappin_destination_position = position
end

--- Set registered favorite destination.
---@param position Vector4
function Navigation:SetFavoriteDestination(position)
	self.favorite_destination_position = position
end

--- Excute Auto Pilot.
---@return boolean
function Navigation:AutoPilot()
	self.log_obj:Record(LogLevel.Info, "AutoPilot Start")
	self.av_obj.is_auto_pilot = true
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
		if self.favorite_destination_position:IsZero() then
			self.log_obj:Record(LogLevel.Debug, "No Favorite Destination", "StartAutoPilot")
			self:InterruptAutoPilot()
			return false
		end
		destination_position = self.favorite_destination_position
		self.log_obj:Record(LogLevel.Info, "AutoPilot to Favorite Destination")
	end

	destination_position.z = destination_position.z + self.av_obj.destination_z_offset

	local current_position = self.av_obj:GetPosition()

	local direction_vector = Vector4.new(destination_position.x - current_position.x, destination_position.y - current_position.y, destination_position.z - current_position.z, 1)
	self.initial_destination_length = Vector4.Length(direction_vector)

	-- Store target altitude for maintaining flight height
	local target_altitude
	if self.av_obj.autopilot_is_only_horizontal then
		self:AutoLeaving(direction_vector, self.autopilot_leaving_height - current_position.z)
		target_altitude = self.autopilot_leaving_height
		self.log_obj:Record(LogLevel.Info, "Select Leaving Only Horizontal")
	else
		self:AutoLeaving(direction_vector, self.av_obj.standard_leaving_height)
		-- Keep cruise altitude stable relative to destination, not start position.
		target_altitude = destination_position.z + self.av_obj.standard_leaving_height
		self.log_obj:Record(LogLevel.Info, "Select Leaving Horizontal and Vertical")
	end

	-- Adjust destination altitude to match target flight altitude
	-- Use the HIGHER of flight altitude or actual destination altitude
	-- This prevents downward bias while maintaining safe flight altitude
	local adjusted_z = math.max(destination_position.z, target_altitude)

	local ea_landing_extra_height = 0

	local altitude_adjusted_destination = Vector4.new(
		destination_position.x,
		destination_position.y,
		adjusted_z,  -- Use higher altitude (either flight altitude or destination or EA overshoot)
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
	-- Local-avoidance state reset
	self.local_avoidance_stuck_timer = 0
	self.local_avoidance_stuck_escape_time = 0
	self.local_avoidance_stuck_abort = false
	self.local_avoidance_stuck_needs_replan = false
	self.local_avoidance_net_check_dist = nil
	self.local_avoidance_net_check_time = 0
	-- Yaw smoothing reset
	self.yaw_target_smoothed = nil

	--- NEW: Initialize sector navigation system
	self:InitializeSectorSystem()

	-- Determine navigation phases based on start/destination knowledge
	local ap_start_known = self:IsSectorAreaKnown(current_position)
	local ap_dest_known  = self:IsSectorAreaKnown(altitude_adjusted_destination)
	self.autopilot_scan_dirty_count    = 0
	self.autopilot_scan_last_save_time = os.clock()
	self.autopilot_dest_is_unknown     = not ap_dest_known
	self.astar_local_avoidance_recheck_time    = 0

	if not ap_start_known then
		-- Phase start_local: start is in unknown sector.
		-- Navigate to nearest known sector using local avoidance + scanning, then switch to A*.
		local nearest, dist = self:FindNearestKnownSectorPos(current_position)
		if nearest then
			self.autopilot_phase        = "start_local"
			self.autopilot_local_target = nearest
			self.log_obj:Record(LogLevel.Info, string.format(
				"AutoPilot [start_local]: start in UNKNOWN sector - navigating to nearest known sector (%.0fm away)",
				dist))
		else
			-- No known sectors at all: navigate entire route with local avoidance
			self.autopilot_phase        = "final_local"
			self.autopilot_local_target = altitude_adjusted_destination
			self.log_obj:Record(LogLevel.Info,
				"AutoPilot [final_local]: no known sectors exist - full local avoidance mode")
		end
		self.current_global_route = {}
		self.current_route_index  = 1
	else
		-- Phase astar: start is in known sector - plan an A* route.
		-- If destination is unknown, route to nearest known sector near dest, then final_local.
		self.autopilot_phase        = "astar"
		self.autopilot_local_target = nil
		local astar_dest = altitude_adjusted_destination
		if not ap_dest_known then
			local nearest, dist = self:FindNearestKnownSectorPos(altitude_adjusted_destination)
			if nearest then
				astar_dest = nearest
				self.log_obj:Record(LogLevel.Info, string.format(
					"AutoPilot [astar]: destination UNKNOWN - A* routes to nearest known (%.1f, %.1f, %.1f, %.0fm away), then local avoidance",
					astar_dest.x, astar_dest.y, astar_dest.z, dist))
			else
				-- No known sectors: fallback to full local avoidance
				self.autopilot_phase        = "final_local"
				self.autopilot_local_target = altitude_adjusted_destination
				self.log_obj:Record(LogLevel.Info,
					"AutoPilot [final_local]: no known sectors - full local avoidance mode")
			end
		else
			self.log_obj:Record(LogLevel.Info,
				"AutoPilot [astar]: start and destination both in KNOWN sectors - pure A* navigation")
		end
		if self.autopilot_phase == "astar" then
			self.current_global_route = self:PlanGlobalRoute(current_position, astar_dest)
			self.current_route_index  = 1
		else
			-- final_local fallback
			self.current_global_route = {}
			self.current_route_index  = 1
		end
	end
	self.last_route_plan_time = os.clock()
	self.altitude_adjusted_destination = altitude_adjusted_destination
	-- Save route for external visualization
	self:SaveLastRoute(self.current_global_route, current_position, altitude_adjusted_destination)

	-- autopilot loop
	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1

		if self.av_obj.is_leaving or self.av_obj.core_obj.event_obj:IsInMenuOrPopupOrPhoto() then
			return
		end

		if not self.av_obj.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
			Cron.Halt(timer)
			return
		elseif self:IsCollision() then
			self.log_obj:Record(LogLevel.Info, "Collision Detected")
			self:RecordDirectCollision()
			self:InterruptAutoPilot()
			Cron.Halt(timer)
			return
		end

		-- set destination vector
		current_position = self.av_obj:GetPosition()
		local current_time = os.clock()

		-- === Phase management ===
		-- Transition: start_local -> astar when vehicle enters a known sector.
		if self.autopilot_phase == "start_local" and self:IsSectorAreaKnown(current_position) then
			-- Save suppressed during autopilot to avoid I/O stutter affecting A* route.
			self.autopilot_scan_dirty_count = 0
			self.autopilot_phase        = "astar"
			self.autopilot_local_target = nil
			local astar_dest = altitude_adjusted_destination
			if self.autopilot_dest_is_unknown then
				local nearest = self:FindNearestKnownSectorPos(altitude_adjusted_destination)
				if nearest then astar_dest = nearest end
			end
			self.current_global_route = self:PlanGlobalRoute(current_position, astar_dest)
			self.current_route_index  = 1
			self:SaveLastRoute(self.current_global_route, current_position, altitude_adjusted_destination)
			self.local_avoidance_stuck_timer       = 0
			self.local_avoidance_stuck_escape_time = 0
			self.local_avoidance_net_check_dist    = nil
			self.local_avoidance_net_check_time    = 0
			self.log_obj:Record(LogLevel.Info, "AutoPilot [start_local->astar]: entered known sector, A* route planned")
		end

		-- Scanning: handled entirely by StartObstacleRecording()'s Cron timer.
		-- No per-tick scanning here; the Cron fires every obstacle_record_interval seconds
		-- regardless of driving mode.

		-- Distance to final fly-to point (altitude_adjusted_destination).
		-- When destination is inside an exception area the fly-to point is above
		-- the EA; landing will handle the final descent.
		local ddx = altitude_adjusted_destination.x - current_position.x
		local ddy = altitude_adjusted_destination.y - current_position.y
		local ddz = altitude_adjusted_destination.z - current_position.z
		local horiz_to_final = math.sqrt(ddx*ddx + ddy*ddy)
		local dist_to_final_arr = math.sqrt(ddx*ddx + ddy*ddy + (ddz < 0 and 0 or ddz*ddz))
		-- Always track distance to final destination (not current A* waypoint) for HUD display
		self.dest_remaining_to_final = horiz_to_final

		-- === A* Route Waypoint Following ===
		-- Advance waypoint index when vehicle reaches current waypoint.
		-- This makes the vehicle actually fly along the A*-planned route
		-- instead of heading straight to the final destination.
		-- NOTE: advance threshold uses HORIZONTAL distance only to avoid premature
		-- advancement when the vehicle is still climbing/descending to the waypoint Z.
		local nav_target = altitude_adjusted_destination  -- fallback: aim at flight-altitude dest
		if #self.current_global_route > 0 and horiz_to_final > self.sector_size * 1.5 then
			local advance_thr   = self.sector_size * 0.9   -- ~18 m: advance to next waypoint
			local lookahead_dist = self.sector_size * 2.0  -- ~40 m: start blending toward next WP
			-- Compute horizontal velocity direction (for "passed waypoint" detection)
			local vel = self.av_obj.engine_obj.direction_velocity
			local vel_hx, vel_hy = vel.x, vel.y
			local vel_hlen = math.sqrt(vel_hx*vel_hx + vel_hy*vel_hy)
			while self.current_route_index <= #self.current_global_route do
				local wp_key = self.current_global_route[self.current_route_index]
				local wp_pos = self:SectorKeyToPosition(wp_key)
				if wp_pos then
					local wdx = current_position.x - wp_pos.x  -- vec: wp -> vehicle (X)
					local wdy = current_position.y - wp_pos.y  -- vec: wp -> vehicle (Y)
					local horiz_to_wp = math.sqrt(wdx*wdx + wdy*wdy)  -- horizontal only
					-- "Passed" detection: dot product of (vehicle->wp) with velocity < 0
					-- means the waypoint is now behind or perpendicular to the heading.
					-- This fires when the vehicle turns away from the WP at a sharp corner.
					local passed_wp = false
					if horiz_to_wp < lookahead_dist and vel_hlen > 1.0 then
						-- vehicle->wp = (-wdx, -wdy); dot with velocity direction
						local dot_toward = (-wdx * vel_hx + (-wdy) * vel_hy) / vel_hlen
						passed_wp = (dot_toward < -0.3 * horiz_to_wp)  -- WP clearly behind us
					end
					if horiz_to_wp < advance_thr or passed_wp then
						self.log_obj:Record(LogLevel.Debug, string.format(
							"Route: waypoint %d/%d reached (%s, dist=%.1fm, passed=%s), advancing",
							self.current_route_index, #self.current_global_route, wp_key,
							horiz_to_wp, tostring(passed_wp)))
						self.current_route_index = self.current_route_index + 1
					else
						-- Lookahead blending: when approaching a waypoint, smoothly blend
						-- nav_target toward the *next* waypoint to avoid sharp corners.
						nav_target = wp_pos
						if horiz_to_wp < lookahead_dist and self.current_route_index < #self.current_global_route then
							local next_key = self.current_global_route[self.current_route_index + 1]
							local next_pos = self:SectorKeyToPosition(next_key)
							if next_pos then
								-- blend=0 when far (aim at current WP), blend=1 when near advance_thr (aim at next WP)
								local blend = (1.0 - (horiz_to_wp - advance_thr) / (lookahead_dist - advance_thr))
								blend = math.max(0.0, math.min(1.0, blend))
								nav_target = Vector4.new(
									wp_pos.x + (next_pos.x - wp_pos.x) * blend,
									wp_pos.y + (next_pos.y - wp_pos.y) * blend,
									wp_pos.z + (next_pos.z - wp_pos.z) * blend,
									1)
							end
						end
						break
					end
				else
					self.current_route_index = self.current_route_index + 1
				end
			end
			-- All waypoints passed: aim directly at the flight-altitude destination.
			if self.current_route_index > #self.current_global_route then
				nav_target = altitude_adjusted_destination
				-- Partial route exhausted: replan A* from current position.
				-- Only continue A* if new route brings us >= 50m closer to destination.
				-- Otherwise switch to local avoidance (astar_local_avoidance phase).
				if self.astar_is_partial_route
					and horiz_to_final > self.sector_size * 2 then
					local replan_dest = altitude_adjusted_destination
					if self.autopilot_dest_is_unknown then
						local nearest = self:FindNearestKnownSectorPos(altitude_adjusted_destination)
						if nearest then replan_dest = nearest end
					end
					local new_route = self:PlanGlobalRoute(current_position, replan_dest)
					self.last_route_plan_time = os.clock()
					-- Measure progress: how much closer does new route's terminal get us?
					local dist_gained = 0
					if #new_route > 0 then
						local last_wp_pos = self:SectorKeyToPosition(new_route[#new_route])
						if last_wp_pos then
							local ldx = replan_dest.x - last_wp_pos.x
							local ldy = replan_dest.y - last_wp_pos.y
							dist_gained = horiz_to_final - math.sqrt(ldx*ldx + ldy*ldy)
						end
					end
					if dist_gained >= 50 then
						-- New route makes meaningful progress: stay in A* phase.
						self.current_global_route = new_route
						self.current_route_index  = 1
						self:SaveLastRoute(new_route, current_position, altitude_adjusted_destination)
						self.log_obj:Record(LogLevel.Info, string.format(
							"A* partial replan: %d waypoints, gained %.0fm (horiz_to_final=%.0fm)",
							#new_route, dist_gained, horiz_to_final))
					else
						-- Route makes no significant progress: fall back to local avoidance.
						self.autopilot_phase           = "astar_local_avoidance"
						self.astar_local_avoidance_recheck_time = os.clock()
						self.current_global_route      = {}
						self.current_route_index       = 1
						self.local_avoidance_stuck_timer       = 0
						self.local_avoidance_stuck_escape_time = 0
						self.local_avoidance_net_check_dist    = nil
						self.local_avoidance_net_check_time    = 0
						self.log_obj:Record(LogLevel.Info, string.format(
							"A* partial replan gained only %.0fm (<50m) - switching to local avoidance (horiz_to_final=%.0fm)",
							dist_gained, horiz_to_final))
					end
				end
			end
		end

		-- Empty-route retry: A* previously returned {} (no viable path found within iteration limit).
		-- Apply same 50m-progress check: if new route doesn't advance us, switch to astar_local_avoidance.
		-- 1s cooldown prevents per-tick A* thrashing when route stays empty.
		if self.astar_is_partial_route
			and #self.current_global_route == 0
			and horiz_to_final > self.sector_size * 2
			and self.autopilot_phase == "astar"
			and (os.clock() - self.last_route_plan_time) > 1.0 then
			local replan_dest = altitude_adjusted_destination
			if self.autopilot_dest_is_unknown then
				local nearest = self:FindNearestKnownSectorPos(altitude_adjusted_destination)
				if nearest then replan_dest = nearest end
			end
			local new_route = self:PlanGlobalRoute(current_position, replan_dest)
			self.last_route_plan_time = os.clock()
			local dist_gained = 0
			if #new_route > 0 then
				local last_wp_pos = self:SectorKeyToPosition(new_route[#new_route])
				if last_wp_pos then
					local ldx = replan_dest.x - last_wp_pos.x
					local ldy = replan_dest.y - last_wp_pos.y
					dist_gained = horiz_to_final - math.sqrt(ldx*ldx + ldy*ldy)
				end
			end
			if dist_gained >= 50 then
				self.current_global_route = new_route
				self.current_route_index  = 1
				self.log_obj:Record(LogLevel.Info, string.format(
					"A* empty-route retry: %d waypoints, gained %.0fm",
					#new_route, dist_gained))
			else
				self.autopilot_phase           = "astar_local_avoidance"
				self.astar_local_avoidance_recheck_time = os.clock()
				self.current_global_route      = {}
				self.current_route_index       = 1
				self.local_avoidance_stuck_timer       = 0
				self.local_avoidance_stuck_escape_time = 0
				self.local_avoidance_net_check_dist    = nil
				self.local_avoidance_net_check_time    = 0
				self.log_obj:Record(LogLevel.Info, string.format(
					"A* empty-route retry: no progress (gained=%.0fm) - switching to local avoidance",
					dist_gained))
			end
		end

		-- === astar_local_avoidance phase: local-avoidance fallback while A* can't make progress ===
		-- Every 5s, if current sector is known, replan A* and resume if progress >= 50m.
		if self.autopilot_phase == "astar_local_avoidance"
			and horiz_to_final > self.sector_size * 2
			and (os.clock() - self.astar_local_avoidance_recheck_time) > 5.0 then
			self.astar_local_avoidance_recheck_time = os.clock()
			if self:IsSectorAreaKnown(current_position) then
				local replan_dest = altitude_adjusted_destination
				if self.autopilot_dest_is_unknown then
					local nearest = self:FindNearestKnownSectorPos(altitude_adjusted_destination)
					if nearest then replan_dest = nearest end
				end
				local new_route = self:PlanGlobalRoute(current_position, replan_dest)
				self.last_route_plan_time = os.clock()
				local dist_gained = 0
				if #new_route > 0 then
					local last_wp_pos = self:SectorKeyToPosition(new_route[#new_route])
					if last_wp_pos then
						local ldx = replan_dest.x - last_wp_pos.x
						local ldy = replan_dest.y - last_wp_pos.y
						dist_gained = horiz_to_final - math.sqrt(ldx*ldx + ldy*ldy)
					end
				end
				if dist_gained >= 50 then
					self.autopilot_phase      = "astar"
					self.current_global_route = new_route
					self.current_route_index  = 1
					self.log_obj:Record(LogLevel.Info, string.format(
						"astar_local_avoidance -> astar: replan gained %.0fm (%d waypoints)",
						dist_gained, #new_route))
				else
					self.log_obj:Record(LogLevel.Info, string.format(
						"astar_local_avoidance recheck: gained only %.0fm (<50m), continue local avoidance",
						dist_gained))
				end
			else
				self.log_obj:Record(LogLevel.Debug,
					"astar_local_avoidance recheck: current sector unknown, continue local avoidance")
			end
		end

		-- start_local: override nav_target to the nearest known sector (local intermediate target)
		if self.autopilot_phase == "start_local" and self.autopilot_local_target then
			nav_target = self.autopilot_local_target
		end

		-- Phase transition: astar -> final_local when A* route is exhausted and destination is unknown.
		if self.autopilot_phase == "astar"
			and self.autopilot_dest_is_unknown
			and self.current_route_index > #self.current_global_route
			and horiz_to_final > self.sector_size then
			self.autopilot_phase           = "final_local"
			self.local_avoidance_stuck_timer       = 0
			self.local_avoidance_stuck_escape_time = 0
			self.local_avoidance_net_check_dist    = nil
			self.local_avoidance_net_check_time    = 0
			self.log_obj:Record(LogLevel.Info,
				"AutoPilot [astar->final_local]: A* route complete, switching to local avoidance for final leg")
		end

		-- Calculate destination vector toward current nav target (A* waypoint or final dest)
		local dest_dir_vector = Vector4.new(
			nav_target.x - current_position.x,
			nav_target.y - current_position.y,
			nav_target.z - current_position.z, 1)
		if self.av_obj.autopilot_is_only_horizontal then
			dest_dir_vector.z = 0
		end
		-- dest_dir_vector_norm: distance to current nav target (waypoint or final dest)
		self.dest_dir_vector_norm = Vector4.Length(dest_dir_vector)

		-- Update exception area bypass status based on distance to destination
		self:UpdateExceptionAreaBypass()

		-- check destination: use horizontal + upward-only Z so that being above target
		-- at flight altitude doesn't prevent arrival detection
		if dist_to_final_arr < self.av_obj.destination_range then
			self.log_obj:Record(LogLevel.Info, "Arrived at destination")
			self.av_obj.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			-- Landing height: distance from current Z to the ORIGINAL ground destination,
			-- including any extra altitude added for exception area overshoot.
			local landing_height = current_position.z - destination_position.z + self.av_obj.destination_z_offset
			self.log_obj:Record(LogLevel.Info, string.format(
				"Landing: current_z=%.1f, dest_z=%.1f, ea_extra=%.1f, landing_height=%.1f",
				current_position.z, destination_position.z, ea_landing_extra_height, landing_height))
			self:AutoLanding(landing_height, destination_position.z)
			Cron.Halt(timer)
			return
		end

		-- Navigation: A* phase follows waypoints directly (no local avoidance).
		-- Local phases (start_local / final_local) use local-avoidance navigation.
		-- Exception: when A* returned an empty route (no path found within iteration limit),
		-- use local-avoidance navigation while waiting for the next A* retry (every 5 s).
		local navigation_vector
		if self.autopilot_phase == "astar" and #self.current_global_route > 0 then
			-- Pure A* waypoint following
			local dv_len = Vector4.Length(dest_dir_vector)
			if dv_len > 0.001 then
				navigation_vector = Vector4.new(
					dest_dir_vector.x / dv_len,
					dest_dir_vector.y / dv_len,
					dest_dir_vector.z / dv_len, 0)
			else
				navigation_vector = dest_dir_vector
			end
			self.auto_speed_reduce_rate = 0.7
		else
			-- Local avoidance phase (or A* empty-route fallback)
			navigation_vector = self:ComputeLocalAvoidanceDirection(current_position, dest_dir_vector, current_time)
		end

		-- Handle local-avoidance stuck-escape flags.
		if self.local_avoidance_stuck_abort then
			self.local_avoidance_stuck_abort       = false
			self.local_avoidance_stuck_timer       = 0
			self.local_avoidance_stuck_escape_time = 0
			self.log_obj:Record(LogLevel.Warning, "AutoPilot: aborting due to stuck escape failure")
			self:InterruptAutoPilot()
			Cron.Halt(timer)
			return
		end
		if self.local_avoidance_stuck_needs_replan then
			self.local_avoidance_stuck_needs_replan = false
			self.local_avoidance_net_check_dist     = nil  -- reset stuck baseline after replan
			self.local_avoidance_net_check_time     = 0
			-- After escaping stuck, switch to A* if current position is now in known territory
			if self:IsSectorAreaKnown(current_position) then
				self.autopilot_phase        = "astar"
				self.autopilot_local_target = nil
				local astar_dest = altitude_adjusted_destination
				if self.autopilot_dest_is_unknown then
					local nearest = self:FindNearestKnownSectorPos(altitude_adjusted_destination)
					if nearest then astar_dest = nearest end
				end
				self.current_global_route = self:PlanGlobalRoute(current_position, astar_dest)
				self.current_route_index  = 1
				self:SaveLastRoute(self.current_global_route, current_position, altitude_adjusted_destination)
				self.log_obj:Record(LogLevel.Info, "AutoPilot: stuck escape complete - switched to A*")
			else
				self.current_global_route = {}
				self.current_route_index  = 1
				self.log_obj:Record(LogLevel.Info, "AutoPilot: stuck escape complete, continuing local avoidance")
			end
		end

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
		
		-- Combine with proximity-based speed from local avoidance (take the more conservative value)
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
		local vehicle_angle = self.av_obj:GetForward()
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
		-- Shortest-path angular blend (handle 180 deg wrap)
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
		local current_angle = self.av_obj:GetEulerAngles()
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
		if self.av_obj.engine_obj.flight_mode == Def.FlightMode.Helicopter then
			forward_value = math.cos(between_angle_rad)
			local _, _, _, roll_diff_forward, pitch_diff_forward, _ = self.av_obj.engine_obj:CalculateAddVelocity({Def.ActionList.HLeanForward, forward_value})
			left_right_value = math.sin(between_angle_rad)
			local roll_control = {}
			if left_right_value >= 0 then
				roll_control = {Def.ActionList.HLeanLeft, left_right_value}
			else
				roll_control = {Def.ActionList.HLeanRight, -left_right_value}
			end
			local _, _, _, roll_diff_left_right, pitch_diff_left_right, _ = self.av_obj.engine_obj:CalculateAddVelocity(roll_control)
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
			local _, _, _, roll_diff_left_right, pitch_diff_left_right, _ = self.av_obj.engine_obj:CalculateAddVelocity(roll_control)
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
			_, _, _, roll ,pitch ,yaw = self.av_obj.engine_obj:CalculateAddVelocity({Def.ActionList.Idle, 1})
		end

		-- limit
		if current_angle.roll > self.av_obj.engine_obj.max_roll or current_angle.roll < -self.av_obj.engine_obj.max_roll then
			roll = 0
		end
		if current_angle.pitch > self.av_obj.engine_obj.max_pitch or current_angle.pitch < -self.av_obj.engine_obj.max_pitch then
			pitch = 0
		end

		-- Prevent FluctuationVelocity oscillation at target speed during movement
		-- Temporarily increase target velocity margin to avoid 50m/s oscillation
		local current_velocity = Vector4.Vector3To4(self.av_obj.engine_obj.direction_velocity):Length()
		if math.abs(current_velocity - self.autopilot_speed) < 1.0 then  -- Near target speed
			local original_target = self.av_obj.engine_obj.target_velocity
			-- Temporarily set higher target to prevent oscillation
			self.av_obj.engine_obj.target_velocity = self.autopilot_speed * 1.05
			if not self.av_obj.engine_obj:Run(adjust_x, adjust_y, adjust_z, roll, pitch, yaw) then
				self.log_obj:Record(LogLevel.Warning, "Failed to run engine in Autopilot (overshoot prevention)")
			end
			-- Restore original target after run
			self.av_obj.engine_obj.target_velocity = original_target
		else
			if not self.av_obj.engine_obj:Run(adjust_x, adjust_y, adjust_z, roll, pitch, yaw) then
				self.log_obj:Record(LogLevel.Warning, "Failed to run engine in Autopilot")
			end
		end
	end)
	return true
end

--- Excute Leaving when auto pilot is on.
---@param dist_vector Vector4 vector to destination position
---@param height number | nil height to end leaving
function Navigation:AutoLeaving(dist_vector, height)
	self.av_obj.is_leaving = true

	local current_position = self.av_obj:GetPosition()
	local leaving_height = height or self.autopilot_leaving_height - current_position.z
	local leaving_position = Vector4.new(current_position.x, current_position.y, current_position.z + leaving_height, 1)
	self.av_obj.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0.5))
	self.av_obj.engine_obj:SetAngularVelocity(Vector3.new(0, 0, 0))
	self.av_obj.engine_obj:SetFluctuationVelocityParams(self.autopilot_acceleration, self.autopilot_speed)
	self.autopilot_leaving_deceleration_start_flag = false
	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		timer.tick = timer.tick + 1
		if not self.av_obj.is_auto_pilot then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted")
			self.av_obj.is_leaving = false
			Cron.Halt(timer)
			return
		elseif self:IsCollision() then
			self.log_obj:Record(LogLevel.Info, "Collision Detected")
			self:RecordDirectCollision()
			self:InterruptAutoPilot()
			self.av_obj.is_leaving = false
			Cron.Halt(timer)
			return
		end

		-- Stabilize roll and pitch during takeoff
		local _, _, _, roll_idle ,pitch_idle ,yaw_idle = self.av_obj.engine_obj:CalculateAddVelocity({Def.ActionList.Idle, 1})
		if not self.av_obj.engine_obj:OnlyAngularRun(roll_idle, pitch_idle, yaw_idle) then
			self.log_obj:Record(LogLevel.Warning, "Failed to run angular velocity during takeoff")
		end

		local is_detected_celling, search_vector = self:IsWall(Vector4.new(0, 0, 1, 1), self.av_obj.check_cell_distance, 0, "Vertical", true, "simple")
		if is_detected_celling then
			self.log_obj:Record(LogLevel.Info, "Detected Ceiling, Search Vector:" .. search_vector.x .. ", " .. search_vector.y .. ", " .. search_vector.z)
		end
		local current_position_in_leaving = self.av_obj:GetPosition()

		if current_position_in_leaving.z > leaving_position.z or is_detected_celling then
			self.av_obj.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
			self.av_obj.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			self.av_obj.engine_obj:SetAngularVelocity(Vector3.new(0, 0, 0))
			Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
				timer.tick = timer.tick + 1
				if not self.av_obj.is_auto_pilot then
					self.log_obj:Record(LogLevel.Info, "AutoPilot Interrupted by Canceling")
					self.av_obj.is_leaving = false
					Cron.Halt(timer)
					return
				elseif self:IsCollision() then
					self.log_obj:Record(LogLevel.Info, "Collision Detected")
					self:RecordDirectCollision()
					self:InterruptAutoPilot()
					self.av_obj.is_leaving = false
					Cron.Halt(timer)
					return
				end

				-- yaw control
				local vehicle_angle = self.av_obj:GetForward()
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

				if not self.av_obj.engine_obj:Run(0.0, 0.0, 0.0, 0.0, 0.0, yaw_diff_half) then
					self.log_obj:Record(LogLevel.Warning, "Failed to run engine during leaving")
				end

				if math.abs(yaw_diff_half) < 0.1 then
					if not self.av_obj.engine_obj:Run(0.0, 0.0, 0.0, 0.0, 0.0, 0.0) then
						self.log_obj:Record(LogLevel.Warning, "Failed to run engine at leaving end")
					end
					self.av_obj.is_leaving = false
					Cron.Halt(timer)
				end
			end)
			Cron.Halt(timer)
		elseif current_position_in_leaving.z > leaving_position.z - (leaving_height * 0.3) and not self.autopilot_leaving_deceleration_start_flag then
			self.autopilot_leaving_deceleration_start_flag = true
			self.av_obj.engine_obj:SetFluctuationVelocityParams(-self.autopilot_acceleration, self.autopilot_speed * 0.2)
		end
		self.av_obj:MoveThruster({{Def.ActionList.Nothing, 1}})
	end)
end

--- Excute Landing when auto pilot is on.
--- @param height number height to start landing
--- @param target_z number|nil target altitude (destination Z); if provided, stop descending at this Z
function Navigation:AutoLanding(height, target_z)
	local down_time_count = ((height / self.autopilot_speed) / DAV.time_resolution) * 1.8
	self.log_obj:Record(LogLevel.Info, "AutoPilot Landing Start :" .. tostring(down_time_count) .. "s, " .. tostring(height) .. "m" .. (target_z and string.format(", target_z=%.1f", target_z) or ""))
	self.av_obj.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
	self.av_obj.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, -0.5))
	self.av_obj.engine_obj:SetAngularVelocity(Vector3.new(0, 0, 0))
	self.autopilot_leaving_deceleration_start_flag = false
	Cron.Every(DAV.time_resolution, {tick = 1}, function(timer)
		if not self.av_obj.is_auto_pilot then
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
		local _, _, _, roll_idle ,pitch_idle ,yaw_idle = self.av_obj.engine_obj:CalculateAddVelocity({Def.ActionList.Idle, 1})
		if not self.av_obj.engine_obj:OnlyAngularRun(roll_idle, pitch_idle, yaw_idle) then
			self.log_obj:Record(LogLevel.Warning, "Failed to run angular velocity during landing")
		end

		local is_detected_ground, search_vector = self:IsWall(Vector4.new(0, 0, -1, 1), self.av_obj.minimum_distance_to_ground - 0.2, 0, "Vertical", false, "simple")
		if is_detected_ground then
			self.log_obj:Record(LogLevel.Info, "Detected Ground, Search Vector:" .. search_vector.x .. ", " .. search_vector.y .. ", " .. search_vector.z)
		end

		if timer.tick == 1 then
			self.av_obj.engine_obj:SetFluctuationVelocityParams(self.autopilot_acceleration, self.autopilot_speed)
		elseif target_z and self.av_obj:GetPosition().z <= target_z + self.av_obj.minimum_distance_to_ground then
			-- Reached destination altitude: stop here even if physical ground is lower.
			self.log_obj:Record(LogLevel.Info, string.format(
				"AutoPilot Success: reached destination altitude (current_z=%.1f, target_z=%.1f)",
				self.av_obj:GetPosition().z, target_z))
			self.av_obj.is_landed = true
			self.av_obj.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
			self.av_obj.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			self:SuccessAutoPilot()
			Cron.Halt(timer)
		elseif timer.tick > down_time_count then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Success for timeout")
			self.av_obj.is_landed = true
			self.av_obj.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
			self.av_obj.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			self:SuccessAutoPilot()
			Cron.Halt(timer)
		elseif self:GetHeight() < self.av_obj.minimum_distance_to_ground then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Success for minimum_height")
			self.av_obj.is_landed = true
			self.av_obj.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
			self.av_obj.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			self:SuccessAutoPilot()
			Cron.Halt(timer)
		elseif self:IsCollision() or is_detected_ground then
			self.log_obj:Record(LogLevel.Info, "AutoPilot Success for Collision or Ground Detection")
			self.av_obj.is_landed = true
			self.av_obj.engine_obj:SetControlType(Def.EngineControlType.ChangeVelocity)
			self.av_obj.engine_obj:SetDirectionVelocity(Vector3.new(0, 0, 0))
			self:SuccessAutoPilot()
			Cron.Halt(timer)
		elseif self:GetHeight() <= deceleration_height and not self.autopilot_leaving_deceleration_start_flag then
			self.autopilot_leaving_deceleration_start_flag = true
			self.av_obj.engine_obj:SetFluctuationVelocityParams(-self.autopilot_acceleration * deceleration_rate, self.autopilot_speed * 0.2)
		end

		self.av_obj:MoveThruster({{Def.ActionList.Nothing, 1}})

		timer.tick = timer.tick + 1
	end)
end

--- Set AV.is_failture_auto_pilot and AV.is_auto_pilot when AutoPilot Success.

function Navigation:SuccessAutoPilot()
	self.av_obj.is_auto_pilot = false
	self.is_failture_auto_pilot = false
	self.av_obj.core_obj:SetAutoPilotHistory()
	-- Release per-flight caches to prevent memory accumulation.
	self.iswall_cache           = {}
	self.safe_streak_count      = 0
	self.current_global_route   = {}
	self.sector_penalty_cache   = nil
	-- Consolidate learning data
	self.av_obj:ConsolidateMemory()
end

--- Set AV.is_failture_auto_pilot and AV.is_auto_pilot when AutoPilot Failed.

function Navigation:InterruptAutoPilot()
	self.av_obj.is_auto_pilot = false
	self.is_failture_auto_pilot = true
	-- Release per-flight caches to prevent memory accumulation.
	self.iswall_cache           = {}
	self.safe_streak_count      = 0
	self.current_global_route   = {}
	self.sector_penalty_cache   = nil
	-- Consolidate learning data (failures are important for learning)
	self.av_obj:ConsolidateMemory()
end

--- Set AV.is_failture_auto_pilot and get Failture AutoPilot Flag.
---@return boolean
function Navigation:IsFailedAutoPilot()
	local is_failture_auto_pilot = self.is_failture_auto_pilot
	self.is_failture_auto_pilot = false
	return is_failture_auto_pilot
end

--- Apply autopilot parameters derived from user_setting_table.autopilot_speed.

function Navigation:ApplyAutopilotSpeed()
	-- Clamp to valid range (5-50). Old saves may have values outside this range.
	local speed = math.min(50, math.max(5, DAV.user_setting_table.autopilot_speed or 25))
	self.autopilot_speed            = speed
	-- Acceleration: 1.0 at 10 m/s to 3.0 at 48 m/s (linear)
	self.autopilot_acceleration     = math.max(1.0, speed * 0.063)
	-- Turn speed: 0.010 at 10 m/s to 0.030 at 48 m/s (linear)
	self.autopilot_turn_speed       = 0.01 + math.max(0, speed - 10) * 0.000526
	-- Leaving height: 20 m minimum, scales with speed
	self.autopilot_leaving_height   = math.max(20, speed * 2.0)
	-- Fixed search params
	self.autopilot_searching_range  = 96
	self.autopilot_searching_step   = math.max(5, math.floor(speed / 5))
	self.autopilot_min_speed_rate   = 0.4
	self.av_obj.autopilot_is_only_horizontal = false
end

--- Reload autopilot settings (called from UI settings callback).

function Navigation:ReloadAutopilotProfile()
	self:ApplyAutopilotSpeed()
end

--- Get Player Around Direction (for spawn position)
---@param angle number
function Navigation:GetPlayerAroundDirection(angle)
	local player = Game.GetPlayer()
	if player == nil then
		self.log_obj:Record(LogLevel.Warning, "Player is nil in GetPlayerAroundDirection")
		return Vector4.new(0, 0, 0, 1.0)
	end
	return Vector4.RotateAxis(player:GetWorldForward(), Vector4.new(0, 0, 1, 0), angle / 180.0 * Pi())
end

--- Check Player in Exception Area
---@param position Vector4
---@return boolean is_in_area If or not in exception area
---@return string tag Tag
---@return number z max height of exception area
function Navigation:IsInExceptionArea(position)
	-- Exception-area system disabled.
	return false, "None", 0
end

--- This function returns collision status.
---@return boolean
function Navigation:IsCollision()
	return self.av_obj.engine_obj:IsOnGround()
end

-- Update exception area bypass status based on distance to destination

function Navigation:UpdateExceptionAreaBypass()
	self.is_exception_area_bypassed = false
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
function Navigation:IsWall(dir_vec, distance, angle, swing_direction, is_check_exception_area, collision_mode)
	-- Cache system: greatly reduces computation when no obstacle is present
	local current_time = Game.GetTimeSystem():GetGameTimeStamp()
	local current_position = self.av_obj:GetPosition()

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

	-- Evict cache when it grows too large to prevent memory accumulation.
	-- 500 entries covers ~30s of normal flight; older entries are already stale.
	if self.iswall_cache_size and self.iswall_cache_size > 500 then
		self.iswall_cache      = {}
		self.iswall_cache_size = 0
		self.safe_streak_count = 0
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

		local adaptive_distance = distance * (1 + math.min(Vector4.Vector3To4(self.av_obj.engine_obj.direction_velocity):Length() / 20.0, 2.0) * 0.4)
		local target_pos = Vector4.new(
			raycast_start_pos.x + adaptive_distance * search_vec.x,
			raycast_start_pos.y + adaptive_distance * search_vec.y,
			raycast_start_pos.z + adaptive_distance * search_vec.z,
			1.0
		)

		if self.av_obj.collision_query_filter == nil then
			self.av_obj:InitializeCollisionQueryFilter()
		end
		local is_success, _ = Game.GetSpatialQueriesSystem():SyncRaycastByQueryFilter(
			raycast_start_pos, target_pos, self.av_obj.collision_query_filter, false, false)
		if is_success then
			self.safe_streak_count = 0  -- Reset
			self.log_obj:Record(LogLevel.Trace, "Simple check - Wall Detected")
			-- Save to cache
			if not self.iswall_cache[cache_key] then
				self.iswall_cache_size = (self.iswall_cache_size or 0) + 1
			end
			self.iswall_cache[cache_key] = {
				result = true,
				search_vec = search_vec,
				timestamp = current_time,
				position = current_position
			}
			return true, search_vec
		end

		self.safe_streak_count = self.safe_streak_count + 1
		self.log_obj:Record(LogLevel.Trace, "Simple check - Safe (streak: " .. self.safe_streak_count .. ")")
		-- Save to cache
		if not self.iswall_cache[cache_key] then
			self.iswall_cache_size = (self.iswall_cache_size or 0) + 1
		end
		self.iswall_cache[cache_key] = {
			result = false,
			search_vec = search_vec,
			timestamp = current_time,
			position = current_position
		}
		return false, search_vec
	end

	-- Optimized detection with balanced performance and coverage
	local current_speed = Vector4.Vector3To4(self.av_obj.engine_obj.direction_velocity):Length()
	local speed_factor = math.min(current_speed / 20.0, 2.0)

	local detection_step = self.collision_check_side_distance

	-- Stepwise grid detection system: 3D positioning with right, forward, and up offsets
	local function check_collision_at_point(offset_right, offset_forward, offset_up)
		offset_up = offset_up or 0  -- Default to 0 if not provided for backward compatibility
		local current_position = self.av_obj:GetPosition()

		-- Calculate position offset: right_vec for left-right, dir_base_vec for front-back, up_vec for up-down
		current_position.x = current_position.x + right_vec.x * offset_right + dir_base_vec.x * offset_forward + up_vec.x * offset_up
		current_position.y = current_position.y + right_vec.y * offset_right + dir_base_vec.y * offset_forward + up_vec.y * offset_up
		current_position.z = current_position.z + right_vec.z * offset_right + dir_base_vec.z * offset_forward + up_vec.z * offset_up

		-- Ground proximity protection: Prevent raycast start points from going below ground during upward checks
		-- if swing_direction == "Vertical" and angle >= 0 then  -- Upward vertical check
		--     local base_position = self.av_obj:GetPosition()  -- Original vehicle position
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

		if self.av_obj.collision_query_filter == nil then
			self.av_obj:InitializeCollisionQueryFilter()
		end
		local is_success, _ = Game.GetSpatialQueriesSystem():SyncRaycastByQueryFilter(
			current_position, target_pos, self.av_obj.collision_query_filter, false, false)
		if is_success then
			self.log_obj:Record(LogLevel.Trace, "Wall Detected")
			return true
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
			if not self.iswall_cache[cache_key] then
				self.iswall_cache_size = (self.iswall_cache_size or 0) + 1
			end
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
				if not self.iswall_cache[cache_key] then
					self.iswall_cache_size = (self.iswall_cache_size or 0) + 1
				end
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
			if not self.iswall_cache[cache_key] then
				self.iswall_cache_size = (self.iswall_cache_size or 0) + 1
			end
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
	if not self.iswall_cache[cache_key] then
		self.iswall_cache_size = (self.iswall_cache_size or 0) + 1
	end
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

--- Check if the sector containing position has any obstacle_map data (known territory).
--- Returns true if at least one cell in this sector exists in obstacle_map.
---@param position Vector4 World position
---@return boolean
function Navigation:IsSectorAreaKnown(position)
	if not position then return false end
	local cs = self.obstacle_cell_size
	local ss = self.sector_size
	local tx = math.floor(position.x / ss)
	local ty = math.floor(position.y / ss)
	local tz = math.floor(position.z / ss)
	-- Sample 8 corner cells of this sector (2x2x2).
	for _, fx in ipairs({0.2, 0.8}) do
		for _, fy in ipairs({0.2, 0.8}) do
			for _, fz in ipairs({0.2, 0.8}) do
				local ckey = math.floor((tx+fx)*ss/cs) .. "_"
							.. math.floor((ty+fy)*ss/cs) .. "_"
							.. math.floor((tz+fz)*ss/cs)
				if self.obstacle_map[ckey] ~= nil then
					return true
				end
			end
		end
	end
	return false
end

--- Find the position of the nearest known sector to a given world position.
--- Iterates over all scanned obstacle cells, converts them to sectors, and returns
--- the sector centre closest to target_pos.
---@param target_pos Vector4 Reference world position
---@return Vector4|nil nearest_pos  Centre of nearest known sector (nil if map is empty)
---@return number      best_dist    Distance to that sector (math.huge if none found)
function Navigation:FindNearestKnownSectorPos(target_pos)
	if not target_pos then return nil, math.huge end
	local ss = self.sector_size
	local cs = self.obstacle_cell_size
	local best_pos  = nil
	local best_dist = math.huge
	local seen = {}
	for ckey, _ in pairs(self.obstacle_map) do
		local cx, cy, cz = ckey:match("([^_]+)_([^_]+)_([^_]+)")
		if cx then
			cx, cy, cz = tonumber(cx), tonumber(cy), tonumber(cz)
			-- World position of cell centre
			local wx = (cx + 0.5) * cs
			local wy = (cy + 0.5) * cs
			local wz = (cz + 0.5) * cs
			-- Sector index that cell belongs to
			local sx = math.floor(wx / ss)
			local sy = math.floor(wy / ss)
			local sz = math.floor(wz / ss)
			local skey = sx .. "_" .. sy .. "_" .. sz
			if not seen[skey] and sz > 0 then  -- skip underground sectors
				seen[skey] = true
				local spos = Vector4.new((sx + 0.5)*ss, (sy + 0.5)*ss, (sz + 0.5)*ss, 1)
				local dx = spos.x - target_pos.x
				local dy = spos.y - target_pos.y
				local dz = spos.z - target_pos.z
				local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
				if dist < best_dist then
					best_dist = dist
					best_pos  = spos
				end
			end
		end
	end
	return best_pos, best_dist
end

--- Initialize Sector Navigation System

function Navigation:InitializeSectorSystem()
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

function Navigation:GenerateSphericalRayPattern()
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

-- Route planning methods are defined in Modules/navigation.lua and attached to AV.

--- 3D local-avoidance raycast helper around center_dir
--- Returns min distance hit among all rays, and the averaged normal of blocked rays
--- half_angle_deg: cone half-angle in degrees, n_rings: 1=center only, 2=center+ring
function Navigation:RaycastDist(from_pos, dir_normalized, max_dist)
	if not from_pos or not dir_normalized then return max_dist end
	local target = Vector4.new(
		from_pos.x + dir_normalized.x * max_dist,
		from_pos.y + dir_normalized.y * max_dist,
		from_pos.z + dir_normalized.z * max_dist, 1)
	if self.av_obj.collision_query_filter == nil then
		self.av_obj:InitializeCollisionQueryFilter()
	end
	local hit, result = Game.GetSpatialQueriesSystem():SyncRaycastByQueryFilter(
		from_pos, target, self.av_obj.collision_query_filter, false, false)
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
	return max_dist, nil
end

-- Obstacle map persistence/recording methods are defined in Modules/navigation.lua and attached to AV.

--- Local-avoidance main navigation function
--- Returns normalized Vector4 movement direction for this tick
function Navigation:ComputeLocalAvoidanceDirection(current_pos, dest_dir_vec, current_time)
	if not current_pos or not dest_dir_vec then
		return Vector4.new(1, 0, 0, 0)
	end

	-- Near-goal guard: in final_local phase, avoid triggering stuck-escape ascent
	-- right before arrival. This keeps the last meters stable and prevents
	-- emergency-looking upward maneuvers just before landing.
	local near_final_local_goal = false
	if self.autopilot_phase == "final_local" then
		local near_goal_dist = math.max((self.av_obj.destination_range or 0) * 2.0, self.sector_size * 0.6)
		local remaining_horiz = self.dest_remaining_to_final or math.huge
		if remaining_horiz <= near_goal_dist then
			near_final_local_goal = true
		end
	end

	-- Normalize destination direction
	local dest_len = math.sqrt(dest_dir_vec.x^2 + dest_dir_vec.y^2 + dest_dir_vec.z^2)
	if dest_len < 0.001 then return Vector4.new(1, 0, 0, 0) end
	local dest_dir = Vector4.new(
		dest_dir_vec.x / dest_len,
		dest_dir_vec.y / dest_len,
		dest_dir_vec.z / dest_len, 0)

	-- Stuck detection every 2 seconds using net progress toward the destination.
	-- If progress is less than 2 m in 2 s, accumulate stuck time.
	-- If progress is greater than 10 m in 2 s, fully reset stuck state.
	-- This accumulates in both DIRECT and BOUNDARY modes to prevent endless loops.
	local stuck_check_interval = 2.0
	local stuck_progress_threshold = -2.0   -- insufficient progress if not at least 2m closer in 2s
	local stuck_reset_threshold    = -10.0  -- full reset when at least 10m closer in 2s
	if near_final_local_goal then
		self.local_avoidance_stuck_timer       = 0
		self.local_avoidance_stuck_escape_time = 0
		self.local_avoidance_stuck_abort       = false
		self.local_avoidance_stuck_needs_replan = false
		self.local_avoidance_net_check_dist    = dest_len
		self.local_avoidance_net_check_time    = current_time
	elseif self.local_avoidance_net_check_dist == nil then
		self.local_avoidance_net_check_dist = dest_len
		self.local_avoidance_net_check_time = current_time
	elseif current_time - self.local_avoidance_net_check_time >= stuck_check_interval then
		local dist_change = dest_len - self.local_avoidance_net_check_dist  -- positive=farther, negative=closer

		if dist_change <= stuck_reset_threshold then
			-- Strong progress (>=10m in 2s): fully reset stuck state.
			if self.local_avoidance_stuck_timer > 0 then
				self.log_obj:Record(LogLevel.Debug, string.format(
					"StuckDetect: good progress %.1fm, resetting stuck timer (was %.0fs)",
					-dist_change, self.local_avoidance_stuck_timer))
			end
			self.local_avoidance_stuck_timer       = 0
			self.local_avoidance_stuck_escape_time = 0
		elseif dist_change > stuck_progress_threshold then
			-- Insufficient progress (receding or <2m closer): accumulate stuck time.
			self.local_avoidance_stuck_timer = self.local_avoidance_stuck_timer + stuck_check_interval
			self.log_obj:Record(LogLevel.Debug, string.format(
				"StuckDetect: insufficient progress %.1fm (dist=%.1fm), stuck=%.0fs/%.0fs",
				dist_change, dest_len, self.local_avoidance_stuck_timer, self.local_avoidance_stuck_threshold))
		end
		-- -10m < dist_change <= -2m: mild progress, treated as neutral.

		self.local_avoidance_net_check_dist = dest_len
		self.local_avoidance_net_check_time = current_time
	end

	-- Stuck escape: ascend until upward is clear, then replan route
	if (not near_final_local_goal) and self.local_avoidance_stuck_timer >= self.local_avoidance_stuck_threshold then
		local up_dir       = Vector4.new(0, 0, 1, 0)
		local up_check_dist = 15.0  -- upward obstacle check distance (15m)
		local up_dist      = self:RaycastDist(current_pos, up_dir, up_check_dist)
		local up_clear     = (up_dist >= up_check_dist - 0.5)

		if self.local_avoidance_stuck_escape_time == 0 then
			-- First stuck frame: verify upward direction is not blocked.
			if not up_clear then
				self.log_obj:Record(LogLevel.Warning, string.format(
					"Local avoidance: STUCK (%.1fs) and upward blocked (%.1fm) - aborting autopilot",
					self.local_avoidance_stuck_timer, up_dist))
				self.local_avoidance_stuck_abort = true
				return dest_dir
			end
			-- Upward path is clear: start ascent-based escape.
			self.local_avoidance_stuck_escape_time = current_time
			self.log_obj:Record(LogLevel.Warning, string.format(
				"Local avoidance: STUCK (%.1fs) - ascending until forward path clears",
				self.local_avoidance_stuck_timer))
		end

		-- During ascent: abort autopilot if a new ceiling is detected.
		if not up_clear then
			self.log_obj:Record(LogLevel.Warning, string.format(
				"Local avoidance: obstacle detected above during escape (%.1fm) - aborting autopilot",
				up_dist))
			self.local_avoidance_stuck_abort = true
			return dest_dir
		end

		-- Check forward clearance; when clear enough, complete escape.
		local fwd_check_dist = math.max(20.0, self.autopilot_speed * 1.5)
		local fwd_dist_check = self:RaycastDist(current_pos, dest_dir, fwd_check_dist)
		local escape_elapsed = current_time - self.local_avoidance_stuck_escape_time

		-- After at least 1s of ascent, finish escape if forward path is >=70% clear.
		if escape_elapsed > 1.0 and fwd_dist_check > fwd_check_dist * 0.7 then
			self.local_avoidance_stuck_timer        = 0
			self.local_avoidance_stuck_escape_time  = 0
			self.local_avoidance_stuck_needs_replan = true
			self.local_avoidance_net_check_dist     = nil  -- reset baseline after escape to avoid stale dist
			self.log_obj:Record(LogLevel.Info, string.format(
				"Local avoidance: escape complete after %.1fs - forward clear (%.1fm), replanning route",
				escape_elapsed, fwd_dist_check))
			return dest_dir  -- route replanning is handled in the AutoPilot loop
		end

		-- Safety timeout: abort if forward path is not cleared after 20s ascent.
		if escape_elapsed > 20.0 then
			self.log_obj:Record(LogLevel.Warning, "Local avoidance: escape timeout (20s) - aborting autopilot")
			self.local_avoidance_stuck_abort = true
			return dest_dir
		end

		-- Still ascending: force upward speed so stale obstacle proximity does not linger.
		self.auto_speed_reduce_rate = 0.5
		return Vector4.new(0, 0, 1, 0)
	end

	-- === Repulsion-field navigation ===
	-- Detect radius: faster speed -> look farther ahead.
	local detect_dist = math.max(20.0, self.autopilot_speed * 2.0)
	-- Collect repulsion forces from spherical ray scan
	local rep_x, rep_y, rep_z, min_fwd_dist = self:CollectSphericalRepulsion(current_pos, dest_dir, detect_dist)
	local rep_mag = math.sqrt(rep_x*rep_x + rep_y*rep_y + rep_z*rep_z)

	-- Speed reduction: proportional to nearest forward obstacle
	local proximity = math.min(min_fwd_dist, detect_dist) / detect_dist
	if proximity < 0.5 then
		self.auto_speed_reduce_rate = math.max(0.2, proximity * 0.8 + 0.2)
	else
		self.auto_speed_reduce_rate = 0.7
	end

	if rep_mag > 0.3 then
		self.log_obj:Record(LogLevel.Trace, string.format(
			"Local avoidance: repulsion=(%.2f,%.2f,%.2f) mag=%.2f fwd_min=%.1fm",
			rep_x, rep_y, rep_z, rep_mag, min_fwd_dist))
	end

	-- Combine goal attraction (weight 1.5) + repulsion forces
	local goal_weight = 1.5
	local nav_x = dest_dir.x * goal_weight + rep_x
	local nav_y = dest_dir.y * goal_weight + rep_y
	local nav_z = dest_dir.z * goal_weight + rep_z
	local nav_len = math.sqrt(nav_x*nav_x + nav_y*nav_y + nav_z*nav_z)
	if nav_len < 0.001 then return dest_dir end
	return Vector4.new(nav_x/nav_len, nav_y/nav_len, nav_z/nav_len, 0)
end

--- Spherical repulsion force collector for potential-field obstacle avoidance.
--- Casts rays in all directions using a Fibonacci sphere pattern (N=32).
--- Returns rep_x, rep_y, rep_z (aggregate repulsion vector) and min_fwd_dist
--- (closest hit distance in the forward hemisphere, for speed control).
function Navigation:CollectSphericalRepulsion(from_pos, forward_dir, detect_dist)
	local fx, fy, fz = forward_dir.x, forward_dir.y, forward_dir.z
	if not self.local_ray_angles or #self.local_ray_angles ~= 32 then
		self.local_ray_count = 32
		self:GenerateSphericalRayPattern()
	end
	local rep_x, rep_y, rep_z = 0, 0, 0
	local min_fwd_dist = detect_dist

	for _, dir in ipairs(self.local_ray_angles) do
		local dx, dy, dz = dir.x, dir.y, dir.z
		local end_pos = Vector4.new(
			from_pos.x + dx * detect_dist,
			from_pos.y + dy * detect_dist,
			from_pos.z + dz * detect_dist, 1)
		if self.av_obj.collision_query_filter == nil then
			self.av_obj:InitializeCollisionQueryFilter()
		end
		local hit, result = Game.GetSpatialQueriesSystem():SyncRaycastByQueryFilter(
			from_pos, end_pos, self.av_obj.collision_query_filter, false, false)
		if hit and result and result.position then
			-- Vector from vehicle to hit point
			local hx = result.position.x - from_pos.x
			local hy = result.position.y - from_pos.y
			local hz = result.position.z - from_pos.z
			local hit_dist = math.sqrt(hx*hx + hy*hy + hz*hz)
			if hit_dist > 0.001 then
				-- Track closest forward hit for speed control
				local fwd_dot = (hx / hit_dist) * fx + (hy / hit_dist) * fy + (hz / hit_dist) * fz
				if fwd_dot > 0.5 then
					min_fwd_dist = math.min(min_fwd_dist, hit_dist)
				end
				-- Quadratic repulsion: force proportional to (1 - d/D)^2
				local t = math.max(0.0, 1.0 - hit_dist / detect_dist)
				local force = t * t
				rep_x = rep_x - (hx / hit_dist) * force
				rep_y = rep_y - (hy / hit_dist) * force
				rep_z = rep_z - (hz / hit_dist) * force
			end
		end
	end
	return rep_x, rep_y, rep_z, min_fwd_dist
end

return Navigation

