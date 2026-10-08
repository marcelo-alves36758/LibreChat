const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

function checkBuild(root = process.cwd(), image = false) {
  const read = (file) => fs.readFileSync(path.join(root, file));
  assert.deepEqual(
    read('client/dist/custom.css'),
    read('custom/custom.css'),
    'Ero CSS changed during build',
  );
  const html = read('client/dist/index.html').toString();
  const head = html.split('</head>')[0];
  const styles = head.match(/<link\b[^>]*rel=["']stylesheet["'][^>]*>/g) ?? [];
  assert.ok(
    styles.length > 0 && /href=["']\/custom\.css\?v=/.test(styles.at(-1)),
    'Ero CSS must be the last stylesheet in the head',
  );
  assert.equal(styles.filter((tag) => /href=["']\/custom\.css\?v=/.test(tag)).length, 1);
  if (image) {
    for (const file of [
      '.env',
      'librechat.yaml',
      'custom/librechat.yaml',
      'config/librechat.yaml',
      'private',
      'secrets',
      'custom/private',
      'custom/secrets',
      'custom/librechat.example.yaml',
      'uploads/hero-canary',
      'api/data/hero-canary',
      'logs/hero-canary',
    ]) {
      assert.ok(!fs.existsSync(path.join(root, file)), 'Private material was baked into the image');
    }
  }
}

if (require.main === module) {
  checkBuild(process.cwd(), process.argv.includes('--image'));
  console.log('Hero build checks passed: original Ero CSS present and loaded last.');
}
module.exports = { checkBuild };
