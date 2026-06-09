# Environment setup for CrymbleUI development on Linux.
#
# Platform-specific libs live under locallib/{sfml3,csfml3}/lib/{linux,win32}/
# This script wires up the linux/ subfolders.
# For Windows builds, see embrace-crystal/setup.bat (which points to win32/).
#
# Built from:
#   SFML 3.0.0:        https://github.com/SFML/SFML/releases/tag/3.0.0
#   CSFML 3.0.0-rc.3:  https://github.com/SFML/CSFML/releases/tag/3.0.0-rc.3

# you need to "source" this file (from any directory) - unless you have all of this installed system-wide!
# Usage: source setup.sh
GUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# SFML 3.0 + CSFML 3.0 paths
SFML3=$GUI_DIR/locallib/sfml3
CSFML3=$GUI_DIR/locallib/csfml3

# Guard the RHS refs (${VAR:-}) so sourcing under `set -u` (e.g. tools/build-appimage.sh)
# doesn't abort with "unbound variable" when these are unset on a fresh machine/runner.
export LD_LIBRARY_PATH=$SFML3/lib/linux:$CSFML3/lib/linux:${LD_LIBRARY_PATH:-}
export LIBRARY_PATH=$SFML3/lib/linux:$CSFML3/lib/linux:${LIBRARY_PATH:-}
export CSFML_INCLUDE_DIR=$CSFML3/include
export PKG_CONFIG_PATH=$CSFML3/lib/linux/pkgconfig:${PKG_CONFIG_PATH:-}
