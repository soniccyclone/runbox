#!/bin/sh
# Build the runbox site.
#
# Every page with substance is generated from a file that ships, so the site
# cannot drift from the tool: the method page is SKILL.md, the contract page is
# run-contract.md, and the demo is a real export produced by export.ps1 from the
# committed demo runs.
#
# Fails loudly rather than deploying a partial site.
set -e
cd "$(dirname "$0")"
ROOT=$(cd .. && pwd)

PANDOC=${PANDOC:-pandoc}
command -v "$PANDOC" >/dev/null 2>&1 || PANDOC="$HOME/.local/bin/pandoc"
command -v "$PANDOC" >/dev/null 2>&1 || {
  echo "build: pandoc not found. It converts the shipped markdown to org so the docs cannot drift." >&2
  exit 1
}

# Generated org is cleared every time. A stale page left by a deleted source
# points at a gen/ file that no longer exists, and org fails the whole build on
# the missing include.
rm -rf gen www
rm -f org/skill-*.org org/run-contract.org
mkdir -p gen

# --- one page per skill, from the real SKILL.md ---------------------------
for dir in "$ROOT"/skills/*/; do
  name=$(basename "$dir")
  src="$dir/SKILL.md"
  [ -f "$src" ] || continue

  # The frontmatter is stripped rather than parsed. It is YAML-shaped but the
  # agents that read these files parse it leniently, so a strict parser would
  # reject skills that work. The description is lifted out by line instead.
  desc=$(awk '/^description: /{sub(/^description: /,""); print; exit}' "$src")

  sed '1{/^---$/!q}; 1,/^---$/d' "$src" \
    | "$PANDOC" -f markdown -t org --wrap=none > "gen/$name.org"

  cat > "org/skill-$name.org" <<PAGE
#+TITLE: $name
#+OPTIONS: toc:nil num:nil author:nil date:nil

#+BEGIN_EXPORT html
<div class="cabinet">
<span class="screw tl"></span><span class="screw tr"></span>
<span class="screw bl"></span><span class="screw br"></span>
<div class="nameplate">
  <div><p class="model">Prototype Mill &middot; Model RB-1</p><h1>$name</h1></div>
  <div class="plate-right"><a href="./docs.html">Docs</a></div>
</div>
#+END_EXPORT

#+BEGIN_QUOTE
$desc
#+END_QUOTE

#+INCLUDE: "../gen/$name.org" :minlevel 2

#+BEGIN_EXPORT html
<footer><a href="./docs.html">Documentation</a> ·
<a href="./index.html">Home</a> ·
<a href="https://github.com/soniccyclone/runbox/blob/main/skills/$name/SKILL.md">Source file</a></footer>
</div>
#+END_EXPORT
PAGE
done

# --- the run contract, from the real reference doc ------------------------
CONTRACT="$ROOT/skills/runbox/reference/run-contract.md"
if [ -f "$CONTRACT" ]; then
  "$PANDOC" -f markdown -t org --wrap=none "$CONTRACT" > gen/run-contract.org
  cat > org/run-contract.org <<'PAGE'
#+TITLE: The run contract
#+OPTIONS: toc:nil num:nil author:nil date:nil

#+BEGIN_EXPORT html
<div class="cabinet">
<span class="screw tl"></span><span class="screw tr"></span>
<span class="screw bl"></span><span class="screw br"></span>
<div class="nameplate">
  <div><p class="model">Prototype Mill &middot; Model RB-1</p><h1>Run contract</h1></div>
  <div class="plate-right"><a href="./docs.html">Docs</a></div>
</div>
#+END_EXPORT

#+INCLUDE: "../gen/run-contract.org" :minlevel 2

#+BEGIN_EXPORT html
<footer><a href="./docs.html">Documentation</a> ·
<a href="./index.html">Home</a> ·
<a href="https://github.com/soniccyclone/runbox/blob/main/skills/runbox/reference/run-contract.md">Source file</a></footer>
</div>
#+END_EXPORT
PAGE
fi

# org caches publish timestamps globally and will skip files it thinks are
# unchanged, which hides edits to the skin because that lives in build.el.
rm -rf "$HOME/.org-timestamps"

emacs --batch --load build.el 2>&1 | tee /tmp/runbox-site-build.log
if grep -qiE "^(Error|Debugger entered)" /tmp/runbox-site-build.log; then
  echo "build: emacs reported an error above; refusing to publish a partial site" >&2
  exit 1
fi

test -f www/index.html || { echo "build: no index.html produced" >&2; exit 1; }

# --- the live demo, baked by the real exporter ----------------------------
# Not a mock-up of the gallery: export.ps1 reads the committed demo runs and
# inlines the actual gallery with the actual clips, which is the same artefact
# a user gets from `export.ps1` on their own runs. If the gallery changes, the
# demo changes with it, and if the exporter breaks, this build fails.
PWSH=${PWSH:-pwsh}
if command -v "$PWSH" >/dev/null 2>&1; then
  "$PWSH" -NoProfile -File "$ROOT/skills/runbox/tool/export.ps1" \
    -OutRootOverride "$(pwd)/demo-runs" -Out "$(pwd)/www/demo.html"
  test -s www/demo.html || { echo "build: demo.html was not produced" >&2; exit 1; }
else
  echo "build: pwsh not found, cannot bake the demo" >&2
  exit 1
fi

echo "build: $(find www -name '*.html' | wc -l) pages"
