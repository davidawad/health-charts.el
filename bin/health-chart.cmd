@echo off
rem health-chart from cmd.exe or PowerShell on Windows; the commands are
rem those of bin/health-chart (run "health-chart describe").
rem Set EMACS to pick the binary.
setlocal
if not defined EMACS set "EMACS=emacs"
"%EMACS%" -Q --batch -L "%~dp0.." -l health-chart-batch -f health-chart-batch-main %*
exit /b %ERRORLEVEL%
