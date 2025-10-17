@echo off
setlocal ENABLEDELAYEDEXPANSION

set CONN=BOCHENSOHANDSOME/BOCHENSOHANDSOME@//127.0.0.1:1550/siip

pushd "%~dp0"

if not exist "log" mkdir "log"

REM ---- Keep UTF-8 accents consistent ----
set NLS_LANG=.AL32UTF8
!:  
echo Running S1 DDL...
sqlplus -L -s %CONN% @scripts\S1_create_tables.sql 1>log\S1_ddl.out 2>log\S1_ddl.err
if errorlevel 1 (
  echo S1 DDL failed. See log\S1_ddl.err
  type log\S1_ddl.err
  popd
  exit /b 1
)

for %%T in (constructeur segment typeco couvrir) do (
  echo Loading S1_%%T...
  sqlldr userid=%CONN% control=scripts\S1_%%T.ctl data=data\S1_%%T.csv ^
    log=log\S1_%%T.log bad=log\S1_%%T.bad direct=true errors=100000 skip=1 ^
    readsize=1048576 bindsize=1048576
  if errorlevel 1 (
    echo sqlldr failed for S1_%%T. See log\S1_%%T.log / log\S1_%%T.bad
    popd
    exit /b 1
  )
)

echo S1 load completed successfully.
popd
endlocal
