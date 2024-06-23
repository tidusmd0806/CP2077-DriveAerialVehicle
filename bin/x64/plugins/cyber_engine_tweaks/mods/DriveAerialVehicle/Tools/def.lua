---@class Def
Def = {}
Def.__index = Def

Def.ActionList = {
    Nothing = 0,
    HeliUp = 1,
    HeliDown = 2,
    HeliForward = 3,
    HeliBackward = 4,
    HeliRight = 5,
    HeliLeft = 6,
    HeliTurnRight = 7,
    HeliTurnLeft = 8,
    HeliHover = 9,
    HeliHold = 10,
	---------
    SpinnerForward = 31,
    SpinnerBackward = 32,
    SpinnerRightRotate = 33,
    SpinnerLeftRotate = 34,
    SpinnerUp = 35,
    SpinnerDown = 36,
    SpinnerRight = 37,
    SpinnerLeft = 38,
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
    ----------
    AutoPilot = 200,
}

Def.FlightMode = {
    Heli = "Helicopter",
    Spinner = "Spinner",
}

Def.Situation = {
    Idel = -1,
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

Def.PowerMode = {
    Off = 0,
    On = 1,
    Hold = 2,
    Hover = 3,
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

Def.SoundRestrictionLevel = {
    None = -1,
    Mute = 0,
    PriorityRadio = 1,
}

return Def