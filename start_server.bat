@echo off
title Super Moderator - Launcher
color 0A

echo.
echo  =========================================
echo   Super Moderator - iniciando...
echo  =========================================
echo.

:: --- Python ---------------------------------------------------------------
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRO] Python nao encontrado. Instale Python 3.10+ em https://python.org
    pause
    exit /b 1
)

:: --- Flutter --------------------------------------------------------------
call flutter --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRO] Flutter nao encontrado no PATH. Instale em https://docs.flutter.dev/get-started/install
    pause
    exit /b 1
)

echo [1/3] Instalando dependencias do backend...
python -m pip install -r backend\requirements.txt -q

echo [2/3] Iniciando a API (FastAPI + SQLite) em http://localhost:8000 ...
start "Super Moderator - Backend" cmd /k "cd /d %~dp0backend && python main.py"

echo [3/3] Iniciando o portal (Flutter Web) em http://localhost:3000 ...
echo       A primeira compilacao leva de 30 a 90 segundos.
start "Super Moderator - Portal" cmd /k "cd /d %~dp0 && flutter run -d web-server --release --web-port 3000 --web-hostname localhost"

:: Abre o navegador padrao assim que o portal responder (espera ate ~3 min).
:: (o timeout precisa ser maior que 2s: "localhost" pode levar ~2s tentando IPv6 primeiro)
start "" /min powershell -NoProfile -Command "$u='http://localhost:3000'; $end=(Get-Date).AddMinutes(4); while((Get-Date) -lt $end){ try { Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 8 | Out-Null; Start-Process $u; exit 0 } catch { Start-Sleep -Seconds 2 } }; exit 1"

echo.
echo  =========================================
echo   Portal:  http://localhost:3000   (abre sozinho quando ficar pronto)
echo   API:     http://localhost:8000/docs
echo  =========================================
echo.
echo  Para encerrar, feche as janelas "Backend" e "Portal".
echo  (Fechar a janela do Backend tambem para o robo.)
echo.
pause >nul
