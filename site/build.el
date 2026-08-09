;; Build the runbox site: org -> HTML, wearing the gallery's own finish.
;;
;; The skin is not a choice made here. skills/runbox/tool/gallery/index.html
;; commits to one look and says so in a comment: brushed graphite chassis, amber
;; VFD readout, deliberately pre-2015, "a machine has one". The site is the front
;; door to that machine, so it uses the same palette and the same furniture. If
;; the gallery's finish changes, this changes with it.
(require 'package)
(package-initialize)
(require 'htmlize nil t)
(require 'ox-publish)

(setq org-html-htmlize-output-type 'css
      org-html-head-include-default-style nil
      org-html-head-include-scripts nil
      org-html-validation-link nil
      org-export-with-section-numbers nil
      ;; org defaults to border="2" cellspacing cellpadding rules frame, which
      ;; are HTML 3 presentation attributes and beat the stylesheet. Drop them
      ;; and let CSS draw the readout.
      org-html-table-default-attributes nil)

;; Lifted verbatim from the gallery's :root. Keep them in step.
(defvar rb-palette "
  --amber:#FFB000; --amber-dim:#7A5200; --screen-bg:#0A0B09;
  --ink:#E8E8EE; --engrave:#9A9AA6; --engrave-lo:#6E6E7A;
  --warn:#FF6B4A; --good:#6BE3A8; --slotA:#6BE3A8; --slotB:#FFC24D;
  --ui:\"Lucida Grande\",\"Lucida Sans Unicode\",\"Segoe UI\",Tahoma,Verdana,sans-serif;
  --led:\"Consolas\",\"Lucida Console\",\"DejaVu Sans Mono\",monospace;
")

(setq org-html-head
      (concat "<link rel=\"icon\" href=\"mark.svg\" type=\"image/svg+xml\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<style>
:root {" rb-palette "}
* { box-sizing:border-box; }
body {
  margin:0; min-height:100vh; color:var(--ink);
  font-family:var(--ui); font-size:15px; line-height:1.6;
  background: radial-gradient(ellipse at 50% 0%, #2E2E36 0%, #191920 55%, #0E0E12 100%);
}
#content { max-width:52rem; margin:0 auto; padding:26px 16px 54px; }
.title, .subtitle { display:none; }

/* The chassis. Same construction as the gallery: brushed vertical gradient,
   a lit top edge, a dark base, and four screws holding it to the page. */
.cabinet {
  position:relative; border-radius:9px; padding:16px 20px 22px; margin-bottom:18px;
  background:
    repeating-linear-gradient(90deg, rgba(255,255,255,.030) 0 1px, rgba(0,0,0,.02) 1px 3px),
    linear-gradient(180deg, #55555E 0%, #3C3C44 42%, #2F2F36 52%, #23232A 100%);
  box-shadow:
    inset 0 1px 0 rgba(255,255,255,.30), inset 0 -2px 2px rgba(0,0,0,.55),
    inset 2px 0 3px rgba(0,0,0,.30), inset -2px 0 3px rgba(0,0,0,.30),
    0 10px 26px rgba(0,0,0,.62), 0 2px 0 rgba(255,255,255,.05);
  border:1px solid #14141A;
}
.screw {
  position:absolute; width:11px; height:11px; border-radius:50%;
  background:linear-gradient(180deg,#8B8B95 0%,#55555E 55%,#3A3A42 100%);
  box-shadow: inset 0 1px 0 rgba(255,255,255,.5), 0 1px 2px rgba(0,0,0,.7);
}
.screw::after {
  content:\"\"; position:absolute; left:2px; right:2px; top:4.6px; height:1.6px;
  background:linear-gradient(180deg, rgba(0,0,0,.65), rgba(255,255,255,.18));
  border-radius:1px; transform:rotate(38deg);
}
.screw.tl{top:7px;left:7px} .screw.tr{top:7px;right:7px}
.screw.bl{bottom:7px;left:7px} .screw.br{bottom:7px;right:7px}

.nameplate {
  display:flex; align-items:flex-end; justify-content:space-between; gap:14px;
  flex-wrap:wrap; padding:4px 0 13px; margin-bottom:16px;
  border-bottom:1px solid rgba(0,0,0,.55); box-shadow:0 1px 0 rgba(255,255,255,.09);
}
.nameplate h1 {
  margin:0; font-size:34px; font-weight:700; color:#DCDCE4; letter-spacing:-.01em;
  text-shadow:0 1px 0 rgba(255,255,255,.18), 0 -1px 1px rgba(0,0,0,.75);
}
/* Engraving on the gallery sits on a darker panel than this one, so the two
   engraved greys are lifted a step here. Same treatment, same shadow, legible
   against a chassis that is carrying body copy rather than a readout. */
.model, .plate-right {
  font-family:var(--led); font-size:10px; letter-spacing:.22em; text-transform:uppercase;
  color:#8C8C98; margin:0 0 3px;
  text-shadow:0 1px 0 rgba(255,255,255,.13), 0 -1px 0 rgba(0,0,0,.6);
}
.plate-right { text-align:right; letter-spacing:.13em; color:#A6A6B2; white-space:nowrap; }
.tagline { margin:0 0 1.2rem; color:#B4B4C0; font-size:1.06rem; max-width:44rem; }

/* Engraved section labels, as on the gallery's wells. */
h2 {
  font-family:var(--led); font-size:11px; letter-spacing:.26em; text-transform:uppercase;
  color:#A2A2AE; font-weight:400; margin:2.5rem 0 .85rem;
  padding-bottom:.5rem; border-bottom:1px solid rgba(0,0,0,.42);
  box-shadow:0 1px 0 rgba(255,255,255,.07);
  text-shadow:0 1px 0 rgba(255,255,255,.13), 0 -1px 0 rgba(0,0,0,.6);
}
h3 { font-size:1.02rem; font-weight:700; color:#DCDCE4; margin:1.8rem 0 .5rem; }
p, li { color:var(--ink); }
ol, ul { padding-left:1.15rem; }
li { margin:.35rem 0; }
b, strong { color:var(--amber); font-weight:700; }
a { color:var(--amber); text-decoration:none; border-bottom:1px solid rgba(255,176,0,.28); }
a:hover { border-bottom-color:var(--amber); text-shadow:0 0 6px rgba(255,176,0,.45); }

/* Recessed well, for anything that reads as a readout. */
blockquote {
  margin:1.25rem 0; padding:12px 16px; border-radius:6px; border:1px solid #0D0D11;
  background:linear-gradient(180deg,#17171C 0%,#1D1D23 100%);
  box-shadow: inset 0 3px 7px rgba(0,0,0,.85), inset 0 -1px 0 rgba(255,255,255,.05),
              0 1px 0 rgba(255,255,255,.10);
  color:var(--engrave);
}
blockquote p { margin:0; color:var(--engrave); }

pre.src, pre.example {
  position:relative; margin:1.25rem 0; padding:.9rem 1.1rem; overflow-x:auto;
  border-radius:5px; border:1px solid #0A0B09;
  background:linear-gradient(180deg,#0D0F0C,#131510);
  box-shadow: inset 0 2px 6px rgba(0,0,0,.85);
  font-family:var(--led); font-size:13px; color:var(--amber);
  text-shadow:0 0 5px rgba(255,176,0,.35);
}
code { font-family:var(--led); font-size:.92em; color:var(--amber);
       background:rgba(255,176,0,.07); padding:.1em .35em; border-radius:3px; }
pre code { background:none; padding:0; text-shadow:none; }

/* Amber-on-black readout, matching the delta table. */
table {
  width:100%; border-collapse:collapse; margin:1.25rem 0; overflow:hidden;
  border-radius:5px; border:1px solid #0A0B09;
  background:linear-gradient(180deg,#0D0F0C,#131510);
  box-shadow: inset 0 2px 6px rgba(0,0,0,.85);
  font-family:var(--led); font-size:12.5px; font-variant-numeric:tabular-nums;
}
th, td { padding:7px 12px; text-align:left; }
/* org tags each column with its alignment; numbers belong on the right. */
th.org-right, td.org-right { text-align:right; }
th.org-center, td.org-center { text-align:center; }
th {
  font-size:9px; letter-spacing:.18em; text-transform:uppercase; font-weight:400;
  color:var(--amber-dim); background:linear-gradient(180deg,#1A1C16,#121410);
  border-bottom:1px solid #000;
}
td { color:var(--amber); text-shadow:0 0 5px rgba(255,176,0,.5); }
td:first-child { color:var(--amber-dim); text-shadow:none; }
tbody tr + tr td { border-top:1px solid rgba(255,176,0,.09); }

/* Aqua gel button, as on the transport. */
.btn {
  display:inline-block; margin:.4rem .5rem .4rem 0; position:relative;
  font-family:var(--ui); font-size:12px; font-weight:700; letter-spacing:.04em;
  color:#FFF; padding:9px 18px; border-radius:14px; border:1px solid #0E3D6B;
  background:linear-gradient(180deg,#8FD4FA 0%,#4FA0E4 46%,#2C79C9 54%,#1C5DA8 100%);
  box-shadow: inset 0 1px 0 rgba(255,255,255,.75), inset 0 -1px 0 rgba(0,0,0,.35),
              0 2px 5px rgba(0,0,0,.5), 0 0 11px rgba(66,150,230,.34);
  text-shadow:0 -1px 0 rgba(0,0,0,.4);
}
.btn::after {
  content:\"\"; position:absolute; left:3px; right:3px; top:1px; height:42%;
  border-radius:12px 12px 60% 60% / 12px 12px 100% 100%;
  background:linear-gradient(180deg, rgba(255,255,255,.42), rgba(255,255,255,.04));
  pointer-events:none;
}
.btn:hover { border-bottom-color:#0E3D6B; }
.btn.amber {
  color:#2A1C00; border-color:#6A4B00;
  background:linear-gradient(180deg,#FFDE9A 0%,#FFB93F 46%,#E39400 54%,#B87500 100%);
  box-shadow: inset 0 1px 0 rgba(255,255,255,.7), 0 2px 5px rgba(0,0,0,.5),
              0 0 11px rgba(255,176,0,.3);
  text-shadow:none;
}

footer {
  margin-top:2.5rem; padding-top:1.1rem; border-top:1px solid rgba(0,0,0,.55);
  box-shadow:0 -1px 0 rgba(255,255,255,.06) inset;
  font-family:var(--led); font-size:10px; letter-spacing:.14em; text-transform:uppercase;
  color:var(--engrave-lo);
}
footer a { color:var(--engrave); border-bottom:none; }
footer a:hover { color:var(--amber); }

.org-src-container { margin:1.25rem 0; }
.org-keyword{color:#FFC24D} .org-builtin{color:#6BE3A8}
.org-string{color:#B7E6A6} .org-variable-name{color:#FFD79A}
.org-comment,.org-comment-delimiter{color:var(--engrave-lo);font-style:italic}
#postamble, #table-of-contents { display:none; }
@media (max-width:720px){ .nameplate h1{font-size:26px} }
</style>"))

(setq org-publish-project-alist
      `(("runbox-org"
         :base-directory "./org" :base-extension "org"
         :publishing-directory "./www" :recursive t
         :publishing-function org-html-publish-to-html)
        ("runbox-assets"
         :base-directory "./org" :base-extension "svg\\|png"
         :publishing-directory "./www" :recursive t
         :publishing-function org-publish-attachment)
        ("runbox" :components ("runbox-org" "runbox-assets"))))

(org-publish-all t)
(message "built runbox site")
