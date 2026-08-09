import { parseArgs } from 'node:util';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { TARGET_IDS } from './targets.js';

export const VERSION = JSON.parse(
  readFileSync(path.join(import.meta.dirname, '..', 'package.json'), 'utf8'),
).version;

export const USAGE = `runbox init [--global] [--agent <name>] [--skip-toolchain-check]

  --agent <name>            install for one target; repeat for several.
                            ${TARGET_IDS.join(', ')}
  --global                  install to the user directory instead of this repo
  --skip-toolchain-check    install even without a usable .NET SDK

With no --agent, runbox detects what this repo uses and asks.
Rerunning is also the update path: it always writes the current skills.

After installing, wire the harness into the project it will record:

  <skills-dir>\\runbox\\install.ps1 -Launch "godot --path {game}"`;

export function parse(argv) {
  const { values, positionals } = parseArgs({
    args: argv,
    allowPositionals: true,
    options: {
      agent: { type: 'string', multiple: true },
      global: { type: 'boolean', short: 'g' },
      'skip-toolchain-check': { type: 'boolean' },
      help: { type: 'boolean', short: 'h' },
      version: { type: 'boolean', short: 'v' },
    },
  });

  const targets = values.agent ?? [];
  const unknown = targets.filter((t) => !TARGET_IDS.includes(t));
  if (unknown.length) {
    throw new Error(`unknown target: ${unknown.join(', ')}. Known: ${TARGET_IDS.join(', ')}`);
  }

  return {
    command: positionals[0] ?? 'init',
    targets,
    interactive: targets.length === 0,
    global: values.global === true,
    skipToolchainCheck: values['skip-toolchain-check'] === true,
    help: values.help === true,
    version: values.version === true,
  };
}
