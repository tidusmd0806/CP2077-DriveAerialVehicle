DAV = {
	description = "Drive an Aerodyne Vehicele",
	version = "0.1",
    ready = false,
    is_debug_mode = true,
    time_resolution = 0.01,
    ui_choice_hub = nil,
    ui_choice_handler = nil,
    is_ui_choice_custom = false
}

-- import modules
DAV.Cron = require('External/Cron.lua')
DAV.Core = require('Modules/core.lua')
DAV.Debug = require('Debug/debug.lua')

-- create instances
DAV.core_obj = DAV.Core:New()
DAV.debug_obj = DAV.Debug:New(DAV.core_obj)

registerForEvent('onInit', function()

    DAV.core_obj:Init()

    -- Observe player action
    Observe("PlayerPuppet", "OnAction", function(self, action)
        local action_name = Game.NameToString(action:GetName(action))
		local action_type = action:GetType(action).value
        local action_value = action:GetValue(action)

        if DAV.is_debug_mode then
            DAV.debug_obj:PrintActionCommand(action_name, action_type, action_value)
        end

        DAV.core_obj:StorePlayerAction(action_name, action_type, action_value)

    end)

    -- Overside choice ui (refer to https://www.nexusmods.com/cyberpunk2077/mods/7299)
    Override("InteractionUIBase", "OnDialogsData", function(_, value, wrapped_method)
        local data = FromVariant(value)
        local hubs = data.choiceHubs
        table.insert(hubs, DAV.ui_choice_hub)
        data.choiceHubs = hubs
        wrapped_method(ToVariant(data))
    end)

    -- Observe("InteractionUIBase", "OnDialogsData", function(self)
    --     DAV.ui_choice_handler = self
    -- end)

    Observe("InteractionUIBase", "OnInitialize", function(self)
        DAV.ui_choice_handler = self
    end)

    -- -- Device interactions causing UI flickering
    -- Override("InteractionUIBase", "OnInteractionData", function(_, value, wrapped_method)
    --     if DAV.is_ui_choice_custom then return end
    --     wrapped_method(value)
    -- end)

    Override("UISystem", "QueueEvent", function(_, value, wrapped_method)
        local name = value:ToString()
        -- print(name)
        if name == "gameuiUpdateInputHintEvent" then
            print("--------")
            print(value.data.action.value)
            print(value.data.source.value)
            print(value.targetHintContainer.value)
            print("--------")
        end
        if name == "UIVendorAttachedEvent" then
            local ib = Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UI_Vendor)
            local ibd = GetAllBlackboardDefs().UI_Vendor
            -- print("--------")
            -- print(value.vendorID)
            -- print(value.vendorObject)
            -- print("--------")
        end
        wrapped_method(value)
    end)

    Override("OpenVendorUI", "CreateInteraction", function(self, value_1, value_2, value_3, wrapped_method)
        -- print(self:GetActionName().value)
        if self:GetActionName().value == "vehicle_door_quest_locked" then
            print("OpenVendorUI")
            return
        end
        wrapped_method(value_1, value_2, value_3)
    end)

    Observe("hudCarController", "OnInitialize", function(self)
        print("OnInitialize")
        DAV.hudCarController = self
        return true
    end)

    DAV.ready = true
    print('Drive an Aerodyne Vehicle Mod is ready!')
end)

-- Debug Window
registerForEvent("onDraw", function()
    if DAV.is_debug_mode then
        DAV.debug_obj:ImGuiMain()
    end
end)

registerHotkey('CallAerodyneVehicle', 'Call Aerodyne Vehicle', function()
    DAV.core_obj:CallAerodyneVehicle()
end)

registerHotkey('ChangeAerodyneDoor', 'Change Door (TMP)', function()
    DAV.core_obj:ChangeAerodyneDoor(1)
end)

registerHotkey('LockAerodyneDoor', 'Lock (TMP)', function()
    DAV.core_obj:LockAerodyneDoor()
end)

registerHotkey('UnlockAerodyneDoor', 'Unlock (TMP)', function()
    DAV.core_obj:UnlockAerodyneDoor()
end)

registerHotkey('Mount', 'Mount (TMP)', function()
    DAV.core_obj:Mount(3)
end)

registerHotkey('Unmount', 'Unmount (TMP)', function()
    DAV.core_obj:Unmount()
end)

registerForEvent('onUpdate', function(delta)
    -- This is required for Cron to function
    DAV.Cron.Update(delta)
end)

return DAV