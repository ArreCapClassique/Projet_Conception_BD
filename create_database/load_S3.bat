@echo off
setlocal ENABLEDELAYEDEXPANSION

set CONN=BOCHENSOHANDSOME/BOCHENSOHANDSOME@//127.0.0.1:1550/siip

pushd "%~dp0"

if not exist "log" mkdir "log"

REM ---- Keep UTF-8 accents consistent ----
set NLS_LANG=.AL32UTF8

echo Running S3 DDL...
sqlplus -L -s %CONN% @scripts\S3_create_tables.sql 1>log\S3_ddl.out 2>log\S3_ddl.err
if errorlevel 1 (
  echo S3 DDL failed. See log\S3_ddl.err
  type log\S3_ddl.err
  popd
  exit /b 1
)

for %%T in (agence reserverprive reserversoc louer) do (
  echo Loading S3_%%T...
  sqlldr userid=%CONN% control=scripts\S3_%%T.ctl data=data\S3_%%T.csv ^
    log=log\S3_%%T.log bad=log\S3_%%T.bad direct=true errors=100000 skip=1 ^
    readsize=1048576 bindsize=1048576
  if errorlevel 1 (
    echo sqlldr failed for S3_%%T. See log\S3_%%T.log / log\S3_%%T.bad
    popd
    exit /b 1
  )
)

echo S3 load completed successfully.
popd
endlocal
