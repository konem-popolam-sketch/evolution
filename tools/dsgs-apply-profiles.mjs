#!/usr/bin/env node
/**
 * Делает студийный ростер DSGS (50 агентов) основой AgentTeams:
 * вставляет/заменяет запись `- id: agent-teams` в cordis.patch.yml профиля
 * сгенерированным блоком tools/generated/agent-teams.profiles.yml.
 *
 * Запуск: node tools/dsgs-apply-profiles.mjs [--dry-run]
 */
import { readFileSync, writeFileSync, copyFileSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { homedir } from 'node:os';

const DRY = process.argv.includes('--dry-run');
const maxIdx = process.argv.indexOf('--max-members');
const MAX_MEMBERS = maxIdx >= 0 ? Number(process.argv[maxIdx + 1]) : null;
const HOME = homedir();
const PATCH = `${HOME}/.dsh/profiles/desktop/cordis.patch.yml`;
const GENERATED = 'C:/Users/Igor/OneDrive/Desktop/claude god/tools/generated/agent-teams.profiles.yml';

for (const [label, p] of [['патч', PATCH], ['сгенерированный блок', GENERATED]]) {
  if (!existsSync(p)) {
    console.error(`нет файла (${label}): ${p}`);
    process.exit(2);
  }
}

const patch = readFileSync(PATCH, 'utf8').replace(/\r\n/g, '\n');
const blockRaw = readFileSync(GENERATED, 'utf8').replace(/\r\n/g, '\n').trimEnd() + '\n';
const block = MAX_MEMBERS === null
  ? blockRaw
  : blockRaw.replace(/^(\s*)maxMembers:\s*\d+$/m, `$1maxMembers: ${MAX_MEMBERS}`);
if (MAX_MEMBERS !== null && block === blockRaw) {
  console.error('не удалось заменить maxMembers в блоке');
  process.exit(2);
}

const lines = patch.split('\n');
const starts = [];
for (let i = 0; i < lines.length; i += 1) {
  if (/^- id:\s*\S+\s*$/.test(lines[i])) starts.push(i);
}
const found = starts.filter((s) => lines[s].replace(/^- id:\s*/, '').trim().replace(/^["']|["']$/g, '') === 'agent-teams');

let nextPatch;
if (found.length > 1) {
  console.error(`ожидалась максимум одна запись "- id: agent-teams", найдено ${found.length}`);
  process.exit(2);
} else if (found.length === 1) {
  const start = found[0];
  const nextEntry = starts.find((i) => i > start) ?? lines.length;
  const before = lines.slice(0, start).join('\n').trimEnd();
  const after = lines.slice(nextEntry).join('\n').trimStart();
  nextPatch = [before, block.trimEnd(), after].filter((s) => s.length > 0).join('\n\n') + '\n';
} else {
  nextPatch = patch.trimEnd() + '\n\n' + block;
}

// Проверка YAML и состава через js-yaml профиля.
const requireProfile = createRequire(`${HOME}/.dsh/profiles/desktop/`);
let yaml = null;
try {
  yaml = requireProfile('js-yaml');
} catch {
  console.warn('! js-yaml не найден — YAML не проверяется');
}
if (yaml) {
  let parsed;
  try {
    parsed = yaml.load(nextPatch);
  } catch (err) {
    console.error(`YAML не разбирается: ${err.message}`);
    process.exit(2);
  }
  const entry = Array.isArray(parsed) ? parsed.find((e) => e && e.id === 'agent-teams') : null;
  const profiles = entry?.config?.profiles ?? {};
  const members = Object.values(profiles).flatMap((p) => p?.members ?? []);
  const named = members.filter((m) => /·/.test(m.role ?? '')).length;
  console.log(`YAML ок: записей ${parsed.length}, профилей ${Object.keys(profiles).length}, членов ${members.length}, с именем в роли ${named}`);
  if (members.length !== 50 || Object.keys(profiles).length !== 11 || named !== 50) {
    console.error('состав не совпал с ожидаемым (50 членов / 11 профилей / все с именем)');
    process.exit(2);
  }
  if (MAX_MEMBERS !== null && entry?.config?.maxMembers !== MAX_MEMBERS) {
    console.error(`maxMembers не применился: ${entry?.config?.maxMembers}`);
    process.exit(2);
  }
  if (MAX_MEMBERS !== null) console.log(`maxMembers = ${entry.config.maxMembers}`);
}

const bytesBefore = Buffer.byteLength(patch, 'utf8');
const bytesAfter = Buffer.byteLength(nextPatch, 'utf8');
console.log(`патч: ${bytesBefore} -> ${bytesAfter} байт (UTF-8)`);

if (DRY) {
  console.log('dry-run: файл не изменён');
  process.exit(0);
}

const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const backup = `${PATCH}.bak-studio-${stamp}`;
copyFileSync(PATCH, backup);
writeFileSync(PATCH, nextPatch, 'utf8');
console.log(`записано: ${PATCH}`);
console.log(`бэкап:   ${backup}`);
