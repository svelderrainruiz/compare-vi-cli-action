const { EventEmitter } = require('events');

const providers = new Map();
let activeProviderId;
const events = new EventEmitter();

function registerProvider(provider) {
  if (!provider || typeof provider.id !== 'string') {
    throw new Error('Provider must define a string id');
  }
  if (providers.has(provider.id)) {
    throw new Error(`Provider ${provider.id} already registered`);
  }
  providers.set(provider.id, provider);
  if (!activeProviderId) {
    activeProviderId = provider.id;
    events.emit('activeChanged', activeProviderId);
  }
  events.emit('registered', provider.id);
  return provider;
}

function unregisterProvider(id) {
  const existing = providers.get(id);
  if (existing?.deactivate) {
    try { existing.deactivate(); } catch (_) { /* noop */ }
  }
  providers.delete(id);
  events.emit('unregistered', id);
  if (activeProviderId === id) {
    const next = providers.keys().next();
    const fallback = next && !next.done ? next.value : undefined;
    activeProviderId = fallback;
    events.emit('activeChanged', activeProviderId);
  }
}

function getProvider(id) {
  return providers.get(id);
}

function listProviders() {
  return Array.from(providers.values());
}

function setActiveProvider(id) {
  if (!providers.has(id)) {
    return false;
  }
  if (activeProviderId !== id) {
    activeProviderId = id;
    events.emit('activeChanged', activeProviderId);
  }
  return true;
}

function getActiveProviderId() {
  return activeProviderId;
}

function getActiveProvider() {
  return activeProviderId ? providers.get(activeProviderId) : undefined;
}

function onDidChangeActiveProvider(listener) {
  events.on('activeChanged', listener);
  return {
    dispose: () => events.removeListener('activeChanged', listener)
  };
}

module.exports = {
  registerProvider,
  unregisterProvider,
  getProvider,
  listProviders,
  setActiveProvider,
  getActiveProvider,
  getActiveProviderId,
  onDidChangeActiveProvider
};
