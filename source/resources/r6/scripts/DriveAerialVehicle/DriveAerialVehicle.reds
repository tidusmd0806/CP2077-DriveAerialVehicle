// Title: Drive an Aerial Vehicle HUD Popup And Audio System
// Author: tidusmd
// Version: 3.1.0
// The code of UI was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)
// CopyRight (C) 2024, tidusmd. All rights reserved.

module DAV
import DAV.AutopilotMenu.*
import Codeware.UI.*
import Audioware.*

//*** Aerial Vehicle Popup UI ***//
public class AerialVehiclePopup extends InGamePopup {
	protected let m_header: ref<InGamePopupHeader>;
	protected let m_footer: ref<InGamePopupFooter>;
	protected let m_content: ref<InGamePopupContent>;
	protected let m_autopilot_base: ref<AutopilotBase>;
	protected let m_wrapper: wref<AerialVehiclePopupWrapper>;

	protected cb func OnCreate() {
		super.OnCreate();

		this.m_container.SetAnchor(inkEAnchor.Centered);
		this.m_container.SetMargin(0, 30, 0, 0);
		this.m_container.SetWidth(2000.0);
		this.m_container.SetHeight(1500.0);

		this.m_header = InGamePopupHeader.Create();
		this.m_header.SetTitle(this.m_wrapper.GetTranslation("ui_popup_title"));
		this.m_header.SetFluffRight(this.m_wrapper.GetTranslation("ui_popup_header"));
		this.m_header.Reparent(this);

		this.m_footer = InGamePopupFooter.Create();
		this.m_footer.SetFluffIcon(n"fluff_triangle2");
		this.m_footer.SetFluffText(this.m_wrapper.GetTranslation("ui_popup_footer"));
		this.m_footer.Reparent(this);

		this.m_content = InGamePopupContent.Create();
		this.m_content.Reparent(this);

		this.m_autopilot_base = AutopilotBase.Create(this.m_wrapper);
		this.m_autopilot_base.SetSize(this.m_content.GetSize());
		this.m_autopilot_base.Reparent(this.m_content);
	}

	protected cb func OnInitialize() {
		super.OnInitialize();

		this.m_autopilot_base.SetHints(this.m_footer.GetHints());
	}

	protected cb func OnUninitialize() {
		super.OnUninitialize();
		this.m_wrapper.SetOpenFlag(false);
	}

	public func UseCursor() -> Bool {
		return true;
	}

	public func SetWrapper(wrapper: ref<AerialVehiclePopupWrapper>) {
		this.m_wrapper = wrapper;
	}

	public func Show(requester: ref<inkGameController>){
		this.Open(requester);
	}

	public func SetDestination(mappim_address: String, selected_number: Int32) {
		this.m_autopilot_base.SetDestination(mappim_address, selected_number);
	}

	public func SetFavoriteList(favorite_list: array<String>) {
		this.m_autopilot_base.SetFavoriteList(favorite_list);
	}

	public func SetCurrentAddress(address: String) {
		this.m_autopilot_base.SetCurrentAddress(address);
	}

	public func GetSelectedNumber() -> Int32 {
		return this.m_autopilot_base.GetSelectedNumber();
	}

	public func GetFavoriteList() -> array<String> {
		return this.m_autopilot_base.GetFavoriteList();
	}
	
}

public class AerialVehiclePopupWrapper {
	protected let m_aerial_vehicle_popup: ref<AerialVehiclePopup>;
	protected let m_is_popup_open: Bool;
	protected let m_selected_number: Int32;
	protected let m_favorite_list: array<String>;
	protected let m_translation_system: ref<TranslationSystem>;

	public func Create() {
		this.m_aerial_vehicle_popup = new AerialVehiclePopup();
		this.m_translation_system = new TranslationSystem();
		this.m_translation_system.InitializeKey();
		this.m_aerial_vehicle_popup.SetWrapper(this);
	}

	public func Show(requester: ref<inkGameController>) {
		this.m_is_popup_open = true;
		this.m_aerial_vehicle_popup.Show(requester);
	}

	public func IsClosed() -> Bool {
		if !(this.m_is_popup_open) {
			return true;
		} else {
			this.SetAutopilotData();
			return false;
		}
	}

	public func GetSelectedNumber() -> Int32 {
		return this.m_selected_number;
	}

	public func GetFavoriteList() -> array<String> {
		return this.m_favorite_list;
	}

	public func SetOpenFlag(is_open: Bool) {
		this.m_is_popup_open = is_open;
	}

	public func Initialize(favorite_list: array<String>, mappim_address: String, current_address: String, selected_number: Int32) {
		this.m_favorite_list = favorite_list;
		this.m_selected_number = selected_number;
		this.m_aerial_vehicle_popup.SetFavoriteList(favorite_list);
		this.m_aerial_vehicle_popup.SetDestination(mappim_address, selected_number);
		this.m_aerial_vehicle_popup.SetCurrentAddress(current_address);
	}

	public func SetAutopilotData() {
		this.m_selected_number = this.m_aerial_vehicle_popup.GetSelectedNumber();
		this.m_favorite_list = this.m_aerial_vehicle_popup.GetFavoriteList();
	}

	public func SetTranslation(key: String, value: String) {
		this.m_translation_system.SetValue(key, value);
	}

	public func GetTranslation(key: String) -> String {
		return this.m_translation_system.GetValue(key);
	}
}

public class TranslationSystem {
	protected let m_key_list: array<String>;
	protected let m_value_list: array<String>;

	public func InitializeKey() {
		this.m_key_list = 
		["ui_popup_title",
		 "ui_popup_header",
		 "ui_popup_footer",
		 "ui_popup_destination_title",
		 "ui_popup_destination_button",
		 "ui_popup_destination_input_hint",
		 "ui_popup_favorite_title",
		 "ui_popup_favorite_input_hint",
		 "ui_popup_register_title",
		 "ui_popup_register_input_hint",
		 "ui_popup_register_confirm_title",
		 "ui_popup_register_confirm_text"
		];

		ArrayResize(this.m_value_list, ArraySize(this.m_key_list));
	}

	public func SetValue(key: String, value: String) -> Bool {
		let i = 0;
		while (i < ArraySize(this.m_key_list)) {
			if Equals(this.m_key_list[i], key) {
				this.m_value_list[i] = value;
				return true;
			}
			i += 1;
		} 
		return false;
	}

	public func GetValue(key: String) -> String {
		let i = 0;
		while (i < ArraySize(this.m_key_list)) {
			if Equals(this.m_key_list[i], key) {
				return this.m_value_list[i];
			}
			i += 1;
		}
		return "Undefined";
	}

}

//*** Aerial Vehicle Audio System ***//
@addField(PlayerPuppet)
let m_dav_veh_emitter_id: EntityID;
@addField(PlayerPuppet)
let m_dav_idle_sound_tag_name: CName;
@addField(PlayerPuppet)
let m_dav_control_sound_tag_name: CName;
@addField(PlayerPuppet)
let m_dav_control_sound_thruster_tag_name: CName;


public class DAVAudioSystem extends ScriptableSystem {
	private func OnAttach() {
		GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/AfterAttach", this, n"OnExcaliburSpawn")
			.AddTarget(EntityTarget.RecordID(t"Vehicle.av_rayfield_excalibur_dav"));
		GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/AfterAttach", this, n"OnManticoreSpawn")
			.AddTarget(EntityTarget.RecordID(t"Vehicle.av_militech_manticore_dav"));
		GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/AfterAttach", this, n"OnAtlusSpawn")
			.AddTarget(EntityTarget.RecordID(t"Vehicle.av_zetatech_atlus_dav"));
		GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/AfterAttach", this, n"OnSurveyorSpawn")
			.AddTarget(EntityTarget.RecordID(t"Vehicle.av_zetatech_surveyor_dav"));
		GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/AfterAttach", this, n"OnValgusSpawn")
			.AddTarget(EntityTarget.RecordID(t"Vehicle.q000_nomad_border_patrol_heli_dav"));
		GameInstance.GetCallbackSystem().RegisterCallback(n"Entity/AfterAttach", this, n"OnMayhemSpawn")
			.AddTarget(EntityTarget.RecordID(t"Vehicle.q000_nomad_border_patrol_heli_mayhem_dav"));
	}
	private cb func OnExcaliburSpawn(event: ref<EntityLifecycleEvent>) {
		let target = event.GetEntity();
		if !IsDefined(target) { return; }
		this.RegisterEmitter(target.GetEntityID(), n"DAV_AV_Idle_Sound");
		this.RegisterEmitter(target.GetEntityID(), n"DAV_AV_Control_Sound");
	}
	private cb func OnManticoreSpawn(event: ref<EntityLifecycleEvent>) {
		let target = event.GetEntity();
		if !IsDefined(target) { return; }
		this.RegisterEmitter(target.GetEntityID(), n"DAV_Heli_Idle_Sound");
		this.RegisterEmitter(target.GetEntityID(), n"DAV_Heli_Control_Sound");
	}
	private cb func OnAtlusSpawn(event: ref<EntityLifecycleEvent>) {
		let target = event.GetEntity();
		if !IsDefined(target) { return; }
		this.RegisterEmitter(target.GetEntityID(), n"DAV_AV_Idle_Sound");
		this.RegisterEmitter(target.GetEntityID(), n"DAV_AV_Control_Sound");
	}
	private cb func OnSurveyorSpawn(event: ref<EntityLifecycleEvent>) {
		let target = event.GetEntity();
		if !IsDefined(target) { return; }
		this.RegisterEmitter(target.GetEntityID(), n"DAV_AV_Idle_Sound");
		this.RegisterEmitter(target.GetEntityID(), n"DAV_AV_Control_Sound");
	}
	private cb func OnValgusSpawn(event: ref<EntityLifecycleEvent>) {
		let target = event.GetEntity();
		if !IsDefined(target) { return; }
		this.RegisterEmitter(target.GetEntityID(), n"DAV_Heli_Idle_Sound");
		this.RegisterEmitter(target.GetEntityID(), n"DAV_Heli_Control_Sound");
		this.RegisterEmitter(target.GetEntityID(), n"DAV_Heli_Thruster_Sound");
	}
	private cb func OnMayhemSpawn(event: ref<EntityLifecycleEvent>) {
		let target = event.GetEntity();
		if !IsDefined(target) { return; }
		this.RegisterEmitter(target.GetEntityID(), n"DAV_Heli_Idle_Sound");
		this.RegisterEmitter(target.GetEntityID(), n"DAV_Heli_Control_Sound");
		this.RegisterEmitter(target.GetEntityID(), n"DAV_Heli_Thruster_Sound");
	}
	private func RegisterEmitter(emitter_id: EntityID, tag_name: CName) {
		let game = this.GetGameInstance();
		let player = GetPlayer(game);
		player.m_dav_veh_emitter_id = emitter_id;
		if Equals(tag_name, n"DAV_AV_Idle_Sound") {
			player.m_dav_idle_sound_tag_name = tag_name;
		} else if Equals(tag_name, n"DAV_AV_Control_Sound") {
			player.m_dav_control_sound_tag_name = tag_name;
		} else if Equals(tag_name, n"DAV_Heli_Idle_Sound") {
			player.m_dav_idle_sound_tag_name = tag_name;
		} else if Equals(tag_name, n"DAV_Heli_Control_Sound") {
			player.m_dav_control_sound_tag_name = tag_name;
		} else if Equals(tag_name, n"DAV_Heli_Thruster_Sound") {
			player.m_dav_control_sound_thruster_tag_name = tag_name;
		} else {
			return; // Invalid tag name
		}
		if !GameInstance.GetAudioSystemExt(game).IsRegisteredEmitter(emitter_id, tag_name) {
			GameInstance.GetAudioSystemExt(game).RegisterEmitter(emitter_id, tag_name);
		}
	}
}

@addMethod(PlayerPuppet)
private cb func OnDAVSoundEvent(event: ref<ActionEvent>) {
	let game = this.GetGame();
	let event_name : CName = event.eventAction;
	let time_to_live : Float = event.timeToLive;
	if !GameInstance.GetAudioSystemExt(game).IsRegisteredEmitter(this.m_dav_veh_emitter_id, this.m_dav_idle_sound_tag_name) {return;}
	if Equals(event_name, n"dav_av_idle_start") {
		GameInstance.GetAudioSystemExt(game).PlayOnEmitter(n"dav_av_idle", this.m_dav_veh_emitter_id, this.m_dav_idle_sound_tag_name, LinearTween.Immediate(time_to_live));
	} else if Equals(event_name, n"dav_av_idle_stop") {
		GameInstance.GetAudioSystemExt(game).StopOnEmitter(n"dav_av_idle", this.m_dav_veh_emitter_id, this.m_dav_idle_sound_tag_name, LinearTween.Immediate(time_to_live));
	} else if Equals(event_name, n"dav_av_accel_start") {
		GameInstance.GetAudioSystemExt(game).PlayOnEmitter(n"dav_av_accel", this.m_dav_veh_emitter_id, this.m_dav_control_sound_tag_name, LinearTween.Immediate(time_to_live));
	} else if Equals(event_name, n"dav_av_accel_stop") {
		GameInstance.GetAudioSystemExt(game).StopOnEmitter(n"dav_av_accel", this.m_dav_veh_emitter_id, this.m_dav_control_sound_tag_name, LinearTween.Immediate(time_to_live));
	} else if Equals(event_name, n"dav_heli_idle_start") {
		GameInstance.GetAudioSystemExt(game).PlayOnEmitter(n"dav_heli_idle", this.m_dav_veh_emitter_id, this.m_dav_idle_sound_tag_name, LinearTween.Immediate(time_to_live));
	} else if Equals(event_name, n"dav_heli_idle_stop") {
		GameInstance.GetAudioSystemExt(game).StopOnEmitter(n"dav_heli_idle", this.m_dav_veh_emitter_id, this.m_dav_idle_sound_tag_name, LinearTween.Immediate(time_to_live));
	} else if Equals(event_name, n"dav_heli_accel_start") {
		GameInstance.GetAudioSystemExt(game).PlayOnEmitter(n"dav_heli_accel", this.m_dav_veh_emitter_id, this.m_dav_control_sound_tag_name, LinearTween.Immediate(time_to_live));
	} else if Equals(event_name, n"dav_heli_accel_stop") {
		GameInstance.GetAudioSystemExt(game).StopOnEmitter(n"dav_heli_accel", this.m_dav_veh_emitter_id, this.m_dav_control_sound_tag_name, LinearTween.Immediate(time_to_live));
	} else if Equals(event_name, n"dav_heli_thruster_start") {
		GameInstance.GetAudioSystemExt(game).PlayOnEmitter(n"dav_heli_thruster", this.m_dav_veh_emitter_id, this.m_dav_control_sound_thruster_tag_name, LinearTween.Immediate(time_to_live));
	} else if Equals(event_name, n"dav_heli_thruster_stop") {
		GameInstance.GetAudioSystemExt(game).StopOnEmitter(n"dav_heli_thruster", this.m_dav_veh_emitter_id, this.m_dav_control_sound_thruster_tag_name, LinearTween.Immediate(time_to_live));
	}
}