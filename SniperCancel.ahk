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

; رقم الإصدار: البناء التلقائي يحط الرقم الصحيح هنا
global AppVersion := "1.0.0"
global RepoApi := "https://api.github.com/repos/iiKurro/sniper-cancel/releases/latest"
global DownloadUrl := "https://github.com/iiKurro/sniper-cancel/releases/latest/download/SniperCancel.exe"

; ---------- الإعدادات ----------
global SettingsDir := A_AppData "\SniperCancel"
global SettingsFile := SettingsDir "\settings.ini"
DirCreate SettingsDir
EnsureUnicodeIni()

global Defaults := Map(
    "Trigger",      "LButton",
    "Tomahawk",     "e",
    "Swap",         "1",         ; وضع الزر الواحد: يضغطه مرتين
    "SwapMode",     0,           ; 0 = زر واحد مرتين، 1 = زرين منفصلين
    "PistolKey",    "2",
    "PrimaryKey",   "1",
    "Toggle",       "F8",
    "ProfileKey",   "F9",
    "DelayShot",    40,
    "HoldTomahawk", 60,
    "DelaySwap",    30,
    "SwapGap",      50,
    "Track",        0,
    "GameOnly",     1,
    "GameExe",      "cod.exe",   ; أكثر من اسم: افصل بينها بفاصلة
    "Indicator",    1,
    "IndicatorPos", 1,           ; 1 فوق يسار، 2 فوق يمين، 3 تحت يسار، 4 تحت يمين
    "CheckUpdates", 1,
    "Profile",      "افتراضي"
)

; حدود التوقيت (مللي ثانية)
global Limits := Map(
    "DelayShot",    [0, 1000],
    "HoldTomahawk", [10, 1000],
    "DelaySwap",    [0, 1000],
    "SwapGap",      [10, 1000]
)
global TimingKeys := ["DelayShot", "HoldTomahawk", "DelaySwap", "SwapGap"]
global KeyFields := ["Trigger", "Tomahawk", "Swap", "PistolKey", "PrimaryKey", "Toggle", "ProfileKey"]
global FlagFields := ["SwapMode", "Track", "GameOnly", "Indicator", "CheckUpdates"]

global Cfg := Map()
for k, v in Defaults
    Cfg[k] := IniRead(SettingsFile, "Settings", k, v)
for k in TimingKeys
    Cfg[k] := ClampMs(k, Cfg[k])
for k in FlagFields
    Cfg[k] := Cfg[k] ? 1 : 0
Cfg["IndicatorPos"] := ClampInt(Cfg["IndicatorPos"], 1, 4, 1)

global Enabled := false
global Busy := false
global Capturing := false
global OnPrimary := true
global Bound := []
global UpdateAvailable := false, LatestVersion := ""

InitProfiles()

; ---------- الواجهة ----------
global G := Gui("+MinimizeBox", "كاتم السنايبر")
G.SetFont("s10", "Segoe UI")
global Y := 12
global KeyEdits := Map(), KeyBtns := Map(), MsEdits := Map(), FlagBoxes := Map()

Section(title) {
    global Y
    G.AddText("x20 y" Y " w400 Center", title)
    Y += 28
}

AddKeyRow(label, key) {
    global Y
    G.AddText("x250 y" Y " w170 Right", label)
    edt := G.AddEdit("x120 y" (Y - 3) " w120 ReadOnly Center", Cfg[key])
    btn := G.AddButton("x20 y" (Y - 4) " w90", "تعيين")
    btn.OnEvent("Click", (*) => CaptureKey(key))
    KeyEdits[key] := edt
    KeyBtns[key] := btn
    Y += 32
    return edt
}

AddMsRow(label, key) {
    global Y
    lim := Limits[key]
    G.AddText("x250 y" Y " w170 Right", label)
    edt := G.AddEdit("x120 y" (Y - 3) " w120 Number Center", Cfg[key])
    edt.OnEvent("Change", (ctl, *) => SaveIfValid(key, ctl.Value))
    edt.OnEvent("LoseFocus", (ctl, *) => SetSetting(key, ctl.Value))
    G.AddText("x20 y" Y " w90 Right cGray", lim[1] "–" lim[2] " مث")
    MsEdits[key] := edt
    Y += 32
}

AddFlag(label, key) {
    global Y
    box := G.AddCheckbox("x20 y" Y " w400 Right", label)
    box.Value := Cfg[key]
    box.OnEvent("Click", (ctl, *) => SetSetting(key, ctl.Value))
    FlagBoxes[key] := box
    Y += 26
}

Section("الأزرار")
AddKeyRow("زر الطلقة:", "Trigger")
AddKeyRow("زر التوماهوك:", "Tomahawk")
AddFlag("تبديل بزرين منفصلين (زر للمسدس وزر للرئيسي)", "SwapMode")
AddKeyRow("زر تبديل السلاح:", "Swap")
AddKeyRow("زر المسدس:", "PistolKey")
AddKeyRow("زر السلاح الرئيسي:", "PrimaryKey")
AddKeyRow("زر التشغيل والإيقاف:", "Toggle")
AddKeyRow("زر تغيير الملف:", "ProfileKey")

Y += 6
Section("ملف التوقيت")
global ProfileBox := G.AddDropDownList("x120 y" (Y - 3) " w300", [])
ProfileBox.OnEvent("Change", (ctl, *) => ProfileLoad(ctl.Text))
G.AddButton("x20 y" (Y - 4) " w90", "حذف").OnEvent("Click", (*) => AskDeleteProfile())
Y += 34
G.AddButton("x120 y" (Y - 4) " w300", "حفظ التوقيت الحالي كملف جديد").OnEvent("Click", (*) => AskNewProfile())
Y += 36
AddMsRow("انتظار بعد الطلقة:", "DelayShot")
AddMsRow("مدة مسك التوماهوك:", "HoldTomahawk")
AddMsRow("انتظار قبل التبديل:", "DelaySwap")
AddMsRow("بين التبديل والرجوع:", "SwapGap")

Y += 6
Section("اللعبة")
AddFlag("يشتغل بس وانت داخل اللعبة", "GameOnly")
G.AddText("x250 y" Y " w170 Right", "اسم برنامج اللعبة:")
global GameEdit := G.AddEdit("x120 y" (Y - 3) " w120 Center", Cfg["GameExe"])
GameEdit.OnEvent("LoseFocus", (ctl, *) => SetSetting("GameExe", ctl.Value))
G.AddButton("x20 y" (Y - 4) " w90", "تحديد").OnEvent("Click", (*) => DetectGame())
Y += 34
G.AddText("x20 y" Y " w400 Right cGray", "اضغط تحديد ثم افتح اللعبة خلال ٥ ثواني")
Y += 26

Y += 6
Section("خيارات")
AddFlag("تعرّف تلقائي: يشتغل بس وانت ماسك السلاح الرئيسي", "Track")
AddFlag("مؤشر صغير على الشاشة", "Indicator")
AddFlag("تنبيهني إذا نزل إصدار جديد", "CheckUpdates")

Y += 8
global StatusText := G.AddText("x20 y" Y " w400 Center", "")
Y += 28
global ToggleBtn := G.AddButton("x230 y" Y " w190 h32", "تشغيل")
ToggleBtn.OnEvent("Click", (*) => ToggleEnabled())
G.AddButton("x20 y" Y " w190 h32", "تجربة").OnEvent("Click", (*) => RunTest())
Y += 40
global UpdateText := G.AddText("x20 y" Y " w400 Center cBlue Hidden", "")
UpdateText.OnEvent("Click", (*) => Run(DownloadUrl))
Y += 24
G.AddText("x20 y" Y " w400 Center cGray", "إذا سكّرت النافذة يكمل البرنامج شغله من أيقونة جنب الساعة")
global WinH := Y + 30

G.OnEvent("Close", (*) => (G.Hide(), true))

; ---------- المؤشر على الشاشة ----------
global Osd := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "مؤشر الكاتم")
Osd.BackColor := "010101"
Osd.MarginX := 8, Osd.MarginY := 4
Osd.SetFont("s11 Bold", "Segoe UI")
global OsdText := Osd.AddText("w220 Right", "")
WinSetTransColor "010101", Osd

; ---------- أيقونة جنب الساعة ----------
A_TrayMenu.Delete()
A_TrayMenu.Add("فتح الإعدادات", (*) => G.Show())
A_TrayMenu.Add("تشغيل / إيقاف", (*) => ToggleEnabled())
A_TrayMenu.Add("تجربة الحركة", (*) => RunTest())
A_TrayMenu.Add()
A_TrayMenu.Add("خروج", (*) => ExitApp())
A_TrayMenu.Default := "فتح الإعدادات"
A_IconTip := "كاتم السنايبر"

BindHotkeys()
RefreshProfiles()
RefreshSwapRows()
UpdateStatus()
G.Show("w440 h" WinH)
if Cfg["CheckUpdates"]
    SetTimer CheckUpdate, -3000
return

; ---------- الإعدادات ----------
EnsureUnicodeIni() {
    ; الأسماء العربية (ملفات التوقيت) تحتاج الملف يكون بترميز يدعم العربي
    if !FileExist(SettingsFile) {
        FileAppend "", SettingsFile, "UTF-16"
        return
    }
    f := FileOpen(SettingsFile, "r")
    bom := f.Length >= 2 ? f.ReadUShort() : 0
    f.Close()
    if (bom = 0xFEFF)
        return
    text := FileRead(SettingsFile)
    FileDelete SettingsFile
    FileAppend text, SettingsFile, "UTF-16"
}

ClampInt(v, lo, hi, fallback) {
    if !IsInteger(v)
        return fallback
    return Max(lo, Min(hi, Integer(v)))
}

ClampMs(key, v) {
    lim := Limits[key]
    return ClampInt(v, lim[1], lim[2], Defaults[key])
}

Save(key) {
    IniWrite Cfg[key], SettingsFile, "Settings", key
}

; نقطة وحدة لتغيير أي إعداد (الواجهة تستخدمها)
SetSetting(key, value) {
    if !Defaults.Has(key)
        return false
    if Limits.Has(key) {
        value := ClampMs(key, value)
        Cfg[key] := value
        Save(key)
        IniWrite value, SettingsFile, ProfileSection(Cfg["Profile"]), key
        if MsEdits.Has(key) && MsEdits[key].Value != value
            MsEdits[key].Value := value
        return true
    }
    if HasValue(FlagFields, key)
        value := value ? 1 : 0
    else if (key = "IndicatorPos")
        value := ClampInt(value, 1, 4, 1)
    else if (key = "GameExe")
        value := Trim(value)
    else if HasValue(KeyFields, key) {
        old := Cfg[key]
        Cfg[key] := value
        try BindHotkeys()
        catch {
            Cfg[key] := old
            BindHotkeys()
            return false
        }
        Save(key)
        if KeyEdits.Has(key)
            KeyEdits[key].Value := value
        UpdateStatus()
        return true
    }
    Cfg[key] := value
    Save(key)
    if FlagBoxes.Has(key)
        FlagBoxes[key].Value := value
    if (key = "SwapMode") {
        BindHotkeys()
        RefreshSwapRows()
    }
    if (key = "CheckUpdates" && value)
        SetTimer CheckUpdate, -100
    UpdateStatus()
    return true
}

; وقت الكتابة: يحفظ بس إذا الرقم داخل الحدود، والتصحيح يصير لما تطلع من الخانة
SaveIfValid(key, v) {
    lim := Limits[key]
    if IsInteger(v) && v >= lim[1] && v <= lim[2]
        SetSetting(key, v)
}

HasValue(arr, v) {
    for x in arr
        if (x = v)
            return true
    return false
}

RefreshSwapRows() {
    two := Cfg["SwapMode"]
    for k, on in Map("Swap", !two, "PistolKey", two, "PrimaryKey", two)
        KeyEdits[k].Enabled := on, KeyBtns[k].Enabled := on
}

; ---------- ملفات التوقيت ----------
ProfileSection(name) => "Profile " name

InitProfiles() {
    if (ProfileList().Length = 0)
        ProfileSave(Cfg["Profile"])
    else if !ProfileExists(Cfg["Profile"])
        ProfileLoad(ProfileList()[1], false)
}

ProfileList() {
    list := []
    try sections := IniRead(SettingsFile)
    catch
        return list
    for s in StrSplit(sections, "`n", "`r")
        if (SubStr(s, 1, 8) = "Profile ")
            list.Push(SubStr(s, 9))
    return list
}

ProfileExists(name) => HasValue(ProfileList(), name)

ProfileSave(name) {
    name := Trim(name)
    if (name = "" || InStr(name, "]"))
        return false
    for k in TimingKeys
        IniWrite Cfg[k], SettingsFile, ProfileSection(name), k
    Cfg["Profile"] := name
    Save("Profile")
    return true
}

ProfileLoad(name, refresh := true) {
    if !ProfileExists(name)
        return false
    for k in TimingKeys {
        Cfg[k] := ClampMs(k, IniRead(SettingsFile, ProfileSection(name), k, Cfg[k]))
        Save(k)
    }
    Cfg["Profile"] := name
    Save("Profile")
    if refresh
        RefreshProfiles()
    return true
}

ProfileDelete(name) {
    list := ProfileList()
    if (list.Length <= 1 || !ProfileExists(name))
        return false
    IniDelete SettingsFile, ProfileSection(name)
    if (Cfg["Profile"] = name)
        ProfileLoad(ProfileList()[1], false)
    RefreshProfiles()
    return true
}

ProfileNext(*) {
    list := ProfileList()
    if (list.Length < 2)
        return
    i := 1
    for idx, n in list
        if (n = Cfg["Profile"])
            i := idx
    ProfileLoad(list[Mod(i, list.Length) + 1])
    SoundBeep 700, 80
    OsdFlash("الملف: " Cfg["Profile"])
}

RefreshProfiles() {
    list := ProfileList()
    ProfileBox.Delete()
    ProfileBox.Add(list)
    for idx, n in list
        if (n = Cfg["Profile"])
            ProfileBox.Choose(idx)
    for k in TimingKeys
        MsEdits[k].Value := Cfg[k]
}

AskNewProfile() {
    r := InputBox("اكتب اسم الملف الجديد (مثلاً اسم السنايبر):", "كاتم السنايبر", "w300 h130")
    if (r.Result != "OK" || Trim(r.Value) = "")
        return
    if !ProfileSave(r.Value)
        return MsgBox("الاسم ما ينفع، جرّب اسم ثاني.", "كاتم السنايبر")
    RefreshProfiles()
}

AskDeleteProfile() {
    name := Cfg["Profile"]
    if (ProfileList().Length <= 1)
        return MsgBox("لازم يبقى ملف واحد على الأقل.", "كاتم السنايبر")
    if (MsgBox("تحذف الملف «" name "»؟", "كاتم السنايبر", "YesNo") = "Yes")
        ProfileDelete(name)
}

; ---------- اللعبة ----------
GameActive(*) {
    if !Cfg["GameOnly"]
        return true
    for exe in StrSplit(Cfg["GameExe"], ",") {
        exe := Trim(exe)
        if (exe != "" && WinActive("ahk_exe " exe))
            return true
    }
    return false
}

DetectGame() {
    Loop 5 {
        ToolTip "افتح اللعبة الحين... " (6 - A_Index)
        Sleep 1000
    }
    ToolTip
    try exe := WinGetProcessName("A")
    catch
        exe := ""
    if (exe = "" || exe = "explorer.exe" || InStr(A_ScriptFullPath, exe)) {
        MsgBox "ما لقيت اللعبة، تأكد إنك فتحتها قبل ما يخلص العد.", "كاتم السنايبر"
        return
    }
    SetSetting("GameExe", exe)
    GameEdit.Value := exe
    MsgBox "تم، البرنامج بيشتغل بس داخل: " exe, "كاتم السنايبر"
}

; ---------- التشغيل ----------
ToggleEnabled(*) {
    global Enabled, OnPrimary
    if Capturing
        return
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
    OsdUpdate()
}

BindHotkeys() {
    global Bound
    for h in Bound {
        SetContext(h[2])
        try Hotkey h[1], "Off"
    }
    HotIf
    Bound := []

    ; زر الطلقة وأزرار التبديل: بس داخل اللعبة
    BindOne("~*" Cfg["Trigger"], OnShot, GameActive)
    if Cfg["SwapMode"] {
        BindOne("~*" Cfg["PistolKey"], (*) => SetPrimary(false), GameActive)
        BindOne("~*" Cfg["PrimaryKey"], (*) => SetPrimary(true), GameActive)
    } else
        BindOne("~*" Cfg["Swap"], OnManualSwap, GameActive)

    BindOne("*" Cfg["Toggle"], ToggleEnabled)
    if (Cfg["ProfileKey"] != "")
        BindOne("*" Cfg["ProfileKey"], ProfileNext)
}

BindOne(name, fn, ctx := "") {
    SetContext(ctx)
    try Hotkey name, fn, "On"
    finally HotIf
    Bound.Push([name, ctx])
}

SetContext(ctx) {
    if (ctx = "")
        HotIf
    else
        HotIf ctx
}

OnManualSwap(*) {
    ; التبديل اللي تسويه بيدك يغير السلاح اللي ماسكه
    global OnPrimary
    if Enabled
        OnPrimary := !OnPrimary
}

SetPrimary(v) {
    global OnPrimary
    OnPrimary := v
}

; يرسل الزر برمزه الفعلي في الكيبورد عشان الألعاب تفهمه أكثر
SendName(key) {
    sc := GetKeySC(key)
    return sc ? Format("sc{:03X}", sc) : key
}

TapKey(key, holdMs := 20) {
    k := SendName(key)
    Send "{Blind}{" k " down}"
    Sleep holdMs
    Send "{Blind}{" k " up}"
}

DoSequence() {
    Sleep Cfg["DelayShot"]
    TapKey(Cfg["Tomahawk"], Cfg["HoldTomahawk"])
    Sleep Cfg["DelaySwap"]
    if Cfg["SwapMode"] {
        TapKey(Cfg["PistolKey"])
        Sleep Cfg["SwapGap"]
        TapKey(Cfg["PrimaryKey"])
    } else {
        TapKey(Cfg["Swap"])
        Sleep Cfg["SwapGap"]
        TapKey(Cfg["Swap"])
    }
}

OnShot(*) {
    global Busy
    if (!Enabled || Busy || Capturing)
        return
    if (Cfg["Track"] && !OnPrimary)
        return
    Busy := true
    try DoSequence()
    Busy := false
}

; تجربة: عد تنازلي ثم يسوي الحركة مرة وحدة (حتى لو البرنامج موقّف)
RunTest(*) {
    global Busy
    if (Busy || Capturing)
        return
    Busy := true
    Loop 3 {
        ToolTip "تجربة الحركة بعد " (4 - A_Index) "..."
        Sleep 1000
    }
    ToolTip "تجربة الحركة الحين"
    try DoSequence()
    ToolTip
    Busy := false
}

; ---------- المؤشر ----------
OsdUpdate() {
    if !Cfg["Indicator"] {
        Osd.Hide()
        return
    }
    OsdText.Text := (Enabled ? "● الكاتم شغّال" : "● الكاتم موقّف") "  ·  " Cfg["Profile"]
    OsdText.SetFont(Enabled ? "c22DD55" : "cFF5555")
    OsdShow()
}

OsdShow() {
    pos := Cfg["IndicatorPos"]
    w := 240, h := 30
    x := (pos = 1 || pos = 3) ? 10 : A_ScreenWidth - w - 10
    y := (pos <= 2) ? 10 : A_ScreenHeight - h - 50
    Osd.Show("NA x" x " y" y " w" w " h" h)
}

OsdFlash(text) {
    OsdText.Text := text
    OsdText.SetFont("cFFCC33")
    OsdShow()
    SetTimer OsdUpdate, -1500
}

; ---------- الإصدار الجديد ----------
CheckUpdate() {
    global UpdateAvailable, LatestVersion
    if !Cfg["CheckUpdates"]
        return
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(2000, 2000, 3000, 3000)
        req.Open("GET", RepoApi, false)
        req.SetRequestHeader("User-Agent", "SniperCancel")
        req.Send()
        if (req.Status != 200)
            return
        if !RegExMatch(req.ResponseText, '"tag_name"\s*:\s*"v?([\d.]+)"', &m)
            return
    } catch
        return
    if (VerCompare(m[1], AppVersion) <= 0)
        return
    UpdateAvailable := true
    LatestVersion := m[1]
    UpdateText.Text := "فيه إصدار جديد " LatestVersion " · اضغط هنا للتحميل"
    UpdateText.Visible := true
    try A_TrayMenu.Insert("1&", "تحميل الإصدار الجديد " LatestVersion, (*) => Run(DownloadUrl))
    TrayTip "فيه إصدار جديد " LatestVersion ". افتح البرنامج للتحميل.", "كاتم السنايبر"
}

; ---------- تعيين الأزرار ----------
CaptureKey(key) {
    global Capturing
    if Capturing
        return
    Capturing := true
    edt := KeyEdits[key]
    old := Cfg[key]
    edt.Value := "اضغط الزر..."
    Sleep 350  ; عشان ما ياخذ ضغطة الماوس اللي ضغطت فيها "تعيين"

    found := ""
    deadline := A_TickCount + 8000
    while (found = "" && A_TickCount < deadline) {
        Loop 254 {
            vk := A_Index
            if (vk = 0x10 || vk = 0x11 || vk = 0x12)  ; نتجاهل النسخ العامة من شفت وكنترول وألت
                continue
            if (vk >= 0x9C && vk <= 0x9F)  ; أكواد عجلة الماوس الوهمية: تطلع مضغوطة دايم فتنمسك بدون ما تضغط شي
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

    edt.Value := old
    if (found != "" && found != "Escape") {
        if !SetSetting(key, found)
            MsgBox "ما قدرت أستخدم هذا الزر، جرّب زر ثاني.", "كاتم السنايبر"
    }
    if (found != "")
        KeyWait found
    Capturing := false
    UpdateStatus()
}
