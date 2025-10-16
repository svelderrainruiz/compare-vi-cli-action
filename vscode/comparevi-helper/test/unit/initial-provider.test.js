const { pickInitialProviderId } = require('../../lib/providerSelection');

describe('pickInitialProviderId', () => {
  it('prefers saved provider when metadata reports availability', () => {
    const meta = [
      { id: 'comparevi', disabled: false },
      { id: 'gcli', disabled: false, status: { ok: true } }
    ];

    const result = pickInitialProviderId('gcli', meta, 'comparevi');

    expect(result).toEqual({ id: 'gcli', fallbackReason: null });
  });

  it('falls back to fallback provider when saved provider is disabled', () => {
    const meta = [
      { id: 'comparevi', disabled: false },
      { id: 'gcli', disabled: true, status: { ok: false, message: 'missing binary' } }
    ];

    const result = pickInitialProviderId('gcli', meta, 'comparevi');

    expect(result.id).toBe('comparevi');
    expect(result.fallbackReason).toContain('missing binary');
  });

  it('falls back when saved provider is unknown', () => {
    const meta = [{ id: 'comparevi', disabled: false }];

    const result = pickInitialProviderId('ghost', meta, 'comparevi');

    expect(result.id).toBe('comparevi');
    expect(result.fallbackReason).toMatch(/not registered/i);
  });
});
