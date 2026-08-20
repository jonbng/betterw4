import { defineConfig } from 'wxt';
import tailwindcss from '@tailwindcss/vite';
import path from 'path';

// See https://wxt.dev/api/config.html
export default defineConfig({
  manifest: {
    name: 'BetterW4',
    description: 'A modern interface for W4 at UWC Red Cross Nordic.',
    // No `version` key — WXT falls back to package.json.
    author: 'Jonathan Bangert' as any,
    homepage_url: 'https://github.com/jonbng/betterw4',
    action: {
      default_title: 'BetterW4',
    },
    permissions: ['activeTab', 'storage'],
    web_accessible_resources: [
      {
        resources: ['assets/*'],
        matches: ['*://w4.uwcrcn.no/*'],
      },
    ],
  },
  hooks: {
    'build:manifestGenerated': (wxt, manifest) => {
      if (wxt.config.browser === 'firefox') {
        manifest.browser_specific_settings = {
          gecko: {
            id: '{7f2e9c1a-4b8d-4a3e-9f6c-1d5e8a2b7c40}',
            strict_min_version: '109.0',
            data_collection_permissions: {
              required: ['none'],
            },
          },
        };
      }
      if (wxt.config.browser === 'safari') {
        manifest.name = 'BetterW4';
        if (manifest.action && typeof manifest.action === 'object') {
          manifest.action.default_title = 'BetterW4';
        }

        manifest.browser_specific_settings = {
          ...(manifest.browser_specific_settings ?? {}),
          safari: { strict_min_version: '18.0' },
        };

        // Safari does not apply host_permissions CORS bypass to a background
        // service worker — only to a background page. Emit `scripts` alongside
        // `service_worker` so either environment works.
        const background = manifest.background as
          | { service_worker?: string; scripts?: string[]; persistent?: boolean }
          | undefined;
        if (background?.service_worker) {
          background.scripts = [background.service_worker];
          delete background.persistent;
        }
      }
    },
  },
  webExt: {
    startUrls: ['https://w4.uwcrcn.no/'],
  },
  zip: {
    excludeSources: [
      'node_modules/**',
      '.output/**',
      '.wxt/**',
      '.env',
      '.claude/**',
      '.mcp.json',
      '.github/**',
      'docs/**',
      '.cursor/**',
      'screenshots/**',
      'CLAUDE.md',
      'AGENTS.md',
      'ARCHITECTURE.md',
      'web-ext.config.ts',
    ],
  },
  vite: () => ({
    plugins: [tailwindcss()],
    resolve: {
      alias: {
        '@': path.resolve(__dirname, './'),
        'react': 'preact/compat',
        'react-dom': 'preact/compat',
        'react/jsx-runtime': 'preact/jsx-runtime',
      },
    },
  }),
});
