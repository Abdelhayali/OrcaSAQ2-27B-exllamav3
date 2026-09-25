@echo off
setlocal
rem ============================================================================
rem  OrcaSAQ2-27B  -  build the VISION model (model-vl)
rem
rem  model-vl = the OrcaSAQ2 text model (orcarouter/OrcaSAQ-2-27B) + the
rem  EXL3-quantized Qwen3.8-27B vision tower. The tower is not a single HF
rem  repo - it was quantized locally and is shipped in this repo under .\vision
rem  (vision.safetensors, ~0.57 GB, via git-lfs). This script:
rem     1. downloads the text model into .\model-vl  (12.3 GB, resumes)
rem     2. overlays the 3 VL files from .\vision  (config.json, the safetensors
rem        index, and vision.safetensors)
rem  Needs: the venv from setup.bat (venv\Scripts\python.exe) and git-lfs.
rem ============================================================================
set ROOT=%~dp0
if "%ROOT:~-1%"=="\" set ROOT=%ROOT:~0,-1%
set PY=%ROOT%\venv\Scripts\python.exe
set VL=%ROOT%\model-vl

if not exist "%PY%" (echo venv not found - run setup.bat first. & goto :fail)
if not exist "%ROOT%\vision\vision.safetensors" (
  echo vision\vision.safetensors not found.
  echo If you cloned without LFS, run:  git lfs pull
  goto :fail
)

echo.
echo [1/2] Text model into %VL%
if not exist "%VL%\model-00001-of-00004.safetensors" (
  if not exist "%VL%" mkdir "%VL%"
  "%PY%" -c "from huggingface_hub import snapshot_download; snapshot_download('orcarouter/OrcaSAQ-2-27B', local_dir=r'%VL%')" || goto :fail
) else (echo   already present)

echo.
echo [2/2] Overlay the vision tower + VL config/index
copy /y "%ROOT%\vision\config.json" "%VL%\config.json" >nul || goto :fail
copy /y "%ROOT%\vision\model.safetensors.index.json" "%VL%\model.safetensors.index.json" >nul || goto :fail
copy /y "%ROOT%\vision\vision.safetensors" "%VL%\vision.safetensors" >nul || goto :fail
echo   done.

echo.
echo Vision model ready at %VL%. Set VISION=1 in start_exl3.bat and run it.
pause
exit /b 0

:fail
echo.
echo Vision setup failed - see the messages above.
pause
exit /b 1
