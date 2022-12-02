@ECHO OFF
REM Copied from Myby
SET Error=0

IF "%1"=="clean" GOTO :CLEAN

:COMPILE
    SET FLAGS=-g -w
    REM TODO: surely there's a way to emulate src/*.d
    SET FILES=src/main.d src/impl.d src/interpret.d
    dmd %FLAGS% %FILES% -of=plis.exe
    SET Error=%ERRORLEVEL%
    GOTO :End

:CLEAN
    DEL *.pdb *.exe *.ilk *.obj
    GOTO :End

:End
REM Set errorlevel. Yes, this is the best way.
CMD /C "EXIT /B %Error%"
