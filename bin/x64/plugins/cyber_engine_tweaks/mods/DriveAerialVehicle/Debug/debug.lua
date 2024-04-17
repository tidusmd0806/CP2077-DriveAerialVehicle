local Def = require("Tools/def.lua")
local Log = require("Tools/log.lua")
local Utils = require("Tools/utils.lua")
local Debug = {}
Debug.__index = Debug

function Debug:New(core_obj)
    local obj = {}
    obj.core_obj = core_obj

    -- set parameters
    obj.is_print_command = false
    obj.is_im_gui_situation = false
    obj.is_im_gui_player_position = false
    obj.is_im_gui_av_position = false
    obj.is_im_gui_lift_force = false
    obj.is_im_gui_engine_info = false
    obj.is_im_gui_sound_check = false
    obj.is_im_gui_mappin_position = false

    obj.selected_sound = "first"
    return setmetatable(obj, self)
end

function Debug:Init()
    ImGui.SetNextWindowPos(100, 500, ImGuiCond.FirstUseEver) -- set window position x, y
    ImGui.SetNextWindowSize(800, 1000, ImGuiCond.Appearing) -- set window size w, h
    ImGui.Begin("DAV DEBUG WINDOW")
    ImGui.Text("Debug Mode : On")
end

function Debug:End()
    ImGui.End()
end

function Debug:SelectPrint()
    self.is_print_command = ImGui.Checkbox("[Print] Action Command", self.is_print_command)
end

function Debug:ImGuiMain()

    self:Init()
    self:SetLogLevel()
    self:ImGuiSituation()
    self:ImGuiPlayerPosition()
    self:ImGuiAVPosition()
    self:ImGuiLiftForceAndSpeed()
    self:ImGuiCurrentEngineInfo()
    self:ImGuiSoundCheck()
    self:ImGuiMappinPosition()
    self:ImGuiExcuteFunction()
    self:SelectPrint()

end

function Debug:SetLogLevel()
    local selected = false
    if ImGui.BeginCombo("LogLevel", Utils:GetKeyFromValue(LogLevel, MasterLogLevel)) then
		for _, key in ipairs(Utils:GetKeys(LogLevel)) do
			if Utils:GetKeyFromValue(LogLevel, MasterLogLevel) == key then
				selected = true
			else
				selected = false
			end
			if(ImGui.Selectable(key, selected)) then
				MasterLogLevel = LogLevel[key]
			end
		end
		ImGui.EndCombo()
	end
end

function Debug:ImGuiSituation()
    self.is_im_gui_situation = ImGui.Checkbox("[ImGui] Current Situation", self.is_im_gui_situation)
    if self.is_im_gui_situation then
        ImGui.Text("Current Situation : " .. self.core_obj.event_obj.current_situation)
    end
end

function Debug:ImGuiPlayerPosition()
    self.is_im_gui_player_position = ImGui.Checkbox("[ImGui] Player Position Angle", self.is_im_gui_player_position)
    if self.is_im_gui_player_position then
        local x = string.format("%.2f", Game.GetPlayer():GetWorldPosition().x)
        local y = string.format("%.2f", Game.GetPlayer():GetWorldPosition().y)
        local z = string.format("%.2f", Game.GetPlayer():GetWorldPosition().z)
        ImGui.Text("[world]X:" .. x .. ", Y:" .. y .. ", Z:" .. z)
        local roll = string.format("%.2f", Game.GetPlayer():GetWorldOrientation():ToEulerAngles().roll)
        local pitch = string.format("%.2f", Game.GetPlayer():GetWorldOrientation():ToEulerAngles().pitch)
        local yaw = string.format("%.2f", Game.GetPlayer():GetWorldOrientation():ToEulerAngles().yaw)
        ImGui.Text("[world]Roll:" .. roll .. ", Pitch:" .. pitch .. ", Yaw:" .. yaw)
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        local absolute_position = Utils:WorldToBodyCoordinates(Game.GetPlayer():GetWorldPosition(), self.core_obj.av_obj.position_obj:GetPosition(), self.core_obj.av_obj.position_obj:GetQuaternion())
        local absolute_position_x = string.format("%.2f", absolute_position.x)
        local absolute_position_y = string.format("%.2f", absolute_position.y)
        local absolute_position_z = string.format("%.2f", absolute_position.z)
        ImGui.Text("[local]X:" .. absolute_position_x .. ", Y:" .. absolute_position_y .. ", Z:" .. absolute_position_z)
    end
end

function Debug:ImGuiAVPosition()
    self.is_im_gui_av_position = ImGui.Checkbox("[ImGui] AV Position Angle", self.is_im_gui_av_position)
    if self.is_im_gui_av_position then
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        local x = string.format("%.2f", self.core_obj.av_obj.position_obj:GetPosition().x)
        local y = string.format("%.2f", self.core_obj.av_obj.position_obj:GetPosition().y)
        local z = string.format("%.2f", self.core_obj.av_obj.position_obj:GetPosition().z)
        local roll = string.format("%.2f", self.core_obj.av_obj.position_obj:GetEulerAngles().roll)
        local pitch = string.format("%.2f", self.core_obj.av_obj.position_obj:GetEulerAngles().pitch)
        local yaw = string.format("%.2f", self.core_obj.av_obj.position_obj:GetEulerAngles().yaw)
        ImGui.Text("X: " .. x .. ", Y: " .. y .. ", Z: " .. z)
        ImGui.Text("Roll:" .. roll .. ", Pitch:" .. pitch .. ", Yaw:" .. yaw)
    end
end

function Debug:ImGuiLiftForceAndSpeed()
    self.is_im_gui_lift_force = ImGui.Checkbox("[ImGui] Lift Force And Speed", self.is_im_gui_lift_force)
    if self.is_im_gui_lift_force then
        if self.core_obj.av_obj.position_obj.entity == nil then
            return
        end
        local v_x = string.format("%.2f", self.core_obj.av_obj.engine_obj.horizenal_x_speed)
        local v_y = string.format("%.2f", self.core_obj.av_obj.engine_obj.horizenal_y_speed)
        local v_z = string.format("%.2f", self.core_obj.av_obj.engine_obj.vertical_speed)
        ImGui.Text("F: " .. self.core_obj.av_obj.engine_obj.lift_force .. ", v_x: " .. v_x .. ", v_y: " .. v_y .. ", v_z: " .. v_z)
    end
end

function Debug:ImGuiCurrentEngineInfo()
    self.is_im_gui_engine_info = ImGui.Checkbox("[ImGui] Current Engine Info", self.is_im_gui_engine_info)
    if self.is_im_gui_engine_info then
        local v = string.format("%.2f", self.core_obj.av_obj.engine_obj.current_speed)
        ImGui.Text("Current Power Mode : " .. self.core_obj.av_obj.engine_obj.current_mode .. ", Current Speed : " .. v)
    end
end

function Debug:ImGuiSoundCheck()
    self.is_im_gui_sound_check = ImGui.Checkbox("[ImGui] Sound Check", self.is_im_gui_sound_check)
    if self.is_im_gui_sound_check then
        if ImGui.BeginCombo("##Sound List", self.selected_sound) then
            for key, _ in pairs(self.core_obj.event_obj.sound_obj.sound_data) do
                if (ImGui.Selectable(key, (self.selected_sound==key))) then
                    self.selected_sound = key
                end
            end
            ImGui.EndCombo()
        end

        if ImGui.Button("Play", 150, 60) then
            self.core_obj.event_obj.sound_obj:PlaySound(self.selected_sound)
        end

        if ImGui.Button("Stop", 150, 60) then
            self.core_obj.event_obj.sound_obj:StopSound(self.selected_sound)
        end
    end
end

function Debug:ImGuiMappinPosition()
    self.is_im_gui_mappin_position = ImGui.Checkbox("[ImGui] Custom Mappin Position", self.is_im_gui_mappin_position)
    if self.is_im_gui_mappin_position then
        local x = string.format("%.2f", self.core_obj.current_custom_mappin_position.x)
        local y = string.format("%.2f", self.core_obj.current_custom_mappin_position.y)
        local z = string.format("%.2f", self.core_obj.current_custom_mappin_position.z)
        ImGui.Text("X: " .. x .. ", Y: " .. y .. ", Z: " .. z)
    end
end

function Debug:ImGuiExcuteFunction()
    if ImGui.Button("Test Function 1",300, 60) then
        local seat_number = DAV.core_obj.av_obj.seat_index
    
        local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
        local player = Game.GetPlayer()
        local ent_id = entity:GetEntityID()
        local seat = DAV.core_obj.av_obj.active_seat[seat_number]
    
        local data = NewObject('handle:gameMountEventData')
        data.isInstant = true
        data.slotName = seat
        data.mountParentEntityId = ent_id
        data.entryAnimName = "forcedTransition"
    
        local slotID = NewObject('gamemountingMountingSlotId')
        slotID.id = seat
    
        local mounting_info = NewObject('gamemountingMountingInfo')
        mounting_info.childId = player:GetEntityID()
        mounting_info.parentId = ent_id
        mounting_info.slotId = slotID
    
        local mount_event = NewObject('handle:gamemountingUnmountingRequest')
        mount_event.lowLevelMountingInfo = mounting_info
        mount_event.mountData = data
    
        Game.GetMountingFacility():Unmount(mount_event)

        local player_past_pos = Game.GetPlayer():GetWorldPosition()
        -- set entity id to position object
        DAV.Cron.Every(0.001, {tick = 1}, function(timer)
            local player_current_pos = Game.GetPlayer():GetWorldPosition()
            local distance = Vector4.Distance(player_past_pos, player_current_pos)
            if distance > 1 then
            
                local entity = Game.FindEntityByID(DAV.core_obj.av_obj.entity_id)
                local player = Game.GetPlayer()
                local ent_id = entity:GetEntityID()
                local seat = DAV.core_obj.av_obj.active_seat[seat_number]
            
            
                local data = NewObject('handle:gameMountEventData')
                data.isInstant = false
                data.slotName = seat
                data.mountParentEntityId = ent_id
                data.entryAnimName = "stand__2h_on_sides__01__to__sit_couch__AV_excalibur__01__turn270__getting_into_AV__01"
            
            
                local slot_id = NewObject('gamemountingMountingSlotId')
                slot_id.id = seat
            
                local mounting_info = NewObject('gamemountingMountingInfo')
                mounting_info.childId = player:GetEntityID()
                mounting_info.parentId = ent_id
                mounting_info.slotId = slot_id
            
                local mounting_request = NewObject('handle:gamemountingMountingRequest')
                mounting_request.lowLevelMountingInfo = mounting_info
                mounting_request.mountData = data
            
                Game.GetMountingFacility():Mount(mounting_request)
            
                DAV.core_obj.av_obj.position_obj:ChangePosition()
            
                -- return position near mounted vehicle	
                DAV.Cron.Every(1, {tick = 1}, function(timer)
                    local entity = player:GetMountedVehicle()
                    if entity ~= nil then
                        DAV.Cron.Halt(timer)
                    end
                end)
                DAV.Cron.Halt(timer)
            end
        end)

        
        print("Excute Test Function 1")
    end
    if ImGui.Button("Test Function 2",300, 60) then
        print("Excute Test Function 2")
    end
    if ImGui.Button("Test Function 3",300, 60) then
        if DAV.debug_param_1 == false then
            DAV.debug_param_1 = true
            DAV.Cron.Every(1, {tick = 0}, function(timer)
                timer.tick = timer.tick + 1
                if DAV.debug_param_1 == false then
                    print("Telep Stop Time:" .. timer.tick .. "s")
                    DAV.Cron.Halt(timer)
                end
            end)
        else
            DAV.debug_param_1 = false
        end
        print("Excute Test Function 3")
    end
end

function Debug:PrintActionCommand(action_name, action_type, action_value)
    if self.is_print_command then
        print("Action Name : " .. action_name .. ", Action Type : " .. action_type, ", Action Value : " .. action_value)
    end
end

return Debug
