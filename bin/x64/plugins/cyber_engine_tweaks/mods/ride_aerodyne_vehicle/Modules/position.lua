local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
local Position = {}
Position.__index = Position

function Position:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Position")
    obj.entity = nil
    obj.next_position = nil
    obj.next_angle = nil

    local width, height, depth = 10, 4, 2
    local half_width, half_height, half_depth = width / 2, height / 2, depth / 2
    self.local_corners = {
        { x= half_width, y= half_height, z= half_depth },
        { x= half_width, y= half_height, z=-half_depth },
        { x= half_width, y=-half_height, z= half_depth },
        { x= half_width, y=-half_height, z=-half_depth },
        { x=-half_width, y= half_height, z= half_depth },
        { x=-half_width, y= half_height, z=-half_depth },
        { x=-half_width, y=-half_height, z= half_depth },
        { x=-half_width, y=-half_height, z=-half_depth },
    }
    self.corners = {}

    return setmetatable(obj, self)
end

function Position:SetEntity(entity)
    if entity == nil then
        self.log_obj:Record(LogLevel.Warning, "Entity is nil for SetEntity")
    end
    self.entity = entity
end

function Position:SetCorners()
    local vector = self:GetPosition()
    local quaternion = self:GetQuaternion()
    for i, corner in ipairs(self.local_corners) do
        local rotated = Utils:RotateVectorByQuaternion(corner, quaternion)
        self.corners[i] = {x = rotated.x + vector.x, y = rotated.y + vector.y, z = rotated.z + vector.z}
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
    if self:CheckCollision(pos, self.next_position) then
        self.log_obj:Record(LogLevel.Debug, "Collision Detected")
        self.next_position = Vector4.new(pos.x, pos.y, pos.z, 1.0)
        return false
    end

    local rot = self:GetEulerAngles()
    self.next_angle = EulerAngles.new(rot.roll + roll, rot.pitch + pitch, rot.yaw + yaw)

    return true
end

function Position:ChangePosition()

    if self.entity == nil then
        self.log_obj:Record(LogLevel.Error, "No vehicle entity for ChangePosition")
        return false
    end
    Game.GetTeleportationFacility():Teleport(self.entity, self.next_position, self.next_angle)
end

function Position:CheckCollision(current_pos, next_pos)

    local filters = {'Static', 'Terrain'}

    self:SetCorners()
    local direction = {x = next_pos.x - current_pos.x, y = next_pos.y - current_pos.y, z = next_pos.z - current_pos.z}

    for _, corner in ipairs(self.corners) do
        local current_corner = Vector4.new(corner.x, corner.y, corner.z, 1.0)
        local next_corner = Vector4.new(corner.x + direction.x, corner.y + direction.y, corner.z + direction.z, 1.0)
        for _, filter in ipairs(filters) do
            local success, result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_corner, next_corner, filter, false, false)
            if success then
                return true
            end
        end
    end

    return false
end

return Position