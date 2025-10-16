const fs = require('fs');
const Module = require('module');

const configGetMock = vi.fn();
const onDidChangeConfigurationMock = vi.fn(() => ({ dispose: vi.fn() }));

const vscodeStub = {
  workspace: {
    getConfiguration: vi.fn(() => ({ get: configGetMock })),
    onDidChangeConfiguration: onDidChangeConfigurationMock
  },
  window: {
    showInformationMessage: vi.fn(),
    showWarningMessage: vi.fn(),
    showErrorMessage: vi.fn()
  }
};

const originalLoad = Module._load;
Module._load = function patchedModuleLoad(request, parent, isMain) {
  if (request === 'vscode') {
    return vscodeStub;
  }
  return originalLoad.call(this, request, parent, isMain);
};

afterAll(() => {
  Module._load = originalLoad;
});

const registry = require('../../providers/registry');
const providers = require('../../providers');
const createGcliProvider = require('../../providers/gcli');

function resetRegistry() {
  for (const provider of registry.listProviders()) {
    registry.unregisterProvider(provider.id);
  }
}

describe('provider registry', () => {
  beforeEach(() => {
    resetRegistry();
    configGetMock.mockReset();
  });

  afterEach(() => {
    resetRegistry();
  });

  it('sets the first registered provider as active and emits change event', () => {
    const seen = [];
    const listener = registry.onDidChangeActiveProvider((id) => seen.push(id));
    const provider = { id: 'comparevi', deactivate: vi.fn() };

    registry.registerProvider(provider);

    expect(registry.getActiveProviderId()).toBe('comparevi');
    expect(seen).toContain('comparevi');

    listener.dispose();
  });

  it('does not change active provider when switching to unknown id', () => {
    registry.registerProvider({ id: 'comparevi', deactivate: vi.fn() });

    const result = registry.setActiveProvider('missing');

    expect(result).toBe(false);
    expect(registry.getActiveProviderId()).toBe('comparevi');
  });

  it('falls back to another provider when the active one is unregistered', () => {
    const first = { id: 'comparevi', deactivate: vi.fn() };
    const second = { id: 'gcli', deactivate: vi.fn() };

    registry.registerProvider(first);
    registry.registerProvider(second);
    registry.setActiveProvider('gcli');

    registry.unregisterProvider('gcli');

    expect(registry.getActiveProviderId()).toBe('comparevi');
  });

  it('exposes provider metadata with disabled flag and status message', () => {
    const status = { ok: false, message: 'binary missing' };
    const provider = {
      id: 'gcli',
      displayName: 'G CLI',
      docsUrl: 'https://example.test',
      deactivate: vi.fn(),
      isAvailable: () => false,
      getStatus: () => status
    };

    providers.registerProvider(provider);
    const metadata = providers.listProviderMetadata().find((item) => item.id === 'gcli');

    expect(metadata).toBeDefined();
    expect(metadata.disabled).toBe(true);
    expect(metadata.status).toEqual(status);
    expect(metadata.docsUrl).toBe(provider.docsUrl);
  });
});

describe('g-cli provider status', () => {
  beforeEach(() => {
    configGetMock.mockReset();
    configGetMock.mockReturnValue('');
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('reports missing executable when default path is absent', () => {
    const expectedPath = process.platform === 'win32'
      ? 'C\\Program Files\\G-CLI\\bin\\g-cli.exe'
      : '/usr/local/bin/g-cli';
    const existsSpy = vi.spyOn(fs, 'existsSync').mockReturnValue(false);

    const provider = createGcliProvider();
    const status = provider.getStatus();

    expect(status.ok).toBe(false);
    expect(status.message).toContain(expectedPath);
    expect(provider.isAvailable()).toBe(false);

    existsSpy.mockRestore();
  });

  it('uses configured path and marks provider available when executable exists', () => {
    const customPath = process.platform === 'win32' ? 'C:\\temp\\g-cli.exe' : '/opt/g-cli/bin/g-cli';
    configGetMock.mockReturnValue(customPath);
    const existsSpy = vi.spyOn(fs, 'existsSync').mockImplementation((p) => p === customPath);

    const provider = createGcliProvider();
    const status = provider.getStatus();

    expect(status.ok).toBe(true);
    expect(status.message).toContain(customPath);
    expect(provider.isAvailable()).toBe(true);

    existsSpy.mockRestore();
  });
});
