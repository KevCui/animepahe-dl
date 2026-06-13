#!/usr/bin/env node
/**
 * unpacker.cjs
 * A secure, static Dean Edwards packer decoder.
 * Reads packed JS from stdin and prints all unpacked blocks to stdout.
 * Zero-dependency, no eval/code-execution.
 */

const fs = require('fs');

function unpackAll(packed) {
  const packerRegex = /}\s*\(\s*(['"])(.*?)\1\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(['"])(.*?)\5\.split\(\s*['"]\|['"]\s*\)/gs;
  const matches = [...packed.matchAll(packerRegex)];

  if (matches.length === 0) {
    throw new Error('Failed to match any Dean Edwards packed JS blocks.');
  }

  let results = [];
  for (const match of matches) {
    let p = match[2];
    const a = parseInt(match[3], 10);
    let c = parseInt(match[4], 10);
    const k = match[6].split('|');

    const encode = (val) => {
      return (val < a ? '' : encode(Math.floor(val / a))) + 
             ((val = val % a) > 35 ? String.fromCharCode(val + 29) : val.toString(36));
    };

    while (c--) {
      if (k[c]) {
        const baseVal = encode(c);
        const escapedBaseVal = baseVal.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&');
        const reg = new RegExp('\\b' + escapedBaseVal + '\\b', 'g');
        p = p.replace(reg, k[c]);
      }
    }
    results.push(p);
  }

  return results.join('\n');
}

function main() {
  try {
    const input = fs.readFileSync(0, 'utf-8');
    if (!input || !input.trim()) {
      process.exit(0);
    }
    const unpacked = unpackAll(input);
    console.log(unpacked);
  } catch (err) {
    console.error('Error unpacking code:', err.message);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}
