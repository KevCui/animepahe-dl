#!/usr/bin/env node
/**
 * unpacker.cjs
 * A secure, static Dean Edwards packer decoder.
 * Reads packed JS from stdin and prints the unpacked code to stdout.
 * Zero-dependency, no eval/code-execution.
 */

const fs = require('fs');

function unpack(packed) {
  // Regex to extract the packer arguments: p, a, c, k
  // Format: }('payload', a, c, 'dictionary'.split('|'))
  const packerRegex = /}\s*\(\s*(['"])(.*?)\1\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(['"])(.*?)\5\.split\(\s*['"]\|['"]\s*\)/s;
  const match = packed.match(packerRegex);

  if (!match) {
    throw new Error('Failed to match Dean Edwards packed JS format.');
  }

  let p = match[2];
  const a = parseInt(match[3], 10);
  let c = parseInt(match[4], 10);
  const k = match[6].split('|');

  const encode = (val) => {
    return (val < a ? '' : encode(Math.floor(val / a))) + 
           ((val = val % a) > 35 ? String.fromCharCode(val + 29) : val.toString(36));
  };

  // Unpack by replacing all base-A strings with their dictionary values
  // We decrement c and replace its base-A representation
  while (c--) {
    if (k[c]) {
      const baseVal = encode(c);
      // Escape special characters in baseVal for Regex
      const escapedBaseVal = baseVal.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&');
      const reg = new RegExp('\\b' + escapedBaseVal + '\\b', 'g');
      p = p.replace(reg, k[c]);
    }
  }

  return p;
}

function main() {
  try {
    const input = fs.readFileSync(0, 'utf-8');
    if (!input || !input.trim()) {
      process.exit(0);
    }
    const unpacked = unpack(input);
    console.log(unpacked);
  } catch (err) {
    console.error('Error unpacking code:', err.message);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}
