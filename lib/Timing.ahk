; توقيت دقيق بالمللي ثانية
; Sleep العادي في AHK يقرّب الانتظار لساعة ويندوز (حوالي ١٥ مللي ثانية):
; ٤٠ تطلع ٤٧ تقريباً، و٥٠ تطلع ٦٢. هنا الانتظار يطلع نفس الرقم بفرق ١ مللي ثانية تقريباً.

; يطلب من ويندوز ساعة بدقة ١ مللي ثانية (وقت ما الكاتم شغّال بس)، ويرجعها لما يوقف
FineTimer(on) {
    static active := false, honored := false
    on := !!on
    if (on = active)
        return
    if (on && !honored) {
        honored := true
        ; ويندوز ١١ يتجاهل طلب الدقة لو نوافذ البرنامج مخفية، هذا يقوله لا تتجاهله
        ; PROCESS_POWER_THROTTLING_STATE: Version 1، نتحكم بـ IGNORE_TIMER_RESOLUTION ونطفيه
        st := Buffer(12, 0)
        NumPut("uint", 1, "uint", 0x4, "uint", 0, st)
        try DllCall("SetProcessInformation", "ptr", DllCall("GetCurrentProcess", "ptr"), "int", 4, "ptr", st, "uint", 12)
    }
    active := on
    DllCall("winmm\" (on ? "timeBeginPeriod" : "timeEndPeriod"), "uint", 1)
}

; ينتظر عدد مللي ثانية بالضبط
; طول الانتظار يرد على رسائل ويندوز، عشان الماوس والأزرار والنافذة ما تعلق
Wait(ms) {
    static freq := 0
    if (ms <= 0)
        return
    if !freq
        DllCall("QueryPerformanceFrequency", "int64*", &freq)
    DllCall("QueryPerformanceCounter", "int64*", &now := 0)
    stop := now + ms * freq / 1000
    while (now < stop) {
        ; ينام لين يخلص الوقت أو توصل رسالة (QS_ALLINPUT)
        DllCall("MsgWaitForMultipleObjects", "uint", 0, "ptr", 0, "int", 0, "uint", Floor((stop - now) * 1000 / freq), "uint", 0x4FF)
        Sleep -1
        DllCall("QueryPerformanceCounter", "int64*", &now)
    }
}
