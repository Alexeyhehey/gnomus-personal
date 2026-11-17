@echo off
rem Gnomus: connect one free API key with hidden input.  add_key.cmd GROQ_API_KEY | OPENROUTER_API_KEY | GEMINI_API_KEY
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0add_key.ps1" -Name %1
