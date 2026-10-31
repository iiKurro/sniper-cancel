; كاتم السنايبر: بعد كل طلقة يمسك التوماهوك ثم يبدل السلاح ويرجعه بسرعة
#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook true
InstallKeybdHook()
InstallMouseHook()
SetWorkingDir A_ScriptDir
ProcessSetPriority "High"
if !A_IsCompiled && FileExist(A_ScriptDir "\icon.ico")
    TraySetIcon A_ScriptDir "\icon.ico"

;@Ahk2Exe-SetName كاتم السنايبر
;@Ahk2Exe-SetDescription كاتم السنايبر
;@Ahk2Exe-SetVersion 2.0.0
;@Ahk2Exe-SetMainIcon icon.ico

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
global Capturing := false

; ---------- الألوان ----------
global C := {
    bg:     "09090B",
    card:   "141417",
    line:   "27272A",
    keyBg:  "1F1F23",
    keyLn:  "3F3F46",
    txt:    "FAFAFA",
    muted:  "A1A1AA",
    dim:    "71717A",
    off:    "3F3F46",
    acc:    "22C55E",
    accBg:  "052E16"
}

; ---------- أدوات الرسم ----------
global Layers := [[], [], []]   ; خلفيات البطاقات وحدودها: تنرسم تحت كل شيء
global Rounded := []            ; عناصر بزوايا دائرية
global Clickable := Map()       ; عناصر يتغير فوقها المؤشر ليد

global G := Gui("-MaximizeBox", "كاتم السنايبر")
G.BackColor := C.bg
G.MarginX := 0, G.MarginY := 0
G.SetFont("s10 c" C.txt, "Segoe UI")
G.AddButton("x-200 y-200 w10 h10 Default")  ; ياخذ التركيز بدال أول خانة رقم

; شكل ملوّن (خلفية أو حد) بزوايا دائرية
Shape(x, y, w, h, color, r, layer) {
    ctl := G.AddText(Format("x{} y{} w{} h{} +0x4000000 Background{}", x, y, w, h, color))
    Layers[layer + 1].Push(ctl)
    if r
        Rounded.Push([ctl, r])
    return ctl
}

; بطاقة بحد رفيع
Card(x, y, w, h, border := "") {
    o := Shape(x, y, w, h, border = "" ? C.line : border, 12, 0)
    i := Shape(x + 1, y + 1, w - 2, h - 2, C.card, 11, 1)
    return o
}

Label(x, y, w, h, text, opts := "", bg := "") {
    ctl := G.AddText(Format("x{} y{} w{} h{} Right E0x2000 Background{} {}", x, y, w, h, bg = "" ? C.card : bg, opts), text)
    return ctl
}

MakeClickable(ctl, fn) {
    ctl.OnEvent("Click", fn)
    Clickable[ctl.Hwnd] := true
}

; مفتاح التشغيل (سويتش)
MakeSwitch(x, y, fn) {
    track := Shape(x, y, 46, 26, C.off, 13, 2)
    knob := G.AddText(Format("x{} y{} w20 h20 Background{}", x + 23, y + 3, "FFFFFF"))
    Rounded.Push([knob, 10])
    MakeClickable(track, fn)
    MakeClickable(knob, fn)
    return {track: track, knob: knob, x: x, y: y}
}

SetSwitch(sw, on) {
    sw.track.Opt("+Background" (on ? C.acc : C.off))
    sw.track.Redraw()
    ; بالعربي: مطفي = الدائرة يمين، شغّال = الدائرة يسار
    sw.knob.Move(on ? sw.x + 3 : sw.x + 23)
    sw.knob.Redraw()
}

; زر بشكل مفتاح الكيبورد
KeyCap(x, y, w, key) {
    border := Shape(x, y, w, 30, C.keyLn, 7, 2)
    G.SetFont("s10 bold")
    cap := G.AddText(Format("x{} y{} w{} h26 Center +0x200 E0x2000 Background{} c{}", x + 1, y + 1, w - 2, C.keyBg, C.txt), KeyLabel(Cfg[key]))
    G.SetFont("s10 norm")
    Rounded.Push([cap, 6])
    obj := {border: border, cap: cap, key: key}
    MakeClickable(cap, (*) => CaptureKey(obj))
    return obj
}

; خانة رقم مع زر ناقص وزائد
Stepper(x, y, key) {
    Shape(x, y, 26, 26, C.line, 7, 2)
    minus := G.AddText(Format("x{} y{} w24 h24 Center +0x200 Background{} c{}", x + 1, y + 1, C.keyBg, C.muted), "−")
    Rounded.Push([minus, 6])

    G.SetFont("s11 bold", "Consolas")
    edt := G.AddEdit(Format("x{} y{} w44 h22 Number Center -E0x200 Limit4 Background{} c{}", x + 31, y + 3, C.card, C.txt), Cfg[key])
    G.SetFont("s10 norm", "Segoe UI")
    edt.OnEvent("Change", (ctl, *) => SaveNumber(key, ctl))

    Shape(x + 80, y, 26, 26, C.line, 7, 2)
    plus := G.AddText(Format("x{} y{} w24 h24 Center +0x200 Background{} c{}", x + 81, y + 1, C.keyBg, C.muted), "+")
    Rounded.Push([plus, 6])

    G.SetFont("s8")
    G.AddText(Format("x{} y{} w24 h26 +0x200 E0x2000 Background{} c{}", x + 110, y, C.card, C.muted), "مث")
    G.SetFont("s10")

    MakeClickable(minus, (*) => StepBy(key, edt, -5))
    MakeClickable(plus, (*) => StepBy(key, edt, 5))
    return edt
}

; ---------- الواجهة ----------

; العنوان
G.SetFont("s16 bold")
Label(150, 12, 270, 34, "كاتم السنايبر", "", C.bg)
G.SetFont("s9 norm c" C.muted)
Label(150, 46, 270, 20, "يكتم صوت الطلقة تلقائيًا بعد كل ضربة", "", C.bg)
G.SetFont("s10 c" C.txt)

; شارة الحالة
global BadgeBorder := Shape(20, 22, 84, 28, C.line, 14, 2)
G.SetFont("s9 bold")
global Badge := G.AddText(Format("x21 y23 w82 h26 Center +0x200 E0x2000 Background{} c{}", C.bg, C.muted), "")
Rounded.Push([Badge, 13])
G.SetFont("s10 norm")

; بطاقة التشغيل
global PowerCard := Card(20, 78, 400, 64)
G.SetFont("s11 bold")
Label(110, 88, 294, 24, "التشغيل")
G.SetFont("s9 norm c" C.muted)
global ToggleHint := Label(110, 112, 294, 20, "")
G.SetFont("s10 c" C.txt)
global PowerSwitch := MakeSwitch(36, 97, (*) => ToggleEnabled())

; الأزرار
G.SetFont("s9 bold c" C.muted)
Label(20, 152, 396, 20, "الأزرار  ·  اضغط على الزر عشان تغيّره", "", C.bg)
G.SetFont("s10 norm c" C.txt)

RowH := 40
y0 := 176
Card(20, y0, 400, RowH * 4)
global Caps := []
for i, row in [["زر الطلقة", "Trigger"], ["زر التوماهوك", "Tomahawk"], ["زر تبديل السلاح", "Swap"], ["زر التشغيل والإيقاف", "Toggle"]] {
    top := y0 + RowH * (i - 1)
    if (i > 1)
        Shape(21, top, 398, 1, C.line, 0, 2)
    Label(170, top + 10, 234, 22, row[1])
    Caps.Push(KeyCap(36, top + 5, 112, row[2]))
}

; التوقيت
y1 := y0 + RowH * 4 + 12
G.SetFont("s9 bold c" C.muted)
Label(20, y1, 396, 20, "التوقيت", "", C.bg)
G.SetFont("s10 norm c" C.txt)

y2 := y1 + 24
Card(20, y2, 400, RowH * 4)
for i, row in [["انتظار بعد الطلقة", "DelayShot"], ["مدة مسك التوماهوك", "HoldTomahawk"], ["انتظار قبل التبديل", "DelaySwap"], ["بين التبديل والرجوع", "SwapGap"]] {
    top := y2 + RowH * (i - 1)
    if (i > 1)
        Shape(21, top, 398, 1, C.line, 0, 2)
    Label(190, top + 10, 214, 22, row[1])
    Stepper(36, top + 7, row[2])
}

; التعرف التلقائي
y3 := y2 + RowH * 4 + 12
Card(20, y3, 400, 56)
Label(110, y3 + 8, 294, 22, "تعرّف تلقائي على السلاح")
G.SetFont("s8 c" C.muted)
Label(110, y3 + 30, 294, 18, "يشتغل بس وانت ماسك السنايبر (يحسب ضغطات التبديل)")
G.SetFont("s10 c" C.txt)
global TrackSwitch := MakeSwitch(36, y3 + 15, (*) => ToggleTrack())

; ملاحظة تحت
G.SetFont("s8 c" C.dim)
G.AddText(Format("x20 y{} w400 h18 Center E0x2000 Background{}", y3 + 66, C.bg), "لو سكّرت النافذة يكمل شغله من الأيقونة اللي جنب الساعة")
G.SetFont("s10 c" C.txt)
global WinH := y3 + 92

G.OnEvent("Close", (*) => (G.Hide(), true))
OnMessage(0x0020, OnSetCursor)  ; مؤشر اليد فوق الأزرار

; ترتيب الطبقات: البطاقات تحت وكل شيء ثاني فوقها
for layer in [3, 2, 1]
    for ctl in Layers[layer]
        DllCall("SetWindowPos", "ptr", ctl.Hwnd, "ptr", 1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x13)

; ---------- أيقونة جنب الساعة ----------
A_TrayMenu.Delete()
A_TrayMenu.Add("فتح الإعدادات", (*) => ShowWindow())
A_TrayMenu.Add("تشغيل / إيقاف", (*) => ToggleEnabled())
A_TrayMenu.Add()
A_TrayMenu.Add("خروج", (*) => ExitApp())
A_TrayMenu.Default := "فتح الإعدادات"
A_IconTip := "كاتم السنايبر"

BindHotkeys()
SetSwitch(TrackSwitch, Cfg["Track"])
UpdateStatus()
ShowWindow()
return

; ---------- الدوال ----------
ShowWindow() {
    static first := true
    if first {
        first := false
        DarkTitleBar(G.Hwnd)
        G.Show("w440 h" WinH " Hide")
        ApplyRounding()
    }
    G.Show()
}

DarkTitleBar(hwnd) {
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 20, "int*", 1, "int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 35, "int*", BGR(C.bg), "int", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "int", 34, "int*", BGR(C.line), "int", 4)
}

BGR(hex) {
    n := Integer("0x" hex)
    return ((n & 0xFF) << 16) | (n & 0xFF00) | ((n >> 16) & 0xFF)
}

ApplyRounding() {
    scale := A_ScreenDPI / 96
    rc := Buffer(16)
    for item in Rounded {
        ctl := item[1], r := Round(item[2] * scale)
        DllCall("GetClientRect", "ptr", ctl.Hwnd, "ptr", rc)
        w := NumGet(rc, 8, "int"), h := NumGet(rc, 12, "int")
        rgn := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", w + 1, "int", h + 1, "int", r * 2, "int", r * 2, "ptr")
        DllCall("SetWindowRgn", "ptr", ctl.Hwnd, "ptr", rgn, "int", true)
    }
}

OnSetCursor(wParam, lParam, msg, hwnd) {
    if Clickable.Has(wParam) {
        DllCall("SetCursor", "ptr", DllCall("LoadCursor", "ptr", 0, "ptr", 32649, "ptr"))
        return true
    }
}

SetColor(ctl, bg, fg := "") {
    ctl.Opt("+Background" bg)
    if (fg != "")
        ctl.SetFont("c" fg)
    ctl.Redraw()
}

KeyLabel(k) {
    static names := Map(
        "LButton", "كليك يسار", "RButton", "كليك يمين", "MButton", "زر العجلة",
        "XButton1", "زر جانبي ١", "XButton2", "زر جانبي ٢", "Space", "مسافة",
        "LShift", "شفت", "RShift", "شفت يمين", "LControl", "كنترول", "RControl", "كنترول يمين",
        "LAlt", "ألت", "RAlt", "ألت يمين", "Tab", "تاب", "CapsLock", "كابس", "Enter", "إنتر"
    )
    return names.Has(k) ? names[k] : StrUpper(k)
}

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

StepBy(key, edt, d) {
    v := Max(0, Min(2000, Integer(Cfg[key]) + d))
    Cfg[key] := v
    Save(key)
    edt.Value := v
}

ToggleTrack() {
    Cfg["Track"] := Cfg["Track"] ? 0 : 1
    Save("Track")
    SetSwitch(TrackSwitch, Cfg["Track"])
}

ToggleEnabled() {
    global Enabled, OnPrimary
    if Capturing
        return
    Enabled := !Enabled
    OnPrimary := true
    SoundBeep Enabled ? 900 : 400, 120
    UpdateStatus()
}

UpdateStatus() {
    ToggleHint.Text := "أو اضغط " KeyLabel(Cfg["Toggle"]) " وانت داخل اللعبة"
    SetSwitch(PowerSwitch, Enabled)
    if Enabled {
        Badge.Text := "شغّال  ●"
        SetColor(Badge, C.accBg, C.acc)
        SetColor(BadgeBorder, C.acc)
        SetColor(PowerCard, C.acc)
        A_IconTip := "كاتم السنايبر: شغّال"
    } else {
        Badge.Text := "موقّف  ●"
        SetColor(Badge, C.bg, C.muted)
        SetColor(BadgeBorder, C.line)
        SetColor(PowerCard, C.line)
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
    if (!Enabled || Busy || Capturing)
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
CaptureKey(obj) {
    global Capturing
    if Capturing
        return
    Capturing := true
    key := obj.key
    old := Cfg[key]

    obj.cap.Text := "اضغط زر..."
    SetColor(obj.border, C.acc)
    SetColor(obj.cap, C.keyBg, C.acc)
    KeyWait "LButton"   ; عشان ما ياخذ الضغطة اللي ضغطت فيها على الزر
    Sleep 120

    found := ""
    deadline := A_TickCount + 8000
    while (found = "" && A_TickCount < deadline) {
        Loop 254 {
            vk := A_Index
            if (vk = 0x10 || vk = 0x11 || vk = 0x12 || (vk >= 0x9C && vk <= 0x9F))  ; نتجاهل شفت وكنترول وألت العامة وعجلة الماوس
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

    if (found != "" && found != "Escape") {
        Cfg[key] := found
        Save(key)
        try BindHotkeys()
        catch {
            MsgBox "ما قدرت أستخدم هذا الزر، جرّب زر ثاني.", "كاتم السنايبر"
            Cfg[key] := old, Save(key)
            BindHotkeys()
        }
    }
    if (found != "")
        KeyWait found

    obj.cap.Text := KeyLabel(Cfg[key])
    SetColor(obj.border, C.keyLn)
    SetColor(obj.cap, C.keyBg, C.txt)
    Capturing := false
    UpdateStatus()
}
