// Adopt patch: DAV flight audio on a vehicle DAV did not spawn.
// DAVAudioSystem only registers the Audioware emitters on spawn of DAV's own AV records, so an
// adopted (player-driven) vehicle had no emitter and OnDAVSoundEvent dropped every flight sound.
// Lua calls these on adopt/release to attach/detach the same emitter tags to the adopted entity.

module DAV
@if(ModuleExists("Audioware"))
import Audioware.*

@if(ModuleExists("Audioware"))
@addMethod(PlayerPuppet)
public func DAVAdoptRegisterAudio(emitter_id: EntityID, is_heli: Bool) -> Bool {
	let audio = GameInstance.GetAudioSystemExt(this.GetGame());
	let idle_tag: CName = is_heli ? n"DAV_Heli_Idle_Sound" : n"DAV_AV_Idle_Sound";
	let control_tag: CName = is_heli ? n"DAV_Heli_Control_Sound" : n"DAV_AV_Control_Sound";
	this.m_dav_veh_emitter_id = emitter_id;
	this.m_dav_idle_sound_tag_name = idle_tag;
	this.m_dav_control_sound_tag_name = control_tag;
	if !audio.IsRegisteredEmitter(emitter_id, idle_tag) {
		audio.RegisterEmitter(emitter_id, idle_tag);
	}
	if !audio.IsRegisteredEmitter(emitter_id, control_tag) {
		audio.RegisterEmitter(emitter_id, control_tag);
	}
	if is_heli {
		this.m_dav_control_sound_thruster_tag_name = n"DAV_Heli_Thruster_Sound";
		if !audio.IsRegisteredEmitter(emitter_id, n"DAV_Heli_Thruster_Sound") {
			audio.RegisterEmitter(emitter_id, n"DAV_Heli_Thruster_Sound");
		}
	}
	return audio.IsRegisteredEmitter(emitter_id, idle_tag);
}

@if(ModuleExists("Audioware"))
@addMethod(PlayerPuppet)
public func DAVAdoptUnregisterAudio(emitter_id: EntityID) -> Void {
	let audio = GameInstance.GetAudioSystemExt(this.GetGame());
	let tags: array<CName> = [n"DAV_AV_Idle_Sound", n"DAV_AV_Control_Sound", n"DAV_Heli_Idle_Sound", n"DAV_Heli_Control_Sound", n"DAV_Heli_Thruster_Sound"];
	for tag in tags {
		if audio.IsRegisteredEmitter(emitter_id, tag) {
			audio.UnregisterEmitter(emitter_id, tag);
		}
	}
}

@if(!ModuleExists("Audioware"))
@addMethod(PlayerPuppet)
public func DAVAdoptRegisterAudio(emitter_id: EntityID, is_heli: Bool) -> Bool {
	return false;
}

@if(!ModuleExists("Audioware"))
@addMethod(PlayerPuppet)
public func DAVAdoptUnregisterAudio(emitter_id: EntityID) -> Void {}
