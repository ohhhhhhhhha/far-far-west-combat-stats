import * as fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const moduleRoot = path.dirname(fileURLToPath(import.meta.url));

export async function runTests({ root = moduleRoot, LuaFactory, wasmPath } = {}) {
  const Factory = LuaFactory ?? (await import('wasmoon')).LuaFactory;
  const factory = new Factory(wasmPath);
  const testDirectory = 'FFWTools/tests';
  const tests = (await fs.readdir(path.join(root, testDirectory)))
    .filter(name => name.endsWith('_test.lua')).sort();
  for (const directory of ['FFWTools/src/FFWStats/Scripts', testDirectory]) {
    for (const name of await fs.readdir(path.join(root, directory))) {
      if (name.endsWith('.lua')) {
        await factory.mountFile('/' + directory + '/' + name,
          await fs.readFile(path.join(root, directory, name)));
      }
    }
  }
  await factory.mountFile('/FFWTools/tests/Data/.fixture', '');
  const results = [];
  for (const name of tests) {
    const lua = await factory.createEngine();
    const output = [];
    lua.global.set('print', (...args) => output.push(args.map(String).join(' ')));
    try {
      // Match Windows rename behavior; Wasmoon's overwrite semantics differ.
      await lua.doString(`
        local rename = os.rename
        os.rename = function(from, to)
          local file = io.open(to, 'rb')
          if file then file:close(); return nil, 'destination exists', 17 end
          return rename(from, to)
        end
        os.exit = function(code) error('test exit ' .. tostring(code)) end
        dofile(${JSON.stringify(testDirectory + '/' + name)})
      `);
      results.push({ file: name, passed: true, output });
    } catch (error) {
      results.push({ file: name, passed: false, error: error.message, output });
    } finally {
      lua.global.close();
    }
  }
  return results;
}
