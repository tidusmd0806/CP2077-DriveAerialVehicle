local Log = require("Tools/log.lua")
local Hud = {}
Hud.__index = Hud

function Hud:New(engine_obj)

    local obj = {}
    obj.log_obj = Log:New()
    obj.log_obj:SetLevel(LogLevel.Info, "Hud")

    -- set default parameters
    obj.engine_obj = engine_obj
    obj.interaction_ui_base = nil
    obj.interaction_hub = nil
    obj.choice_title = "AV"
	obj.hud_car_controller = nil

    obj.is_speed_meter_shown = false

    return setmetatable(obj, self)
end

function Hud:Init(choice_title)

    self:SetOverride()
    self:SetObserve()
    self:SetChoiceTitle(choice_title)

end

function Hud:SetOverride()

    -- Overside choice ui (refer to https://www.nexusmods.com/cyberpunk2077/mods/7299)
    Override("InteractionUIBase", "OnDialogsData", function(_, arg_1, wrapped_method)
        local data = FromVariant(arg_1)
        local hubs = data.choiceHubs
        table.insert(hubs, self.interaction_hub)
        data.choiceHubs = hubs
        wrapped_method(ToVariant(data))
    end)

	Override("OpenVendorUI", "CreateInteraction", function(this, arg_1, arg_2, arg_3, wrapped_method)
        if this:GetActionName().value == "vehicle_door_quest_locked" then
            self.log_obj:Record(LogLevel.Debug, "Anti vehicle door quest locked")
            return
        end
        wrapped_method(arg_1, arg_2, arg_3)
    end)

end

function Hud:SetObserve()

    Observe("InteractionUIBase", "OnInitialize", function(this)
        self.interaction_ui_base = this
    end)

    Observe("InteractionUIBase", "OnDialogsData", function(this)
        self.interaction_ui_base = this
    end)

	Observe("hudCarController", "OnInitialize", function(this)
        self.hud_car_controller = this
    end)

    -- Observe("hudCarController", "drawRPMGaugeFull", function(this, rpmValue)
    --     print("drawRPMGaugeFull")
    -- end)

    Observe("hudCarController", "QueueBroadcastEvent", function(this, event)
        print("QueueBroadcastEvent")
        local name = event:ToString()
        print(name)
    end)

    Observe("hudCarController", "ProjectWorldToScreen", function(this, vector)
        print("ProjectWorldToScreen")
    end)

    Observe("hudCarController", "ShowGameNotification", function(this, value)
        print("ShowGameNotification")
    end)
    
    Observe("hudCarController", "OnVarModified", function(this, groupPath, varName, varType, reason)
        print("OnVarModified")
    end)

    
    Observe("hudCarController", "OnCameraModeChanged", function(this, mode)
        print("OnCameraModeChanged")
    end)
    
    Observe("hudCarController", "OnGearValueChanged", function(this, gearValue)
        print("OnGearValueChanged")
    end)
    
    Observe("hudCarController", "OnInitialize", function(this)
        print("OnInitialize")
    end)
    
    Observe("hudCarController", "OnLeanAngleChanged", function(this, leanAngle)
        print("OnLeanAngleChanged")
    end)
    
    Observe("hudCarController", "OnMountingEvent", function(this, evt)
        print("OnMountingEvent")
    end)
    
    Observe("hudCarController", "OnPlayerAttach", function(this, playerPuppet)
        print("OnPlayerAttach")
    end)
    
    Observe("hudCarController", "OnPlayerDetach", function(this, playerPuppet)
        print("OnPlayerDetach")
    end)
    
    Observe("hudCarController", "OnRpmMaxChanged", function(this, rpmMax)
        print("OnRpmMaxChanged")
    end)
    
    -- Observe("hudCarController", "OnRpmValueChanged", function(this, rpmValue)
    --     print("OnRpmValueChanged")
    -- end)
    
    -- Observe("hudCarController", "OnSpeedValueChanged", function(this, speedValue)
    --     print("OnSpeedValueChanged")
    -- end)
    
    Observe("hudCarController", "OnUninitialize", function(this)
        print("OnUninitialize")
    end)
    
    -- Observe("hudCarController", "OnUnmountingEvent", function(this, evt)
    --     print("OnUnmountingEvent")
    -- end)

    Override("hudCarController", "OnUnmountingEvent", function(this, evt, met)
        print("OnUnmountingEvent")
    end)
    
    Observe("hudCarController", "OnZoomChange", function(this, evt)
        print("OnZoomChange")
    end)
    
    Observe("hudCarController", "SetMeasurementUnits", function(this, value)
        print("SetMeasurementUnits")
        print(value)
    end)
    
    Observe("hudCarController", "CheckIfInTPP", function(this)
        print("CheckIfInTPP")
    end)
    
    -- Observe("hudCarController", "EvaluateRPMMeterWidget", function(this, currentAmountOfChunks)
    --     print("EvaluateRPMMeterWidget")
    -- end)
    
    -- Observe("hudCarController", "RegisterToVehicle", function(this, register)
    --     print("RegisterToVehicle")
    --     if register then
    --         print("true")
    --     else
    --         print("false")
    --     end
    -- end)

    Override("hudCarController", "RegisterToVehicle", function(this, register, method)
        print("RegisterToVehicle")
        if register then
            method(register)
        else
            print("false")
        end
    end)
    
    Observe("hudCarController", "RegisterUserSettingsListener", function(this)
        print("RegisterUserSettingsListener")
    end)
    
    Observe("hudCarController", "Reset", function(this)
        print("Reset")
    end)
    
    Observe("hudCarController", "UpdateChunkVisibility", function(this)
        print("UpdateChunkVisibility")
    end)
    
    Observe("hudCarController", "UpdateMeasurementUnits", function(this)
        print("UpdateMeasurementUnits")
    end)

    Observe("hudCarController", "GetIntroAnimation", function(this)
        print("GetIntroAnimation")
    end)
    
    Observe("hudCarController", "GetOutroAnimation", function(this)
        print("GetOutroAnimation")
    end)
    
    Observe("hudCarController", "ToggleVisibility", function(this, value, isSkippingInOutAnimation)
        print("ToggleVisibility")
        if value then
            print("true")
        else
            print("false")
        end
        if isSkippingInOutAnimation then
            print("true")
        else
            print("false")
        end
    end)
    
    Observe("hudCarController", "UpdateRequired", function(this)
        print("UpdateRequired")
    end)
    
    Observe("hudCarController", "HideRequest", function(this)
        print("HideRequest")
    end)
    
    Observe("hudCarController", "IsPlayingMultiplayer", function(this)
        print("IsPlayingMultiplayer")
    end)
    
    Observe("hudCarController", "OnHideAnimationFinished", function(this, anim)
        print("OnHideAnimationFinished")
    end)
    
    Observe("hudCarController", "OnPlayInitFoldingAnimFinished", function(this, anim)
        print("OnPlayInitFoldingAnimFinished")
    end)
    
    Observe("hudCarController", "PlayInitFoldingAnim", function(this)
        print("PlayInitFoldingAnim")
    end)
    
    Observe("hudCarController", "ShowRequest", function(this)
        print("ShowRequest")
    end)
    
    Observe("hudCarController", "CreateContextChangeAnimations", function(this)
        print("CreateContextChangeAnimations")
    end)

    Observe("hudCarController", "AsyncSpawnFromExternal", function(this, spawnData, callbackObject, callbackFunctionName)
        print("AsyncSpawnFromExternal")
    end)
    
    Observe("hudCarController", "AsyncSpawnFromExternal", function(this, parentWidget, resourcePath, libraryID, callbackObject, callbackFunctionName, userData)
        print("AsyncSpawnFromExternal")
    end)
    
    Observe("hudCarController", "AsyncSpawnFromLocal", function(this, spawnData, callbackObject, callbackFunctionName)
        print("AsyncSpawnFromLocal")
    end)
    
    Observe("hudCarController", "AsyncSpawnFromLocal", function(this, parentWidget, libraryID, callbackObject, callbackFunctionName, userData)
        print("AsyncSpawnFromLocal")
    end)
    
    Observe("hudCarController", "CallCustomCallback", function(this, eventName)
        print("CallCustomCallback")
    end)
    
    Observe("hudCarController", "FindLibraryID", function(this, widgetRecord, screenTypeRecord, styleRecord, id, path)
        print("FindLibraryID")
    end)
    
    Observe("hudCarController", "FindWidgetDataInLibrary", function(this, parentWidget, widgetRecord, screenTypeRecord, styleRecord, id, path)
        print("FindWidgetDataInLibrary")
    end)
    
    Observe("hudCarController", "FindWidgetInLibrary", function(this, parentWidget, widgetRecord, screenTypeRecord, styleRecord, id, path)
        print("FindWidgetInLibrary")
    end)
    
    Observe("hudCarController", "GetChildControllerByPath", function(this, widgetNamePath)
        print("GetChildControllerByPath")
    end)
    
    Observe("hudCarController", "GetChildWidgetByPath", function(this, widgetNamePath)
        print("GetChildWidgetByPath")
    end)
    
    Observe("hudCarController", "GetController", function(this, path)
        print("GetController")
    end)
    
    Observe("hudCarController", "GetController", function(this, widgetNamePath)
        print("GetController")
    end)
    
    Observe("hudCarController", "GetControllerByType", function(this, controllerType, path)
        print("GetControllerByType")
    end)
    
    Observe("hudCarController", "GetControllers", function(this, path)
        print("GetControllers")
    end)
    
    Observe("hudCarController", "GetControllersByType", function(this, controllerType, path)
        print("GetControllersByType")
    end)
    
    Observe("hudCarController", "GetNumControllers", function(this, path)
        print("GetNumControllers")
    end)
    
    Observe("hudCarController", "GetNumControllersOfType", function(this, controllerType, path)
        print("GetNumControllersOfType")
    end)
    
    Observe("hudCarController", "GetRootCompoundWidget", function(this)
        print("GetRootCompoundWidget")
    end)
    
    -- Observe("hudCarController", "GetRootWidget", function(this)
    --     print("GetRootWidget")
    -- end)
    
    Observe("hudCarController", "GetSystemRequestsHandler", function(this)
        print("GetSystemRequestsHandler")
    end)
    
    Observe("hudCarController", "GetWidget", function(this, path)
        print("GetWidget")
    end)
    
    Observe("hudCarController", "GetWidget", function(this, widgetNamePath)
        print("GetWidget")
    end)
    
    Observe("hudCarController", "HasExternalLibrary", function(this, resourcePath, libraryID)
        print("HasExternalLibrary")
    end)
    
    Observe("hudCarController", "HasLocalLibrary", function(this, libraryID)
        print("HasLocalLibrary")
    end)
    
    Observe("hudCarController", "IsKeyboardConnected", function(this)
        print("IsKeyboardConnected")
    end)
    
    Observe("hudCarController", "PlayLibraryAnimation", function(this, animationName, playbackOptions)
        print("PlayLibraryAnimation")
    end)
    
    Observe("hudCarController", "PlayLibraryAnimationOnAutoSelectedTargets", function(this, animationName, target, playbackOptions)
        print("PlayLibraryAnimationOnAutoSelectedTargets")
    end)
    
    Observe("hudCarController", "PlayLibraryAnimationOnTargets", function(this, animationName, targets, playbackOptions)
        print("PlayLibraryAnimationOnTargets")
    end)
    
    Observe("hudCarController", "QueueEvent", function(this, evt)
        print("QueueEvent")
        local name = evt:ToString()
        print(name)

    end)
    
    Observe("hudCarController", "RegisterToCallback", function(this, eventName, object, functionName)
        print("RegisterToCallback")
        print(eventName)
        print(object:GetClassName())
        print(functionName)
    end)
    
    Observe("hudCarController", "RegisterToGlobalInputCallback", function(this, eventName, object, functionName)
        print("RegisterToGlobalInputCallback")
    end)
    
    Observe("hudCarController", "RequestProcessFitToViewport", function(this)
        print("RequestProcessFitToViewport")
    end)
    
    Observe("hudCarController", "RequestSetFocus", function(this, widget)
        print("RequestSetFocus")
    end)
    
    Observe("hudCarController", "RequestWidgetFromLibrary", function(this, parentWidget, widgetRecord, screenTypeRecord, styleRecord, id, path, spawnData)
        print("RequestWidgetFromLibrary")
    end)

    Observe("hudCarController", "RequestWidgetFromLibraryById", function(this, parentWidget, id, path, spawnData, asyncSpawnRequest)
        print("RequestWidgetFromLibraryById")
    end)
    
    Observe("hudCarController", "RequestWidgetFromLibraryByRecord", function(this, parentWidget, widgetRecord, screenTypeRecord, styleRecord, spawnData, asyncSpawnRequest)
        print("RequestWidgetFromLibraryByRecord")
    end)
    
    Observe("hudCarController", "SpawnFromExternal", function(this, parentWidget, resourcePath, libraryID)
        print("SpawnFromExternal")
        print(parentWidget.name)
        print(libraryID)
    end)
    
    Observe("hudCarController", "SpawnFromLocal", function(this, parentWidget, libraryID)
        print("SpawnFromLocal")
        print(parentWidget.name)
        print(libraryID)
    end)
    
    Observe("hudCarController", "UnregisterFromCallback", function(this, eventName, object, functionName)
        print("UnregisterFromCallback")
    end)
    
    Observe("hudCarController", "UnregisterFromGlobalInputCallback", function(this, eventName, object, functionName)
        print("UnregisterFromGlobalInputCallback")
    end)
    
    Observe("hudCarController", "CreateWidget", function(this, parentWidget, id, path)
        print("CreateWidget")
    end)
    
    Observe("hudCarController", "CreateWidgetAsync", function(this, parentWidget, id, path, spawnData)
        print("CreateWidgetAsync")
    end)
    
    Observe("hudCarController", "ReadUICondition", function(this, condition)
        print("ReadUICondition")
    end)

end

function Hud:SetChoiceTitle(title)
    self.choice_title = title
end

function Hud:ShowChoice()

    local choice = gameinteractionsvisListChoiceData.new()
    choice.localizedName = GetLocalizedText("LocKey#81569")
    choice.inputActionName = CName.new("click")

    local hub = gameinteractionsvisListChoiceHubData.new()
    hub.title = self.choice_title
    hub.choices = {choice}
    hub.activityState = gameinteractionsvisEVisualizerActivityState.Active
    hub.hubPriority = 1
    hub.id = 6083991

    self.interaction_hub = hub

    local ui_interaction_define = GetAllBlackboardDefs().UIInteractions;
    local interaction_blackboard = Game.GetBlackboardSystem():Get(ui_interaction_define)

    interaction_blackboard:SetInt(ui_interaction_define.ActiveChoiceHubID, self.interaction_hub.id)
    local data = interaction_blackboard:GetVariant(ui_interaction_define.DialogChoiceHubs)
    self.interaction_ui_base:OnDialogsData(data)

end

function Hud:HideChoice()

    self.interaction_hub = nil

    local ui_interaction_define = GetAllBlackboardDefs().UIInteractions;
    local interaction_blackboard = Game.GetBlackboardSystem():Get(ui_interaction_define)

    local data = interaction_blackboard:GetVariant(ui_interaction_define.DialogChoiceHubs)
    self.interaction_ui_base:OnDialogsData(data)

end

function Hud:ShowMeter()
    self.hud_car_controller:OnInitialize()
    -- self.hud_car_controller = hudCarController.new()
    -- self.hud_car_controller:Reset()
    -- self.hud_car_controller:ToggleVisibility(true, false)
    self.hud_car_controller:ShowRequest()
    -- self.hud_car_controller:UpdateChunkVisibility()
    -- self.hud_car_controller:ShowRequest()self.hud_car_controller:RegisterUserSettingsListener()
    self.hud_car_controller:OnCameraModeChanged(true)
    self.hud_car_controller:UpdateMeasurementUnits()
    if self.is_speed_meter_shown then
        return
    else
        self.is_speed_meter_shown = true
        DAV.Cron.Every(1, function()
            local coordinate_speed = math.sqrt(self.engine_obj.horizenal_x_speed * self.engine_obj.horizenal_x_speed 
                                                + self.engine_obj.horizenal_y_speed * self.engine_obj.horizenal_y_speed 
                                                + self.engine_obj.vertical_speed * self.engine_obj.vertical_speed)
            local mph = coordinate_speed * (3600 / 1600)
            local power_level = math.floor((self.engine_obj.lift_force - self.engine_obj.min_lift_force) / ((self.engine_obj.max_lift_force - self.engine_obj.min_lift_force) / 10))
            self.hud_car_controller:OnSpeedValueChanged(mph / 3)
            self.hud_car_controller:OnRpmValueChanged(power_level)
            self.hud_car_controller:EvaluateRPMMeterWidget(power_level)
            if not self.is_speed_meter_shown then
                DAV.Cron.Halt()
            end
        end)
    end
end

function Hud:HideMeter()
    self.hud_car_controller:HideRequest()
    self.hud_car_controller:OnCameraModeChanged(false)
    self.is_speed_meter_shown = false
end

return Hud