local Position = {}
Position.__index = Position

function Position:new()
    local obj = {}
    return setmetatable(obj, self)
end

function Position:getPlayerPosition()
    return Game.GetPlayer():GetWorldPosition()
end

function Position:getPlayerAngle()
    return Game.GetPlayer():GetWorldOrientation():ToEulerAngles()
end

function Position:getDirection(angle)
    return Vector4.RotateAxis(Game.GetPlayer():GetWorldForward(), Vector4.new(0, 0, 1, 0), angle / 180.0 * Pi())
end

function Position:getPosition(distance, angle)
    local pos = self:getPlayerPosition()
    local heading = self:getDirection(angle)
    return Vector4.new(pos.x + (heading.x * distance), pos.y + (heading.y * distance), pos.z + heading.z, pos.w + heading.w)
end

function Position:getOrientation(angle)
    return EulerAngles.ToQuat(Vector4.ToRotation(self:getDirection(angle)))
end

return Position
