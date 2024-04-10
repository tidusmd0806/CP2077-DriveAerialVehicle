local Def = require("Tools/def.lua")
local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
local Position = {}
Position.__index = Position

function Position:New(all_models)
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Position")
    obj.entity = nil
    obj.next_position = nil
    obj.next_angle = nil
    obj.all_models = all_models
    obj.model_index = 1

    obj.min_direction_norm = 0.5 -- NOT Change this value
    obj.collision_max_count = 80
    obj.dividing_rate = 0.5

    obj.collision_filters = {"Static", "Destructible", "Terrain", "Debris", "Cloth", "Water"}

    -- set default parameters
    obj.collision_count = 0
    obj.is_collision = false
    obj.reflection_vector = {x = 0, y = 0, z = 0}
    obj.is_power_on = false

    obj.local_corners = {}
    obj.corners = {}
    obj.entry_point = {}
    obj.entry_area_radius = 0

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
            EFHG is the left face
            ABDC is the right face
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

function Position:ChangeWorldCordinate(basic_vector ,point_list)
    local quaternion = self:GetQuaternion()
    local result_list = {}
    for i, corner in ipairs(point_list) do
        local rotated = Utils:RotateVectorByQuaternion(corner, quaternion)
        result_list[i] = {x = rotated.x + basic_vector.x, y = rotated.y + basic_vector.y, z = rotated.z + basic_vector.z}
    end
    return result_list
end

function Position:SetEntryArea()
    local vector = self:GetPosition()
    local quaternion = self:GetQuaternion()
    for i, corner in ipairs(self.local_entry_area) do
        local rotated = Utils:RotateVectorByQuaternion(corner, quaternion)
        self.entry_area[i] = {x = rotated.x + vector.x, y = rotated.y + vector.y, z = rotated.z + vector.z}
    end
end

function Position:GetPosition()
    if self.entity == nil then
        self.log_obj:Record(LogLevel.Error, "No vehicle entity for GetPosition")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return self.entity:GetWorldPosition()
end

function Position:GetForward()
    if self.entity == nil then
        self.log_obj:Record(LogLevel.Error, "No vehicle entity for GetForward")
        return Vector4.new(0, 0, 0, 1.0)
    end
    return self.entity:GetWorldForward()
end

function Position:GetQuaternion()
    if self.entity == nil then
        self.log_obj:Record(LogLevel.Error, "No vehicle entity for GetQuaternion")
        return Quaternion.new(0, 0, 0, 1.0)
    end
    return self.entity:GetWorldOrientation()
end

function Position:GetEulerAngles()
    if self.entity == nil then
        self.log_obj:Record(LogLevel.Error, "No vehicle entity for GetEulerAngles")
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
    local world_entry_point = self:ChangeWorldCordinate(basic_vector, {self.entry_point})
    local player_pos = Game.GetPlayer():GetWorldPosition()
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
    end

    self.next_angle = EulerAngles.new(0, 0, angle.yaw)
    self:ChangePosition()
end

function Position:GetExitPosition()
    local basic_vector = self:GetPosition()
    return self:ChangeWorldCordinate(basic_vector, {self.exit_point})[1]
end

return Position