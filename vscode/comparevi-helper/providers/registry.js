const providers = new Map();

function registerProvider(provider) {
  if (!provider || typeof provider.id !== 'string') {
    throw new Error('Provider must define a string id');
  }
  if (providers.has(provider.id)) {
    throw new Error(`Provider ${provider.id} already registered`);
  }
  providers.set(provider.id, provider);
  return provider;
}

function unregisterProvider(id) {
  const existing = providers.get(id);
  if (existing?.deactivate) {
    try { existing.deactivate(); } catch (_) { /* noop */ }
  }
  providers.delete(id);
}

function getProvider(id) {
  return providers.get(id);
}

function listProviders() {
  return Array.from(providers.values());
}

module.exports = {
  registerProvider,
  unregisterProvider,
  getProvider,
  listProviders
};
