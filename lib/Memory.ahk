; This is a stripped down version of my already srtripped down Memory library, based on EmuHook 0.6.8
class Memory {
    version := "0.6.8"
    programExe := ""
    programPID := ""
    programPID_ahk := ""
	ram := 0
	wram := 0
	sram := 0
	baseProc := ""
    romType := "pc"
    pHndlR := ""
    pHndlW := ""
    endian := "l"
    convertAddr := 0
	
	__New(exeOrPid, romType := "pc"){
        if(InStr(exeOrPid, "ahk_pid")){
            this.programPID_ahk := exeOrPid
            this.programPID := StrReplace(exeOrPid, "ahk_pid ")
            WinGet, pname, ProcessName, %exeOrPid%
            this.programExe := "ahk_exe " pname
            this.pHndl := DllCall("OpenProcess", "int", 2035711, "char", 0, "UInt", this.programPID, "UInt")
            this.baseProc := this.getProcessBaseAddress()
        }else if(exeOrPid == ""){
            MsgBox, 0x10, Error!, No process found!
            ExitApp
        }else{
            MsgBox, 0x10, Error!, Wrong Executable format!
            ExitApp
        }
        this.ram := this.baseProc
        SetFormat, integer, D
	}
    
    __Delete() {
        this.Destroy()
    }
    
    Destroy() {
        if (this.pHndl)
            DllCall("CloseHandle", "int", this.pHndl)
        this.pHndl := 0
    }
    
    setEndian(endian) {
        this.endian := endian
    }

    ; Read Mem
    rm(MADDRESS, BYT := 1) {
        VarSetCapacity(MVALUE, BYT, 0)
        DllCall("ReadProcessMemory", "UInt", this.pHndl, "Ptr", MADDRESS, "Ptr", &MVALUE, "Uint", BYT)
        result := 0
        if (this.endian = "b") {
            Loop %BYT%
                result := (result << 8) | *(&MVALUE + A_Index - 1)
        } else {
            Loop %BYT%
                result += *(&MVALUE + A_Index - 1) << (8 * (A_Index - 1))
        }
        return result
    }

    ; Write Mem
    wm(WVALUE, MADDRESS, BYT := 1) {
        if (this.endian = "b") {
            VarSetCapacity(BYTES, BYT, 0)
            Loop %BYT%
                NumPut((WVALUE >> (8 * (BYT - A_Index))) & 0xFF, BYTES, A_Index - 1, "UChar")
            DllCall("WriteProcessMemory", "UInt", this.pHndl, "UInt", MADDRESS, "Ptr", &BYTES, "Uint", BYT, "Uint*", 0)
        } else {
            DllCall("WriteProcessMemory", "UInt", this.pHndl, "UInt", MADDRESS, "Uint*", WVALUE, "Uint", BYT, "Uint*", 0)
        }
    }
        
    ; Read Mem Detect -> Detects the address space based on the system
    rmd(targetAddr, BYT := 1, ramBlock := "ram") {
        return this.rm(this.detectAddressSpace(targetAddr, ramBlock), BYT, this.endian)
    }

    ; Write Mem Detect -> Detects the address space based on the system
    wmd(WVALUE, targetAddr, BYT := 1, ramBlock := "ram") {
        this.wm(WVALUE, this.detectAddressSpace(targetAddr, ramBlock), BYT, this.endian)
    }
    
    detectAddressSpace(targetAddr, ramBlock := "ram"){
        targetAddr += this.ram
        return targetAddr
    }
    
    getProcessBaseAddress(windowMatchMode := "3") {
        DetectHiddenWindows, On ; Not needed but probably helps
        if (windowMatchMode && A_TitleMatchMode != windowMatchMode) {
            mode := A_TitleMatchMode
            SetTitleMatchMode, %windowMatchMode%
        }
        WinGet, hWnd, ID, % this.programPID_ahk
        if mode
            SetTitleMatchMode, %mode%
        DetectHiddenWindows, Off
        if !hWnd
            return
        return DllCall(A_PtrSize = 4 ? "GetWindowLong" : "GetWindowLongPtr", "Ptr", hWnd, "Int", -6, A_Is64bitOS ? "Int64" : "UInt")
    }

}

FHex( int, pad=0 ) { ; Function by [VxE]. Formats an integer (decimals are truncated) as hex.
; "Pad" may be the minimum number of digits that should appear on the right of the "0x".
	Static hx := "0123456789ABCDEF"
	If !( 0 < int |= 0 )
		Return !int ? "0x0" : "-" FHex( -int, pad )
        
	s := 1 + Floor( Ln( int ) / Ln( 16 ) )
	h := SubStr( "0x0000000000000000", 1, pad := pad < s ? s + 2 : pad < 16 ? pad + 2 : 18 )
	u := A_IsUnicode = 1

	Loop % s
		NumPut( *( &hx + ( ( int & 15 ) << u ) ), h, pad - A_Index << u, "UChar" ), int >>= 4
	Return h

}

; Get the base address of a module in another process by PID.
GetModuleBaseAddress(pid, modName) {
    static PROCESS_QUERY_INFORMATION := 0x0400
         , PROCESS_VM_READ          := 0x0010
         , LIST_MODULES_ALL         := 0x03

    hProc := DllCall("OpenProcess", "UInt", PROCESS_QUERY_INFORMATION|PROCESS_VM_READ
                                 , "Int",  False
                                 , "UInt", pid, "Ptr")
    if !hProc
        return 0

    cap := 1024 * A_PtrSize
    VarSetCapacity(modBuf, cap, 0)
    needed := 0

    ok := DllCall("Psapi.dll\EnumProcessModulesEx", "Ptr",  hProc
                                                , "Ptr",  &modBuf
                                                , "UInt", cap
                                                , "UIntP", needed
                                                , "UInt", LIST_MODULES_ALL)
    if !ok
        ok := DllCall("Psapi.dll\EnumProcessModules", "Ptr",  hProc
                                                   , "Ptr",  &modBuf
                                                   , "UInt", cap
                                                   , "UIntP", needed)

    if !ok {
        DllCall("CloseHandle", "Ptr", hProc)
        return 0
    }

    count := needed // A_PtrSize
    baseAddr := 0

    Loop % count {
        hMod := NumGet(modBuf, (A_Index-1)*A_PtrSize, "Ptr")
        VarSetCapacity(nameBuf, 520*2, 0)  ; room for 520 WCHARs
        len := DllCall("Psapi.dll\GetModuleBaseNameW", "Ptr", hProc
                                                      , "Ptr", hMod
                                                      , "Ptr", &nameBuf
                                                      , "UInt", 520, "UInt")
        name := StrGet(&nameBuf, len, "UTF-16")
        if (StrLower(name) = StrLower(modName)) {
            baseAddr := hMod
            break
        }
    }
    DllCall("CloseHandle", "Ptr", hProc)
    return baseAddr
}

; Convenience: find PID by process EXE name and then get the module base.
GetModuleBaseByProcessName(procExe, modName) {
    Process, Exist, %procExe%
    pid := ErrorLevel
    return pid ? GetModuleBaseAddress(pid, modName) : 0
}

StrLower(str) {
	StringLower, str, str
	return str
}