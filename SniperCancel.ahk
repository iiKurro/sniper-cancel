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
    "Track",     0,
    "Lang",      "ar"
)

global Cfg := Map()
for k, v in Defaults
    Cfg[k] := IniRead(SettingsFile, "Settings", k, v)

global Enabled := false
global Busy := false
global OnPrimary := true
global BoundTrigger := "", BoundToggle := "", BoundSwap := ""
global CapturingKey := ""
global AppVersion := "2.0.0"

#Include lib\WebView2\WebView2.ahk

; ---------- ملفات الواجهة ----------
; الواجهة صفحة ويب صغيرة تنفتح بمحرك الويب اللي جاي مع ويندوز
; وتنقفل كاملة أول ما تسكّر النافذة عشان يبقى البرنامج خفيف بالخلفية
if A_IsCompiled {
    try FileInstall "ui.html", SettingsDir "\ui.html", 1
    try FileInstall "lib\WebView2\64bit\WebView2Loader.dll", SettingsDir "\WebView2Loader.dll", 1
}
global UiFile := A_IsCompiled ? SettingsDir "\ui.html" : A_ScriptDir "\ui.html"
global LoaderDll := A_IsCompiled ? SettingsDir "\WebView2Loader.dll" : A_ScriptDir "\lib\WebView2\64bit\WebView2Loader.dll"

global WVC := 0, WV := 0, WebMsgSub := 0

global G := Gui("-MaximizeBox", T("كاتم السنايبر", "Sniper Cancel"))
G.BackColor := "07080A"
G.MarginX := 0, G.MarginY := 0
G.OnEvent("Close", (*) => (CloseWindow(), true))
G.OnEvent("Size", (*) => (WVC && WVC.Fill()))

; ---------- أيقونة جنب الساعة ----------
BuildTrayMenu()

BindHotkeys()
UpdateStatus()
ShowWindow()
return

; ---------- النافذة ----------
ShowWindow() {
    global WVC, WV, WebMsgSub
    static first := true
    if first {
        first := false
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", G.Hwnd, "int", 20, "int*", 1, "int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", G.Hwnd, "int", 35, "int*", 0x0A0807, "int", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", G.Hwnd, "int", 34, "int*", 0x2E2A2A, "int", 4)
        ; الطول يناسب الشاشة، والباقي ينزل بالسحب
        MonitorGetWorkArea(, , &top, , &bottom)
        h := Min(790, Floor((bottom - top) / (A_ScreenDPI / 96)) - 60)
        G.Show("w520 h" h)
    } else
        G.Show()

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
        if MsgBox(T("ما قدرت أفتح الواجهة. غالبًا جهازك ناقصه مكوّن (WebView2) من مايكروسوفت.`n`nتبي أفتح صفحة تحميله؟ البرنامج نفسه شغّال وتقدر تستخدم زر التشغيل عادي.", "Could not open the settings window. Your PC is probably missing Microsoft WebView2.`n`nOpen its download page? The app itself still works with the on/off hotkey.") "`n`n(" e.Message ")", T("كاتم السنايبر", "Sniper Cancel"), "YesNo Icon! " RtlFlag()) = "Yes"
            Run "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
        G.Hide()
    }
}

CloseWindow() {
    global WVC, WV, WebMsgSub
    G.Hide()
    WebMsgSub := 0
    if WVC
        try WVC.Close()
    WVC := WV := 0
}

OnWebMessage(sender, args) {
    msg := args.TryGetWebMessageAsString()
    parts := StrSplit(msg, "|")
    switch parts[1] {
        case "ready":
            PushState()
        case "toggle":
            SetTimer(() => ToggleEnabled(), -1)
        case "capture":
            if (parts.Length >= 2 && RegExMatch(parts[2], "^(Trigger|Tomahawk|Swap|Toggle)$"))
                SetTimer(CaptureKey.Bind(parts[2]), -1)
        case "set":
            if (parts.Length >= 3 && parts[2] = "Lang" && RegExMatch(parts[3], "^(ar|en)$")) {
                Cfg["Lang"] := parts[3]
                Save("Lang")
                G.Title := T("كاتم السنايبر", "Sniper Cancel")
                BuildTrayMenu()
                UpdateStatus()
                return
            }
            if (parts.Length >= 3 && RegExMatch(parts[2], "^(DelayShot|HoldTomahawk|DelaySwap|SwapGap|Track)$") && IsInteger(parts[3])) {
                v := Integer(parts[3])
                v := parts[2] = "Track" ? (v ? 1 : 0) : Max(0, Min(2000, v))
                Cfg[parts[2]] := v
                Save(parts[2])
            }
    }
}

; النص حسب اللغة المختارة
T(ar, en) => Cfg["Lang"] = "en" ? en : ar

; رسائل ويندوز من اليمين لليسار لما تكون اللغة عربي
RtlFlag() => Cfg["Lang"] = "en" ? "" : "0x180000"

BuildTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add(T("فتح الإعدادات", "Open settings"), (*) => ShowWindow())
    A_TrayMenu.Add(T("تشغيل / إيقاف", "On / Off"), (*) => ToggleEnabled())
    A_TrayMenu.Add()
    A_TrayMenu.Add(T("خروج", "Exit"), (*) => ExitApp())
    A_TrayMenu.Default := T("فتح الإعدادات", "Open settings")
}

JsonStr(v) {
    v := StrReplace(v, "\", "\\")
    v := StrReplace(v, '"', '\"')
    return '"' v '"'
}

PushState() {
    if !WV
        return
    c := "", l := ""
    for k, v in Cfg
        c .= (c = "" ? "" : ",") JsonStr(k) ":" (IsInteger(v) ? v : JsonStr(v))
    for k in ["Trigger", "Tomahawk", "Swap", "Toggle"]
        l .= (l = "" ? "" : ",") JsonStr(k) ":" JsonStr(KeyLabel(Cfg[k]))
    json := '{"cfg":{' c '},"labels":{' l '},"enabled":' (Enabled ? "true" : "false")
        . ',"capturing":' JsonStr(CapturingKey) ',"version":' JsonStr(AppVersion) '}'
    try WV.PostWebMessageAsJson(json)
}

; ---------- الدوال ----------
KeyLabel(k) {
    static names := Map(
        "LButton", "كليك يسار", "RButton", "كليك يمين", "MButton", "زر العجلة",
        "XButton1", "زر جانبي ١", "XButton2", "زر جانبي ٢", "Space", "مسافة",
        "LShift", "شفت", "RShift", "شفت يمين", "LControl", "كنترول", "RControl", "كنترول يمين",
        "LAlt", "ألت", "RAlt", "ألت يمين", "Tab", "تاب", "CapsLock", "كابس", "Enter", "إنتر"
    )
    if (Cfg["Lang"] = "en")
        return RegExReplace(StrUpper(SubStr(k, 1, 1)) SubStr(k, 2), "^(LButton|RButton|MButton)$", "$1")
    return names.Has(k) ? names[k] : StrUpper(k)
}

Save(key) {
    IniWrite Cfg[key], SettingsFile, "Settings", key
}

ToggleEnabled() {
    global Enabled, OnPrimary
    if (CapturingKey != "")
        return
    Enabled := !Enabled
    OnPrimary := true
    SoundBeep Enabled ? 900 : 400, 120
    UpdateStatus()
}

UpdateStatus() {
    A_IconTip := T("كاتم السنايبر: ", "Sniper Cancel: ") (Enabled ? T("شغّال", "ON") : T("موقّف", "OFF"))
    PushState()
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
    if (!Enabled || Busy || CapturingKey != "")
        return
    if WinActive("ahk_id " G.Hwnd)   ; الضغط داخل نافذة الإعدادات ما يحسب طلقة
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
CaptureKey(key) {
    global CapturingKey
    if (CapturingKey != "")
        return
    CapturingKey := key
    old := Cfg[key]
    PushState()
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
            MsgBox T("ما قدرت أستخدم هذا الزر، جرّب زر ثاني.", "Can't use that key, try another one."), T("كاتم السنايبر", "Sniper Cancel"), RtlFlag()
            Cfg[key] := old, Save(key)
            BindHotkeys()
        }
    }
    if (found != "")
        KeyWait found

    CapturingKey := ""
    UpdateStatus()
}
