@echo off
REM Environment setup for CrymbleUI on Windows.
REM
REM SFML 3.0 and CSFML 3.0 static libs are vendored under
REM   locallib\sfml3\lib\win32\
REM   locallib\csfml3\lib\win32\
REM (the Linux equivalents live in the sibling lib\linux\ directories — see
REM  setup.sh for the matching POSIX configuration).
REM
REM Built from:
REM   SFML 3.0.0:        https://github.com/SFML/SFML/releases/tag/3.0.0
REM                      (with the out-of-tree Windows GL sync patch — see
REM                       locallib\sfml3\lib\win32\README.md)
REM   CSFML 3.0.0-rc.3:  https://github.com/SFML/CSFML/releases/tag/3.0.0-rc.3
REM
REM Usage: call setup.bat (from any directory)

set GUI_DIR=%~dp0

set SFML3=%GUI_DIR%locallib\sfml3
set CSFML3=%GUI_DIR%locallib\csfml3

set LIB=%SFML3%\lib\win32;%CSFML3%\lib\win32;%LIB%
set INCLUDE=%SFML3%\include;%CSFML3%\include;%INCLUDE%
set CSFML_INCLUDE_DIR=%CSFML3%\include
