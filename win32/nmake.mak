# MSVC build for official/EDB Windows PostgreSQL (Visual Studio, /MD UCRT).
# Driven by scripts/build-msvc.bat — do not mix with MinGW PGXS.
#
# nmake /f win32\nmake.mak ECL_PREFIX=... PG_INC=... PG_INC_SERVER=... PG_LIB=...

!IFNDEF ECL_PREFIX
!ERROR ECL_PREFIX is required (MSVC ECL install prefix from scripts/build-ecl-msvc.bat)
!ENDIF
!IFNDEF PG_INC_SERVER
!ERROR PG_INC_SERVER is required (pg_config --includedir-server)
!ENDIF
!IFNDEF PG_LIB
!ERROR PG_LIB is required (pg_config --libdir)
!ENDIF

!IFNDEF PG_INC
PG_INC = $(PG_INC_SERVER)\..
!ENDIF
!IFNDEF PKGLIBDIR
PKGLIBDIR = $(PG_LIB)
!ENDIF
!IFNDEF SHAREDIR
SHAREDIR = $(PG_INC)\..\share
!ENDIF
!IFNDEF BINDIR
BINDIR = $(PG_INC)\..\bin
!ENDIF

CC = cl
CFLAGS = /nologo /O2 /W3 /MD /std:c11 /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS /D_CRT_SECURE_NO_DEPRECATE
INCLUDES = /I"$(PG_INC)" /I"$(PG_INC_SERVER)" /I"$(PG_INC_SERVER)\port\win32" /I"$(PG_INC_SERVER)\port\win32_msvc" /I"$(ECL_PREFIX)" /I"src"

OBJS = src\plecl.obj src\convert.obj src\spi.obj

all: plecl.dll

src\plecl.obj: src\plecl.c src\plecl.h
	$(CC) $(CFLAGS) $(INCLUDES) /c src\plecl.c /Fo$@

src\convert.obj: src\convert.c src\plecl.h
	$(CC) $(CFLAGS) $(INCLUDES) /c src\convert.c /Fo$@

src\spi.obj: src\spi.c src\plecl.h
	$(CC) $(CFLAGS) $(INCLUDES) /c src\spi.c /Fo$@

plecl.dll: $(OBJS)
	$(CC) $(CFLAGS) /LD $(OBJS) /Fe$@ /link /DLL /INCREMENTAL:NO /nologo "/LIBPATH:$(PG_LIB)" "/LIBPATH:$(ECL_PREFIX)" postgres.lib ecl.lib user32.lib ws2_32.lib

clean:
	-del /Q src\plecl.obj src\convert.obj src\spi.obj plecl.dll plecl.exp plecl.lib plecl.pdb 2>nul

install: plecl.dll
	if not exist "$(PKGLIBDIR)" mkdir "$(PKGLIBDIR)"
	if not exist "$(BINDIR)" mkdir "$(BINDIR)"
	if not exist "$(SHAREDIR)" mkdir "$(SHAREDIR)"
	if not exist "$(SHAREDIR)\extension" mkdir "$(SHAREDIR)\extension"
	copy /Y plecl.dll "$(PKGLIBDIR)\plecl.dll"
	copy /Y lisp\plecl.lisp "$(PKGLIBDIR)\plecl.lisp"
	copy /Y lisp\inspect.lisp "$(PKGLIBDIR)\inspect.lisp"
	copy /Y lisp\blob.lisp "$(PKGLIBDIR)\blob.lisp"
	copy /Y vendor\asdf.lisp "$(PKGLIBDIR)\asdf.lisp"
	copy /Y plecl.control "$(SHAREDIR)\extension\plecl.control"
	copy /Y sql\plecl--0.1.0.sql "$(SHAREDIR)\extension\plecl--0.1.0.sql"
	copy /Y "$(ECL_PREFIX)\ecl.dll" "$(PKGLIBDIR)\ecl.dll"
	copy /Y "$(ECL_PREFIX)\ecl.dll" "$(BINDIR)\ecl.dll"
	if exist "$(ECL_PREFIX)\help.doc" copy /Y "$(ECL_PREFIX)\help.doc" "$(PKGLIBDIR)\help.doc"
	if exist "$(ECL_PREFIX)\encodings" xcopy /E /I /Y "$(ECL_PREFIX)\encodings" "$(PKGLIBDIR)\encodings\"
