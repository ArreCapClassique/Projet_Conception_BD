@echo off
setlocal ENABLEDELAYEDEXPANSION

set CONN=BOCHENTHEHANDSOME/BOCHENTHEHANDSOME@//127.0.0.1:1550/siip

pushd "%~dp0"

if not exist "log" mkdir "log"

REM ---- Keep UTF-8 accents consistent ----
set NLS_LANG=.AL32UTF8

echo Running BRIDGE DDL...
sqlplus -L -s %CONN% @scripts\BRIDGE_create_tables.sql 1>log\BRIDGE_ddl.out 2>log\BRIDGE_ddl.err
if errorlevel 1 (
  echo BRIDGE DDL failed. See log\BRIDGE_ddl.err
  type log\BRIDGE_ddl.err
  popd
  exit /b 1
)

for %%T in (MA_CO, VILLE_REGION) do (
  echo Loading BRIDGE_%%T...
  sqlldr userid=%CONN% control=scripts\BRIDGE_%%T.ctl data=data\BRIDGE_%%T.csv ^
    log=log\BRIDGE_%%T.log bad=log\BRIDGE_%%T.bad direct=true errors=100000 skip=1 ^
    readsize=1048576 bindsize=1048576
  if errorlevel 1 (
    echo sqlldr failed for BRIDGE_%%T. See log\BRIDGE_%%T.log / log\BRIDGE_%%T.bad
    popd
    exit /b 1
  )
)

echo BRIDGE load completed successfully.
popd
endlocal
