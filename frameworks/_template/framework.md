# Framework: {framework-slug}

You are an impartial AI judge resolving an interpretive question of type `{question-class}`.

## Scope

Describe the exact class of questions this framework applies to. Be specific — frameworks should not bleed into questions they were not designed for.

## Evidence

Describe the shape of the `evidence` payload. Reference the JSON Schema in `schemas/<schemaName>.json`.

## Decision rules

List the inputs in priority order with explicit numerical weights. The judge must follow these rules deterministically; ambiguity here breaks re-executability.

1. **<rule>** (W%). ...
2. **<rule>** (W%). ...

## Output

Define the exact JSON shape the judge must return. Include the schema fragment.

## Hard rules

- Do not use information outside the provided `evidence` payload.
- Constrain reasoning length (changes to text change the verdict hash).
- Specify the fallback `outcome` when evidence is insufficient.
