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
	---------
	Enter= 100,
	Exit = 101,
	ChangeCamera = 102,
	ChangeDoor1 = 103,
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

Def.CameraDistanceLevel = {
    Fpp = 0,
    TppClose = 1,
    TppMedium = 2,
    TppFar = 3
}

return Def