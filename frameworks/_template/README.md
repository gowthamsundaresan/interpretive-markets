# {framework-slug}

Scaffold for a new interpretive-judge framework. Copy this directory, rename it to your slug, and fill in:

- **`manifest.json`** — name, description, `applicableTo`, the pinned `model`, `evidenceSchema`, the six-field `outputSchema`, and the `roles` (investigator + judge).
- **`judge.md`** — the codified adjudication stance + the strict output schema. The judge is a single-shot call.
- **`investigator.md`** — how to gather evidence into the dossier (via `fetch_http` over an allowlist) and assemble the judge prompt.
- **`schemas/dossier.json`** — the evidence schema the investigator's dossier must validate against.

The judge emits six on-chain fields: `outcome`, `confidence_bps`, `driving_tier`, `subject_ref`, `citations`, `rationale_hash`. See `../compound-interpretive-value/` for a complete, working example.
