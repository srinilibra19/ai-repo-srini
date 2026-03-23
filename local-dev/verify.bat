@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM verify.bat — Hermes local infrastructure verification (Windows)
REM
REM Checks that all Docker Compose services are healthy and all provisioned
REM resources (Solace queues, LocalStack SNS/SQS/S3, PostgreSQL) are present.
REM
REM Usage (standalone):
REM   local-dev\verify.bat
REM   (or from repo root): local-dev\verify.bat
REM
REM Usage (with SDKPerf publish test):
REM   set SDKPERF_HOME=C:\tools\sdkperf && local-dev\verify.bat
REM
REM Exit codes:
REM   0 — all checks passed
REM   1 — one or more checks failed
REM =============================================================================

set SCRIPT_DIR=%~dp0
set PASS_COUNT=0
set FAIL_COUNT=0

REM ---------------------------------------------------------------------------
REM LocalStack AWS CLI environment (dummy credentials — LocalStack does not validate)
REM ---------------------------------------------------------------------------
if not defined AWS_ACCESS_KEY_ID     set AWS_ACCESS_KEY_ID=test
if not defined AWS_SECRET_ACCESS_KEY set AWS_SECRET_ACCESS_KEY=test
if not defined AWS_DEFAULT_REGION    set AWS_DEFAULT_REGION=us-east-1
set LS_ENDPOINT=http://localhost:4566

cd /d "%SCRIPT_DIR%"

echo.

REM ===========================================================================
REM 1 — Container health
REM ===========================================================================
echo == 1. Container health ======================================================

call :check_healthy hermes-solace
call :check_healthy hermes-postgres
call :check_healthy hermes-localstack
call :check_init_exited hermes-solace-init

REM ===========================================================================
REM 2 — Solace queue provisioning
REM ===========================================================================
echo.
echo == 2. Solace queue provisioning =============================================

docker logs hermes-solace-init > "%TEMP%\hermes_init_logs.tmp" 2>&1

findstr /C:"Provisioning complete" "%TEMP%\hermes_init_logs.tmp" >nul 2>&1
if !errorlevel! equ 0 (
    call :pass "provision-queues.sh completed successfully"
) else (
    call :fail_check "provision-queues.sh did not complete (check: docker logs hermes-solace-init)"
)

REM DMQ check — unique .dmq suffix avoids overlap with main queue
findstr /C:"hermes.flightschedules.dmq" "%TEMP%\hermes_init_logs.tmp" >nul 2>&1
if !errorlevel! equ 0 (
    call :pass "hermes.flightschedules.dmq"
) else (
    call :fail_check "hermes.flightschedules.dmq  not found in provisioning log"
)

REM Main queue check — "Queue hermes.flightschedules" avoids matching the DMQ line
findstr /C:"Queue hermes.flightschedules" "%TEMP%\hermes_init_logs.tmp" >nul 2>&1
if !errorlevel! equ 0 (
    call :pass "hermes.flightschedules"
) else (
    call :fail_check "hermes.flightschedules  not found in provisioning log"
)

REM Topic subscription check
findstr /C:"flightschedules/>" "%TEMP%\hermes_init_logs.tmp" >nul 2>&1
if !errorlevel! equ 0 (
    call :pass "flightschedules/>  subscription"
) else (
    call :fail_check "flightschedules/>  subscription not found in provisioning log"
)

REM ===========================================================================
REM 3 — LocalStack AWS resources
REM ===========================================================================
echo.
echo == 3. LocalStack AWS resources ==============================================

where aws >nul 2>&1
if !errorlevel! neq 0 (
    call :skip "AWS CLI not installed -- skipping LocalStack checks"
    call :skip "  Install: winget install Amazon.AWSCLI"
) else (
    aws --endpoint-url=%LS_ENDPOINT% sns list-topics --output text > "%TEMP%\hermes_sns.tmp" 2>&1
    findstr /C:"hermes-flightschedules.fifo" "%TEMP%\hermes_sns.tmp" >nul 2>&1
    if !errorlevel! equ 0 (
        call :pass "SNS FIFO topic : hermes-flightschedules.fifo"
    ) else (
        call :fail_check "SNS FIFO topic : hermes-flightschedules.fifo  not found"
    )

    aws --endpoint-url=%LS_ENDPOINT% sqs list-queues --output text > "%TEMP%\hermes_sqs.tmp" 2>&1
    findstr /C:"hermes-flightschedules-consumer-a.fifo" "%TEMP%\hermes_sqs.tmp" >nul 2>&1
    if !errorlevel! equ 0 (
        call :pass "SQS FIFO queue : hermes-flightschedules-consumer-a.fifo"
    ) else (
        call :fail_check "SQS FIFO queue : hermes-flightschedules-consumer-a.fifo  not found"
    )

    findstr /C:"hermes-flightschedules-dlq.fifo" "%TEMP%\hermes_sqs.tmp" >nul 2>&1
    if !errorlevel! equ 0 (
        call :pass "SQS DLQ        : hermes-flightschedules-dlq.fifo"
    ) else (
        call :fail_check "SQS DLQ        : hermes-flightschedules-dlq.fifo  not found"
    )

    aws --endpoint-url=%LS_ENDPOINT% s3 ls > "%TEMP%\hermes_s3.tmp" 2>&1
    findstr /C:"hermes-claim-check-local" "%TEMP%\hermes_s3.tmp" >nul 2>&1
    if !errorlevel! equ 0 (
        call :pass "S3 bucket      : hermes-claim-check-local"
    ) else (
        call :fail_check "S3 bucket      : hermes-claim-check-local  not found"
    )
)

REM ===========================================================================
REM 4 — PostgreSQL
REM ===========================================================================
echo.
echo == 4. PostgreSQL ============================================================

docker compose exec -T postgres pg_isready -U hermes -d hermes >nul 2>&1
if !errorlevel! equ 0 (
    call :pass "PostgreSQL accepting connections  localhost:5432  db=hermes"
) else (
    call :fail_check "PostgreSQL not ready  (container: hermes-postgres)"
)

REM ===========================================================================
REM 5 — SDKPerf test publish (optional)
REM ===========================================================================
echo.
echo == 5. SDKPerf test publish (optional) ======================================

if not defined SDKPERF_HOME (
    call :skip "SDKPERF_HOME not set -- skipping publish test"
    call :skip "  To enable: set SDKPERF_HOME=C:\tools\sdkperf"
) else (
    if not exist "%SDKPERF_HOME%\sdkperf_java.bat" (
        call :skip "sdkperf_java.bat not found in SDKPERF_HOME=%SDKPERF_HOME%"
    ) else (
        "%SDKPERF_HOME%\sdkperf_java.bat" ^
            -cip=tcp://localhost:55555 -cu=admin@default -cp=admin ^
            -pql=flightschedules/events -mn=3 -mr=1 -msa=512 -q >nul 2>&1
        if !errorlevel! equ 0 (
            call :pass "SDKPerf published 3 test messages to flightschedules/events"
        ) else (
            call :fail_check "SDKPerf publish failed (is Solace healthy? is port 55555 reachable?)"
        )
    )
)

REM ===========================================================================
REM Summary
REM ===========================================================================
echo.
echo ==============================================================================
echo  Verification Summary
echo ==============================================================================
echo   PASS : !PASS_COUNT!
echo   FAIL : !FAIL_COUNT!
echo ==============================================================================

if !FAIL_COUNT! equ 0 (
    echo.
    echo   All checks passed -- local stack is ready.
    echo.
    exit /b 0
) else (
    echo.
    echo   !FAIL_COUNT! check^(s^) failed -- review output above.
    echo.
    exit /b 1
)

REM ===========================================================================
REM Subroutines
REM ===========================================================================

:pass
set /a PASS_COUNT+=1
echo   [PASS] %~1
goto :eof

:fail_check
set /a FAIL_COUNT+=1
echo   [FAIL] %~1
goto :eof

:skip
echo   [SKIP] %~1
goto :eof

:check_healthy
for /f "delims=" %%h in ('docker inspect --format "{{.State.Health.Status}}" %1 2^>nul') do set _HEALTH=%%h
if not defined _HEALTH set _HEALTH=missing
if "!_HEALTH!"=="healthy" (
    call :pass "%1 -- healthy"
) else (
    call :fail_check "%1 -- !_HEALTH! (expected: healthy)"
)
set _HEALTH=
goto :eof

:check_init_exited
for /f "delims=" %%s in ('docker inspect --format "{{.State.Status}}" %1 2^>nul') do set _STATE=%%s
for /f "delims=" %%e in ('docker inspect --format "{{.State.ExitCode}}" %1 2^>nul') do set _EXIT=%%e
if not defined _STATE set _STATE=missing
if not defined _EXIT  set _EXIT=missing
if "!_STATE!"=="exited" if "!_EXIT!"=="0" (
    call :pass "%1 -- exited(0)  provisioning complete"
    goto :check_init_exited_done
)
call :fail_check "%1 -- state=!_STATE! exit=!_EXIT! (expected: exited/0)"
:check_init_exited_done
set _STATE=
set _EXIT=
goto :eof
