const { createProviderSwitcher } = require('../../lib/providerSwitcher');

describe('provider switch telemetry helper', () => {
  let setActiveProviderMock;
  let listProviderMetadataMock;
  let getActiveProviderIdMock;
  let telemetryMock;
  let switchProvider;

  beforeEach(() => {
    setActiveProviderMock = vi.fn(() => true);
    listProviderMetadataMock = vi.fn(() => []);
    getActiveProviderIdMock = vi.fn(() => undefined);
    telemetryMock = vi.fn(() => Promise.resolve());
    switchProvider = createProviderSwitcher({
      setActiveProvider: setActiveProviderMock,
      listProviderMetadata: listProviderMetadataMock,
      getActiveProviderId: getActiveProviderIdMock,
      recordTelemetry: telemetryMock
    });
  });

  it('records telemetry when switching providers', async () => {
    getActiveProviderIdMock.mockReturnValueOnce('comparevi');
    listProviderMetadataMock.mockReturnValueOnce([
      { id: 'comparevi', disabled: false, status: { ok: true, message: 'CompareVI ready' } },
      { id: 'gcli', disabled: true, status: { ok: false, message: 'g-cli missing' } }
    ]);

    const result = await switchProvider('gcli', { recordTelemetry: true, telemetryReason: 'test' });

    expect(result).toBe(true);
    expect(setActiveProviderMock).toHaveBeenCalledWith('gcli');
    expect(telemetryMock).toHaveBeenCalledTimes(1);
    const [eventName, payload] = telemetryMock.mock.calls[0];
    expect(eventName).toBe('comparevi.provider.switch');
    expect(payload).toMatchObject({
      from: 'comparevi',
      to: 'gcli',
      available: false,
      reason: 'test',
      status: 'g-cli missing',
      statusOk: false
    });
  });

  it('skips telemetry when provider remains unchanged', async () => {
    getActiveProviderIdMock.mockReturnValueOnce('comparevi');

    const result = await switchProvider('comparevi', { recordTelemetry: true, telemetryReason: 'test' });

    expect(result).toBe(true);
    expect(telemetryMock).not.toHaveBeenCalled();
  });

  it('returns false when underlying setActiveProvider fails', async () => {
    setActiveProviderMock.mockReturnValueOnce(false);

    const result = await switchProvider('missing', { recordTelemetry: true });

    expect(result).toBe(false);
    expect(telemetryMock).not.toHaveBeenCalled();
  });
});
