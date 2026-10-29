@echo off
rem Collects Settlements Advisor diagnostics into a zip on the Desktop (see docs/diagnostics.md).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0collect_diagnostics.ps1" %*
pause
