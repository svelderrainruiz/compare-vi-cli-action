const registry = require('./registry');

function listProviderMetadata() {
  return registry.listProviders().map((provider) => ({
    id: provider.id,
    displayName: provider.displayName || provider.id,
    docsUrl: provider.docsUrl || null,
    disabled: typeof provider.isAvailable === 'function' ? !provider.isAvailable() : false,
    status: typeof provider.getStatus === 'function' ? provider.getStatus() : undefined
  }));
}

module.exports = {
  registerProvider: registry.registerProvider,
  unregisterProvider: registry.unregisterProvider,
  getProvider: registry.getProvider,
  listProviders: registry.listProviders,
  listProviderMetadata,
  getActiveProvider: registry.getActiveProvider,
  getActiveProviderId: registry.getActiveProviderId,
  setActiveProvider: registry.setActiveProvider,
  onDidChangeActiveProvider: registry.onDidChangeActiveProvider
};
