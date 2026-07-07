@echo off
REM Locate MSBuild.exe via vswhere (present on VS2022 hosts) and build the project.
REM Works for both the clean and the poisoned PaymentService.csproj.
setlocal
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo vswhere not found - is Visual Studio installed?
  exit /b 1
)
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe`) do set "MSBUILD=%%i"
if not defined MSBUILD (
  echo MSBuild.exe not found via vswhere
  exit /b 1
)
echo Using MSBuild: %MSBUILD%
"%MSBUILD%" "%~dp0PaymentService.csproj" /p:Configuration=Release /nologo
exit /b %ERRORLEVEL%
