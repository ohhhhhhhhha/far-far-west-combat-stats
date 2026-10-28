import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { inspectPE } from './inspect-pe.mjs';
// Filesystem preparation only: no processes, shell, game launch or deployment.
export async function prepareNative({ root, frameworkDll }) {
 const dir=path.join(root,'FFWTools/src/FFWTeamSync');
 const image=await fs.readFile(frameworkDll);
 const hash=createHash('sha256').update(image).digest('hex');
 if(hash!=='c273e7228687b647226fd63d7ca65888d313ece6be18996ec1320d00a5efe1f8')throw Error('Use the documented Nexus 3.0.1.1183 framework DLL for this build.');
 const pe=inspectPE(image);if(pe.machine!==0x8664||pe.exports.length<100)throw Error('Unexpected UE4SS x64 exports');
 const required=JSON.parse(await fs.readFile(new URL('./ue4ss-imports.json',import.meta.url),'utf8'));
 for(const name of required)if(!pe.exports.includes(name))throw Error('Required UE4SS export missing: '+name);
 const out=path.join(dir,'build-lan');await fs.mkdir(path.join(out,'header-overrides/GUI'),{recursive:true});
 await fs.writeFile(path.join(out,'ImportAnchor.cpp'),'// Empty translation unit for the MSBuild librarian task.\n');
 await fs.writeFile(path.join(out,'UE4SS.def'),'LIBRARY UE4SS.dll\nEXPORTS\n'+required.join('\n')+'\n');
 const original=path.join(root,'FFWTools/vendor/team-sync-ue4ss-1181/source/RE-UE4SS-8333063595fa3c49ad307f3b0f732accbb760d25/UE4SS/include/GUI/GUITab.hpp');
 const header=(await fs.readFile(original,'utf8')).replace('#include <GUI/GUI.hpp>','// Unused circular GUI.hpp include omitted for this non-GUI bridge.');
 await fs.writeFile(path.join(out,'header-overrides/GUI/GUITab.hpp'),header);
 return {directory:out,frameworkSha256:hash,exports:pe.exports.length};
}
