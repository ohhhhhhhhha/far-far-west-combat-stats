import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';

const signaturePath = 'GameRoot/FarFarWest/Binaries/Win64/ue4ss/UE4SS_Signatures/ProcessLocalScriptFunction.lua';

// A clean machine must receive the game-specific scan override at the loader's
// working-directory path. Existing local overrides must not be a prerequisite.
export async function verifyRuntimeArchive({ archive, JSZip, destination }) {
  const zip = await JSZip.loadAsync(await fs.readFile(archive));
  assert.ok(zip.file(signaturePath), 'Fresh installation lacks ProcessLocalScriptFunction scan override');
  const files = Object.values(zip.files).filter(entry => !entry.dir && entry.name.startsWith('GameRoot/'));
  for (const entry of files) {
    const relative = entry.name.slice('GameRoot/'.length);
    assert.ok(!relative.split(/[\\/]/).includes('..'), 'Archive path escapes game directory');
    assert.ok(!/^(?:[A-Za-z]:|\/)/.test(relative), 'Archive includes an absolute installation path');
    assert.ok(!/(?:^|\/)(?:UE4SS\.dll|dwmapi\.dll|UE4SS-settings\.ini|mods\.txt)$/.test(relative),
      'Mod archive must preserve the installed loader and user configuration');
    const target = path.join(destination, relative);
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, await entry.async('nodebuffer'));
  }
  const installed = path.join(destination, signaturePath.slice('GameRoot/'.length));
  assert.ok((await fs.stat(installed)).size > 0, 'Installed scan override is empty');
  return { runtimeFiles: files.length, signatureInstalled: true };
}

// The supported Nexus package owns the loader, settings and game signatures.
// Content-mod updates must leave that dependency and existing Mod Data intact.
export async function verifyNexusRuntimeArchive({ archive, frameworkRoot, JSZip, destination }) {
  const framework = new Map();
  async function stageFramework(directory, relative = '') {
    for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
      const rel = relative ? relative + '/' + entry.name : entry.name;
      if (entry.isDirectory()) await stageFramework(path.join(directory, entry.name), rel);
      else {
        const bytes = await fs.readFile(path.join(directory, entry.name));
        const target = path.join(destination, 'FarFarWest/Binaries/Win64', rel);
        await fs.mkdir(path.dirname(target), { recursive: true });
        await fs.writeFile(target, bytes);
        framework.set('FarFarWest/Binaries/Win64/' + rel, bytes);
      }
    }
  }
  await stageFramework(frameworkRoot);
  const zip = await JSZip.loadAsync(await fs.readFile(archive), { checkCRC32: true });
  const metadata = JSON.parse(await zip.file('package.json').async('string'));
  assert.ok(/^FFW[A-Za-z0-9_-]+$/.test(metadata.id), 'Unexpected component id');
  const preservedData = path.join(destination, 'FarFarWest/Binaries/Win64/ue4ss/Mods', metadata.id, 'Data/.preservation-test');
  await fs.mkdir(path.dirname(preservedData), { recursive: true });
  await fs.writeFile(preservedData, 'existing local preferences');
  let runtimeFiles = 0;
  for (const entry of Object.values(zip.files)) {
    if (!entry.name.startsWith('GameRoot/')) continue;
    const rel = entry.name.slice('GameRoot/'.length);
    assert.ok(!path.isAbsolute(rel) && !rel.split(/[\\/]/).includes('..'), 'Invalid installation path');
    if (!rel) continue;
    const target = path.join(destination, rel);
    if (entry.dir) { await fs.mkdir(target, { recursive: true }); continue; }
    assert.ok(!framework.has(rel), 'Content Mod overwrites Nexus framework file: ' + rel);
    assert.ok(!/\/Data\//.test(rel), 'Runtime package ships or overwrites local Data');
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, await entry.async('nodebuffer'));
    runtimeFiles++;
  }
  for (const [relative, bytes] of framework) {
    assert.ok((await fs.readFile(path.join(destination, relative))).equals(bytes), 'Nexus framework changed: ' + relative);
  }
  assert.equal(await fs.readFile(preservedData, 'utf8'), 'existing local preferences');
  assert.ok((await fs.stat(path.join(destination, signaturePath.slice('GameRoot/'.length)))).size > 0,
    'Combined installation lacks the Nexus startup signature');
  return { runtimeFiles, frameworkFilesPreserved: framework.size, localDataPreserved: true, dependencySignaturePresent: true };
}
