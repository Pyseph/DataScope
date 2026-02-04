@echo off
echo DataScope Plugin Build Script
echo.

echo Installing Wally dependencies...
wally install
if errorlevel 1 (
    echo Failed to install dependencies
    exit /b 1
)

echo.
echo Building plugin...
rojo build plugin.project.json -o DataScope.rbxm
if errorlevel 1 (
    echo Failed to build plugin
    exit /b 1
)

echo.
echo Done! Plugin built as DataScope.rbxm
echo Install by copying to your Roblox plugins folder.
