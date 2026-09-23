@echo off
rem ---------------------------------------------------------------------------
rem Najjar Pro - one-click demo + test run (Windows)
rem Put lua54.exe in this folder (see TESTING.md) or install Lua on PATH.
rem ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"

set LUA=
if exist "lua54.exe" set LUA=lua54.exe
where lua >nul 2>nul && set LUA=lua
where lua54 >nul 2>nul && set LUA=lua54
where lua5.4 >nul 2>nul && set LUA=lua5.4

if "%LUA%"=="" (
  echo.
  echo [!] Lua was not found on this computer.
  echo.
  echo     Easiest fix: download lua54.exe from
  echo     https://sourceforge.net/projects/luabinaries/files/
  echo     and copy it into this folder, then run this file again.
  echo     Full instructions: TESTING.md
  echo.
  pause
  exit /b 1
)

echo ============================================
echo  Najjar Pro - automatic test suite
echo ============================================
"%LUA%" tests\run_tests.lua
if errorlevel 1 (
  echo.
  echo [!] SOME TESTS FAILED - please send a screenshot of this window.
  pause
  exit /b 1
)

echo.
echo ============================================
echo  Generating demo cabinets (English^)
echo ============================================
"%LUA%" main.lua templates\euro-base-900.json out en
"%LUA%" main.lua templates\wardrobe-zones.json out en
"%LUA%" main.lua templates\kitchen-mixed.json out en

echo.
echo ============================================
echo  Opening previews in your browser...
echo ============================================
if exist "out\euro-base-900_preview.svg" start "" out\euro-base-900_preview.svg
if exist "out\wardrobe-zones_preview.svg" start "" out\wardrobe-zones_preview.svg
if exist "out\kitchen-mixed_preview.svg" start "" out\kitchen-mixed_preview.svg

echo.
echo Done!
echo  - Preview SVG files : open in any browser
echo  - BOM CSV files     : open in Excel
echo  - DXF files         : import into ArtCAM / VCarve (Preserve Layers)
echo.
echo Next step: edit templates\MY-CABINET.json with YOUR cabinet
echo and read TESTING.md for the full checklist.
echo.
pause
