@echo off
REM Hard-coded Oracle connection (SID)
REM >>> EDIT THESE THREE LINES <<<
set ORA_USER=BOCHENTHEHANDSOME
set ORA_PASS=BOCHENTHEHANDSOME
set ORA_HOST=localhost
REM -------------------------------
set ORA_PORT=1550
set ORA_SID=siip
set CONN=%ORA_USER%/%ORA_PASS%@//%ORA_HOST%:%ORA_PORT%/%ORA_SID%

REM set CONN=%ORA_USER%/%ORA_PASS%@%ORA_HOST%:%ORA_PORT%:%ORA_SID%

setlocal ENABLEDELAYEDEXPANSION

REM ---- Move to this script's directory ----
pushd "%~dp0"

REM ---- Folders ----
if not exist "log" mkdir "log"

REM Keep UTF-8 accents consistent via environment (works better than CLI param on some builds)
set NLS_LANG=.AL32UTF8

REM ---- Run DDL (includes EXIT) ----
echo Running DDL...
sqlplus -L -s %CONN% @scripts\ED_create_tables.sql 1>log\ED_ddl.out 2>log\ED_ddl.err
if errorlevel 1 (
  echo DDL failed. See log\ED_ddl.err
  type log\ddl.err
  popd
  exit /b 1
)

REM ---- Load tables (relative paths; avoid quoting issues) ----
for %%T in (marque gamme vehicule societe client reserverprive reserversoc louer) do (
  echo Loading %%T...
  sqlldr userid=%CONN% control=scripts\ED_%%T.ctl data=data\ED_%%T.csv log=log\ED_%%T.log bad=log\ED_%%T.bad direct=true errors=100000 skip=1 readsize=1048576 bindsize=1048576
  if errorlevel 1 (
    echo sqlldr failed for %%T. See log\%%T.log / log\%%T.bad
    popd
    exit /b 1
  )
)

echo All loads completed successfully.
popd
endlocal
