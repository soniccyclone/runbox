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

# The export carries no navigation, and must not: it is a standalone file handed
# to someone with no repo, where a link to ./index.html would be dead. Published
# on the site it is a different thing, and without a way back it is a dead end.
# So the bar is injected into the published copy here, leaving export.ps1 and
# everyone's own exports alone.
cat > gen/sitebar.html <<'BAR'
<style>
  .sitebar {
    display:flex; align-items:center; gap:14px; flex-wrap:wrap;
    max-width:1000px; margin:0 auto; padding:10px 16px 0;
    font-family:"Consolas","Lucida Console",monospace; font-size:10px;
    letter-spacing:.18em; text-transform:uppercase; color:#6E6E7A;
  }
  .sitebar a { color:#9A9AA6; text-decoration:none; border-bottom:1px solid rgba(255,176,0,.25); }
  .sitebar a:hover { color:#FFB000; border-bottom-color:#FFB000; }
  .sitebar .what { color:#5C5C68; letter-spacing:.10em; text-transform:none; font-size:11px; }
  .sitebar .right { margin-left:auto; display:flex; gap:14px; }
</style>
<div class="sitebar">
  <a href="./index.html">&#8592; runbox</a>
  <span class="what">A real export of three recorded runs, not a mock-up.</span>
  <!-- Internal links only. The published demo is otherwise byte-identical to
       an export, and check.js asserts it pulls nothing from the network; an
       outbound link here would force that assertion to be weakened. Docs
       carries the GitHub link. -->
  <span class="right">
    <a href="./docs.html">Docs</a>
    <a href="./run-contract.html">Run contract</a>
  </span>
</div>
BAR

awk 'NR==FNR { bar = bar $0 ORS; next }
     !done && /^<body>$/ { print; printf "%s", bar; done = 1; next }
     { print }' gen/sitebar.html www/demo.html > gen/demo.html
grep -q 'class="sitebar"' gen/demo.html || {
  echo "build: could not inject the demo nav bar; the gallery's <body> moved" >&2
  exit 1
}
mv gen/demo.html www/demo.html

echo "build: $(find www -name '*.html' | wc -l) pages"
