import * as fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const moduleRoot = path.dirname(fileURLToPath(import.meta.url));
const sha256 = data => createHash('sha256').update(data).digest('hex');
const json = value => Buffer.from(JSON.stringify(value, null, 2) + '\n');

function within(root, relative) {
  if (path.isAbsolute(relative) || relative.split(/[\\/]/).includes('..')) {
    throw new Error(`Invalid package path: ${relative}`);
  }
  return path.join(root, relative);
}

// Creates local release files only. Does not install, launch, upload or modify saves.
export async function buildRelease({ root = moduleRoot, outputDirectory, JSZip } = {}) {
  const Zip = JSZip ?? (await import('jszip')).default;
  const spec = JSON.parse(await fs.readFile(path.join(root, 'package-manifest.json'), 'utf8'));
  const release = JSON.parse(await fs.readFile(path.join(root, 'release.json'), 'utf8'));
  const output = path.resolve(outputDirectory ?? path.join(root, 'dist', release.version));
  try { await fs.access(output); throw new Error('Output exists; choose a new directory'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }

  const inputs = new Map();
  for (const relative of new Set([...spec.sourceFiles, ...spec.files.map(f => f.source)])) {
    inputs.set(relative, await fs.readFile(within(root, relative)));
  }

  const runtime = new Zip();
  const payload = [];
  for (const entry of spec.files) {
    const data = inputs.get(entry.source);
    runtime.file(entry.path, data);
    if (entry.path.startsWith('GameRoot/')) payload.push({ path: entry.path, sha256: sha256(data) });
  }
  for (const directory of spec.directories) runtime.folder(directory);
  for (const mod of spec.mods) {
    const marker = spec.modRoot + '/' + mod + '/enabled.txt';
    runtime.file(marker, '');
    payload.push({path: marker, sha256: sha256(Buffer.alloc(0))});
  }
  runtime.file('package.json', json({
    schemaVersion: 1, id: spec.id, version: release.version, framework: 'UE4SS',
    installation: 'manual-copy', copyFolder: 'GameRoot', mods: spec.mods,
    directories: spec.directories, obsoleteFiles: spec.obsoleteFiles,
    files: payload, channel: release.channel,
  }));

  const source = new Zip();
  for (const relative of spec.sourceFiles) source.file(relative, inputs.get(relative));
  await fs.mkdir(output, { recursive: true });
  const artifacts = [];
  for (const [zip, name, kind] of [
    [runtime, `${spec.id}-${release.version}.zip`, 'runtime'],
    [source, `${spec.id}-source-${release.version}.zip`, 'source'],
  ]) {
    const data = await zip.generateAsync({
      type: 'nodebuffer', compression: 'DEFLATE', compressionOptions: { level: 6 },
    });
    await fs.writeFile(path.join(output, name), data);
    artifacts.push({ file: name, bytes: data.length, sha256: sha256(data), kind });
  }
  await fs.writeFile(path.join(output, 'SHA256SUMS.txt'),
    artifacts.map(a => `${a.sha256}  ${a.file}`).join('\n') + '\n');
  await fs.writeFile(path.join(output, 'release-manifest.json'), json({
    id: spec.id, version: release.version, framework: 'UE4SS',
    installation: 'manual-copy', artifacts,
  }));
  return { output, id: spec.id, version: release.version, artifacts };
}
