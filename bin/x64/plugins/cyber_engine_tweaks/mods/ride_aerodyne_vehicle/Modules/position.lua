local Log = require("Modules/log.lua")
local Position = {}
Position.__index = Position

function Position:new()
    local obj = {}
    local log_obj = Log:new()
    log_obj:setLevel(LogLevel.INFO, "Position")
    self.game_obj = nil

    return setmetatable(obj, self)
end

function Position:getPlayerDirection(angle)
    return Vector4.RotateAxis(Game.GetPlayer():GetWorldForward(), Vector4.new(0, 0, 1, 0), angle / 180.0 * Pi())
end

function Position:getPlayerPosition(distance, angle)
    local pos = Game.GetPlayer():GetWorldPosition()
    local heading = self:getPlayerDirection(angle)
    return Vector4.new(pos.x + (heading.x * distance), pos.y + (heading.y * distance), pos.z + heading.z, pos.w + heading.w)
end

function Position:getPlayerOrientation(angle)
    return EulerAngles.ToQuat(Vector4.ToRotation(self:getPlayerDirection(angle)))
end

function Position:setNextVehiclePosition(x, y, z, roll, pitch, yaw)
    if self.game_obj == nil then
        self.game_obj = Game['GetMountedVehicle;GameObject'](Game.GetPlayer())
    end
    local pos = self.game_obj:GetWorldPosition()
    local rot = self.game_obj:GetWorldOrientation():ToEulerAngles()
    self.next_pos_x = pos.x + x
    self.next_pos_y = pos.y + y
    self.next_pos_z = pos.z + z
    self.next_rot_roll = rot.roll + roll
    self.next_rot_pitch = rot.pitch + pitch
    self.next_rot_yaw = rot.yaw + yaw
    if self:checkVehicleCollision() then
        self.log_obj:record(LogLevel.DEBUG, "Collision Detected")
        self.next_pos_x = pos.x
        self.next_pos_y = pos.y
        self.next_pos_z = pos.z
        self.next_rot_roll = rot.roll
        self.next_rot_pitch = rot.pitch
        self.next_rot_yaw = rot.yaw
        return false
    end
    return true
end

function Position:changeVehiclePosition()
    Game.GetTeleportationFacility():Teleport(self.game_obj, Vector4.new(self.next_pos_x, self.next_pos_y, self.next_pos_z, 1), EulerAngles.new(self.next_rot_roll, self.next_rot_pitch, self.next_rot_yaw))
end

function Position:checkVehicleCollision()
    local filters = {
        'Static', -- Buildings, Concrete Roads, Crates, etc.
        'Terrain'
    }
    local current_pos = self.game_obj:GetWorldPosition()
    local next_pos = Vector4.new(self.next_pos_x, self.next_pos_y, self.next_pos_z, 1)
    for _, filter in ipairs(filters) do
        local success, result = Game.GetSpatialQueriesSystem():SyncRaycastByCollisionGroup(current_pos, next_pos, filter, false, false)
        if success then
            return true
        end
    end
    return false
end

return Position
