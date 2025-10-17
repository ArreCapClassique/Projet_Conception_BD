@echo off
setlocal ENABLEDELAYEDEXPANSION

set CONN=BOCHENSOHANDSOME/BOCHENSOHANDSOME@//127.0.0.1:1550/siip

pushd "%~dp0"

if not exist "log" mkdir "log"

REM ---- Keep UTF-8 accents consistent ----
set NLS_LANG=.AL32UTF8

echo Running S4 DDL...
sqlplus -L -s %CONN% @scripts\S4_create_tables.sql 1>log\S4_ddl.out 2>log\S4_ddl.err
if errorlevel 1 (
  echo S4 DDL failed. See log\S4_ddl.err
  type log\S4_ddl.err
  popd
  exit /b 1
)

for %%T in (concurrence) do (
  echo Loading S4_%%T...
  sqlldr userid=%CONN% control=scripts\S4_%%T.ctl data=data\S4_%%T.csv ^
    log=log\S4_%%T.log bad=log\S4_%%T.bad direct=true errors=100000 skip=1 ^
    readsize=1048576 bindsize=1048576
  if errorlevel 1 (
    echo sqlldr failed for S4_%%T. See log\S4_%%T.log / log\S4_%%T.bad
    popd
    exit /b 1
  )
)

echo S4 load completed successfully.
popd
endlocal
