import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, copyFileSync, rmSync, mkdtempSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Read-only, pinned upstream source. Never loads .env, production config, tokens,
// security bypasses or deployed services. All metadata calls are mocked below.
const sha = '77665388051de9685632db41c5222e01dbfcacc7';
const root = dirname(fileURLToPath(import.meta.url));
mkdirSync(join(root, '.work'), { recursive: true });
const work = mkdtempSync(join(root, '.work', 'audit-'));
const put = (path, text) => {
  const target = join(work, path);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, text);
};
try {
  for (const path of ['src/routes/media.ts', 'src/services/tmdb.ts', 'src/services/cache.ts',
    'src/utils/countries.ts', 'src/types/models.ts']) {
    const json = JSON.parse(execFileSync('gh', ['api', `repos/sluvskii/sloosh-api/contents/${path}?ref=${sha}`], { encoding: 'utf8' }));
    put(path, Buffer.from(json.content, 'base64'));
  }
  put('package.json', '{"type":"module"}');
  put('src/config.ts', `export const config = { tmdb: {
    token: '', baseUrl: 'https://catalog.invalid/3', defaultLanguage: 'ru-RU',
    imageBaseUrl: 'https://images.invalid' } };`);
  put('src/services/overrides.ts', `
    export const applyOverridesToDetails = (item: any) => item;
    export const applyOverridesToMedia = (item: any) => item;
    export const applyOverridesToMediaResponse = (item: any) => item;
    export const getAllOverrides = () => [];
    export const fetchRemoteOverridesIfNeeded = async () => {};
    export const saveOverride = async () => { throw Error('Writes forbidden in audit'); };
    export const deleteOverride = async () => { throw Error('Writes forbidden in audit'); };
    export type MediaArtworkOverrideDto = Record<string, unknown>;
  `);
  put('src/services/alloha.ts', `
    export const resolveAlloha = async () => { throw Error('Playback forbidden in audit'); };
    export const resolveTmdbInfoByKp = async () => { throw Error('Playback forbidden in audit'); };
  `);
  copyFileSync(join(root, 'cases.ts'), join(work, 'cases.ts'));
  console.log(`Read-only source audit: sluvskii/sloosh-api@${sha}`);
  const result = spawnSync(process.execPath, ['--import', 'tsx', join(work, 'cases.ts')], {
    cwd: root, stdio: 'inherit', env: process.env,
  });
  process.exitCode = result.status ?? 1;
} finally {
  rmSync(work, { recursive: true, force: true });
}
