-- local Log = require("Tools/log.lua")
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
    -- obj.collision_filters = {"Static", "Destructible", "Terrain", "Debris", "Cloth", "Water"}
    obj.collision_filters = {"Static", "Terrain", "Water"}
    obj.far_distance = 100
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
        { x = self.all_models[index].shape.H.x, y = self.all_models[index].shape.H.y, z = self.all_models[index].shape.H.z },
        { x = self.all_models[index].shape.ABFE.x, y = self.all_models[index].shape.ABFE.y, z = self.all_models[index].shape.ABFE.z },
        { x = self.all_models[index].shape.CDHG.x, y = self.all_models[index].shape.CDHG.y, z = self.all_models[index].shape.CDHG.z },
        { x = self.all_models[index].shape.ABDC.x, y = self.all_models[index].shape.ABDC.y, z = self.all_models[index].shape.ABDC.z },
        { x = self.all_models[index].shape.EFHG.x, y = self.all_models[index].shape.EFHG.y, z = self.all_models[index].shape.EFHG.z },
        { x = self.all_models[index].shape.ACGE.x, y = self.all_models[index].shape.ACGE.y, z = self.all_models[index].shape.ACGE.z },
        { x = self.all_models[index].shape.BDHF.x, y = self.all_models[index].shape.BDHF.y, z = self.all_models[index].shape.BDHF.z }
    }
    self.entry_point = { x = self.all_models[index].entry_point.x, y = self.all_models[index].entry_point.y, z = self.all_models[index].entry_point.z }
    self.entry_area_radius = self.all_models[index].entry_area_radius
    self.exit_point = { x = self.all_models[index].exit_point.x, y = self.all_models[index].exit_point.y, z = self.all_models[index].exit_point.z }
end

function Position:SetEntity(entity)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "Entity is nil for SetEntity")
    end
    self.entity = entity
end

function Position:SetEngineState(mode)
    if mode == Def.PowerMode.On then
        self.is_power_on = true
    elseif mode == Def.PowerMode.Off then
        self.is_power_on = false
    else
        self.log_obj:Record(LogLevel.Critical, "Set Invalid Power Mode")
    end
end

function Position:SetSensorPairVectorNum(num)
    self.sensor_pair_vector_num = num
end

function Position:SetJudgedStackLength(length)
    self.judged_stack_length = length
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
        self.log_obj:Record(LogLevel.Warning, "No vehicle entity for GetPosition")
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

function Position:SetNextPosition(x, y, z, roll, pitch, yaw, is_freeze)

    if self.entity == nil then
        self.log_obj:Record(LogLevel.Error, "No vehicle entity for SetNextPosition")
        return Def.TeleportResult.Error
    end

    local pos
    if not is_freeze then
        pos = self:GetPosition()
    else
        pos = self.next_position
    end
    self.next_position = Vector4.new(pos.x + x, pos.y + y, pos.z + z, 1.0)

    local rot
    if not is_freeze then
        rot = self:GetEulerAngles()
    else
        rot = self.next_angle
    end
    self.next_angle = EulerAngles.new(rot.roll + roll, rot.pitch + pitch, rot.yaw + yaw)

    if not is_freeze then
        self:ChangePosition()
    end

    if self:CheckCollision(pos, self.next_position) then
        self.log_obj:Record(LogLevel.Debug, "Collision Detected")

        self.next_position = Vector4.new(pos.x, pos.y, pos.z, 1.0)
        self.next_angle = EulerAngles.new(rot.roll, rot.pitch, rot.yaw)

        if not is_freeze then
            self:ChangePosition()
        end

        if self.is_power_on then
            self.collision_count = self.collision_count + 1
        else
            self.collision_count = 0
        end
        if self.collision_count > self.collision_max_count then
            self.log_obj:Record(LogLevel.Trace, "Collision Count Over")
            self:AvoidStacking()
            self.collision_count = 0
            return Def.TeleportResult.AvoidStack
        end
        return Def.TeleportResult.Collision
    else
        self.collision_count = 0
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
                self:CalculateReflection(current_corner, trace_result)
                return true
            end
        end
    end

    return false
end

function Position:CalculateReflection(current_pos, trace_result)
    local collision_point = trace_result.position
    local normal_vector = trace_result.normal
    local collision_vector = {x = collision_point.x - current_pos.x, y = collision_point.y - current_pos.y, z = collision_point.z - current_pos.z}
    local inner_product = normal_vector.x * collision_vector.x + normal_vector.y * collision_vector.y + normal_vector.z * collision_vector.z
    self.reflection_vector.x = collision_vector.x - 2 * inner_product * normal_vector.x
    self.reflection_vector.y = collision_vector.y - 2 * inner_product * normal_vector.y
    self.reflection_vector.z = collision_vector.z - 2 * inner_product * normal_vector.z
end

function Position:IsCollision()
    local collision_status = self.is_collision
    self.is_collision = false
    return collision_status
end

function Position:GetReflectionVector()
    return self.reflection_vector
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

function Position:AvoidStacking()

    local pos = self:GetPosition()
    local angle = self:GetEulerAngles()

    self.log_obj:Record(LogLevel.Debug, "Avoid Stacking")

    if self.stack_corner_num == 1 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[8].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[8].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[8].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 2 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[7].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[7].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[7].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 3 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[6].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[6].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[6].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 4 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[5].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[5].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[5].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 5 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[4].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[4].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[4].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 6 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[3].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[3].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[3].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 7 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[2].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[2].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[2].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 8 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[1].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[1].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[1].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 9 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[10].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[10].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[10].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 10 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[9].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[9].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[9].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 11 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[12].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[12].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[12].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 12 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[11].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[11].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[11].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 13 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[14].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[14].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[14].z + (1 - self.dividing_rate) * pos.z, 1.0)
    elseif self.stack_corner_num == 14 then
        self.next_position = Vector4.new(self.dividing_rate * self.corners[13].x + (1 - self.dividing_rate) * pos.x, self.dividing_rate * self.corners[13].y + (1 - self.dividing_rate) * pos.y, self.dividing_rate * self.corners[13].z + (1 - self.dividing_rate) * pos.z, 1.0)
    end

    self.next_angle = EulerAngles.new(0, 0, angle.yaw)
    self:ChangePosition()
end

function Position:GetExitPosition()
    local basic_vector = self:GetPosition()
    return self:ChangeWorldCordinate(basic_vector, {self.exit_point})[1]
end

function Position:CalculateVectorField(radius_in, radius_out, max_length, sensing_constant)

    local current_position = self:GetPosition()
    local dividing_vector = Vector4.new(0, 0, 0, 1.0)
    local spherical_vectors = Utils:GenerateUniformVectorsOnSphere(self.sensor_pair_vector_num, radius_out)
    local vector_field = {}

    local k = radius_out - radius_in / radius_out

    for _, spherical_vector in ipairs(spherical_vectors) do
        local world_spherical_vector = Vector4.new(spherical_vector.x + current_position.x, spherical_vector.y + current_position.y, spherical_vector.z + current_position.z, 1.0)
        dividing_vector.x = (1 - k) * current_position.x + k * world_spherical_vector.x
        dividing_vector.y = (1 - k) * current_position.y + k * world_spherical_vector.y
        dividing_vector.z = (1 - k) * current_position.z + k * world_spherical_vector.z

        for _, filter in ipairs(self.collision_filters) do
            local is_success, trace_result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(dividing_vector, world_spherical_vector, filter, false, false)
            if is_success then
                spherical_vector.x = trace_result.position.x - dividing_vector.x
                spherical_vector.y = trace_result.position.y - dividing_vector.y
                spherical_vector.z = trace_result.position.z - dividing_vector.z
                break
            end
        end
        table.insert(vector_field, spherical_vector)

    end

    local sum_vector = Vector4.new(0, 0, 0, 1.0)
    for _, vector in ipairs(vector_field) do
        sum_vector.x = sum_vector.x + vector.x * sensing_constant
        sum_vector.y = sum_vector.y + vector.y * sensing_constant
        sum_vector.z = sum_vector.z + vector.z * sensing_constant
    end

    local norm = math.sqrt(sum_vector.x * sum_vector.x + sum_vector.y * sum_vector.y + sum_vector.z * sum_vector.z)
    if norm > max_length then
        sum_vector.x = sum_vector.x * max_length / norm
        sum_vector.y = sum_vector.y * max_length / norm
        sum_vector.z = sum_vector.z * max_length / norm
    end

    return sum_vector

end

function Position:CheckAutoPilotStackCount(distination_position)
    local current_position = self:GetPosition()

    local distance = math.sqrt((current_position.x - distination_position.x) * (current_position.x - distination_position.x) + (current_position.y - distination_position.y) * (current_position.y - distination_position.y) + (current_position.z - distination_position.z) * (current_position.z - distination_position.z))

    if self.stack_count == 0 then
        self.stack_distance = distance
    end

    if math.abs(distance - self.stack_distance) < self.judged_stack_length then
        self.stack_count = self.stack_count + 1
    else
        self.stack_count = 0
    end

    return self.stack_count
end

function Position:ResetStackCount()
    self.stack_count = 0
end

function Position:GetFarCornerDistance()
    local max_distance = 0
    for _, corner in ipairs(self.local_corners) do
        local curner_distance = math.sqrt(corner.x * corner.x + corner.y * corner.y + corner.z * corner.z)
        if curner_distance > max_distance then
            max_distance = curner_distance
        end
    end
    return max_distance
end

return Position