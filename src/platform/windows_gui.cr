# Windows GUI-subsystem entry shim — OPT-IN via `-Dgui`.
#
# By default a crymbleui app builds as a Windows CONSOLE app: a console window
# opens alongside the GUI and `puts`/STDERR are visible — handy during development.
# Build with `-Dgui` to instead produce a true windowed app with NO console:
#
#   shards build my_app                # console (default — dev sees output)
#   shards build my_app -Dgui          # GUI app, no console window
#
# `-Dgui` is a no-op on non-Windows targets (the whole block is `flag?(:win32)`-gated).
#
# Mechanism (ported from embrace's proven shim): a GUI-subsystem process has no
# console, so writing to STDOUT/STDERR can crash — redirect both to NUL first. Then
# switch the linker to the Windows subsystem and provide the `wWinMain` entry that
# bridges to Crystal's `wmain`. This file is required FIRST by crymble-ui.cr so the
# stream redirect runs before SFML/the GL driver can emit anything.
#
# See https://github.com/crystal-lang/crystal/issues/13058
{% if flag?(:win32) && flag?(:gui) %}
  _null = File.open(File::NULL, "w")
  STDOUT.reopen(_null)
  STDOUT.sync = true
  STDERR.reopen(_null)
  STDERR.sync = true

  @[Link(ldflags: "/ENTRY:wWinMainCRTStartup")]
  @[Link(ldflags: "/SUBSYSTEM:WINDOWS")]
  lib LibCrystalMain
  end

  lib LibC
    alias HINSTANCE = HANDLE
    # shellapi.h
    fun CommandLineToArgvW(lpCmdLine : LPWSTR, pNumArgs : Int*) : LPWSTR*
  end

  fun wWinMain(
    hInstance : LibC::HINSTANCE,
    hPrevInstance : LibC::HINSTANCE,
    pCmdLine : LibC::LPWSTR,
    nCmdShow : LibC::Int,
  ) : LibC::Int
    argv = LibC.CommandLineToArgvW(pCmdLine, out argc)
    wmain(argc, argv)
  ensure
    LibC.LocalFree(argv) if argv
  end
{% end %}
