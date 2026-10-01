export const meta = {
  name: 'understand-and-verify-stock',
  description: 'Map, explain, document and fact-check every targeted Stock Control program',
  phases: [
    { title: 'Map' },
    { title: 'Explain & Document' },
    { title: 'Verify' },
  ],
}

const PROGRAMS = args && args.length ? args : ['stock/st000.cbl', 'stock/st040.cbl', 'stock/st050.cbl', 'stock/st060.cbl']

phase('Map')
const map = await agent(
  'Map the CALL/PERFORM/COPY dependencies across every program in stock/.',
  { agentType: 'cobol-dependency-mapper', label: 'map:stock' }
)

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    confirmed: { type: 'number' },
    contradicted: { type: 'number' },
    unverifiable: { type: 'number' },
    summary: { type: 'string' },
  },
  required: ['confirmed', 'contradicted', 'summary'],
}

// pipeline: program A can be in Verify while program B is still in Explain & Document —
// no barrier between stages, so wall-clock is the slowest single program's chain, not the sum.
const results = await pipeline(
  PROGRAMS,
  prog => parallel([
    () => agent(`Explain ${prog} in plain English, focusing on its business rules.`,
      { agentType: 'cobol-explainer', phase: 'Explain & Document', label: `explain:${prog}` }),
    () => agent(`Document ${prog}.`,
      { agentType: 'cobol-doc-writer', phase: 'Explain & Document', label: `doc:${prog}` }),
  ]),
  (_, prog) => agent(
    `Verify the documentation just written for ${prog} (docs/cobol/<name>.md) against the real source.`,
    { agentType: 'cobol-verifier', phase: 'Verify', label: `verify:${prog}`, schema: VERDICT_SCHEMA }
  )
)

const flagged = PROGRAMS
  .map((prog, i) => ({ prog, verdict: results[i] }))
  .filter(r => r.verdict && r.verdict.contradicted > 0)

log(`${flagged.length} of ${PROGRAMS.length} docs have at least one contradicted claim`)
return { map, results, flagged }
