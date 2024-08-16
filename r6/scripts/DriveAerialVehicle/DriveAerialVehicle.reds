// Title: Aerial Vehicle HUD Popup
// Author: tidusmd
// Version: 2.0.0
// This code was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)

module DAV
import DAV.AutopilotMenu.*
import Codeware.UI.*

public class AerialVehiclePopup extends InGamePopup {
	protected let m_header: ref<InGamePopupHeader>;
	protected let m_footer: ref<InGamePopupFooter>;
	protected let m_content: ref<InGamePopupContent>;
	protected let m_autopilot_base: ref<AutopilotBase>;
	protected let m_wrapper: wref<AerialVehiclePopupWrapper>;

	protected cb func OnCreate() {
		super.OnCreate();

		this.m_container.SetAnchor(inkEAnchor.Centered);
		this.m_container.SetMargin(0, 50, 0, 0);
		this.m_container.SetWidth(2000.0);
		this.m_container.SetHeight(1500.0);

		this.m_header = InGamePopupHeader.Create();
		this.m_header.SetTitle("test1111");
		this.m_header.SetFluffRight("test2");
		this.m_header.Reparent(this);

		this.m_footer = InGamePopupFooter.Create();
		this.m_footer.SetFluffIcon(n"fluff_triangle2");
		this.m_footer.SetFluffText("test3");
		this.m_footer.Reparent(this);

		this.m_content = InGamePopupContent.Create();
		this.m_content.Reparent(this);

		this.m_autopilot_base = AutopilotBase.Create();
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

	public func SetDestination(dest_address: String, mappim_address: String, selected_number: Int32) {
		this.m_autopilot_base.SetDestination(dest_address, mappim_address, selected_number);
	}

	public func SetFavoriteList(favorite_list: array<String>) {
		this.m_autopilot_base.SetFavoriteList(favorite_list);
	}	

	public func GetCurrentAddress() -> String {
		return this.m_autopilot_base.GetCurrentAddress();
	}

	public func SetCurrentAddress(address: String) {
		this.m_autopilot_base.SetCurrentAddress(address);
	}
	
}

public class AerialVehiclePopupWrapper {
	protected let m_aerial_vehicle_popup: ref<AerialVehiclePopup>;

	protected let m_is_popup_open: Bool;

	public func Create() {
		this.m_aerial_vehicle_popup = new AerialVehiclePopup();
		this.m_aerial_vehicle_popup.SetWrapper(this);
	}

	public func Show(requester: ref<inkGameController>) {
		this.m_is_popup_open = true;
		this.m_aerial_vehicle_popup.Show(requester);
	}

	public func IsClosed() -> Bool {
		if !(this.m_is_popup_open)
		{
			return true;
		}
		else 
		{
			return false;
		}
	}

	public func SetOpenFlag(is_open: Bool) {
		this.m_is_popup_open = is_open;
	}

	public func SetDestination(dest_address: String, mappim_address: String, selected_number: Int32) { // selected_number: 0 = Mappin, 1 ~ 5 = Favorite
		this.m_aerial_vehicle_popup.SetDestination(dest_address, mappim_address, selected_number);
	}

	public func SetFavoriteList(favorite_list: array<String>) {
		this.m_aerial_vehicle_popup.SetFavoriteList(favorite_list);
	}

	public func SetCurrentAddress(address: String) {
		this.m_aerial_vehicle_popup.SetCurrentAddress(address);
	}

	public func Test(array: array<String>) -> array<String> {
		let i = 0;
		while i < 5 {
			LogChannel(n"DEBUG", array[i]);
			i += 1;
		}
		return array;
	}


}
