const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const yaml = require('js-yaml');
const { spawnSync } = require('node:child_process');
const { validateAzureGroups, mapModelToAzureConfig } = require('librechat-data-provider');
const { readConfig, validateConfig } = require('./validate.cjs');
const { checkBuild } = require('./check-build.cjs');
const { example, fixture } = require('./fixture.cjs');

test('example requires private values and cannot pass preflight', () => {
  assert.throws(() => validateConfig(yaml.load(example), {}), /placeholders/);
});
test('native schema, both Azure groups, OCR, speech, memory and three Hero agents survive', () => {
  const { config, env } = fixture();
  assert.equal(validateConfig(config, env), config);
  assert.equal(config.endpoints.azureOpenAI.groups.length, 2);
  assert.equal(validateAzureGroups(config.endpoints.azureOpenAI.groups).isValid, true);
  assert.equal(config.ocr.strategy, 'azure_mistral_ocr');
  assert.ok(config.speech.stt.azureOpenAI.deploymentName);
  assert.ok(config.speech.tts.azureOpenAI.deploymentName);
  assert.equal(config.memory.agent.model, 'gpt-5-mini');
  assert.equal(config.modelSpecs.list.length, 3);
  assert.equal(config.interface.title, 'Hero');
});
test('missing environment or inline credentials fail without leaking values', () => {
  const { config, env } = fixture();
  delete env.AZURE_API_KEY;
  assert.throws(() => validateConfig(config, env), /referenced environment/);
  config.ocr.apiKey = 'canary-do-not-print';
  assert.throws(
    () => validateConfig(config, env),
    (error) => /credentials in YAML/.test(error.message) && !error.message.includes('canary'),
  );
});
test('the native Azure mapper resolves primary and secondary deployments and keys', () => {
  const { config, env } = fixture();
  const saved = { ...process.env };
  try {
    Object.assign(process.env, env);
    const { groupMap, modelGroupMap } = validateAzureGroups(config.endpoints.azureOpenAI.groups);
    for (const group of config.endpoints.azureOpenAI.groups) {
      for (const [modelName, model] of Object.entries(group.models)) {
        const mapped = mapModelToAzureConfig({ modelName, groupMap, modelGroupMap });
        assert.equal(mapped.azureOptions.azureOpenAIApiDeploymentName, model.deploymentName);
        assert.equal(mapped.azureOptions.azureOpenAIApiInstanceName, group.instanceName);
        assert.equal(mapped.azureOptions.azureOpenAIApiKey, 'test-only-value');
        assert.equal(mapped.baseURL, group.baseURL);
      }
    }
  } finally {
    for (const key of Object.keys(env)) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  }
});
test('CLI uses private dotenv, honors process precedence and returns failure without config', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hero-cli-'));
  try {
    const { config, env } = fixture();
    const file = path.join(dir, 'config.yaml');
    fs.writeFileSync(file, yaml.dump(config), { mode: 0o600 });
    fs.writeFileSync(
      path.join(dir, '.env'),
      Object.entries(env)
        .map(([k, v]) => `${k}=${v}`)
        .join('\n'),
      { mode: 0o600 },
    );
    const run = (extra) =>
      spawnSync(process.execPath, [path.join(__dirname, 'validate.cjs')], {
        cwd: dir,
        env: { PATH: process.env.PATH, CONFIG_PATH: file, ...extra },
        encoding: 'utf8',
      });
    assert.equal(run({}).status, 0);
    const rejected = run({ AZURE_API_KEY: 'CHANGE_ME' });
    assert.equal(rejected.status, 1);
    assert.ok(!`${rejected.stdout}${rejected.stderr}`.includes('CHANGE_ME'));
    assert.equal(run({ CONFIG_PATH: path.join(dir, 'missing.yaml') }).status, 1);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
test('nested Azure endpoints, duplicate models and missing instance names fail', () => {
  for (const mutation of [
    (c) => {
      c.endpoints.agents.azureOpenAI = c.endpoints.azureOpenAI;
      delete c.endpoints.azureOpenAI;
    },
    (c) => {
      c.endpoints.azureOpenAI.groups[1].models = c.endpoints.azureOpenAI.groups[0].models;
    },
    (c) => {
      delete c.endpoints.azureOpenAI.groups[0].instanceName;
    },
  ]) {
    const { config, env } = fixture();
    mutation(config);
    assert.throws(() => validateConfig(config, env), /Azure|azureOpenAI/);
  }
});
test('agent IDs cannot rely on interpolation unsupported by the catalog', () => {
  const { config, env } = fixture();
  config.modelSpecs.list[0].preset.agent_id = '${TEST_AGENT_ID}';
  env.TEST_AGENT_ID = 'agent_test_only';
  assert.throws(() => validateConfig(config, env), /concrete agent ID/);
});
test('a missing memory model or title model fails before backend startup', () => {
  for (const field of ['memory', 'title']) {
    const { config, env } = fixture();
    if (field === 'memory') config.memory.agent.model = 'missing';
    else config.endpoints.all.titleModel = 'missing';
    assert.throws(() => validateConfig(config, env), /model must exist/);
  }
});
test('private file is explicit; missing and invalid YAML errors are redacted', () => {
  assert.throws(() => readConfig(), /absolute local/);
  assert.throws(() => readConfig('https://example.invalid/config'), /absolute local/);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hero-config-'));
  try {
    const file = path.join(dir, 'config.yaml');
    assert.throws(() => readConfig(file), /missing, unreadable or invalid YAML/);
    fs.writeFileSync(file, 'canary-secret: [broken');
    assert.throws(
      () => readConfig(file),
      (e) => !e.message.includes('canary'),
    );
    fs.writeFileSync(file, yaml.dump(fixture().config), { mode: 0o600 });
    assert.deepEqual(readConfig(file), fixture().config);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
test('build validation detects CSS changes, wrong ordering and baked private files', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hero-build-'));
  try {
    fs.mkdirSync(path.join(dir, 'custom'), { recursive: true });
    fs.mkdirSync(path.join(dir, 'client/dist'), { recursive: true });
    for (const file of ['custom/custom.css', 'client/dist/custom.css'])
      fs.writeFileSync(path.join(dir, file), ':root { --brand: teal; }');
    const html = '<head><link rel="stylesheet" href="/custom.css?v=test" /></head>';
    fs.writeFileSync(path.join(dir, 'client/dist/index.html'), html);
    checkBuild(dir, true);
    fs.writeFileSync(path.join(dir, '.env'), 'canary-private');
    assert.throws(() => checkBuild(dir, true), /Private material/);
    fs.unlinkSync(path.join(dir, '.env'));
    fs.writeFileSync(
      path.join(dir, 'client/dist/index.html'),
      html.replace('</head>', '<link rel="stylesheet" href="/other.css" /></head>'),
    );
    assert.throws(() => checkBuild(dir), /last stylesheet/);
    fs.writeFileSync(path.join(dir, 'client/dist/custom.css'), 'changed');
    assert.throws(() => checkBuild(dir), /CSS changed/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
