#NoEnv
#Persistent
#SingleInstance Force
#Include <Socket>
#Include <cJSON>
#Include <Memory>
SetBatchLines, -1
global serverVersion := "1.0.4"
global servePort := 8000
global processName := "Biohazard.exe"
global address := 0x83523C ; Address to read
global bytes := 1 ; 1,2,4,8 bytes to read
global updateFrequency := 350 ; 350ms
global globalConfig := {}
global emu := {}

Loop, %0%
{
	param := %A_Index%
	switch
	{
		case InStr(param, "-h") || InStr(param, "-help"):
			MsgBox 0x40, Params, Allowed params:`n`n-port=<port>
		case InStr(param, "-port="):
			servePort := StrSplit(param, "=")[2]
	}
}

; Check process exists and attach to it
globalConfig.processName := "ahk_exe " processName
WinGet, processPID, PID, % globalConfig.processName
if (!WinExist(globalConfig.processName)) {
    MsgBox 0x10, Process not found, The target process is not running or was not detected properly.`n`nMake sure target process is not minimized and/or run this as admin.
    ExitApp
}
mem := new Memory("ahk_pid " processPID)

Server := new SocketTCP()
Server.OnAccept := Func("OnAccept")
Server.Bind(["0.0.0.0", servePort])
Server.Listen()
return

OnAccept(Server)
{
	global globalConfig, sock
	sock.Disconnect()
	sock := Server.Accept()
	SetTimer, processData, % updateFrequency
}

processData() {
	global sock, mem, address, bytes
	readValue := mem.rmd(address, bytes)
	try {
		sock.SendText(readValue "`n")
	}
}