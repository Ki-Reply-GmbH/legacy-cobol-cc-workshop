export const meta = {
  name: 'migration-blast-radius',
  description: 'Find the full migration blast radius of one ACAS target across COBOL, scripts, config/SQL and docs, then merge into one report',
  whenToUse: 'args: { target: "<program | copybook | data file>" }, e.g. { target: "salesled.dat" }',
  phases: [
    { title: 'Search', detail: 'four scoped migration-impact-mapper agents in parallel' },
    { title: 'Merge', detail: 'dedupe and write docs/impact/<target>-workflow.md' },
  ],
}

const TARGET = (args && args.target) || 'salesled.dat'
const OUT = `docs/impact/${TARGET}-workflow.md`

const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    names_searched: { type: 'array', items: { type: 'string' } },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          bucket: { type: 'string', enum: ['Confirmed', 'Likely', 'Possible'] },
          location: { type: 'string', description: 'exact path:line, or path plus section/line range' },
          what: { type: 'string', description: 'brief quote or description of the matching text' },
          why: { type: 'string', description: 'one line: why this creates impact (or why only likely/possible)' },
        },
        required: ['bucket', 'location', 'what', 'why'],
      },
    },
    absent_types: { type: 'array', items: { type: 'string' }, description: 'requested artifact types that do not exist in this repo' },
    not_checked: { type: 'array', items: { type: 'string' }, description: 'things outside reach: archives, binaries, runtime-only behaviour' },
  },
  required: ['names_searched', 'findings', 'absent_types', 'not_checked'],
}

const COMMON = `Target: "${TARGET}".
Apply the methodology in your instructions (every alias of the target, glob expansion, the layout-change chain, the FH/DAL cross-cutting rule, case-insensitive search with false-friend checks, Confirmed / Likely / Possible with the weaker bucket when torn, an exact location for every finding).
Do NOT write any file. In this run you are one of four scoped searchers; return your findings only, via the structured output. Another agent merges and writes the report.
Stay inside your scope below. Other agents cover the other artifact types, so don't duplicate their work, but DO use files outside your scope to work out the target's aliases (e.g. read its fileNN.cob or CLAUDE.md to learn its FH, DAL, table and utility names).`

const SCOPES = [
  {
    key: 'cobol',
    prompt: `${COMMON}

SCOPE: all COBOL programs and copybooks: *.cbl, *.cob, *.cpy, *.scb anywhere in the tracked tree. Cover CALL (literal and dynamic via ws-called), PERFORM of the Proc-ACAS-FH-Calls paragraphs, COPY (incl. REPLACING), SELECT/ASSIGN to the target's file-NN, shared file access, and REDEFINES of the target's records. Cite DAL .scb sources rather than the generated *MT.cbl.`,
  },
  {
    key: 'scripts',
    prompt: `${COMMON}

SCOPE: all shell scripts and JCL: every *.sh file (root, per-module, common/master*.sh) plus any JCL. Check literal names AND globs (ls sl*.cbl, acas0*.cbl, *MT.scb, *LD.cbl, mv *.so, tar *.dat): a glob that matches the target's filename, compiled module or data file is a real reference. Check whether any script names, compiles, installs, backs up, loads/unloads or passes the target's filename as a parameter. There is no JCL in this repo as of the last investigation; confirm by Glob and report it under absent_types if so.`,
  },
  {
    key: 'config',
    prompt: `${COMMON}

SCOPE: all YAML, SQL and config files: mysql/ACASDB.sql, any *.yml/*.yaml/*.json/*.param/*.conf/*.cfg/*.ini, .claude/settings.json, .mcp.json, .gitignore, .gitattributes. Check whether the target, or its MySQL table name, appears in a schema, a config value or a connection mapping. presql2-latest.zip contains a 2018 ACASDB.sql and presql2.param that you can't read inside the archive: list them as Possible or not_checked, with the reason. Report YAML (and any other requested type) under absent_types if none exists.`,
  },
  {
    key: 'docs',
    prompt: `${COMMON}

SCOPE: the generated Markdown docs in docs/cobol/ and docs/impact/ only. EXCLUDE ${OUT} and any earlier *-workflow.md report: don't cite this workflow's own output. A doc mentioning the target is evidence that someone documented a dependency, not a dependency itself: grade it at most Possible unless the doc cites an exact source line you can confirm, in which case cite that source line as the location and the doc as supporting context.`,
  },
]

phase('Search')
const results = await parallel(SCOPES.map(s => () =>
  agent(s.prompt, {
    agentType: 'migration-impact-mapper',
    phase: 'Search',
    label: `search:${s.key}`,
    schema: FINDINGS_SCHEMA,
  }).then(r => (r ? { scope: s.key, ...r } : null))
))

const ok = results.filter(Boolean)
const failed = SCOPES.filter((s, i) => !results[i]).map(s => s.key)
if (failed.length) log(`WARNING: no result from scope(s): ${failed.join(', ')} — the merged report will say so`)

// Exact-duplicate removal in plain code: same bucket + same location + same "what".
const seen = new Set()
const all = []
for (const r of ok) {
  for (const f of r.findings) {
    const k = `${f.bucket}|${f.location.trim().toLowerCase()}|${f.what.trim().toLowerCase()}`
    if (seen.has(k)) continue
    seen.add(k)
    all.push({ ...f, scope: r.scope })
  }
}
const counts = { Confirmed: 0, Likely: 0, Possible: 0 }
all.forEach(f => { counts[f.bucket] = (counts[f.bucket] || 0) + 1 })
log(`${ok.length}/4 scopes returned ${all.length} findings before merge: ${counts.Confirmed} Confirmed, ${counts.Likely} Likely, ${counts.Possible} Possible`)

phase('Merge')
const merged = await agent(
  `Merge the scoped impact findings below into ONE report for target "${TARGET}" and write it to ${OUT}.

Rules:
- Use exactly the report structure from your instructions (header, Confirmed / Likely / Possible tables, one-line Bottom line, short Not checked note).
- No duplicates. The same reference reported by two scopes, or the same location described twice, must appear once. When two entries for one location disagree on the bucket, keep the bucket that the cited evidence actually supports and note the disagreement in that row's "why" cell.
- Don't add new findings. Don't drop a finding without saying why (e.g. merged into another row). Every row keeps its exact location.
- Spot-check every Confirmed row by reading the cited line. If the line doesn't say what the finding claims, downgrade it or drop it and say so under Not checked.
- Header: list the union of names searched, the artifact types searched, and the absent types reported by the scopes.${failed.length ? `\n- Scope(s) ${failed.join(', ')} returned nothing (agent failure). State this prominently under Not checked: that artifact type was NOT covered.` : ''}
- If ${OUT} already exists, follow your no-overwrite rule (write the next free -2, -3 name) and say which path you used.

After writing, return: the path written, the final count per bucket, how many duplicates you merged, and the Bottom line sentence.

Scoped results (JSON):
${JSON.stringify(ok.map(r => ({ scope: r.scope, names_searched: r.names_searched, absent_types: r.absent_types, not_checked: r.not_checked })), null, 1)}

Findings after exact-duplicate removal (JSON):
${JSON.stringify(all, null, 1)}`,
  { agentType: 'migration-impact-mapper', phase: 'Merge', label: 'merge' }
)

return { target: TARGET, output: OUT, scopes_ok: ok.map(r => r.scope), scopes_failed: failed, pre_merge_counts: counts, merged }
