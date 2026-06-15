from pathlib import Path
import os


root = Path(__file__).resolve().parent
startup = (
    Path(os.environ["APPDATA"])
    / "Microsoft"
    / "Windows"
    / "Start Menu"
    / "Programs"
    / "Startup"
)
target = startup / "TelegramTranslatorBot.vbs"

escaped_root = str(root).replace('"', '""')
script = f'''Set shell = CreateObject("WScript.Shell")
root = "{escaped_root}"
cmd = "cmd.exe /c cd /d ""{escaped_root}"" && run_scheduled_bot.cmd"
shell.Run cmd, 0, False
'''

startup.mkdir(parents=True, exist_ok=True)
target.write_text(script, encoding="utf-16")
print(f"Installed autostart: {target}")
