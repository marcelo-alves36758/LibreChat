const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
const yaml = require('js-yaml');

function checkPublic(root = process.cwd()) {
  const files = execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8' })
    .split('\0')
    .filter(Boolean);
  const issues = [];
  for (const file of files) {
    if (!fs.existsSync(`${root}/${file}`)) continue; // deleted in the proposed change
    const isExample = /(?:^|\.)example(?:\.|$)/.test(file);
    if (
      /(^|\/)(private|secrets)\//.test(file) ||
      (!isExample &&
        (/(^|\/)\.env(?:\.|$)|\.env$|\.private\.|\.local\.(?:ya?ml|json|env)$/.test(file) ||
          /(^|\/)librechat\.ya?ml$|(^|\/)auth\.json$/.test(file)))
    ) {
      issues.push(`${file}: private runtime file must not be tracked`);
    }
    const content = fs.readFileSync(`${root}/${file}`);
    if (content.includes(0)) continue;
    // Catch tenant metadata wherever it is pasted, including documentation and fixtures.
    if (
      /https:\/\/[a-z0-9-]*(?:hero|ero)[a-z0-9-]*\.(?:openai\.azure\.com|services\.ai\.azure\.com|cognitiveservices\.azure\.com)/i.test(
        content.toString(),
      )
    ) {
      issues.push(`${file}: corporate Azure hostname must be private`);
    }
  }
  const config = yaml.load(fs.readFileSync(`${root}/custom/librechat.example.yaml`, 'utf8'));
  function walk(value, key = '') {
    if (Array.isArray(value)) return value.forEach((v) => walk(v, key));
    if (value && typeof value === 'object')
      return Object.entries(value).forEach(([k, v]) => walk(v, k));
    if (
      ['baseURL', 'instanceName', 'deploymentName', 'agent_id', 'mistralModel'].includes(key) &&
      typeof value === 'string' &&
      !value.includes('REPLACE_') &&
      !/^\$\{[A-Z0-9_]+\}$/.test(value)
    ) {
      issues.push(
        `custom/librechat.example.yaml: ${key} must be a placeholder or environment reference`,
      );
    }
  }
  walk(config);
  if (issues.length) throw new Error(issues.join('\n'));
}

if (require.main === module) {
  checkPublic();
  console.log(
    'Public configuration contains placeholders only; private runtime paths are not tracked.',
  );
}
module.exports = { checkPublic };
