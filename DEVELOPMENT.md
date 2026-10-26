# Development

The repository is self-contained for Lua source and offline tests. Runtime helper copies under FFWStats/Scripts belong to this component; it does not import another Mod repository.

- Lua: `FFWTools/src/FFWStats/Scripts`
- Native Steam bridge: `FFWTools/src/FFWTeamSync`
- Offline tests: `FFWTools/tests`
- Runtime payload allowlist: `package-manifest.json`

Lua tests target Lua 5.4 and use synthetic fixtures. Run each `*_test.lua` separately from the repository root. They write temporary files beneath `FFWTools/tests`; never use a live game's Data directory for tests. Native transport and ABI checks require the dependencies in NATIVE-BUILD.md.

For a JavaScript-hosted environment, import `run-tests.mjs` and call `runTests({root, LuaFactory, wasmPath})`. The included package declares Wasmoon 1.16.0 and JSZip 3.10.1 as development dependencies. The harness mounts only repository Lua source and test fixtures in a virtual filesystem.

Import `package.mjs` and call `buildRelease({root, outputDirectory, JSZip})` to produce the allowlisted runtime ZIP, source ZIP and checksums. A compiled `FFWTools/src/FFWTeamSync/build/main.dll` is required; native build outputs are not part of the source ZIP. The packaging API does not install, launch or upload anything.

Release validation: exported Lua tests run in isolated Lua 5.4 WASM with Windows rename behavior; runtime Lua/DLL hashes are compared with the installed build used for solo acceptance. The native DLL is reused without recompilation in this release. That evidence does not establish full multiplayer event coverage.
