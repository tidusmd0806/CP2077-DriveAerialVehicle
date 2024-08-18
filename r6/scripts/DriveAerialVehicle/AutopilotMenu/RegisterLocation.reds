// This code was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)
module DAV.AutopilotMenu
import DAV.*
import Codeware.UI.*

public class RegisterLocation extends inkCustomController {
	protected let m_root: wref<inkCanvas>;
	protected let m_list: wref<inkVerticalPanel>;
	protected let m_input: wref<HubTextInput>;
	protected let m_autopilot_base: ref<AutopilotBase>;
	protected let m_button_row: ref<inkHorizontalPanel>;
	protected let m_selected_number: Int32;

	protected cb func OnCreate() {
		let root = new inkCanvas();
		root.SetName(n"RegisterLocation");
		root.SetAnchor(inkEAnchor.Fill);
		root.SetSize(2000, 300);
		root.SetChildOrder(inkEChildOrder.Forward);

		let list = new inkVerticalPanel();
		list.SetName(n"list");
		list.SetAnchor(inkEAnchor.Fill);
		list.SetMargin(30, 20, 0, 0);
		list.SetChildOrder(inkEChildOrder.Forward);
		list.SetChildMargin(new inkMargin(0, 0, 0, 5));
		list.SetOpacity(0.6);
		list.Reparent(root);

		let input = HubTextInput.Create();
		input.SetText("Unknown Location");
		input.Reparent(list);

		let input_container = list.GetWidget(n"input");
		input_container.SetHAlign(inkEHorizontalAlign.Center);
		input_container.SetSize(1800, 80);
		input_container.SetMargin(0, 30, 0, 0);

		this.m_root = root;
		this.m_list = list;
		this.m_input = input;

		this.CreateButtons();

		this.SetRootWidget(root);

	}

	protected func CreateButtons() {

		let button_row = new inkHorizontalPanel();
		button_row.SetName(n"button_row");
		button_row.SetAnchor(inkEAnchor.Fill);
		button_row.SetSize(2000, 100);	
		button_row.SetHAlign(inkEHorizontalAlign.Center);
		button_row.SetChildOrder(inkEChildOrder.Forward);
		button_row.SetChildMargin(new inkMargin(40, 0, 40, 0));
		button_row.SetOpacity(0.6);
		button_row.Reparent(this.m_list);

		this.m_button_row = button_row;

		let i = 0;
		while i < 5 {
			let text = ToString(i + 1);
			let button = CustomPopupButton.Create();
			button.SetText(text);
			button.RegisterToCallback(n"OnBtnClick", this, n"OnOpenPopup");
			button.ToggleAnimations(true);
			button.ToggleSounds(true);
			button.Reparent(button_row);

			let button_size = button.GetWidget(n"minSize");
			button_size.SetSize(200, 80);
			let button_content = button.GetWidget(n"content");
			button_content.SetHAlign(inkEHorizontalAlign.Center);

			i += 1;
		}

	}

	protected cb func OnOpenPopup(widget: wref<inkWidget>) {
		let popup = ConfirmationPopup.Show(this.GetGameController(), this.m_autopilot_base.GetWrapper());
		popup.RegisterToCallback(n"OnClose", this, n"OnClosePopup");
	}

	protected cb func OnClosePopup(widget: wref<inkWidget>) {
	    let popup = widget.GetController() as ConfirmationPopup;
		if popup.IsConfirmed() {
			this.m_autopilot_base.RegisterFavoriteList(this.m_selected_number, this.GetCurrentAddress());
		}
	}

	protected cb func OnInitialize() {
		this.RegisterListeners(this.m_button_row);
	}

	protected func RegisterListeners(container: wref<inkCompoundWidget>) {
		let childIndex = 0;
		let numChildren = container.GetNumChildren();

		while childIndex < numChildren {
			let widget = container.GetWidgetByIndex(childIndex);
			let button = widget.GetController() as CustomButton;

			if IsDefined(button) {
				button.RegisterToCallback(n"OnBtnClick", this, n"OnClick");
				button.RegisterToCallback(n"OnRelease", this, n"OnRelease");
				button.RegisterToCallback(n"OnEnter", this, n"OnEnter");
				button.RegisterToCallback(n"OnLeave", this, n"OnLeave");
			}

			childIndex += 1;
		}
	}

    protected cb func OnClick(widget: wref<inkWidget>) -> Bool {
		let button = widget.GetController() as CustomButton;

		let button_number = button.GetText();

        this.m_selected_number = StringToInt(button_number);
	}

	protected cb func OnRelease(evt: ref<inkPointerEvent>) -> Bool {
		let button = evt.GetTarget().GetController() as CustomButton;

		if evt.IsAction(n"popup_moveUp") {
			button.SetDisabled(!button.IsDisabled());

			this.UpdateHints(button);

			this.PlaySound(n"MapPin", n"OnCreate");
		}
	}

	protected cb func OnEnter(evt: ref<inkPointerEvent>) -> Bool {
		let button = evt.GetTarget().GetController() as CustomButton;
		this.UpdateHints(button);
	}

	protected cb func OnLeave(evt: ref<inkPointerEvent>) -> Bool {
		this.RemoveHints();
	}

	protected func UpdateHints(button: ref<CustomButton>) {
		if button.IsEnabled() {
			this.m_autopilot_base.GetHints().AddButtonHint(n"click", this.m_autopilot_base.GetWrapper().GetTranslation("ui_popup_register_input_hint"));
		} else {
			this.m_autopilot_base.GetHints().RemoveButtonHint(n"click");
		}
	}

	protected func RemoveHints() {
		this.m_autopilot_base.GetHints().RemoveButtonHint(n"click");
	}

	public static func Create(autopilot_base: ref<AutopilotBase>) -> ref<RegisterLocation> {
		let self = new RegisterLocation();
		self.CreateInstance();
		self.m_autopilot_base = autopilot_base;
		return self;
	}

	public func GetCurrentAddress() -> String {
		return this.m_input.GetText();
	}

	public func SetCurrentAddress(address: String) {
		this.m_input.SetText(address);
	}
}

public class ConfirmationPopup extends InMenuPopup {
	protected let m_wrapper: ref<AerialVehiclePopupWrapper>;
	protected let m_is_confirm: Bool;

	protected cb func OnCreate() {
		super.OnCreate();

		this.m_is_confirm = false;

		let content = InMenuPopupContent.Create();
		content.SetTitle(this.m_wrapper.GetTranslation("ui_popup_register_confirm_title"));
		content.Reparent(this);

		let text = new inkText();
        text.SetText(this.m_wrapper.GetTranslation("ui_popup_register_confirm_text"));
        text.SetWrapping(true, 700.0);
        text.SetFitToContent(true);
        text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        text.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
        text.BindProperty(n"tintColor", n"MainColors.Red");
        text.BindProperty(n"fontWeight", n"MainColors.BodyFontWeight");
        text.BindProperty(n"fontSize", n"MainColors.ReadableSmall");
        text.Reparent(content.GetContainerWidget());

		let footer = InMenuPopupFooter.Create();
		footer.Reparent(this);

		let confirmBtn = PopupButton.Create();
		confirmBtn.SetText(GetLocalizedText("LocKey#23123"));
		confirmBtn.SetInputAction(n"system_notification_confirm");
		confirmBtn.RegisterToCallback(n"OnBtnClick", this, n"OnClick");
		confirmBtn.ToggleAnimations(true);
		confirmBtn.ToggleSounds(true);
		confirmBtn.Reparent(footer);

		let cancelBtn = PopupButton.Create();
		cancelBtn.SetText(GetLocalizedText("LocKey#22175"));
		cancelBtn.SetInputAction(n"back");
		cancelBtn.ToggleAnimations(true);
		cancelBtn.ToggleSounds(true);
		cancelBtn.Reparent(footer);
	}

	protected cb func OnClick(widget: wref<inkWidget>) {
		this.m_is_confirm = true;
	}

	public func IsConfirmed() -> Bool {
		return this.m_is_confirm;
	}

	public static func Show(requester: ref<inkGameController>, wrapper: ref<AerialVehiclePopupWrapper>) -> ref<ConfirmationPopup> {
		let popup = new ConfirmationPopup();
		popup.m_wrapper = wrapper;
		popup.m_is_confirm = false;
		popup.Open(requester);
		return popup;
	}
}
