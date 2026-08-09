#!/usr/bin/env node
import { homedir } from 'node:os';
import path from 'node:path';
import { parse, USAGE, VERSION } from '../src/cli.js';
import { TARGETS, detect, rank } from '../src/targets.js';
import { install, skillNames } from '../src/install.js';
import { checkToolchain } from '../src/toolchain.js';
import { multiSelect } from '../src/prompt.js';

function die(message, code = 1) {
  console.error(message);
  process.exit(code);
}

let opts;
try {
  opts = parse(process.argv.slice(2));
} catch (e) {
  die(`${e.message}\n\n${USAGE}`);
}

if (opts.version) {
  console.log(VERSION);
  process.exit(0);
}

if (opts.help) {
  console.log(`runbox ${VERSION}\n\n${USAGE}`);
  process.exit(0);
}

if (opts.command !== 'init') {
  die(`unknown command: ${opts.command}\n\n${USAGE}`);
}

const cwd = opts.global ? homedir() : process.cwd();

// Gate before anything is written. Installing a skill whose service cannot
// start leaves an agent following instructions that fail for reasons the
// method has nothing to do with.
const tools = checkToolchain();
if (!tools.ok && !opts.skipToolchainCheck) {
  die(`runbox cannot run here.\n\n${tools.reason}\n\n${tools.remediation}\n
Run with --skip-toolchain-check to install anyway.`);
}
if (!tools.ok && opts.skipToolchainCheck) {
  console.warn(`warning: ${tools.reason}\ninstalling anyway because --skip-toolchain-check was passed.\n`);
}

let targets = opts.targets;
if (opts.interactive) {
  const found = new Set(detect(cwd));
  if (found.size) {
    console.log(`detected: ${[...found].map((id) => TARGETS[id].name).join(', ')}\n`);
  } else {
    console.log('no agent directories detected here; all targets are listed.\n');
  }
  try {
    targets = await multiSelect({
      message: 'Install runbox skills for:',
      choices: rank(cwd).map((id) => ({
        value: id,
        label: TARGETS[id].name,
        hint: found.has(id) ? 'detected' : undefined,
        selected: found.has(id),
      })),
    });
  } catch {
    die('cancelled.', 130);
  }
}

const names = await skillNames();
const written = await install({ cwd, targets, global: opts.global });

console.log(`installed ${names.length} skill(s) to ${targets.length} target(s):\n`);
for (const p of written) console.log(`  ${p}`);

for (const w of tools.warnings ?? []) console.log(`\nnote: ${w}`);

// Depositing the skill is half of it. The service needs a wrapper that knows
// where the skill landed, and the project needs its run output ignored, so the
// next step is named explicitly rather than left in a doc nobody opens.
const first = path.join(written[0] ?? '', 'install.ps1');
console.log(`
Rerun this command to update. It always writes the current skills.

Next, from the project whose runs you want to compare:

  ${first} -Launch "godot --path {game}"

That writes harness\\serve.ps1 and adds run output to .gitignore. Then
.\\harness\\serve.ps1 starts the gallery.`);
