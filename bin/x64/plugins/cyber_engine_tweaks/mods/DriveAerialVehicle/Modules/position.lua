local Utils = require("Tools/utils.lua")
local Position = {}
Position.__index = Position

function Position:New(all_models)
    -- instance --
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Position")
    -- static --
    obj.all_models = all_models
    obj.min_direction_norm = 0.5 -- NOT Change this value
    obj.collision_max_count = 80
    obj.dividing_rate = 0.5
    obj.judged_stack_length = 3
    obj.search_distance = 100
    -- obj.collision_filters = {"Static", "Destructible", "Terrain", "Debris", "Cloth", "Water"}
    -- obj.collision_filters = {"Static", "Terrain", "Water"}
    obj.collision_filters = {"Static", "Terrain"}
    obj.far_distance = 100
    obj.exception_area_path = "Data\\autopilot_exception_area.json"
    -- dyanmic --
    obj.entity = nil
    obj.next_position = nil
    obj.next_angle = nil
    obj.model_index = 1
    obj.collision_count = 0
    obj.is_collision = false
    obj.reflection_vector = {x = 0, y = 0, z = 0}
    obj.is_power_on = false
    obj.local_corners = {}
    obj.corners = {}
    obj.entry_point = {}
    obj.entry_area_radius = 0
    obj.stack_distance = 0
    obj.stack_count = 0
    obj.sensor_pair_vector_num = 15
    obj.collision_trace_result = nil
    obj.autopilot_prevention_length = 10
    return setmetatable(obj, self)
end

--[[
        This is the diagram of the vehicle's local corners
               E-----A
              /|    /|
             / |   / |
            G-----C  |
            |  F--|--B
            | /   | /
            |/    |/       
            H-----D

            ABFE is the front face
            CDHG is the back face
            ABDC is the right face
            EFHG is the left face
            ACGE is the top face
            BDHF is the bottom face           
    ]]

function Position:SetModel(index)
    self.local_corners = {
        { x = self.all_models[index].shape.A.x, y = self.all_models[index].shape.A.y, z = self.all_models[index].shape.A.z },
        { x = self.all_models[index].shape.B.x, y = self.all_models[index].shape.B.y, z = self.all_models[index].shape.B.z },
        { x = self.all_models[index].shape.C.x, y = self.all_models[index].shape.C.y, z = self.all_models[index].shape.C.z },
        { x = self.all_models[index].shape.D.x, y = self.all_models[index].shape.D.y, z = self.all_models[index].shape.D.z },
        { x = self.all_models[index].shape.E.x, y = self.all_models[index].shape.E.y, z = self.all_models[index].shape.E.z },
        { x = self.all_models[index].shape.F.x, y = self.all_models[index].shape.F.y, z = self.all_models[index].shape.F.z },
        { x = self.all_models[index].shape.G.x, y = self.all_models[index].shape.G.y, z = self.all_models[index].shape.G.z },
        { x = self.all_models[index].shape.H.x, y = self.all_models[index].shape.H.y, z = self.all_models[index].shape.H.z }
    }
    self.entry_point = { x = self.all_models[index].entry_point.x, y = self.all_models[index].entry_point.y, z = self.all_models[index].entry_point.z }
    self.entry_area_radius = self.all_models[index].entry_area_radius
    self.exit_point = { x = self.all_models[index].exit_point.x, y = self.all_models[index].exit_point.y, z = self.all_models[index].exit_point.z }
    self.minimum_distance_to_ground = self.all_models[index].minimum_distance_to_ground
    self.autopilot_prevention_length = self.all_models[index].autopilot_prevention_length
    self.autopilot_exception_area_list = Utils:ReadJson(self.exception_area_path)
end

function Position:GetGroundPosition()
    local current_position = self:GetPosition()
    for _, filter in ipairs(self.collision_filters) do
        local is_success, trace_result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_position, Vector4.new(current_position.x, current_position.y, current_position.z - self.search_distance, 1.0), filter, false, false)
        if is_success then
            return trace_result.position.z
        end
    end
    return current_position.z - self.search_distance - 1
end

function Position:GetHeight()
    return self:GetPosition().z - self:GetGroundPosition()
end

function Position:IsWall(dir_vec, distance, angle, swing_direction)
    local dir_base_vec = Vector4.Normalize(dir_vec)
    local up_vec = Vector4.new(0, 0, 1, 1)
    local right_vec = Vector4.Cross(dir_base_vec, up_vec)
    local search_vec
    if swing_direction == "Vertical" then
        search_vec = Vector4.RotateAxis(dir_base_vec, right_vec, angle / 180 * Pi())
    else
        search_vec = Vector4.RotateAxis(dir_base_vec, up_vec, angle / 180 * Pi())
    end
    for _, i in ipairs({0, self.autopilot_prevention_length, -self.autopilot_prevention_length}) do
        for _, j in ipairs({0, self.autopilot_prevention_length, -self.autopilot_prevention_length}) do
            for _, k in ipairs({0, self.autopilot_prevention_length, -self.autopilot_prevention_length}) do
                local current_position = self:GetPosition()
                current_position.x = current_position.x + dir_base_vec.x * i + right_vec.x * j + up_vec.x * k
                current_position.y = current_position.y + dir_base_vec.y * i + right_vec.y * j + up_vec.y * k
                current_position.z = current_position.z + dir_base_vec.z * i + right_vec.z * j + up_vec.z * k
                for _, filter in ipairs(self.collision_filters) do
                    local is_success, _ = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_position, Vector4.new(current_position.x + distance * search_vec.x, current_position.y + distance * search_vec.y, current_position.z + distance * search_vec.z, 1.0), filter, false, false)
                    if is_success then
                        return true, search_vec
                    end
                end
                -- check exception area
                local is_exception, _ = self:IsInExceptionArea(Vector4.new(current_position.x + distance * search_vec.x, current_position.y + distance * search_vec.y, current_position.z + distance * search_vec.z, 1.0))
                if is_exception then
                    return true, search_vec
                end
            end
        end
    end
    return false, search_vec
end

function Position:SetEntity(entity)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "Entity is nil for SetEntity")
    end
    self.entity = entity
end

function Position:ChangeWorldCordinate(basic_vector ,point_list)
    local quaternion = self:GetQuaternion()
    local result_list = {}
    for i, corner in ipairs(point_list) do
        local rotated = Utils:RotateVectorByQuaternion(corner, quaternion)
        result_list[i] = {x = rotated.x + basic_vector.x, y = rotated.y + basic_vector.y, z = rotated.z + basic_vector.z}
    end
    return result_list
end

function Position:GetPosition()
    if self.entity == nil then
        self.log_obj:Record(LogLevel.Trace, "No vehicle entity for GetPosition")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return self.entity:GetWorldPosition()
end

function Position:GetForward()
    if self.entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetForward")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return self.entity:GetWorldForward()
end

function Position:GetRight()
    if self.entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetRight")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return self.entity:GetWorldRight()
end

function Position:GetUp()
    if self.entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetUp")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return self.entity:GetWorldUp()
end

function Position:GetQuaternion()
    if self.entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetQuaternion")
        return Quaternion.new(0, 0, 0, 1.0)
    end
    return self.entity:GetWorldOrientation()
end

function Position:GetEulerAngles()
    if self.entity == nil then
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetEulerAngles")
        return EulerAngles.new(0, 0, 0)
    end
    return self.entity:GetWorldOrientation():ToEulerAngles()
end

function Position:GetPlayerAroundDirection(angle)
    return Vector4.RotateAxis(Game.GetPlayer():GetWorldForward(), Vector4.new(0, 0, 1, 0), angle / 180.0 * Pi())
end

function Position:GetSpawnPosition(distance, angle)
    local pos = Game.GetPlayer():GetWorldPosition()
    local heading = self:GetPlayerAroundDirection(angle)
    return Vector4.new(pos.x + (heading.x * distance), pos.y + (heading.y * distance), pos.z + heading.z, pos.w + heading.w)
end

function Position:GetSpawnOrientation(angle)
    return EulerAngles.ToQuat(Vector4.ToRotation(self:GetPlayerAroundDirection(angle)))
end

function Position:IsPlayerAround()
    local player_pos = Game.GetPlayer():GetWorldPosition()
    if self:GetPosition():IsZero() then
        return true
    end
    local distance = Vector4.Distance(player_pos, self:GetPosition())
    if distance < self.far_distance then
        return true
    else
        return false
    end
end

function Position:SetNextPosition(x, y, z, roll, pitch, yaw)

    if self.entity == nil then
        self.log_obj:Record(LogLevel.Error, "No vehicle entity for SetNextPosition")
        return Def.TeleportResult.Error
    end

    local pos = self:GetPosition()
    self.next_position = Vector4.new(pos.x + x, pos.y + y, pos.z + z, 1.0)

    local rot = self:GetEulerAngles()
    self.next_angle = EulerAngles.new(rot.roll + roll, rot.pitch + pitch, rot.yaw + yaw)

    self:ChangePosition()

    if self:CheckCollision(pos, self.next_position) then
        self.log_obj:Record(LogLevel.Debug, "Collision Detected")

        self.next_position = Vector4.new(pos.x, pos.y, pos.z, 1.0)
        self.next_angle = EulerAngles.new(rot.roll, rot.pitch, rot.yaw)

        self:ChangePosition()

        return Def.TeleportResult.Collision
    else
        return Def.TeleportResult.Success
    end
end

function Position:ChangePosition()

    if self.entity == nil then
        self.log_obj:Record(LogLevel.Error, "No vehicle entity for ChangePosition")
        return false
    end

    Game.GetTeleportationFacility():Teleport(self.entity, self.next_position, self.next_angle)
    return true

end

function Position:SetPosition(position, angle)

    if self.entity == nil then
        self.log_obj:Record(LogLevel.Error, "No vehicle entity for ChangePosition")
        return false
    end

    Game.GetTeleportationFacility():Teleport(self.entity, position, angle)
    return true
end

function Position:CheckCollision(current_pos, next_pos)

    self.corners = self:ChangeWorldCordinate(current_pos, self.local_corners)

    -- Conjecture Direction Norm for Detect Collision
    local direction = {x = next_pos.x - current_pos.x, y = next_pos.y - current_pos.y, z = next_pos.z - current_pos.z}
    local direction_norm = math.sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
    if direction_norm < self.min_direction_norm then
        direction = {x = direction.x * self.min_direction_norm / direction_norm, y = direction.y * self.min_direction_norm / direction_norm, z = direction.z * self.min_direction_norm / direction_norm}
    end

    for i, corner in ipairs(self.corners) do
        local current_corner = Vector4.new(corner.x, corner.y, corner.z, 1.0)
        local next_corner = Vector4.new(corner.x + direction.x, corner.y + direction.y, corner.z + direction.z, 1.0)
        for _, filter in ipairs(self.collision_filters) do
            local success, trace_result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_corner, next_corner, filter, false, false)
            if success then
                self.collision_trace_result = trace_result
                self.stack_corner_num = i
                self.is_collision = true
                return true
            end
        end
    end

    return false
end

function Position:IsCollision()
    local collision_status = self.is_collision
    self.is_collision = false
    return collision_status
end

function Position:IsPlayerInEntryArea()
    local basic_vector = self:GetPosition()
    if basic_vector:IsZero() then
        return false
    end
    local world_entry_point = self:ChangeWorldCordinate(basic_vector, {self.entry_point})
    local player_pos = Game.GetPlayer():GetWorldPosition()
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

function Position:GetExitPosition()
    local basic_vector = self:GetPosition()
    return self:ChangeWorldCordinate(basic_vector, {self.exit_point})[1]
end

function Position:IsInExceptionArea(position)

    for _, area in ipairs(self.autopilot_exception_area_list) do
        if position.x >= area.min_x and position.x <= area.max_x and position.y >= area.min_y and position.y <= area.max_y and position.z >= area.min_z and position.z <= area.max_z then
            return true, area.tag
        end
    end
    return false, "None"

end

return Position