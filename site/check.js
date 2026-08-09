#!/usr/bin/env node
/**
 * Assert the built site before it is deployed.
 *
 * These check the things that rot without anyone noticing: a link to a page the
 * build stopped producing, a demo that quietly grew a network dependency, an
 * install line on the splash that no longer matches the README. None of them
 * break the build on their own, which is exactly why they are asserted.
 */
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import path from 'node:path';

// Defaults to the in-place build. An explicit path lets the site be checked
// after being built somewhere else, which is how it is verified locally.
const SITE = path.resolve(process.argv[2] ?? path.join(import.meta.dirname, 'www'));
const ROOT = path.resolve(import.meta.dirname, '..');

const failures = [];
const check = (ok, message) => { if (!ok) failures.push(message); };

if (!existsSync(SITE)) {
  console.error('check: no www/. Run site/build.sh first.');
  process.exit(1);
}

const pages = readdirSync(SITE).filter((f) => f.endsWith('.html'));
const read = (f) => readFileSync(path.join(SITE, f), 'utf8');

// Every page the site promises must exist.
for (const want of ['index.html', 'docs.html', 'demo.html', 'skill-runbox.html', 'run-contract.html']) {
  check(pages.includes(want), `missing page: ${want}`);
}

// Internal links have to resolve. A renamed page otherwise 404s only for
// whoever clicked it.
for (const page of pages) {
  const html = read(page);
  for (const m of html.matchAll(/href="\.\/([^"#]+)(?:#[^"]*)?"/g)) {
    check(existsSync(path.join(SITE, m[1])), `${page}: dead link to ${m[1]}`);
  }
}

// The demo is published to the open web, so the export's core promise has to
// hold here too: one file, no network. Strip data: URIs first, since those
// contain no host.
const demo = read('demo.html');
const stripped = demo.replace(/data:[a-z]+\/[a-z0-9.+-]+;base64,[A-Za-z0-9+/=]+/g, 'DATAURI');
for (const pat of ['http://', 'https://', 'src="//', 'href="//', '<script src=']) {
  check(!stripped.includes(pat), `demo.html references [${pat}]; an export must be self-contained`);
}
check((demo.match(/data:video\/mp4;base64/g) ?? []).length >= 2,
  'demo.html needs at least two clips, or there is nothing to compare');

// A demo where every run is titled the same is the defect F9 recorded. The
// labels come from the committed runs through the exporter, so this asserts
// that whole path rather than the fixture alone.
const labels = [...demo.matchAll(/"label":"([^"]+)"/g)].map((m) => m[1]);
check(new Set(labels).size >= 2, `demo runs must be distinguishable, got labels: ${labels.join(', ') || 'none'}`);

// The splash tells people how to install. If the README moves on, one of them
// is lying and it will be the one nobody re-reads.
const installLine = 'npx github:soniccyclone/runbox init';
check(readFileSync(path.join(ROOT, 'README.md'), 'utf8').includes(installLine),
  'README no longer contains the install line the splash shows');
check(read('index.html').includes(installLine), 'splash no longer shows the install line');

// The skill page is generated from the real SKILL.md, not transcribed. Pick a
// phrase that only exists in the source.
const skillMd = readFileSync(path.join(ROOT, 'skills/runbox/SKILL.md'), 'utf8');
const marker = 'Do not ask for a verdict on one run';
check(skillMd.includes(marker), `SKILL.md no longer contains the marker phrase [${marker}]`);
check(read('skill-runbox.html').includes(marker), 'skill page is not being generated from SKILL.md');

if (failures.length) {
  console.error(`check: ${failures.length} problem(s)`);
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log(`check: ${pages.length} pages, all good`);
