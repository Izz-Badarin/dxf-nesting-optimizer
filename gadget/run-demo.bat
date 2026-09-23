@echo off
rem ---------------------------------------------------------------------------
rem Najjar Pro - one-click demo + test run (Windows)
rem Works with Lua 5.3, 5.4 or 5.5 - put lua54.exe / lua55.exe in this
rem folder (see TESTING.md) or install Lua on PATH.
rem ---------------------------------------------------------------------------
setlocal
cd /d "%~dp0"

set LUA=
if not defined LUA if exist "lua55.exe" set LUA=lua55.exe
if not defined LUA if exist "lua54.exe" set LUA=lua54.exe
if not defined LUA if exist "lua53.exe" set LUA=lua53.exe
if not defined LUA where lua55  >nul 2>nul && set LUA=lua55
if not defined LUA where lua54  >nul 2>nul && set LUA=lua54
if not defined LUA where lua5.5 >nul 2>nul && set LUA=lua5.5
if not defined LUA where lua5.4 >nul 2>nul && set LUA=lua5.4
if not defined LUA where lua5.3 >nul 2>nul && set LUA=lua5.3
if not defined LUA where lua    >nul 2>nul && set LUA=lua

if "%LUA%"=="" (
  echo.
  echo [!] Lua was not found on this computer.
  echo.
  echo     Easiest fix: download lua55.exe or lua54.exe from
  echo     https://sourceforge.net/projects/luabinaries/files/
  echo     and copy it (and its .dll file^) into this folder,
  echo     then run this file again.
  echo     Full instructions: TESTING.md
  echo.
  pause
  exit /b 1
)

echo Using Lua: %LUA%

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
echo  Import demo: foreign config + cut list
echo ============================================
"%LUA%" convert.lua templates\foreign-demo.json out\imported.json --map importers\generic_flat.json
"%LUA%" main.lua out\imported.json out en

echo.
echo ============================================
echo  Opening previews in your browser...
echo ============================================
if exist "out\kitchen-mixed_viewer.html" start "" out\kitchen-mixed_viewer.html
if exist "out\kitchen-mixed_nesting_1.svg" start "" out\kitchen-mixed_nesting_1.svg
if exist "out\euro-base-900_preview.svg" start "" out\euro-base-900_preview.svg
if exist "out\wardrobe-zones_preview.svg" start "" out\wardrobe-zones_preview.svg
if exist "out\kitchen-mixed_preview.svg" start "" out\kitchen-mixed_preview.svg

echo.
echo Done!
echo  - 3D viewer HTML    : rotate, zoom, EXPLODE slider, dimension check
echo  - Nesting SVGs     : every board laid out, ready to cut
echo  - Preview SVG files : open in any browser
echo  - BOM CSV files     : open in Excel
echo  - DXF files         : import into ArtCAM / VCarve (Preserve Layers)
echo.
echo Next step: edit templates\MY-CABINET.json with YOUR cabinet
echo and read TESTING.md for the full checklist.
echo.
pause
