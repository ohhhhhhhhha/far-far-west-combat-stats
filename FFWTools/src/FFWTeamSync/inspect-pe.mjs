// Static inspection only; does not load or execute the PE image.
export function inspectPE(b) {
  const pe = b.readUInt32LE(0x3c);
  if (b.toString('ascii', pe, pe + 4) !== 'PE\0\0') throw Error('not PE');
  const opt = pe + 24;
  const x64 = b.readUInt16LE(opt) === 0x20b;
  const dirs = opt + (x64 ? 112 : 96);
  const sections = [];
  for (let i = 0, p = opt + b.readUInt16LE(pe + 20); i < b.readUInt16LE(pe + 6); i++, p += 40) {
    sections.push({name: b.toString('ascii', p, p + 8).replace(/\0/g, ''),
      va: b.readUInt32LE(p + 12), virtualSize: b.readUInt32LE(p + 8),
      rawSize: b.readUInt32LE(p + 16), raw: b.readUInt32LE(p + 20)});
  }
  const offset = r => {
    const s = sections.find(s => r >= s.va && r < s.va + Math.max(s.virtualSize, s.rawSize));
    return s ? s.raw + r - s.va : r;
  };
  const textAt = p => b.toString('ascii', p, b.indexOf(0, p));
  const exports = [];
  const er = b.readUInt32LE(dirs);
  if (er) {
    const ep = offset(er), count = b.readUInt32LE(ep + 24), names = offset(b.readUInt32LE(ep + 32));
    for (let i = 0; i < count; i++) exports.push(textAt(offset(b.readUInt32LE(names + i * 4))));
  }
  const imports = {};
  const ir = b.readUInt32LE(dirs + 8);
  if (ir) {
    for (let p = offset(ir); b.readUInt32LE(p) || b.readUInt32LE(p + 12); p += 20) {
      const name = textAt(offset(b.readUInt32LE(p + 12)));
      const names = [];
      const thunk = offset(b.readUInt32LE(p) || b.readUInt32LE(p + 16));
      for (let q = thunk; ; q += x64 ? 8 : 4) {
        const v = x64 ? b.readBigUInt64LE(q) : BigInt(b.readUInt32LE(q));
        if (!v) break;
        if (v & (x64 ? 0x8000000000000000n : 0x80000000n)) names.push('#' + String(v & 0xffffn));
        else names.push(textAt(offset(Number(v)) + 2));
      }
      imports[name] = names;
    }
  }
  return {machine: b.readUInt16LE(pe + 4), exports, imports, sections};
}
