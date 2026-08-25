export const meta = {
  name: 'spec-fanout',
  description:
    'Generate N distinct variants of one spec, each into its own output slot, then screen every variant against the spec before reporting.',
  whenToUse:
    'N independent variants of a single spec — landing pages, prompt variants, config shapes. Not for staged pipelines or work that has to be merged.',
  phases: [
    { title: 'Generate', detail: 'one agent per variant, each writing only its own slot' },
    { title: 'Screen', detail: 'check each variant against the spec and the diversification axis' },
  ],
}

// Invoke with a config object, e.g.
//   Run /spec-fanout with {"spec":"docs/specs/card.md","outDir":"variants","count":6,"axis":"visual density"}
//
// This is the workflow-native successor to the `/infinite` skill this module
// also ships. Prefer this one: the runtime holds the loop and the intermediate
// results, so the controller's context stays clean, the run is resumable, and
// the screening pass is a real gate rather than a suggestion.
const cfg = args || {}
const spec = cfg.spec
const outDir = cfg.outDir || 'variants'
const count = Math.max(1, Number(cfg.count || 5))
const axis = cfg.axis || 'overall approach'

if (!spec) {
  return [
    'Missing `spec`. Invoke with a config object, for example:',
    '  Run /spec-fanout with {"spec":"docs/specs/card.md","outDir":"variants","count":6,"axis":"visual density"}',
    '',
    'Fields: spec (required, path to the spec file), outDir (default "variants"),',
    'count (default 5), axis (what must differ between variants).',
  ].join('\n')
}

const SCREEN_SCHEMA = {
  type: 'object',
  required: ['compliant', 'distinct', 'notes'],
  properties: {
    compliant: { type: 'boolean', description: 'Meets every must-be-true item in the spec.' },
    distinct: { type: 'boolean', description: 'Genuinely differs from the other variants on the stated axis.' },
    violations: { type: 'array', items: { type: 'string' }, description: 'Spec requirements this variant misses.' },
    notes: { type: 'string', description: 'One or two sentences a human can act on.' },
  },
}

const slots = Array.from({ length: count }, (_, i) => ({
  index: i + 1,
  slug: 'iter-' + String(i + 1).padStart(2, '0'),
}))

log('Fanning out ' + count + ' variants of ' + spec + ' into ' + outDir + '/, diversified on: ' + axis)

// pipeline, not parallel: a variant is screened the moment it is written, so a
// slow generator never holds up the screening of the ones already finished.
const reviewed = await pipeline(
  slots,
  (slot) =>
    agent(
      [
        'Read the spec at ' + spec + ' in full.',
        '',
        'Produce EXACTLY ONE variant of it and write your files to ' + outDir + '/' + slot.slug + '/.',
        'That directory is yours alone. Never read, write, or reference any other',
        'slot under ' + outDir + '/ — sibling agents are working there concurrently.',
        '',
        'You are variant ' + slot.index + ' of ' + count + '. What must be different',
        'about yours: ' + axis + '. Honor that literally; if the spec makes it',
        'impossible, say so in your summary rather than emitting a near-duplicate.',
        '',
        'Every must-be-true requirement in the spec applies to your variant. If a',
        'spec requirement conflicts with the diversification axis, follow the spec',
        'and flag the conflict.',
        '',
        'Return under 10 lines: what you built, the axis choice you made, and any',
        'requirement you could not satisfy.',
      ].join('\n'),
      { label: slot.slug, phase: 'Generate' },
    ),
  (summary, slot) =>
    agent(
      [
        'Screen one generated variant against its spec. Read the spec at ' + spec + ',',
        'then read what the generator wrote under ' + outDir + '/' + slot.slug + '/.',
        '',
        "The generator's own summary (treat as an unverified claim, not evidence):",
        summary === null ? '(the generator produced no summary)' : summary,
        '',
        'Judge two things:',
        '1. compliant — does it meet every must-be-true item in the spec?',
        '2. distinct — does it genuinely differ on this axis: ' + axis + '?',
        '',
        'Judge the files, not the summary. Do not fix anything.',
      ].join('\n'),
      { label: 'screen:' + slot.slug, phase: 'Screen', schema: SCREEN_SCHEMA },
    ).then((verdict) => ({ slot: slot.slug, verdict })),
)

const results = reviewed.filter(Boolean)
const clean = results.filter((r) => r.verdict && r.verdict.compliant && r.verdict.distinct)
const problems = results.filter((r) => !clean.includes(r))

log(clean.length + '/' + count + ' variants passed screening')

return {
  spec,
  outDir,
  axis,
  requested: count,
  generated: results.length,
  passed: clean.map((r) => r.slot),
  needsAttention: problems.map((r) => ({
    slot: r.slot,
    compliant: r.verdict ? r.verdict.compliant : null,
    distinct: r.verdict ? r.verdict.distinct : null,
    violations: r.verdict ? r.verdict.violations || [] : [],
    notes: r.verdict ? r.verdict.notes : 'screening agent returned nothing',
  })),
}
