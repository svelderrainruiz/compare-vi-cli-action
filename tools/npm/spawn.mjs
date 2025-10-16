function resolveComSpec(env) {
  const candidates = ['ComSpec', 'COMSPEC', 'comspec'];
  for (const key of candidates) {
    const value = env[key];
    if (typeof value === 'string' && value.trim() !== '') {
      return value;
    }
  }
  return undefined;
}

export function createNpmLaunchSpec(npmArgs, env = process.env) {
  if (process.platform === 'win32') {
    const comSpec = resolveComSpec(env) ?? 'cmd.exe';
    return {
      command: comSpec,
      args: ['/d', '/s', '/c', 'npm', ...npmArgs],
    };
  }

  return {
    command: 'npm',
    args: npmArgs,
  };
}
