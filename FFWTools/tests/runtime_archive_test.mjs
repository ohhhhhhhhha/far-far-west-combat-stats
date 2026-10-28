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
