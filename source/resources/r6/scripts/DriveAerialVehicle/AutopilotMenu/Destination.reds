// This code was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)
module DAV.AutopilotMenu
import DAV.*
import Codeware.UI.*

public class Destination extends inkCustomController {
	protected let m_root: wref<inkCanvas>;
	protected let m_list: wref<inkHorizontalPanel>;
	protected let m_text: wref<inkText>;
	protected let m_autopilot_base: ref<AutopilotBase>;

	protected cb func OnCreate() {
		let root = new inkCanvas();
		root.SetName(n"Destination");
		root.SetAnchor(inkEAnchor.Fill);
		root.SetSize(2000, 120);
		root.SetChildOrder(inkEChildOrder.Forward);

		let list = new inkHorizontalPanel();
		list.SetName(n"list");
		list.SetAnchor(inkEAnchor.Fill);
		list.SetMargin(30, 20, 0, 0);
		list.SetChildOrder(inkEChildOrder.Forward);
		list.SetChildMargin(new inkMargin(0, 0, 0, 5));
		list.SetOpacity(0.6);
		list.Reparent(root);

		let canvas = new inkCanvas();
		canvas.SetName(n"canvas");
		canvas.SetAnchor(inkEAnchor.Fill);
		canvas.SetSize(1500, 100);
		canvas.Reparent(list);

		let dest_text = new inkText();
		dest_text.SetName(n"DestinationText");
        dest_text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        dest_text.SetFontStyle(n"Medium");
        dest_text.SetFontSize(40);
        dest_text.SetLetterCase(textLetterCase.OriginalCase);
        dest_text.SetFitToContent(true);
        dest_text.SetMargin(new inkMargin(48.0, 23.0, 200.0, 6.0));
        dest_text.SetHAlign(inkEHorizontalAlign.Left);
        dest_text.SetVAlign(inkEVerticalAlign.Center);
        dest_text.SetTintColor(ThemeColors.Bittersweet());
		dest_text.SetText(this.m_autopilot_base.GetWrapper().GetTranslation("ui_popup_destination_title"));
		dest_text.Reparent(canvas);

		let reset_button = CustomSimpleButton.Create();
		reset_button.SetName(n"ResetButton");
		reset_button.GetRootComponent().SetSize(300, 80);
		reset_button.GetRootComponent().SetMargin(0, 0, 0, 5);
		reset_button.GetLabel().SetFontSize(30);
		reset_button.SetText(this.m_autopilot_base.GetWrapper().GetTranslation("ui_popup_destination_button"));
		reset_button.ToggleAnimations(true);
		reset_button.ToggleSounds(true);
		reset_button.Reparent(list);

		this.m_root = root;
		this.m_list = list;
		this.m_text = dest_text;

		this.SetRootWidget(root);

	}

	protected cb func OnInitialize() {
		let i = 0;
		while i < 5 {
			this.RegisterListeners(this.m_list);
			i += 1;
		}
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

		let buttonName = button.GetText();
		let buttonEvent = "clicked";

		this.m_autopilot_base.ResetDestination();
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
			this.m_autopilot_base.GetHints().AddButtonHint(n"click", this.m_autopilot_base.GetWrapper().GetTranslation("ui_popup_destination_input_hint"));
		} else {
			this.m_autopilot_base.GetHints().RemoveButtonHint(n"click");
		}

	}

	protected func RemoveHints() {
		this.m_autopilot_base.GetHints().RemoveButtonHint(n"click");
	}

	public static func Create(autopilot_base: ref<AutopilotBase>) -> ref<Destination> {
		let self = new Destination();
		self.m_autopilot_base = autopilot_base;
		self.CreateInstance();

		return self;
	}

	public func SetDestination(dest_address: String) {
		this.m_text.SetText(dest_address);
	}
}
