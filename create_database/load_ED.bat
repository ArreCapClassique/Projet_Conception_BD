@echo off
setlocal ENABLEDELAYEDEXPANSION

set CONN=BOCHENTHEHANDSOME/BOCHENTHEHANDSOME@//127.0.0.1:1550/siip

pushd "%~dp0"

if not exist "log" mkdir "log"

REM ---- Keep UTF-8 accents consistent ----
set NLS_LANG=.AL32UTF8

echo Running ED DDL...
sqlplus -L -s %CONN% @scripts\ED_create_tables.sql 1>log\ED_ddl.out 2>log\ED_ddl.err
if errorlevel 1 (
  echo ED DDL failed. See log\ED_ddl.err
  type log\ED_ddl.err
  popd
  exit /b 1
)

for %%T in (marque gamme vehicule societe client reserverprive reserversoc louer) do (
  echo Loading ED_%%T...
  sqlldr userid=%CONN% control=scripts\ED_%%T.ctl data=data\ED_%%T.csv ^
    log=log\ED_%%T.log bad=log\ED_%%T.bad direct=true errors=100000 skip=1 ^
    readsize=1048576 bindsize=1048576
  if errorlevel 1 (
    echo sqlldr failed for ED_%%T. See log\ED_%%T.log / log\ED_%%T.bad
    popd
    exit /b 1
  )
)

echo Running ED data corrections...
sqlplus -L -s %CONN% @scripts\correction_ED.sql 1>log\correction_ED.out 2>log\correction_ED.err
if errorlevel 1 (
  echo ED correction failed. See log\correction_ED.err
  type log\correction_ED.err
  popd
  exit /b 1
)

echo ED load completed successfully.
popd
endlocal
