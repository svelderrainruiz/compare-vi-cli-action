function pickInitialProviderId(savedProviderId, providersMeta, fallbackId) {
  const defaultId = (typeof fallbackId === 'string' && fallbackId.trim().length)
    ? fallbackId
    : 'comparevi';
  if (!savedProviderId || savedProviderId === defaultId) {
    return { id: defaultId, fallbackReason: null };
  }

  const list = Array.isArray(providersMeta) ? providersMeta : [];
  const match = list.find((meta) => meta && meta.id === savedProviderId);
  if (!match) {
    return { id: defaultId, fallbackReason: 'Provider not registered.' };
  }

  const disabled = !!match.disabled;
  const status = match.status || {};
  const statusOk = typeof status.ok === 'boolean' ? status.ok : !disabled;
  if (disabled || statusOk === false) {
    const message = (typeof status.message === 'string' && status.message.trim().length)
      ? status.message.trim()
      : (disabled ? 'Provider marked unavailable.' : 'Provider health check failed.');
    return { id: defaultId, fallbackReason: message };
  }

  return { id: savedProviderId, fallbackReason: null };
}

module.exports = {
  pickInitialProviderId
};
