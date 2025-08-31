# Arduino TCP Memory Exchange

![Preview](https://github.com/elModo7/ArduinoUnoR4Wifi_TCP_Memory_Viewer/blob/main/img/preview.jpg?raw=true)

Basic example of an Arduino Uno R4 WiFi receiving a number via TCP and displaying it on the built-in led matrix. The backend reads one address from a process's memory and sends it via the opened TCP socket to the arduino client. 


> [!CAUTION]
> In the case that you use this for a game, **use it for offline games**, *I am not responsible for any misuse of this tool.* It is also very likely that it may be flagged by anticheats if you target a game process.

## Credits

 - [Socket.ahk](https://github.com/G33kDude/Socket.ahk) TCP socket library for AutoHotkey.

 - [cJSON.ahk](https://github.com/G33kDude/cJson.ahk/tree/main) Fast JSON library for AutoHotkey.

This is a stripped down version of one of my [EmuHook](https://github.com/elModo7/EmuHook) demos.
