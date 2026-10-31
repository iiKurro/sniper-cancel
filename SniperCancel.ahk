; كاتم السنايبر: بعد كل طلقة يمسك التوماهوك ثم يبدل السلاح ويرجعه بسرعة
#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true
InstallKeybdHook()
InstallMouseHook()
SetWorkingDir A_ScriptDir
ProcessSetPriority "High"

;@Ahk2Exe-SetName كاتم السنايبر
;@Ahk2Exe-SetDescription كاتم السنايبر
;@Ahk2Exe-SetVersion 1.0.0

; ---------- الإعدادات ----------
global SettingsDir := A_AppData "\SniperCancel"
global SettingsFile := SettingsDir "\settings.ini"
DirCreate SettingsDir

global Defaults := Map(
    "Trigger",   "LButton",
    "Tomahawk",  "e",
    "Swap",      "1",
    "Toggle",    "F8",
    "DelayShot", 40,
    "HoldTomahawk", 60,
    "DelaySwap", 30,
    "SwapGap",   50,
    "Track",     0
)

global Cfg := Map()
for k, v in Defaults
    Cfg[k] := IniRead(SettingsFile, "Settings", k, v)

global Enabled := false
global Busy := false
global OnPrimary := true
global BoundTrigger := "", BoundToggle := "", BoundSwap := ""

; ---------- الواجهة ----------
global G := Gui("+MinimizeBox", "كاتم السنايبر")
G.SetFont("s10", "Segoe UI")

AddKeyRow(label, key, y) {
    G.AddText("x250 y" y " w170 Right", label)
    edt := G.AddEdit("x120 y" (y - 3) " w120 ReadOnly Center", Cfg[key])
    btn := G.AddButton("x20 y" (y - 4) " w90", "تعيين")
    btn.OnEvent("Click", (*) => CaptureKey(key, edt))
    return edt
}

AddMsRow(label, key, y) {
    G.AddText("x250 y" y " w170 Right", label)
    edt := G.AddEdit("x120 y" (y - 3) " w120 Number Center", Cfg[key])
    edt.OnEvent("Change", (ctl, *) => SaveNumber(key, ctl))
    G.AddText("x20 y" y " w90 Right", "مللي ثانية")
    return edt
}

G.AddText("x20 y12 w400 Center", "الأزرار")
AddKeyRow("زر التفعيل (الطلقة):", "Trigger", 42)
AddKeyRow("زر التوماهوك:", "Tomahawk", 76)
AddKeyRow("زر تبديل السلاح:", "Swap", 110)
AddKeyRow("زر التشغيل والإيقاف:", "Toggle", 144)

G.AddText("x20 y184 w400 Center", "التوقيت")
AddMsRow("انتظار بعد الطلقة:", "DelayShot", 214)
AddMsRow("مدة مسك التوماهوك:", "HoldTomahawk", 248)
AddMsRow("انتظار قبل التبديل:", "DelaySwap", 282)
AddMsRow("بين التبديل والرجوع:", "SwapGap", 316)

global TrackBox := G.AddCheckbox("x20 y352 w400 Right", "تعرّف تلقائي: يشتغل بس وانت ماسك السلاح الرئيسي")
TrackBox.Value := Cfg["Track"]
TrackBox.OnEvent("Click", (ctl, *) => (Cfg["Track"] := ctl.Value, Save("Track"), UpdateStatus()))

global StatusText := G.AddText("x20 y386 w400 Center", "")
global ToggleBtn := G.AddButton("x120 y414 w200 h32", "تشغيل")
ToggleBtn.OnEvent("Click", (*) => ToggleEnabled())
G.AddText("x20 y456 w400 Center cGray", "إذا سكّرت النافذة يكمل البرنامج شغله من أيقونة جنب الساعة")

G.OnEvent("Close", (*) => (G.Hide(), true))

; ---------- أيقونة جنب الساعة ----------
A_TrayMenu.Delete()
A_TrayMenu.Add("فتح الإعدادات", (*) => G.Show())
A_TrayMenu.Add("تشغيل / إيقاف", (*) => ToggleEnabled())
A_TrayMenu.Add()
A_TrayMenu.Add("خروج", (*) => ExitApp())
A_TrayMenu.Default := "فتح الإعدادات"
A_IconTip := "كاتم السنايبر"

BindHotkeys()
UpdateStatus()
G.Show("w440 h486")
return

; ---------- الدوال ----------
Save(key) {
    IniWrite Cfg[key], SettingsFile, "Settings", key
}

SaveNumber(key, ctl) {
    v := ctl.Value
    if (v = "")
        return
    Cfg[key] := Integer(v)
    Save(key)
}

ToggleEnabled() {
    global Enabled, OnPrimary
    Enabled := !Enabled
    OnPrimary := true
    SoundBeep Enabled ? 900 : 400, 120
    UpdateStatus()
}

UpdateStatus() {
    if Enabled {
        StatusText.Text := "شغّال ✓"
        StatusText.SetFont("cGreen Bold")
        ToggleBtn.Text := "إيقاف"
        A_IconTip := "كاتم السنايبر: شغّال"
    } else {
        StatusText.Text := "موقّف"
        StatusText.SetFont("cRed Bold")
        ToggleBtn.Text := "تشغيل"
        A_IconTip := "كاتم السنايبر: موقّف"
    }
}

BindHotkeys() {
    global BoundTrigger, BoundToggle, BoundSwap
    for h in [BoundTrigger, BoundToggle, BoundSwap]
        if (h != "")
            try Hotkey h, "Off"

    BoundTrigger := "~*" Cfg["Trigger"]
    BoundToggle := "*" Cfg["Toggle"]
    BoundSwap := "~*" Cfg["Swap"]

    Hotkey BoundTrigger, OnShot, "On"
    Hotkey BoundToggle, (*) => ToggleEnabled(), "On"
    Hotkey BoundSwap, OnManualSwap, "On"
}

OnManualSwap(*) {
    ; التبديل اللي تسويه بيدك يغير السلاح اللي ماسكه
    global OnPrimary
    if Enabled
        OnPrimary := !OnPrimary
}

TapKey(key, holdMs := 20) {
    Send "{Blind}{" key " down}"
    Sleep holdMs
    Send "{Blind}{" key " up}"
}

OnShot(*) {
    global Busy
    if (!Enabled || Busy)
        return
    if (Cfg["Track"] && !OnPrimary)
        return
    Busy := true
    try {
        Sleep Cfg["DelayShot"]
        TapKey(Cfg["Tomahawk"], Cfg["HoldTomahawk"])
        Sleep Cfg["DelaySwap"]
        TapKey(Cfg["Swap"])
        Sleep Cfg["SwapGap"]
        TapKey(Cfg["Swap"])
    }
    Busy := false
}

; ---------- تعيين الأزرار ----------
CaptureKey(key, edt) {
    global Enabled
    wasOn := Enabled
    Enabled := false
    old := edt.Value
    edt.Value := "اضغط الزر..."
    Sleep 350  ; عشان ما ياخذ ضغطة الماوس اللي ضغطت فيها "تعيين"

    found := ""
    deadline := A_TickCount + 8000
    while (found = "" && A_TickCount < deadline) {
        Loop 254 {
            vk := A_Index
            if (vk = 0x10 || vk = 0x11 || vk = 0x12)  ; نتجاهل النسخ العامة من شفت وكنترول وألت
                continue
            if GetKeyState(Format("vk{:02X}", vk), "P") {
                name := GetKeyName(Format("vk{:02X}", vk))
                if (name != "") {
                    found := name
                    break
                }
            }
        }
        Sleep 10
    }

    if (found = "" || found = "Escape") {
        edt.Value := old
    } else {
        Cfg[key] := found
        Save(key)
        edt.Value := found
        try BindHotkeys()
        catch {
            MsgBox "ما قدرت أستخدم هذا الزر، جرّب زر ثاني.", "كاتم السنايبر"
            Cfg[key] := old, Save(key), edt.Value := old
            BindHotkeys()
        }
    }
    if (found != "")
        KeyWait found
    Enabled := wasOn
    UpdateStatus()
}
