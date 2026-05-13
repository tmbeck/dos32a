@echo off
@rem
@rem DOS/32A full build (in-container, runs under dosbox-x).
@rem
@rem D: = /app (repo root)
@rem C: = /opt/watcom (Open Watcom v2: binw/ host bins, h/ headers,
@rem      lib286|lib386/ libs; binw/dos32a.exe receives our rebuilt stub
@rem      for wcl386's -l=dos32a system lookup).
@rem
@rem All outputs land in d:\out\. The version-bumper (sutils/build/build) is
@rem not invoked; the utilities embed whatever build number their checked-in
@rem oemtitle.inf carries.

cd d:\
set PATH=z:\;c:\binw;d:\bin
set WATCOM=c:
set INCLUDE=c:\h;d:\h32;d:\src\sutils\misc
set TASMFLAGS=-r -ml -m -q -zn -w2 -m5 -id:\src\sutils\misc
set WCLFLAGS=-oneatx -ohirbk -ei -zp16 -6 -fp6 -fpi87 -bt=dos

echo === DOS/32A v9.12.1 full build === > build.log

@rem ----- 1) dos32a.exe (TASM + TLINK; the 9.12.1 fixes ship here) -----
echo --- dos32a.exe --- >> d:\build.log
cd d:\src\dos32a
d:\bin\tasm32 /dEXEC_TYPE=0 /m /ml /c /la kernel.asm >> d:\build.log
d:\bin\tasm32 /dEXEC_TYPE=0 /m /ml /c /la dos32a.asm >> d:\build.log
d:\bin\tlink /3 dos32a kernel,d:\out\dos32a.exe >> d:\build.log

@rem ----- 2) Plant dos32a.exe at WATCOM\binw so wcl386 -l=dos32a finds it -----
copy d:\out\dos32a.exe c:\binw\dos32a.exe >> d:\build.log

@rem ----- 3) STUB32A + STUB32C (16-bit DOS stubs) -----
echo --- stub32a / stub32c --- >> d:\build.log
cd d:\src\stub32a
tasm32 -dEXEC_TYPE=0 %TASMFLAGS% stub32a.asm >> d:\build.log
tasm32 -dEXEC_TYPE=0 %TASMFLAGS% stub32c.asm >> d:\build.log
wcl %WCLFLAGS% -lr -fe=stub32a stub32a.obj >> d:\build.log
wcl %WCLFLAGS% -lr -fe=stub32c stub32c.obj >> d:\build.log
copy stub32a.exe d:\out\ >> d:\build.log
copy stub32c.exe d:\out\ >> d:\build.log

@rem ----- 4) SB - SUNSYS Bind Utility -----
echo --- sb --- >> d:\build.log
cd d:\src\sb
tasm32 %TASMFLAGS% sbind.asm >> d:\build.log
wcl386 %WCLFLAGS% -l=dos32a -fe=sb -k65536 sbind.obj main.c >> d:\build.log
copy sb.exe d:\out\ >> d:\build.log

@rem ----- 5) SC - SUNSYS Compress Utility -----
echo --- sc --- >> d:\build.log
cd d:\src\sc
tasm32 %TASMFLAGS% scomp.asm >> d:\build.log
tasm32 %TASMFLAGS% sload.asm >> d:\build.log
wcl386 %WCLFLAGS% -l=dos32a -fe=sc -k65536 scomp.obj sload.obj encode.c main.c >> d:\build.log
copy sc.exe d:\out\ >> d:\build.log

@rem ----- 6) SS - SUNSYS Setup Utility -----
echo --- ss --- >> d:\build.log
cd d:\src\ss
tasm32 %TASMFLAGS% setup.asm >> d:\build.log
wcl386 %WCLFLAGS% -l=dos32a -fe=ss -k65536 setup.obj main.c >> d:\build.log
copy ss.exe d:\out\ >> d:\build.log

@rem ----- 7) SD - SUNSYS Debugger -----
echo --- sd --- >> d:\build.log
cd d:\src\sd
tasm32 -dSVR=0 %TASMFLAGS% sd.asm >> d:\build.log
wcl386 %WCLFLAGS% -l=dos32a -fe=sd sd.obj >> d:\build.log
copy sd.exe d:\out\ >> d:\build.log

@rem ----- 8) sdebug.lib (SD as static library) -----
echo --- sdebug.lib --- >> d:\build.log
cd d:\src\sd\sdlib
tasm32 %TASMFLAGS% sdebug.asm >> d:\build.log
wlib -b -c sdebug.lib +-sdebug.obj >> d:\build.log
copy sdebug.lib d:\out\ >> d:\build.log

@rem ----- 9) PCTEST -----
echo --- pctest --- >> d:\build.log
cd d:\src\sutils\pctest
tasm32 %TASMFLAGS% pctest.asm >> d:\build.log
wcl386 %WCLFLAGS% -fe=pctest.exe -k65535 -l=dos32a main.c pctest.obj >> d:\build.log
copy pctest.exe d:\out\ >> d:\build.log

@rem ----- 10) SVER -----
echo --- sver --- >> d:\build.log
cd d:\src\sutils\sver
wcl %WCLFLAGS% -lr -fe=sver.exe main.c >> d:\build.log
copy sver.exe d:\out\ >> d:\build.log

cd d:\
echo === build complete === >> build.log
