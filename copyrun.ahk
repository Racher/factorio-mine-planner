#SingleInstance force

$F5::
If WinActive("ahk_exe Code.exe") and WinExist("ahk_exe Factorio.exe")
{
    Send, ^a
    Send, ^c
    Send, {LButton}
    WinActivate ahk_exe Factorio.exe
    Sleep, 100
    Send, {Insert}
    Send, /clear
    Send, {Enter}
    Send, {Insert}
    Send, /c
    Send, {Space}
    Send, ^v
    Send, {Enter}
    Return
}
Send, {F5}
Return
If WinActive("ahk_exe Factorio.exe")
{
    Send, {Insert}
    Send, /c
    Send, {Space}
    Send, ^v
    Send, {Enter}
    Return
}