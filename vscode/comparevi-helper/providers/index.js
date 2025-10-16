const registry = require('./registry');

function listProviderMetadata() {
  return registry.listProviders().map((provider) => ({
    id: provider.id,
    displayName: provider.displayName || provider.id
  }));
}

function getActiveProvider() {
  const providers = registry.listProviders();
  return providers.length ? providers[0] : undefined;
}

module.exports = {
  registerProvider: registry.registerProvider,
  unregisterProvider: registry.unregisterProvider,
  getProvider: registry.getProvider,
  listProviders: registry.listProviders,
  listProviderMetadata,
  getActiveProvider
};
