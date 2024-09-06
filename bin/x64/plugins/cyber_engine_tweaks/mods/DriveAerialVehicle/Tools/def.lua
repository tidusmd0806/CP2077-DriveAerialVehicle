---@class Def
Def = {}
Def.__index = Def

---@enum Def.ActionList
Def.ActionList = {
    Idle = -1,
    Nothing = 0,
    --------
    Forward = 1,
    Backward = 2,
    RightRotate = 3,
    LeftRotate = 4,
    LeanForward = 5,
    LeanBackward = 6,
    Up = 7,
    Down = 8,
    Right = 9,
    Left = 10,
    LeanReset = 11,
    ----------
    -- HLift = 21,
    HUp = 21,
    HDown = 22,
    HLeanForward = 23,
    HLeanBackward = 24,
    HLeanRight = 25,
    HLeanLeft = 26,
    HRightRotate = 27,
    HLeftRotate = 28,
    HAccelerate = 29,
    -- HHover = 30,
    ----------
	Enter= 100,
	Exit = 101,
	ChangeCamera = 102,
	ChangeDoor1 = 103,
    ChangeDoor2 = 104, -- not used
    SelectUp = 105,
    SelectDown = 106,
    ToggleRadio = 107,
    OpenRadio = 108,
    ToggleCrystalDome = 109,
    ToggleAppearance = 110,
    ----------
    ToggleAutopilot = 200,
    OpenAutopilotPanel = 201,
}

---@enum Def.Situation
Def.Situation = {
    idle = -1,
    Normal = 0,
    Landing = 1,
    Waiting = 2,
    InVehicle = 3,
    TalkingOff = 4,
}

---@enum Def.DoorOperation
Def.DoorOperation = {
	Change = 0,
	Open = 1,
	Close = 2,
}

Def.TeleportResult = {
    Error = -1,
    Collision = 0,
    Success = 1,
    AvoidStack = 2,
}

Def.CameraDistanceLevel = {
    TppSeat = 0,
    Fpp = 1,
    TppClose = 2,
    TppMedium = 3,
    TppFar = 4,
}

Def.AutopilotSpeedLevel = {
    Slow = 1,
    Normal = 2,
    Fast = 3,
}

Def.FlightMode = {
    AV = 0,
    Helicopter = 1,
}

return Def