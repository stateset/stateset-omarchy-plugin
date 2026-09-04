#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const contract = JSON.parse(fs.readFileSync(path.join(root, 'contract.json'), 'utf8'));
const modelPath = path.join(root, 'Model.js');
const begin = '// BEGIN GENERATED CONTRACT — run node scripts/generate-contract.mjs';
const end = '// END GENERATED CONTRACT';

if (!Number.isInteger(contract.schemaVersion) || contract.schemaVersion < 1) {
  throw new Error('contract.schemaVersion must be a positive integer');
}
if (!/^\d+\.\d+\.\d+$/.test(contract.controllerVersion)) {
  throw new Error('contract.controllerVersion must be semantic versioning');
}
if (!Array.isArray(contract.capabilities) || contract.capabilities.length === 0
    || new Set(contract.capabilities).size !== contract.capabilities.length
    || contract.capabilities.some(value => typeof value !== 'string' || !/^[a-z][a-z-]*$/.test(value))) {
  throw new Error('contract.capabilities must contain unique kebab-case names');
}
if (!Number.isInteger(contract.snapshot?.version) || contract.snapshot.version < 1
    || !Number.isInteger(contract.snapshot?.maxAgeMs) || contract.snapshot.maxAgeMs < 1
    || !Number.isInteger(contract.snapshot?.maxBytes) || contract.snapshot.maxBytes < 1) {
  throw new Error('contract.snapshot values must be positive integers');
}

const generated = [
  begin,
  `var STATUS_SCHEMA_VERSION = ${contract.schemaVersion}`,
  `var CONTROLLER_SERIES = ${JSON.stringify(contract.controllerVersion.split('.').slice(0, 2).join('.'))}`,
  `var STATUS_CAPABILITIES = ${JSON.stringify(contract.capabilities)}`,
  `var SNAPSHOT_STATE_VERSION = ${contract.snapshot.version}`,
  `var SNAPSHOT_MAX_AGE_MS = ${contract.snapshot.maxAgeMs}`,
  `var SNAPSHOT_MAX_BYTES = ${contract.snapshot.maxBytes}`,
  end,
].join('\n');

const source = fs.readFileSync(modelPath, 'utf8');
const start = source.indexOf(begin);
const finish = source.indexOf(end);
if (start < 0 || finish < start) throw new Error('Model.js generated contract markers are missing');
const next = source.slice(0, start) + generated + source.slice(finish + end.length);

if (process.argv.includes('--check')) {
  if (next !== source) throw new Error('Model.js contract constants are stale; run node scripts/generate-contract.mjs');
} else {
  fs.writeFileSync(modelPath, next);
}
