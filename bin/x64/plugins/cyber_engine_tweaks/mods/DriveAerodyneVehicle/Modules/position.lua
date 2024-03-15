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

    obj.local_corners = {}
    obj.corners = {}
    obj.local_entry_area = {}
    obj.entry_area = {}
    obj.min_direction_norm = 0.5 -- NOT Change this value
    obj.collision_max_count = 50
    obj.dividing_rate = 0.2

    obj.collision_filters = {"Static", "Destructible", "Terrain", "Debris", "Cloth", "Water"}

    -- set default parameters
    obj.collision_count = 0
    obj.is_collision = false
    obj.is_power_on = false

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
    self.local_entry_area = {
        { x = self.all_models[index].entry_area.A.x, y = self.all_models[index].entry_area.A.y, z = self.all_models[index].entry_area.A.z },
        { x = self.all_models[index].entry_area.B.x, y = self.all_models[index].entry_area.B.y, z = self.all_models[index].entry_area.B.z },
        { x = self.all_models[index].entry_area.C.x, y = self.all_models[index].entry_area.C.y, z = self.all_models[index].entry_area.C.z },
        { x = self.all_models[index].entry_area.D.x, y = self.all_models[index].entry_area.D.y, z = self.all_models[index].entry_area.D.z },
        { x = self.all_models[index].entry_area.E.x, y = self.all_models[index].entry_area.E.y, z = self.all_models[index].entry_area.E.z },
        { x = self.all_models[index].entry_area.F.x, y = self.all_models[index].entry_area.F.y, z = self.all_models[index].entry_area.F.z },
        { x = self.all_models[index].entry_area.G.x, y = self.all_models[index].entry_area.G.y, z = self.all_models[index].entry_area.G.z },
        { x = self.all_models[index].entry_area.H.x, y = self.all_models[index].entry_area.H.y, z = self.all_models[index].entry_area.H.z },
    }
end

function Position:SetEntity(entity)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "Entity is nil for SetEntity")
    end
    self.entity = entity
end

function Position:SetEngineState(is_power_on)
    self.is_power_on = is_power_on
end

function Position:SetCorners()
    local vector = self:GetPosition()
    local quaternion = self:GetQuaternion()
    for i, corner in ipairs(self.local_corners) do
        local rotated = Utils:RotateVectorByQuaternion(corner, quaternion)
        self.corners[i] = {x = rotated.x + vector.x, y = rotated.y + vector.y, z = rotated.z + vector.z}
    end
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

function Position:GetFoword()
    if self.entity == nil then
        self.log_obj:Record(LogLevel.Error, "No vehicle entity for GetFoword")
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
        return false
    end

    local pos = self:GetPosition()
    self.next_position = Vector4.new(pos.x + x, pos.y + y, pos.z + z, 1.0)

    local rot = self:GetEulerAngles()
    self.next_angle = EulerAngles.new(rot.roll + roll, rot.pitch + pitch, rot.yaw + yaw)

    self:ChangePosition()

    if self:CheckCollision(pos, self.next_position) then
        self.log_obj:Record(LogLevel.Debug, "Collision Detected")
        if self.is_power_on then
            self.collision_count = self.collision_count + 1
        else
            self.collision_count = 0
        end
        self.next_position = Vector4.new(pos.x, pos.y, pos.z, 1.0)
        self.next_angle = EulerAngles.new(rot.roll, rot.pitch, rot.yaw)
        self:ChangePosition()
        if self.collision_count > self.collision_max_count then
            self.log_obj:Record(LogLevel.Trace, "Collision Count Over")
            self:AvoidStacking()
            self.collision_count = 0
        end
        return false
    else
        self.collision_count = 0
        return true
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

    self:SetCorners()

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
            local success, result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_corner, next_corner, filter, false, false)
            if success then
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
    self:SetEntryArea()
    local player_pos = Game.GetPlayer():GetWorldPosition()
    local player_vector = {x = player_pos.x, y = player_pos.y, z = player_pos.z}

    local planes = {
        {A = self.entry_area[1], B = self.entry_area[2], C = self.entry_area[5]},  -- front face
        {A = self.entry_area[3], B = self.entry_area[4], C = self.entry_area[7]},  -- back face
        {A = self.entry_area[5], B = self.entry_area[6], C = self.entry_area[8]},  -- left face
        {A = self.entry_area[2], B = self.entry_area[4], C = self.entry_area[3]},  -- right face
        {A = self.entry_area[1], B = self.entry_area[3], C = self.entry_area[5]},  -- top face
        {A = self.entry_area[2], B = self.entry_area[4], C = self.entry_area[6]}   -- bottom face
    }

    local firstDistance = Utils:DistanceFromPlane(player_vector, planes[1])
    print(firstDistance)
    for i = 2, #planes do
        if Utils:DistanceFromPlane(player_vector, planes[i]) * firstDistance < 0 then
            return false
        end
    end
    return true
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

return Position