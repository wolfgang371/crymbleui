# crymble-ui locallib — vendored SFML / CSFML libraries

CrymbleUI's GUI backend is built on SFML 3.0.0 and CSFML 3.0.0-rc.3. Rather
than asking every consumer to install those system-wide, we vendor the
already-built static libs here, one subfolder per OS.

## Layout

```
sfml3/
├── include/                  shared C++ headers (same on every OS)
└── lib/
    ├── linux/                Linux .so + .a + cmake/ + pkgconfig/
    └── win32/                Windows .lib + patch + README

csfml3/
├── include/                  shared C headers
└── lib/
    ├── linux/                Linux .so + pkgconfig/
    └── win32/                Windows .lib
```

## Picking the right subfolder at build time

Two setup scripts wire this up:

- **Linux**:   `crymble-ui/setup.sh` (also `embrace-crystal/setup.sh`) sets
  `LD_LIBRARY_PATH` / `LIBRARY_PATH` / `PKG_CONFIG_PATH` to point at the
  `lib/linux/` subfolders.
- **Windows**: `embrace-crystal/setup.bat` sets `LIB` / `INCLUDE` to point
  at the `lib/win32/` subfolders.

Source the appropriate one before running `shards build` and the platform
linker will find the right libs automatically.

## ⚠️ Windows: patched sfml-graphics

`sfml3/lib/win32/sfml-graphics.lib` is **not** stock SFML 3.0.0 — it has an
out-of-tree patch that fixes a stochastic font glyph garbling bug on
Windows GL drivers. The patch source and a build/rebuild README live next
to the lib:

- `sfml3/lib/win32/sfml-graphics-windows-glsync.patch`
- `sfml3/lib/win32/README.md`

Full root-cause analysis: `crymble-ui/docs/WINDOWS_SFML_GL_SYNC_BUG.md`.

## Versions

- **SFML**:  3.0.0  (https://github.com/SFML/SFML/releases/tag/3.0.0)
- **CSFML**: 3.0.0-rc.3  (https://github.com/SFML/CSFML/releases/tag/3.0.0-rc.3)
