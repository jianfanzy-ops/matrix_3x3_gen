@echo off
rem Starts Questa in this folder and runs tb_run.do.
rem vsim comes from QUESTA_BIN in local_paths.do (copy of local_paths_example.do), else from PATH.
cd /d "%~dp0"
set "QUESTA_BIN="
if exist local_paths.do for /f "tokens=2,*" %%a in ('findstr /b /c:"set QUESTA_BIN " local_paths.do') do set "QUESTA_BIN=%%b"
if defined QUESTA_BIN set "QUESTA_BIN=%QUESTA_BIN:/=\%"
if defined QUESTA_BIN (set "VSIM=%QUESTA_BIN%\vsim") else (set "VSIM=vsim")
"%VSIM%" -do tb_run.do
