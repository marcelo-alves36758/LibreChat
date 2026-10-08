// Synthetic configuration for offline tests only; never use it for deployment.
const fs = require('node:fs');
const path = require('node:path');
const yaml = require('js-yaml');

const example = fs.readFileSync(
  path.resolve(__dirname, '../../custom/librechat.example.yaml'),
  'utf8',
);
function fixture() {
  const config = yaml.load(
    example.replace(/REPLACE_[A-Z0-9_]+/g, (key) =>
      key.endsWith('_AGENT_ID')
        ? `agent_test_${key.slice(8).toLowerCase()}`
        : `test-${key.slice(8).toLowerCase().replace(/_/g, '-')}`,
    ),
  );
  const env = {};
  for (const match of example.matchAll(/\$\{([A-Z_][A-Z0-9_]*)\}/g)) {
    env[match[1]] = match[1].endsWith('_URL') ? 'https://example.invalid/v1' : 'test-only-value';
  }
  return { config, env };
}
if (require.main === module) {
  const dir = process.argv[2];
  if (!dir || !path.isAbsolute(dir)) throw new Error('An absolute temporary directory is required');
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const { config, env } = fixture();
  fs.writeFileSync(path.join(dir, 'config.yaml'), yaml.dump(config), { mode: 0o600, flag: 'wx' });
  fs.writeFileSync(
    path.join(dir, 'runtime.env'),
    Object.entries(env)
      .map(([k, v]) => `${k}=${v}`)
      .join('\n'),
    { mode: 0o600, flag: 'wx' },
  );
}
module.exports = { example, fixture };
