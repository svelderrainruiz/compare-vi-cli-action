export function createSanitizedNpmEnv(baseEnv = process.env) {
  const env = { ...baseEnv };

  const proxyMappings = [
    { source: 'npm_config_http_proxy', target: 'npm_config_proxy' },
    { source: 'NPM_CONFIG_HTTP_PROXY', target: 'NPM_CONFIG_PROXY' },
  ];

  for (const mapping of proxyMappings) {
    const value = env[mapping.source];
    if (typeof value === 'string' && value.trim() !== '') {
      if (!env[mapping.target]) {
        env[mapping.target] = value;
      }
    }
    delete env[mapping.source];
  }

  return env;
}
