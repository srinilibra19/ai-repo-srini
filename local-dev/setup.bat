@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM setup.bat — Hermes local development stack — one-command setup (Windows)
REM
REM Automates: prerequisite checks, .env creation, mTLS cert generation,
REM Docker Compose up, health polling, and full infrastructure verification.
REM
REM Usage:
REM   local-dev\setup.bat                   full setup
REM   local-dev\setup.bat --skip-certs      skip cert generation (use existing)
REM   local-dev\setup.bat --skip-verify     skip post-startup verification
REM
REM Exit codes:
REM   0 — stack started and all verification checks passed
REM   1 — setup failed (error printed above)
REM =============================================================================

set SCRIPT_DIR=%~dp0
set SKIP_CERTS=0
set SKIP_VERIFY=0
set PREREQ_FAIL=0

REM ---------------------------------------------------------------------------
REM Argument parsing
REM ---------------------------------------------------------------------------
:parse_args
if "%~1"=="--skip-certs"  set SKIP_CERTS=1  & shift & goto parse_args
if "%~1"=="--skip-verify" set SKIP_VERIFY=1 & shift & goto parse_args
if not "%~1"=="" (
    echo Unknown option: %~1
    echo Usage: setup.bat [--skip-certs] [--skip-verify]
    exit /b 1
)

cd /d "%SCRIPT_DIR%"

echo.

REM ===========================================================================
REM 1 — Prerequisite checks
REM ===========================================================================
echo == 1. Prerequisite checks ===================================================

where docker >nul 2>&1
if !errorlevel! neq 0 (
    echo   [FAIL] Docker not found -- install Docker Desktop
    echo          https://www.docker.com/products/docker-desktop
    set PREREQ_FAIL=1
) else (
    docker info >nul 2>&1
    if !errorlevel! neq 0 (
        echo   [FAIL] Docker daemon not running -- start Docker Desktop and retry
        set PREREQ_FAIL=1
    ) else (
        for /f "delims=" %%v in ('docker version --format "{{.Server.Version}}" 2^>nul') do set DOCKER_VER=%%v
        if not defined DOCKER_VER set DOCKER_VER=unknown
        echo   [PASS] Docker !DOCKER_VER! -- running
    )
)

docker compose version >nul 2>&1
if !errorlevel! neq 0 (
    echo   [FAIL] Docker Compose v2 not found -- update Docker Desktop to 4.x+
    set PREREQ_FAIL=1
) else (
    for /f "delims=" %%v in ('docker compose version --short 2^>nul') do set COMPOSE_VER=%%v
    if not defined COMPOSE_VER set COMPOSE_VER=unknown
    echo   [PASS] Docker Compose !COMPOSE_VER!
)

where aws >nul 2>&1
if !errorlevel! neq 0 (
    echo   [WARN] AWS CLI not found -- LocalStack verification will be skipped
    echo          Install: winget install Amazon.AWSCLI
) else (
    for /f "tokens=1" %%v in ('aws --version 2^>^&1') do echo   [PASS] AWS CLI -- %%v
)

REM Check Git Bash is available (needed for generate-certs.sh)
if !SKIP_CERTS! equ 0 (
    where bash >nul 2>&1
    if !errorlevel! neq 0 (
        echo   [WARN] bash not found -- certificate generation will be skipped
        echo          Install Git for Windows (includes Git Bash): https://git-scm.com/download/win
        echo          Or run: winget install Git.Git
        set SKIP_CERTS=1
    ) else (
        for /f "delims=" %%v in ('bash --version 2^>nul ^| findstr /C:"version"') do (
            echo   [PASS] %%v
            goto bash_found
        )
        :bash_found
    )
)

if !PREREQ_FAIL! equ 1 (
    echo.
    echo   [FAIL] Prerequisite checks failed. Fix errors above and re-run.
    echo.
    exit /b 1
)

REM ===========================================================================
REM 2 — Environment file
REM ===========================================================================
echo.
echo == 2. Environment file ======================================================

if exist "%SCRIPT_DIR%.env" (
    echo   [INFO] .env already exists -- using existing file
) else (
    if not exist "%SCRIPT_DIR%.env.example" (
        echo   [FAIL] .env.example not found at %SCRIPT_DIR%.env.example
        exit /b 1
    )
    copy "%SCRIPT_DIR%.env.example" "%SCRIPT_DIR%.env" >nul
    echo   [INFO] Created .env from .env.example
    echo   [WARN] Review %SCRIPT_DIR%.env and adjust any values if needed
)

REM ===========================================================================
REM 3 — mTLS certificates
REM ===========================================================================
echo.
echo == 3. mTLS certificates =====================================================

if !SKIP_CERTS! equ 1 (
    echo   [SKIP] --skip-certs set -- skipping certificate generation
) else (
    if exist "%SCRIPT_DIR%certs\server-combined.pem" (
        echo   [INFO] Certificates already exist -- skipping generation
        echo   [INFO] To regenerate: del local-dev\certs\*.pem ^&^& local-dev\setup.bat
    ) else (
        if not exist "%SCRIPT_DIR%certs\generate-certs.sh" (
            echo   [FAIL] generate-certs.sh not found at %SCRIPT_DIR%certs\generate-certs.sh
            exit /b 1
        )
        echo   [INFO] Generating mTLS certificates via Git Bash...
        bash "%SCRIPT_DIR%certs\generate-certs.sh"
        if !errorlevel! neq 0 (
            echo   [FAIL] Certificate generation failed
            exit /b 1
        )
        echo   [INFO] Certificates generated
    )
)

REM ===========================================================================
REM 4 — Docker Compose up
REM ===========================================================================
echo.
echo == 4. Starting Docker Compose stack =========================================

echo   [INFO] Running: docker compose up -d
docker compose up -d
if !errorlevel! neq 0 (
    echo   [FAIL] docker compose up failed
    exit /b 1
)

REM ===========================================================================
REM 5 — Wait for services to become healthy
REM ===========================================================================
echo.
echo == 5. Waiting for services to become healthy ================================

set POLL_TIMEOUT=120
set POLL_INTERVAL=10
set ELAPSED=0

echo   [INFO] Polling every %POLL_INTERVAL%s (timeout: %POLL_TIMEOUT%s)

:health_loop
set ALL_HEALTHY=1
set _H_SOLACE=
set _H_POSTGRES=
set _H_LOCALSTACK=

for /f "delims=" %%h in ('docker inspect --format "{{.State.Health.Status}}" hermes-solace 2^>nul') do set _H_SOLACE=%%h
for /f "delims=" %%h in ('docker inspect --format "{{.State.Health.Status}}" hermes-postgres 2^>nul') do set _H_POSTGRES=%%h
for /f "delims=" %%h in ('docker inspect --format "{{.State.Health.Status}}" hermes-localstack 2^>nul') do set _H_LOCALSTACK=%%h

if not defined _H_SOLACE     set _H_SOLACE=missing
if not defined _H_POSTGRES   set _H_POSTGRES=missing
if not defined _H_LOCALSTACK set _H_LOCALSTACK=missing

if not "!_H_SOLACE!"=="healthy"     set ALL_HEALTHY=0
if not "!_H_POSTGRES!"=="healthy"   set ALL_HEALTHY=0
if not "!_H_LOCALSTACK!"=="healthy" set ALL_HEALTHY=0

echo   [%ELAPSED%s] solace=!_H_SOLACE! postgres=!_H_POSTGRES! localstack=!_H_LOCALSTACK!

if !ALL_HEALTHY! equ 1 (
    echo   [INFO] All services healthy after !ELAPSED!s
    goto health_done
)

if !ELAPSED! geq !POLL_TIMEOUT! (
    echo   [FAIL] Timed out after !POLL_TIMEOUT!s waiting for healthy status
    echo          Run: docker compose logs
    exit /b 1
)

timeout /t %POLL_INTERVAL% /nobreak >nul
set /a ELAPSED+=%POLL_INTERVAL%
goto health_loop

:health_done
echo   [INFO] Waiting 10s for hermes-solace-init to complete provisioning...
timeout /t 10 /nobreak >nul

REM ===========================================================================
REM 6 — Infrastructure verification
REM ===========================================================================
echo.
echo == 6. Infrastructure verification ===========================================

if !SKIP_VERIFY! equ 1 (
    echo   [SKIP] --skip-verify set
    echo   [INFO] Run local-dev\verify.bat manually when ready
) else (
    if not exist "%SCRIPT_DIR%verify.bat" (
        echo   [FAIL] verify.bat not found at %SCRIPT_DIR%verify.bat
        exit /b 1
    )
    call "%SCRIPT_DIR%verify.bat"
    if !errorlevel! neq 0 (
        echo.
        echo   [FAIL] Verification found failures -- review output above
        exit /b 1
    )
)

REM ===========================================================================
REM Done
REM ===========================================================================
echo.
echo ==============================================================================
echo  Local stack is up and verified. You are ready to develop!
echo ==============================================================================
echo.
echo   Solace Admin UI : http://localhost:8080  (admin / admin)
echo   PostgreSQL      : localhost:5432  db=hermes  user=hermes
echo   LocalStack      : http://localhost:4566
echo.
echo   Next step: run the application
echo     mvnw spring-boot:run -Dspring-boot.run.profiles=local
echo.
exit /b 0
