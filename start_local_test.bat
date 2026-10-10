@echo off
title Atila's Client - Teste local (2 contas)
color 0E

echo.
echo  =========================================
echo   Atila's Client - TESTE LOCAL, 2 contas
echo  =========================================
echo.
echo  Isso roda o backend e o portal 100%% local (sem VPS, sem proxy -
echo  a saida de rede eh a sua conexao residencial direta, igual o teste
echo  pede). Usa um banco de dados local separado (backend\super_moderator.db),
echo  nunca toca no banco de producao da VPS.
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

:: --- Log persistente --------------------------------------------------------
if not exist "%~dp0logs" mkdir "%~dp0logs"
for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm-ss"') do set TS=%%T
set LOGFILE=%~dp0logs\teste_2_contas_%TS%.log
echo  Log desta sessao: %LOGFILE%
echo.

echo [1/3] Instalando dependencias do backend...
python -m pip install -r backend\requirements.txt -q

echo [2/3] Iniciando a API (FastAPI + SQLite local) em http://localhost:8000 ...
echo       Tudo que o backend logar (conexoes, acoes, erros da API do
echo       SuperLive) vai tanto na janela quanto no arquivo de log acima.
start "Atila's Client - Backend (teste local)" cmd /k "cd /d %~dp0backend && set SM_RELOAD=1 && set SM_LOG_FILE=%LOGFILE% && python main.py"

echo [3/3] Iniciando o portal (Flutter Web) em http://localhost:3000 ...
echo       A primeira compilacao leva de 30 a 90 segundos.
start "Atila's Client - Portal (teste local)" cmd /k "cd /d %~dp0 && flutter run -d web-server --release --web-port 3000 --web-hostname localhost"

start "" /min powershell -NoProfile -Command "$u='http://localhost:3000'; $end=(Get-Date).AddMinutes(4); while((Get-Date) -lt $end){ try { Invoke-WebRequest $u -UseBasicParsing -TimeoutSec 8 | Out-Null; Start-Process $u; exit 0 } catch { Start-Sleep -Seconds 2 } }; exit 1"

echo.
echo  =========================================
echo   Portal:  http://localhost:3000   (abre sozinho quando ficar pronto)
echo   API:     http://localhost:8000/docs
echo   Log:     %LOGFILE%
echo  =========================================
echo.
echo  PARA TESTAR COM 2 CONTAS AO MESMO TEMPO:
echo   1. Na aba que abrir, entre/crie a conta portal da geffinho e,
echo      em Robo, conecte a conta SuperLive dela normalmente.
echo   2. Abra uma segunda janela em modo anonimo/privado do navegador
echo      (importante: aba normal compartilha o login salvo) apontando
echo      pra http://localhost:3000, entre/crie a conta portal da nyx e
echo      conecte a OUTRA conta SuperLive la.
echo   3. Deixe as duas rodando normalmente (sem forcar nada, sem rajada)
echo      e observe. Qualquer erro, aviso ou coisa estranha da API do
echo      SuperLive fica registrado no arquivo de log acima, com hora.
echo.
echo  Para encerrar, feche as janelas "Backend" e "Portal".
echo.
pause >nul
