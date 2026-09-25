@echo off
setlocal
rem ============================================================================
rem  OrcaSAQ2-27B  -  one-time setup (safe to re-run; finished steps are skipped)
rem    1. create a Python 3.13 venv with torch 2.10.0+cu128 + exllamav3 1.5.1
rem    2. unpack the exllamav3 wheel into .\exl3lib
rem    3. download the text model into .\model  (12.3 GB, resumes if interrupted)
rem  Needs: git, and either uv or pip on PATH. No Docker required.
rem ============================================================================
set ROOT=%~dp0
if "%ROOT:~-1%"=="\" set ROOT=%ROOT:~0,-1%
set VENV=%ROOT%\venv
set PY=%VENV%\Scripts\python.exe
set WHEEL=%ROOT%\wheels\exllamav3-1.5.1+cu128.torch2.10.0-cp313-cp313-win_amd64.whl
set WHEEL_URL=https://github.com/turboderp-org/exllamav3/releases/download/v1.5.1/exllamav3-1.5.1%%2Bcu128.torch2.10.0-cp313-cp313-win_amd64.whl

where git >nul 2>&1 || (echo git is not installed. & goto :fail)
where uv >nul 2>&1 || (echo uv not found - installing it via pip... & pip install uv || goto :fail)

echo.
echo [1/4] Python 3.13 venv
if not exist "%PY%" (
  uv venv --python 3.13 "%VENV" || goto :fail
  uv pip install --python "%PY%" --index-url https://download.pytorch.org/whl/cu128 "torch==2.10.0" || goto :fail
  uv pip install --python "%PY%" transformers==5.17.0 aiohttp pillow safetensors rich blessed prompt_toolkit pydantic requests huggingface_hub || goto :fail
) else (echo   already present)

echo.
echo [2/4] exllamav3 1.5.1 wheel
if not exist "%WHEEL%" (
  if not exist "%ROOT%\wheels" mkdir "%ROOT%\wheels"
  curl -L -o "%WHEEL%" "%WHEEL_URL%" || goto :fail
) else (echo   already present)
if not exist "%ROOT%\exl3lib\exllamav3\__init__.py" (
  "%PY%" -m zipfile -e "%WHEEL%" "%ROOT%\exl3lib" || goto :fail
) else (echo   already unpacked)

echo.
echo [3/4] Text model orcarouter/OrcaSAQ-2-27B
if not exist "%ROOT%\model\config.json" (
  if not exist "%ROOT%\model" mkdir "%ROOT%\model"
  "%PY%" -c "from huggingface_hub import snapshot_download; snapshot_download('orcarouter/OrcaSAQ-2-27B', local_dir=r'%ROOT%\model')" || goto :fail
) else (echo   already present)

echo.
echo [4/4] Vision model (optional)
rem  model-vl = the text model plus the EXL3-quantized Qwen3.8-27B vision tower
rem  (vision.safetensors, ~0.57 GB). It is a local build, not a single HF repo, so
rem  it is not downloaded here. If you do not have it, set VISION=0 in start_exl3.bat
rem  and run text-only from .\model.
if not exist "%ROOT%\model-vl\config.json" (
  echo   model-vl not found - text-only mode (VISION=0) will be used.
) else (echo   already present)

echo.
echo Setup complete. Edit the settings at the top of start_exl3.bat, then run it.
pause
exit /b 0

:fail
echo.
echo Setup failed - see the messages above.
pause
exit /b 1
