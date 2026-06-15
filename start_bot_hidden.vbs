Set shell = CreateObject("WScript.Shell")
root = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
cmd = "cmd.exe /c cd /d """ & root & """ && run_scheduled_bot.cmd"
shell.Run cmd, 0, False
