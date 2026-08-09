import { execFileSync } from 'node:child_process';

/**
 * What runbox needs before its skills are worth installing.
 *
 * Depositing a skill whose service cannot start is the failure this gate
 * exists to prevent: the agent reads SKILL.md, follows it, and the first
 * command fails for a reason the method has nothing to do with.
 *
 * Hard requirements block. ffmpeg is a warning, because runs index fine
 * without it and the gallery simply shows no video.
 */

function run(cmd, args) {
  try {
    return execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  } catch {
    return null;
  }
}

/** The SDK majors present, e.g. [8, 10]. File-based apps need 10 or newer. */
function dotnetSdkMajors() {
  const out = run('dotnet', ['--list-sdks']);
  if (out === null) return null;
  return out
    .split(/\r?\n/)
    .map((line) => /^(\d+)\./.exec(line.trim()))
    .filter(Boolean)
    .map((m) => Number(m[1]));
}

export function checkToolchain({ platform = process.platform } = {}) {
  const warnings = [];

  if (platform !== 'win32') {
    return {
      ok: false,
      reason: `runbox targets Windows for now, and this is ${platform}.`,
      remediation:
        'The service and gallery are portable, but install.ps1 and the generated\n' +
        'harness are not. Nothing here will work end to end yet.',
      warnings,
    };
  }

  const majors = dotnetSdkMajors();
  if (majors === null) {
    return {
      ok: false,
      reason: 'no .NET SDK found on PATH.',
      remediation:
        'runbox runs its service as a file-based app, which needs the .NET SDK 10\n' +
        'or newer. Install it from https://dotnet.microsoft.com/download and reopen\n' +
        'your shell so PATH is picked up.',
      warnings,
    };
  }
  if (!majors.some((m) => m >= 10)) {
    return {
      ok: false,
      reason: `.NET SDK ${majors.join(', ')} found, but file-based apps need 10 or newer.`,
      remediation:
        'Install the .NET 10 SDK from https://dotnet.microsoft.com/download. Older\n' +
        'SDKs cannot run a .cs file without a project, which is how the service ships.',
      warnings,
    };
  }

  if (run('ffmpeg', ['-version']) === null) {
    warnings.push(
      'ffmpeg is not on PATH. Runs will index and compare fine, but they will have\n' +
      '      no clips, and the carousel is a good deal less useful without motion.',
    );
  }

  return { ok: true, warnings };
}
