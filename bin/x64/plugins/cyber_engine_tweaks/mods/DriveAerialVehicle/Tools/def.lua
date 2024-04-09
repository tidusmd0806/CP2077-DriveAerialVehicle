Def = {}
Def.__index = Def

Def.ActionList = {
    Nothing = 0,
    Up = 1,
    Down = 2,
    Forward = 3,
    Backward = 4,
    Right = 5,
    Left = 6,
    TurnRight = 7,
    TurnLeft = 8,
    Hover = 9,
    Hold = 10,
	---------
	Enter= 100,
	Exit = 101,
	ChangeCamera = 102,
	ChangeDoor1 = 103,
    ----------
    AutoPilot = 200,
}

Def.Situation = {
    Normal = 0,
    Landing = 1,
    Waiting = 2,
    InVehicle = 3,
    TalkingOff = 4,
}

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

return Def