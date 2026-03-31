#!/usr/bin/env node

import test from 'node:test';
import assert from 'node:assert/strict';
import { deriveStandardsActionItems } from '../fork-lane-local-assurance-ci.mjs';

test('deriveStandardsActionItems creates uplift work for weak standards areas only', () => {
  const score = {
    areas: {
      REQ: { score: 1, rationale: 'Weak requirement signals.', top_fix: 'Add SRS and RTM.', standards: ['29148'], evidence_paths: ['docs/requirements/srs.md'] },
      ARCH: { score: 3, rationale: 'Defined.', top_fix: 'Keep views current.', standards: ['42010'], evidence_paths: ['docs/architecture/overview.md'] },
      TEST: { score: 2, rationale: 'Partial testing evidence.', top_fix: 'Publish coverage artifacts.', standards: ['29119-2', '29119-3'], evidence_paths: ['.github/workflows/fork-lane-design-audit.yml'] },
      CM: { score: 4, rationale: 'Managed.', top_fix: 'Keep CM plan current.', standards: ['10007', '12207'], evidence_paths: ['docs/cm/cm-plan.md'] },
      DOC: { score: 0, rationale: 'No meaningful documentation evidence.', top_fix: 'Add information-item map.', standards: ['15289'], evidence_paths: [] }
    }
  };

  const items = deriveStandardsActionItems(score);

  assert.deepEqual(items.map((item) => item.id), [
    'standards-req-uplift',
    'standards-test-uplift',
    'standards-doc-uplift'
  ]);
  assert.equal(items[0].priority, 'high');
  assert.equal(items[1].priority, 'medium');
  assert.equal(items[2].priority, 'high');
});
