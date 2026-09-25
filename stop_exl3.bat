@echo off
rem Stop the native exllamav3 OrcaSAQ2 server and free VRAM.
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { $_.CommandLine -like '*exl3_serve.py*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Output ('Stopped PID ' + $_.ProcessId) }"
echo.
echo GPU memory now:
nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
pause
