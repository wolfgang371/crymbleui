#!/bin/bash
# The showcase as a GitHub Pages site: builds showcase_demo for the web and writes the site to bin/pages/ (the page,
# the module, its scripts, NOTICES, and .nojekyll so Pages serves the files as they are). Publishing is a separate,
# deliberate step - docs/WEB.md ("Publishing the showcase") says how. Run from crymble-ui's root.
set -euo pipefail

bin/crymble-web build showcase_demo
rm -rf bin/pages
cp -r bin/web/showcase_demo bin/pages
touch bin/pages/.nojekyll
echo "pages.sh: bin/pages/ ($(du -sh bin/pages | cut -f1)) - try it with: python3 -m http.server -d bin/pages 8765"
