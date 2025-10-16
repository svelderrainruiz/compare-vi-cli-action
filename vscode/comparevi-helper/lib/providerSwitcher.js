function createProviderSwitcher({ setActiveProvider, listProviderMetadata, getActiveProviderId, recordTelemetry }) {
  if (typeof setActiveProvider !== 'function') {
    throw new TypeError('setActiveProvider must be a function');
  }
  const metadataFn = typeof listProviderMetadata === 'function' ? listProviderMetadata : (() => []);
  const activeIdFn = typeof getActiveProviderId === 'function' ? getActiveProviderId : (() => undefined);
  const telemetryFn = typeof recordTelemetry === 'function'
    ? recordTelemetry
    : (() => Promise.resolve());

  return async function switchProvider(providerId, { recordTelemetry: shouldRecord = false, telemetryReason } = {}) {
    const previousId = activeIdFn();
    const result = setActiveProvider(providerId);
    if (!result) {
      return false;
    }

    if (shouldRecord && previousId !== providerId) {
      try {
        const metadataList = metadataFn();
        const meta = Array.isArray(metadataList)
          ? metadataList.find((item) => item && item.id === providerId)
          : undefined;
        const available = meta ? !meta.disabled : true;
        const payload = {
          from: previousId ?? null,
          to: providerId,
          available,
          reason: telemetryReason || 'manual'
        };
        const status = meta?.status;
        if (status && typeof status === 'object') {
          if (typeof status.message === 'string' && status.message.trim().length) {
            payload.status = status.message;
          }
          if (typeof status.ok === 'boolean') {
            payload.statusOk = status.ok;
          }
        }
        await telemetryFn('comparevi.provider.switch', payload);
      } catch (error) {
        if (typeof console !== 'undefined' && typeof console.warn === 'function') {
          console.warn('[comparevi] failed to record provider switch telemetry', error);
        }
      }
    }

    return true;
  };
}

module.exports = {
  createProviderSwitcher
};
