@echo off
setlocal
rem ============================================================================
rem  OrcaSAQ2-27B on native exllamav3  -  no Docker, no vLLM, starts in ~1 min
rem  Uses the exllamav3 install in .\exl3lib and the venv in .\venv (see setup.bat).
rem  Edit the values below, save, then double-click this file.
rem ============================================================================

rem  1 = accept images (model-vl: Orca + the Qwen3.8-27B vision encoder, ~0.6 GB
rem  more VRAM, loaded on the first image request). 0 = text only (model).
set VISION=1

rem  Context length in tokens (KV cache size).
set CTX=262144

rem  MTP drafting: 1 = on (head inside the checkpoint), 0 = off
set MTP=1

rem  Draft tokens per step with MTP on. Empty = the drafter's default (4).
rem  Each +1 costs ~144 MiB of VRAM on this model.
set NDT=

rem  1 = adapt draft length to the acceptance rate (NDT becomes a ceiling)
set DYN=0

rem  Prompt chunk size in tokens: how much of a prompt is processed at once.
rem  Working-buffer VRAM scales with it. Empty = exllamav3 default (plans for
rem  4096). 1024 frees VRAM for context/vision; 512 frees more. Smaller only
rem  slows reading LONG prompts - generation speed is unchanged.
set CHUNK=1024

rem  KV cache quantization bits: 4, 6 or 8 (or "8,4" for K,V). Lower = more context.
set CQ=4

rem  Port on this PC:  http://127.0.0.1:%PORT%/v1
set PORT=8000

rem  0.0.0.0 = reachable from your network, 127.0.0.1 = this PC only
set HOST=127.0.0.1

rem  Longest reply in tokens when the app does not set max_tokens itself
rem  (server default is 1024). Thinking counts toward it. Upper limit: CTX
rem  minus the prompt. Apps that send their own max_tokens override this.
set MAX_TOKENS=4096

rem  Model name clients put in their requests
set SERVED_NAME=OrcaSAQ2-27B

rem ============================================================================
rem  Nothing to edit below this line
rem ============================================================================
set ROOT=%~dp0
if "%ROOT:~-1%"=="\" set ROOT=%ROOT:~0,-1%
set PY=%ROOT%\venv\Scripts\python.exe

if not exist "%PY%" (echo venv not found at %PY% - run setup.bat first. & goto :fail)
set MDIR=%ROOT%\model
if "%VISION%"=="1" set MDIR=%ROOT%\model-vl
if not exist "%MDIR%\config.json" (echo Model folder %MDIR% not found. & goto :fail)

set OPTS=-cs %CTX% -cq %CQ%
if "%MTP%"=="1" (set OPTS=%OPTS% -dm mtp) else (set OPTS=%OPTS% -dm none)
if "%MTP%"=="1" if not "%NDT%"=="" set OPTS=%OPTS% -ndt %NDT%
if "%MTP%"=="1" if "%DYN%"=="1" set OPTS=%OPTS% -dds
if not "%CHUNK%"=="" set OPTS=%OPTS% -chunk %CHUNK%

rem  Stops PyTorch's CPU thread pool spin-waiting between small ops.
set KMP_BLOCKTIME=0

echo.
echo GPU memory in use before start:
nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
echo Starting  ctx=%CTX%  mtp=%MTP%  vision=%VISION%  kv=%CQ%-bit  port=%PORT%
echo Server log follows. Close this window or run stop_exl3.bat to stop.
echo.
"%PY%" "%ROOT%\exl3_serve.py" -m "%MDIR%" %OPTS% --port %PORT% --host %HOST% --model-label %SERVED_NAME%
echo.
echo Server exited.
:fail
pause
exit /b 1
