@echo off
TITLE VoiceInk Launcher

echo.
echo =================================================================
echo  VoiceInk for Windows - Build & Run Script
echo =================================================================
echo.
echo This script will build and run the main application.
echo Please ensure you have the .NET 8 Desktop SDK installed.
echo.

REM Navigate to the main UI project directory
cd VoiceInk.Windows.UI

echo Locating project...
IF NOT EXIST VoiceInk.Windows.UI.csproj (
    echo ERROR: Could not find the project file 'VoiceInk.Windows.UI.csproj' in the current directory.
    cd ..
    pause
    exit /b 1
)

echo.
echo Restoring dependencies and building the project...
echo This may take a moment on the first run.
echo.

REM Use the dotnet CLI to run the project.
REM This command automatically handles restoring dependencies, building, and launching.
dotnet run

echo.
echo =================================================================
echo  Application has been closed.
echo =================================================================
echo.

REM Navigate back to the root directory
cd ..

pause
