@echo off
setlocal enabledelayedexpansion

git submodule update --init --recursive
if errorlevel 1 exit /b 1

for /f "tokens=*" %%s in ('git config --file .gitmodules --get-regexp path') do (
    set "line=%%s"
    set "name=!line:submodule.=!"
    for /f "tokens=1 delims=." %%n in ("!name!") do set "name=%%n"
    for /f "tokens=2" %%p in ("!line!") do set "path=%%p"

    for /f "delims=" %%b in ('git config --file .gitmodules --get "submodule.!name!.branch" 2^>nul') do (
        echo Checking out !path! -^> %%b
        pushd "!path!"
        git checkout %%b
        popd
    )
)

endlocal
