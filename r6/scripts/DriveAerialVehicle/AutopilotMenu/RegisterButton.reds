// This code was created based on psiberx's InkPlayground. (https://github.com/psiberx/cp2077-playground)
module DAV.AutopilotMenu
import Codeware.UI.*

public class RegisterButton extends inkCustomController {
    protected let m_root: wref<inkCanvas>;
    protected let m_rb_area: wref<inkHorizontalPanel>;

    protected cb func OnCreate() {
		let root = new inkCanvas();
		root.SetName(n"RegisterButton");
		root.SetAnchor(inkEAnchor.Fill);
		root.SetMargin(new inkMargin(16.0, 12.0, 0.0, 12.0));
        root.SetSize(500, 500);
		root.SetChildOrder(inkEChildOrder.Backward);

		let rb_area = new inkHorizontalPanel();
		rb_area.SetName(n"rb_area");
		rb_area.SetAnchor(inkEAnchor.Fill);
		rb_area.SetChildOrder(inkEChildOrder.Backward);
		rb_area.SetOpacity(0.6);
		rb_area.Reparent(root);

		this.m_root = root;
		this.m_rb_area = rb_area;

		this.SetRootWidget(root);

        let text_array = ["1", "2", "3", "4", "5"];
        for text in text_array {
            this.CreateButton(text);
        }
	}

    protected cb func OnInitialize() {
		this.RegisterListeners(this.m_rb_area);
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

		// this.Log(buttonName + ": " + buttonEvent);
        LogChannel(n"DEBUG", buttonName + ": " + buttonEvent);
	}

	protected cb func OnRelease(evt: ref<inkPointerEvent>) -> Bool {
		// let button = evt.GetTarget().GetController() as CustomButton;

		// if evt.IsAction(n"popup_moveUp") {
		// 	button.SetDisabled(!button.IsDisabled());

		// 	let buttonName = button.GetText();
		// 	let buttonEvent = button.IsDisabled()
		// 		? "InkPlayground-ButtonBasics-Event-Disable"
		// 		: "InkPlayground-ButtonBasics-Event-Enable";

		// 	this.Log(buttonName + ": " + buttonEvent);
		// 	this.UpdateHints(button);

		// 	this.PlaySound(n"MapPin", n"OnCreate");
		// }
	}

	protected cb func OnEnter(evt: ref<inkPointerEvent>) -> Bool {
		// let button = evt.GetTarget().GetController() as CustomButton;

		// this.UpdateHints(button);
	}

	protected cb func OnLeave(evt: ref<inkPointerEvent>) -> Bool {
		// this.RemoveHints();
	}

    protected func CreateButton(text: String) {
        let text_name = StringToName(text);
        let button = SimpleButton.Create();
		button.SetName(text_name);
		button.SetText(text);
		button.ToggleAnimations(true);
		button.ToggleSounds(true);
		button.Reparent(this.m_rb_area);
    }

    public static func Create() -> ref<RegisterButton> {
		let self = new RegisterButton();
		self.CreateInstance();

		return self;
	}

}