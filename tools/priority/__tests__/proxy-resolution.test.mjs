import test from 'node:test';
import assert from 'node:assert/strict';

import { resolveProxyUrl, shouldBypassProxy } from '../sync-standing-priority.mjs';

async function withEnv(overrides, fn) {
  const keys = Object.keys(overrides);
  const previous = new Map();

  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(process.env, key)) {
      previous.set(key, process.env[key]);
    } else {
      previous.set(key, undefined);
    }
    const value = overrides[key];
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }

  try {
    await fn();
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}

test('resolveProxyUrl selects HTTPS proxy when available', async () => {
  await withEnv(
    {
      HTTPS_PROXY: 'http://proxy.example:8443',
      https_proxy: '',
      HTTP_PROXY: '',
      http_proxy: '',
      ALL_PROXY: '',
      all_proxy: '',
      NO_PROXY: '',
      no_proxy: ''
    },
    () => {
      assert.equal(resolveProxyUrl('https://api.github.com'), 'http://proxy.example:8443');
      assert.equal(resolveProxyUrl('http://example.com'), null);
    }
  );
});

test('resolveProxyUrl falls back to HTTP proxy for HTTPS when needed', async () => {
  await withEnv(
    {
      HTTPS_PROXY: '',
      https_proxy: '',
      HTTP_PROXY: 'http://proxy.example:8080',
      http_proxy: '',
      ALL_PROXY: '',
      all_proxy: '',
      NO_PROXY: '',
      no_proxy: ''
    },
    () => {
      assert.equal(resolveProxyUrl('https://api.github.com'), 'http://proxy.example:8080');
      assert.equal(resolveProxyUrl('http://example.com'), 'http://proxy.example:8080');
    }
  );
});

test('resolveProxyUrl respects NO_PROXY patterns and wildcards', async () => {
  await withEnv(
    {
      HTTPS_PROXY: 'http://proxy.example:8443',
      https_proxy: '',
      HTTP_PROXY: '',
      http_proxy: '',
      NO_PROXY: '.github.com,localhost',
      no_proxy: ''
    },
    () => {
      assert.equal(resolveProxyUrl('https://api.github.com'), null);
      assert.equal(resolveProxyUrl('https://example.com'), 'http://proxy.example:8443');
    }
  );

  await withEnv(
    {
      HTTPS_PROXY: 'http://proxy.example:8443',
      NO_PROXY: '*'
    },
    () => {
      assert.equal(resolveProxyUrl('https://api.github.com'), null);
    }
  );
});

test('shouldBypassProxy handles IPv6 and port-specific exclusions', async () => {
  await withEnv(
    {
      NO_PROXY: '::1,[2001:db8::1]:443,example.com:8443'
    },
    () => {
      assert.equal(shouldBypassProxy('https://[::1]/'), true);
      assert.equal(shouldBypassProxy('https://[2001:db8::1]:443/path'), true);
      assert.equal(shouldBypassProxy('https://[2001:db8::1]:444/path'), false);
      assert.equal(shouldBypassProxy('https://service.example.com:8443/api'), true);
      assert.equal(shouldBypassProxy('https://service.example.com:443/api'), false);
    }
  );
});
