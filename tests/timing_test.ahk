; فحص دقة التوقيت (يشتغل في البناء التلقائي): يقارن Wait الدقيق بـ Sleep العادي
; يطلع برقم 1 لو متوسط فرق Wait أكثر من ٤ مللي ثانية
#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\..\lib\Timing.ahk

FineTimer(true)
freq := 0
DllCall("QueryPerformanceFrequency", "int64*", &freq)

; كم زاد (أو نقص) الانتظار عن المطلوب، بالمللي ثانية
Elapsed(fn, ms) {
    DllCall("QueryPerformanceCounter", "int64*", &a := 0)
    fn(ms)
    DllCall("QueryPerformanceCounter", "int64*", &b := 0)
    return (b - a) * 1000 / freq - ms
}

runs := 15, out := "", worst := 0
for ms in [5, 17, 40, 63, 100] {
    w := 0, wMax := 0, s := 0
    Loop runs {
        e := Elapsed(Wait, ms)
        w += e, wMax := Max(wMax, Abs(e))
        s += Elapsed(Sleep, ms)
    }
    worst := Max(worst, Abs(w / runs))
    out .= Format("{:4} ms   Wait: avg {:+6.2f}  max {:5.2f}   |   Sleep: avg {:+6.2f}`n", ms, w / runs, wMax, s / runs)
}

; التوقيت العشوائي: كم رقم مختلف يطلع من ٤٠ إلى ٥٥
seen := Map()
Loop 500
    seen[Random(40, 55)] := true
out .= Format("Random(40, 55) gave {} different values out of 16`n", seen.Count)
out .= Format("Worst average error of Wait: {:.2f} ms`n", worst)
FileAppend out, "*"
ExitApp (worst > 4 || seen.Count < 16) ? 1 : 0
