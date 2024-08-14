// Title: Aerial Vehicle HUD Popup
// Author: tidusmd
// Version: 2.0.0
// This code was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)

// import InkPlayground.Workbench.*
// import InkPlayground.Practices.*
module MyMod
import AutopilotMenu.*
import Codeware.UI.*

public class AerialVehiclePopup extends InGamePopup {
	protected let m_header: ref<InGamePopupHeader>;
	protected let m_footer: ref<InGamePopupFooter>;
	protected let m_content: ref<InGamePopupContent>;
	// protected let m_workbench: ref<Workbench>;
	protected let m_main_contents: ref<MainContents>;

	protected cb func OnCreate() {
		super.OnCreate();

		this.m_container.SetHeight(1140.0);

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

		this.m_main_contents = MainContents.Create();
		this.m_main_contents.SetSize(this.m_content.GetSize());
		this.m_main_contents.Reparent(this.m_content);

		this.m_main_contents.GetHistory().AddEntry("test4");
		// this.m_footer.GetHints().AddButtonHint(n"popup_moveUp", "test5");
		// this.AddHint(n"popup_moveUp", "fsawa");
		// this.m_main_contents.UpdateHint(
		// 	n"click",
		// 	"ttt"
		// );

		// this.m_workbench = Workbench.Create();
		// this.m_workbench.SetSize(this.m_content.GetSize());
		// this.m_workbench.Reparent(this.m_content);

		// this.m_workbench.AddPractice(new ColorPalette());
		// this.m_workbench.AddPractice(new ButtonBasics());
		// this.m_workbench.AddPractice(new DragImage());
		// this.m_workbench.AddPractice(new CursorState());
		// this.m_workbench.AddPractice(new InputText());
		// this.m_workbench.AddPractice(new InnerPopup());
	}

	protected cb func OnInitialize() {
		super.OnInitialize();

		// this.m_workbench.SetHints(this.m_footer.GetHints());
	}

	public func UseCursor() -> Bool {
		return true;
	}

	// public static func Show(requester: ref<inkGameController>){
	// 	let self = new AerialVehiclePopup();
	// 	self.Open(requester);
	// }
	public func Show(requester: ref<inkGameController>){
		this.Open(requester);
	}

	public func AddHint(action: CName, label: String) {
		this.m_footer.GetHints().AddButtonHint(action, label);
	}

	public func RemoveHint(action: CName) {
		this.m_footer.GetHints().RemoveButtonHint(action);
	}
	
}

public class MySystem  {
	protected let m_popup: ref<AerialVehiclePopup>;

	public func Create() {
		this.m_popup = new AerialVehiclePopup();
	}

	public func Show(requester: ref<inkGameController>) {
		this.m_popup.Show(requester);
	}

	public func AddHint(action: String, label: String) {
		LogChannel(n"DEBUG", action);
		let actionName = StringToName(action);
		this.m_popup.AddHint(actionName, label);
	}
}
