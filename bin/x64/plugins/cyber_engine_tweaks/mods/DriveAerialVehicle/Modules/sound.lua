local Log = require("Tools/log")
local Utils = require("Tools/utils")

local Sound = {}
Sound.__index = Sound

function Sound:New()
    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Sound")

    obj.sound_data = {}
    obj.playing_sound = {}

    return setmetatable(obj, self)
end

function Sound:Init()
    self.sound_data = Utils:ReadJson("Data/sound.json")
end

function Sound:PlaySound(sound_name)

    local event = PlaySoundEvent.new()
    event.soundEvent = CName.new(self.sound_data[sound_name])
    Game.GetPlayer():PlaySoundEvent(self.sound_data[sound_name])
    table.insert(self.playing_sound, {sound_name = sound_name, event = event})
    return true
end

function Sound:StopSound(sound_name)
    for index, value in ipairs(self.playing_sound) do
        if value.sound_name == sound_name then
            Game.GetPlayer():StopSoundEvent(value.event)
            table.remove(self.playing_sound, index)
            return true
        end
    end
    return false
end

function Sound:StopAllSound()
    for index, value in ipairs(self.playing_sound) do
        Game.GetPlayer():StopSoundEvent(value.event)
    end
    self.playing_sound = {}
end

return Sound