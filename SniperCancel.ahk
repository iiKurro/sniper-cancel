; كاتم السنايبر: بعد كل طلقة يمسك التوماهوك ثم يبدل السلاح ويرجعه بسرعة
#Requires AutoHotkey v2.0
#SingleInstance Off
; خفة: ما فيه أي تكرار يشتغل بالخلفية، كل شي يصير بس لما تضغط زر
KeyHistory 0
ListLines False

; نسخة وحدة بس: لو البرنامج مفتوح من قبل، نفتح نافذته ونطلع
global ShowMsg := DllCall("RegisterWindowMessage", "str", "SniperCancelShow", "uint")
DllCall("CreateMutex", "ptr", 0, "int", false, "str", "SniperCancelSingleInstance")
if (A_LastError = 183) {
    DllCall("PostMessage", "ptr", 0xFFFF, "uint", ShowMsg, "ptr", 0, "ptr", 0)
    ExitApp
}
SetWorkingDir A_ScriptDir
ProcessSetPriority "High"
if !A_IsCompiled && FileExist(A_ScriptDir "\icon.ico")
    TraySetIcon A_ScriptDir "\icon.ico"

;@Ahk2Exe-SetName كاتم السنايبر
;@Ahk2Exe-SetDescription كاتم السنايبر
;@Ahk2Exe-SetVersion 1.0.0
;@Ahk2Exe-SetMainIcon icon.ico

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
    "Profile",      "افتراضي",
    "Lang",         "ar"         ; ar أو en
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
if (Cfg["Lang"] != "en")
    Cfg["Lang"] := "ar"
Cfg["IndicatorPos"] := ClampInt(Cfg["IndicatorPos"], 1, 4, 1)

global Enabled := false
global Busy := false
global Capturing := false
global OnPrimary := true
global Bound := []
global UpdateAvailable := false, LatestVersion := ""

InitProfiles()

; ---------- الواجهة ----------
; الواجهة صفحة ويب (ui.html) تنفتح بمحرك الويب اللي جاي مع ويندوز
; تنبني بس لما تفتح النافذة، وأول ما تسكّرها تنمسح كاملة من الذاكرة
#Include lib\WebView2\WebView2.ahk

if A_IsCompiled {
    ; لو الملف مستخدم (نسخة ثانية فاتحة) نكمل عادي
    try {
        FileInstall "ui.html", SettingsDir "\ui.html", 1
    }
    try {
        FileInstall "lib\WebView2\64bit\WebView2Loader.dll", SettingsDir "\WebView2Loader.dll", 1
    }
}
global UiFile := A_IsCompiled ? SettingsDir "\ui.html" : A_ScriptDir "\ui.html"
global LoaderDll := A_IsCompiled ? SettingsDir "\WebView2Loader.dll" : A_ScriptDir "\lib\WebView2\64bit\WebView2Loader.dll"
global WVC := 0, WV := 0, WebMsgSub := 0
global CapturingKey := "", Updating := false
; بقايا الواجهة القديمة: فاضية، عشان الدوال اللي تتأكد منها تشتغل بدون تغيير
global KeyEdits := Map(), KeyBtns := Map(), MsEdits := Map(), FlagBoxes := Map()

global G := Gui("-MaximizeBox", AppTitle())
G.BackColor := "07080A"
G.MarginX := 0, G.MarginY := 0
G.OnEvent("Close", (*) => (CloseWindow(), true))
G.OnEvent("Size", (*) => (WVC && WVC.Fill()))
OnMessage(ShowMsg, (*) => ShowWindow())

; ---------- المؤشر على الشاشة ----------
global Osd := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "مؤشر الكاتم")
Osd.BackColor := "010101"
Osd.MarginX := 8, Osd.MarginY := 4
Osd.SetFont("s11 Bold", "Segoe UI")
global OsdText := Osd.AddText("w220 Right", "")
WinSetTransColor "010101", Osd

; ---------- أيقونة جنب الساعة ----------
BuildTrayMenu()

BindHotkeys()
UpdateStatus()
ShowWindow()
if Cfg["CheckUpdates"]
    SetTimer CheckUpdate, -3000
return

; نافذة وحدة بس: نفس النافذة تنعرض وتتقدم بدل ما تنفتح ثانية
ShowWindow(*) {
    global WVC, WV, WebMsgSub
    static first := true
    if first {
        first := false
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", G.Hwnd, "int", 20, "int*", 1, "int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", G.Hwnd, "int", 35, "int*", 0x0A0807, "int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", G.Hwnd, "int", 34, "int*", 0x2E2A2A, "int", 4)
        ; الطول يناسب الشاشة، والباقي ينزل بالسحب
        MonitorGetWorkArea(, , &top, , &bottom)
        h := Min(860, Floor((bottom - top) / (A_ScreenDPI / 96)) - 60)
        G.Show("w540 h" h)
    } else
        G.Show()
    WinActivate G

    if WVC
        return
    try {
        WVC := WebView2.CreateControllerAsync(G.Hwnd, 0, SettingsDir "\webview", "", LoaderDll).await2()
        try WVC.DefaultBackgroundColor := 0x0A0807FF
        WVC.Fill()
        WV := WVC.CoreWebView2
        st := WV.Settings
        try st.AreDevToolsEnabled := false
        try st.AreDefaultContextMenusEnabled := false
        try st.IsZoomControlEnabled := false
        try st.IsStatusBarEnabled := false
        WebMsgSub := WV.WebMessageReceived(OnWebMessage)
        WV.Navigate("file:///" StrReplace(UiFile, "\", "/"))
    } catch as e {
        WVC := WV := WebMsgSub := 0
        G.Hide()
        if MsgBox(T("ما قدرت أفتح الواجهة. غالبًا جهازك ناقصه مكوّن (WebView2) من مايكروسوفت.`n`nتبي أفتح صفحة تحميله؟ البرنامج نفسه شغّال وتقدر تستخدم زر التشغيل عادي.", "Could not open the settings window. Your PC is probably missing Microsoft WebView2.`n`nOpen its download page? The app itself still works with the on/off hotkey.") "`n`n(" e.Message ")", AppTitle(), "YesNo Icon! " RtlFlag()) = "Yes"
            Run "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
    }
}

; تسكير النافذة يمسح الواجهة كاملة (مو بس يخفيها) عشان ما تاخذ ذاكرة ولا معالج
CloseWindow() {
    global WVC, WV, WebMsgSub
    G.Hide()
    WebMsgSub := 0
    if WVC
        try WVC.Close()
    WVC := WV := 0
    ; نرجّع الذاكرة اللي أخذتها الواجهة للويندوز
    SetTimer(() => DllCall("SetProcessWorkingSetSize", "ptr", -1, "ptr", -1, "ptr", -1), -1500)
}

OnWebMessage(sender, args) {
    p := StrSplit(args.TryGetWebMessageAsString(), "|", , 3)
    a1 := p.Length >= 2 ? p[2] : "", a2 := p.Length >= 3 ? p[3] : ""
    switch p[1] {
        case "ready":   PushState()
        case "toggle":  SetTimer(ToggleEnabled, -1)
        case "test":    SetTimer(RunTest, -1)
        case "detect":  SetTimer(DetectGame, -1)
        case "update":  SetTimer(DoUpdate, -1)
        case "capture":
            if HasValue(KeyFields, a1)
                SetTimer(CaptureKey.Bind(a1), -1)
        case "set":
            if (a1 = "Profile")
                return
            if !SetSetting(a1, a2)
                PushState()
            else if (a1 = "Lang") {
                G.Title := AppTitle()
                BuildTrayMenu()
                PushState()
            }
        case "profile":
            switch a1 {
                case "load": ProfileLoad(a2)
                case "new":
                    if !ProfileSave(a2)
                        MsgBox T("الاسم ما ينفع، جرّب اسم ثاني.", "Invalid name, try another."), AppTitle(), RtlFlag()
                case "del":  ProfileDelete(Cfg["Profile"])
            }
            PushState()
    }
}

JsonStr(v) {
    v := StrReplace(v, "\", "\\")
    v := StrReplace(v, '"', '\"')
    v := StrReplace(v, "`n", "\n")
    v := StrReplace(v, "`r", "")
    return '"' v '"'
}

; يرسل كل الحالة للواجهة (لو كانت مفتوحة)
PushState() {
    if !WV
        return
    c := "", l := "", pr := "", lm := ""
    for k, v in Cfg
        c .= (c = "" ? "" : ",") JsonStr(k) ":" (IsInteger(v) ? Integer(v) : JsonStr(v))
    for k in KeyFields
        l .= (l = "" ? "" : ",") JsonStr(k) ":" JsonStr(KeyLabel(Cfg[k]))
    for n in ProfileList()
        pr .= (pr = "" ? "" : ",") JsonStr(n)
    for k, v in Limits
        lm .= (lm = "" ? "" : ",") JsonStr(k) ":[" v[1] "," v[2] "]"
    json := '{"cfg":{' c '},"labels":{' l '},"profiles":[' pr '],"limits":{' lm '}'
        . ',"enabled":' (Enabled ? "true" : "false")
        . ',"capturing":' JsonStr(CapturingKey)
        . ',"version":' JsonStr(AppVersion)
        . ',"update":{"available":' (UpdateAvailable ? "true" : "false") ',"latest":' JsonStr(LatestVersion) ',"busy":' (Updating ? "true" : "false") '}}'
    try WV.PostWebMessageAsJson(json)
}

KeyLabel(k) {
    static names := Map(
        "LButton", "كليك يسار", "RButton", "كليك يمين", "MButton", "زر العجلة",
        "XButton1", "زر جانبي ١", "XButton2", "زر جانبي ٢", "Space", "مسافة",
        "LShift", "شفت", "RShift", "شفت يمين", "LControl", "كنترول", "RControl", "كنترول يمين",
        "LAlt", "ألت", "RAlt", "ألت يمين", "Tab", "تاب", "CapsLock", "كابس", "Enter", "إنتر"
    )
    static en := Map("LButton", "Left click", "RButton", "Right click", "MButton", "Wheel click",
        "XButton1", "Side 1", "XButton2", "Side 2")
    if (k = "")
        return "—"
    if (Cfg["Lang"] = "en")
        return en.Has(k) ? en[k] : StrUpper(SubStr(k, 1, 1)) SubStr(k, 2)
    return names.Has(k) ? names[k] : StrUpper(k)
}

BuildTrayMenu() {
    A_TrayMenu.Delete()
    if UpdateAvailable
        A_TrayMenu.Add(T("تحديث للإصدار الجديد ", "Update to version ") LatestVersion, (*) => DoUpdate())
    A_TrayMenu.Add(T("فتح الإعدادات", "Open settings"), (*) => ShowWindow())
    A_TrayMenu.Add(T("تشغيل / إيقاف", "On / Off"), (*) => ToggleEnabled())
    A_TrayMenu.Add(T("تجربة الحركة", "Test the move"), (*) => RunTest())
    A_TrayMenu.Add()
    A_TrayMenu.Add(T("خروج", "Exit"), (*) => ExitApp())
    A_TrayMenu.Default := T("فتح الإعدادات", "Open settings")
}

; رسائل ويندوز من اليمين لليسار لما تكون اللغة عربي
RtlFlag() => Cfg["Lang"] = "en" ? "" : "0x180000"

; النص باللغة المختارة
T(ar, en) => (Cfg["Lang"] = "en") ? en : ar
AppTitle() => T("كاتم السنايبر", "Sniper Cancel")

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
    else if (key = "Lang")
        value := (value = "en") ? "en" : "ar"
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

RefreshSwapRows() => PushState()

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
    OsdFlash(T("الملف: ", "Profile: ") Cfg["Profile"])
}

RefreshProfiles() => PushState()

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
        ToolTip T("افتح اللعبة الحين... ", "Switch to the game now... ") (6 - A_Index)
        Sleep 1000
    }
    ToolTip
    try exe := WinGetProcessName("A")
    catch
        exe := ""
    if (exe = "" || exe = "explorer.exe" || InStr(A_ScriptFullPath, exe)) {
        MsgBox T("ما لقيت اللعبة، تأكد إنك فتحتها قبل ما يخلص العد.", "Game not found. Open it before the countdown ends."), AppTitle(), RtlFlag()
        return
    }
    SetSetting("GameExe", exe)
    PushState()
    MsgBox T("تم، البرنامج بيشتغل بس داخل: ", "Done. It will only work inside: ") exe, AppTitle(), RtlFlag()
}

; ---------- التشغيل ----------
ToggleEnabled(*) {
    global Enabled, OnPrimary
    if Capturing
        return
    Enabled := !Enabled
    OnPrimary := true
    BindHotkeys()
    SoundBeep Enabled ? 900 : 400, 120
    UpdateStatus()
}

UpdateStatus() {
    A_IconTip := Enabled ? T("كاتم السنايبر: شغّال", "Sniper Cancel: on") : T("كاتم السنايبر: موقّف", "Sniper Cancel: off")
    OsdUpdate()
    PushState()
}

BindHotkeys() {
    global Bound
    for h in Bound {
        SetContext(h[2])
        try Hotkey h[1], "Off"
    }
    HotIf
    Bound := []

    ; زر الطلقة وأزرار التبديل: بس وهو شغّال وداخل اللعبة
    ; وهو موقّف ما فيه أي مراقبة للماوس أو الكيبورد أبداً
    if Enabled
        BindGameKeys()

    ; زر التشغيل وزر الملف يتسجلون عند الويندوز مباشرة بدون مراقبة
    BindOne(Cfg["Toggle"], ToggleEnabled)
    if (Cfg["ProfileKey"] != "")
        BindOne(Cfg["ProfileKey"], ProfileNext)
}

BindGameKeys() {
    BindOne("~*" Cfg["Trigger"], OnShot, GameActive)
    if Cfg["SwapMode"] {
        BindOne("~*" Cfg["PistolKey"], (*) => SetPrimary(false), GameActive)
        BindOne("~*" Cfg["PrimaryKey"], (*) => SetPrimary(true), GameActive)
    } else
        BindOne("~*" Cfg["Swap"], OnManualSwap, GameActive)
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
    if WinActive("ahk_id " G.Hwnd)   ; الضغط داخل نافذة الإعدادات ما يحسب طلقة
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
        ToolTip T("تجربة الحركة بعد ", "Testing in ") (4 - A_Index) "..."
        Sleep 1000
    }
    ToolTip T("تجربة الحركة الحين", "Testing now")
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
    OsdText.Text := (Enabled ? T("● الكاتم شغّال", "● Cancel ON") : T("● الكاتم موقّف", "● Cancel OFF")) "  ·  " Cfg["Profile"]
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
    BuildTrayMenu()
    PushState()
    TrayTip T("فيه إصدار جديد ", "New version ") LatestVersion T(". اضغط تحديث من البرنامج.", " is out. Press Update in the app."), AppTitle()
}

; يحمّل النسخة الجديدة، يبدلها مكان القديمة، ويفتحها على طول
DoUpdate(*) {
    if !A_IsCompiled {
        Run DownloadUrl
        return
    }
    global Updating
    Updating := true
    PushState()
    newExe := A_Temp "\SniperCancel_new.exe"
    try {
        if FileExist(newExe)
            FileDelete newExe
        Download DownloadUrl, newExe
        if (FileGetSize(newExe) < 100000)
            throw Error("small")
    } catch {
        Updating := false
        PushState()
        MsgBox T("ما قدرت أحمّل التحديث، تأكد من النت وجرّب مرة ثانية.", "Could not download the update. Check your internet and try again."), AppTitle(), RtlFlag()
        return
    }
    ; ملف صغير ينتظر البرنامج يقفل، يبدل الملف، ويشغّل الجديد
    bat := A_Temp "\SniperCancel_update.cmd"
    q := Chr(34)
    try FileDelete bat
    FileAppend(
        "@echo off`r`n"
        ":wait`r`n"
        "timeout /t 1 /nobreak >nul`r`n"
        "tasklist /fi " q "PID eq " ProcessExist() q " | find " q " " ProcessExist() " " q " >nul && goto wait`r`n"
        "move /y " q newExe q " " q A_ScriptFullPath q " >nul`r`n"
        "start " q q " " q A_ScriptFullPath q "`r`n"
        "del " q "%~f0" q "`r`n",
        bat, "CP0")
    Run A_ComSpec ' /c "' bat '"', , "Hide"
    ExitApp
}

; ---------- تعيين الأزرار ----------
CaptureKey(key) {
    global Capturing
    if Capturing
        return
    global CapturingKey
    Capturing := true
    CapturingKey := key
    PushState()
    ; المراقبة تشتغل بس وقت التعيين وبعدها تنطفي
    InstallKeybdHook true
    InstallMouseHook true
    KeyWait "LButton"   ; عشان ما ياخذ الضغطة اللي ضغطت فيها على الزر
    Sleep 120

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

    if (found != "" && found != "Escape") {
        if !SetSetting(key, found)
            MsgBox T("ما قدرت أستخدم هذا الزر، جرّب زر ثاني.", "Can't use this key, try another one."), AppTitle(), RtlFlag()
    }
    if (found != "")
        KeyWait found
    InstallKeybdHook false
    InstallMouseHook false
    Capturing := false
    CapturingKey := ""
    UpdateStatus()
}
