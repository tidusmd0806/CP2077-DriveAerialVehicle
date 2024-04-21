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
    obj.is_loop = false

    return setmetatable(obj, self)
end

function Sound:Init()
    self.sound_data = Utils:ReadJson("Data/sound.json")
end

function Sound:PlaySound(sound_name)
    Game.GetPlayer():PlaySoundEvent(self.sound_data[sound_name])
end

function Sound:PlaySoundComplex(sound_name, delay_time, is_loop, duration, loop_time)

    Cron.After(delay_time, function()
        if is_loop then
            Cron.Every(duration, {tick = 1} , function(timer)
                timer.tick = timer.tick + 1
                Game.GetPlayer():PlaySoundEvent(self.sound_data[sound_name])
                if timer.tick * duration >= loop_time then
                    Game.GetPlayer():StopSoundEvent(self.sound_data[sound_name])
                    Cron.Halt(timer)
                end
            end)
        else
            Game.GetPlayer():PlaySoundEvent(self.sound_data[sound_name])
        end
    end)
end

function Sound:StopSound(sound_name)
    Game.GetPlayer():StopSoundEvent(self.sound_data[sound_name])
end

return Sound