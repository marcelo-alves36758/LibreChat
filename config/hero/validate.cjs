const fs = require('node:fs');
const path = require('node:path');
const yaml = require('js-yaml');
const { configSchema, validateAzureGroups } = require('librechat-data-provider');

const envReference = /^\$\{([A-Z_][A-Z0-9_]*)\}$/;
const placeholder = /REPLACE_|CHANGE_ME|YOUR_(?:KEY|RESOURCE|AGENT|DEPLOYMENT)/i;
const credentialField =
  /^(?:api[-_]?key|password|clientSecret|client_secret|access_token|refresh_token|secret|privateKey|Authorization|Ocp-Apim-Subscription-Key)$/i;

function invalid(message) {
  // Messages must describe the rule only, never include values, parser errors or YAML excerpts.
  throw new Error(`Hero configuration: ${message}`);
}

function readConfig(filename) {
  if (!filename || !path.isAbsolute(filename)) {
    invalid('CONFIG_PATH must be an absolute local file path.');
  }
  try {
    if (!fs.statSync(filename).isFile()) invalid('configuration must be a file.');
    return yaml.load(fs.readFileSync(filename, 'utf8'));
  } catch {
    invalid('private configuration is missing, unreadable or invalid YAML.');
  }
}

function validateConfig(config, env = process.env) {
  const result = configSchema.strict().safeParse(config);
  if (!result.success) invalid('LibreChat schema validation failed.');

  // Do not render secrets into YAML. LibreChat resolves supported references at use time.
  function walk(value, key = '') {
    if (Array.isArray(value)) return value.forEach((entry) => walk(entry, key));
    if (value && typeof value === 'object') {
      return Object.entries(value).forEach(([field, entry]) => walk(entry, field));
    }
    if (typeof value !== 'string') return;
    if (placeholder.test(value)) invalid('replace all example placeholders in the private copy.');
    if (credentialField.test(key) && !/^(?:Bearer )?\$\{[A-Z_][A-Z0-9_]*\}$/.test(value)) {
      invalid('credentials in YAML must use environment references.');
    }
    for (const match of value.matchAll(/\$\{([A-Z_][A-Z0-9_]*)\}/g)) {
      const resolved = env[match[1]];
      if (!resolved || !resolved.trim() || placeholder.test(resolved) || resolved.includes('${')) {
        invalid('a referenced environment variable is missing, empty or a placeholder.');
      }
    }
  }
  walk(config);

  if (config.endpoints?.agents?.azureOpenAI || config.endpoints?.agents?.custom) {
    invalid('azureOpenAI and custom belong directly under endpoints, not under agents.');
  }
  const azure = config.endpoints?.azureOpenAI;
  if (!azure?.groups?.length) invalid('Azure OpenAI groups are required.');

  const resolve = (value) => {
    if (typeof value !== 'string') return value;
    const match = value.match(envReference);
    return match ? env[match[1]] : value;
  };
  const groups = azure.groups.map((group) => ({
    ...group,
    instanceName: resolve(group.instanceName),
    baseURL: resolve(group.baseURL),
    deploymentName: resolve(group.deploymentName),
    version: resolve(group.version),
    models: Object.fromEntries(
      Object.entries(group.models).map(([name, model]) => [
        name,
        typeof model === 'boolean'
          ? model
          : {
              ...model,
              deploymentName: resolve(model.deploymentName),
              version: resolve(model.version),
            },
      ]),
    ),
  }));
  if (!validateAzureGroups(groups).isValid) {
    invalid(
      'invalid Azure groups: check unique group/model names, instanceName, deploymentName and version.',
    );
  }
  const modelNames = new Set(groups.flatMap((group) => Object.keys(group.models)));
  if (
    config.memory?.agent?.provider === 'azureOpenAI' &&
    !modelNames.has(config.memory.agent.model)
  ) {
    invalid('the Azure memory model must exist in the configured groups.');
  }
  const all = config.endpoints?.all;
  if (all?.titleEndpoint === 'azureOpenAI' && !modelNames.has(all.titleModel)) {
    invalid('the Azure title model must exist in the configured groups.');
  }

  for (const name of ['hero', 'hero-deep-research', 'hero-prompt-trainer']) {
    const entries = config.modelSpecs?.list?.filter((spec) => spec.name === name) ?? [];
    if (
      entries.length !== 1 ||
      entries[0].preset?.endpoint !== 'agents' ||
      !/^agent_[A-Za-z0-9_-]+$/.test(entries[0].preset?.agent_id ?? '')
    ) {
      invalid('each Hero catalog entry needs a concrete agent ID and the agents endpoint.');
    }
  }
  return config;
}

function main() {
  // Match backend dotenv precedence, without logging its contents.
  require('dotenv').config();
  try {
    validateConfig(readConfig(process.argv[2] || process.env.CONFIG_PATH));
    process.stdout.write(
      'Hero configuration validated (offline; connectivity and agent permissions not checked).\n',
    );
  } catch (error) {
    const safe =
      error instanceof Error && error.message.startsWith('Hero configuration: ')
        ? error.message
        : 'Hero configuration: validation failed.';
    process.stderr.write(`${safe}\n`);
    process.exitCode = 1;
  }
}

if (require.main === module) main();
module.exports = { readConfig, validateConfig };
