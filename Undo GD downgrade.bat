@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gd-downgrade.ps1" -Undo
