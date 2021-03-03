# Package

version = "0.1.0"
author = "Your Name"
description = "dusty"
license = "?"

# Deps
requires "nim >= 1.2.0"
requires "nico >= 0.2.5"

srcDir = "src"

task runr, "Runs dusty for current platform":
 exec "nim c -r -d:release -o:dusty src/main.nim"

task rund, "Runs debug dusty for current platform":
 exec "nim c -r -d:debug -o:dusty src/main.nim"

task release, "Builds dusty for current platform":
 exec "nim c -d:release -o:dusty src/main.nim"

task debug, "Builds debug dusty for current platform":
 exec "nim c -d:debug -o:dusty_debug src/main.nim"

task deps, "Downloads dependencies":
 exec "curl https://www.libsdl.org/release/SDL2-2.0.12-win32-x64.zip -o SDL2_x64.zip"
 exec "unzip SDL2_x64.zip"
 #exec "curl https://www.libsdl.org/release/SDL2-2.0.12-win32-x86.zip -o SDL2_x86.zip"
