# Environment setup for CrymbleUI development
#
# SFML 3.0 and CSFML 3.0 are in locallib/sfml3 and locallib/csfml3
# Built from:
#   SFML 3.0.0: https://github.com/SFML/SFML/releases/tag/3.0.0
#   CSFML 3.0.0-rc.3: https://github.com/SFML/CSFML/releases/tag/3.0.0-rc.3

# you need to "source" this file (from any directory) - unless you have all of this installed system-wide!
# Usage: source setup.sh
GUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# SFML 3.0 + CSFML 3.0 paths
SFML3=$GUI_DIR/locallib/sfml3
CSFML3=$GUI_DIR/locallib/csfml3

export LD_LIBRARY_PATH=$SFML3/lib:$CSFML3/lib:$GUI_DIR/lib/imgui-sfml:$LD_LIBRARY_PATH
export LIBRARY_PATH=$SFML3/lib:$CSFML3/lib:$LIBRARY_PATH
export CSFML_INCLUDE_DIR=$CSFML3/include
export PKG_CONFIG_PATH=$CSFML3/lib/pkgconfig:$PKG_CONFIG_PATH
