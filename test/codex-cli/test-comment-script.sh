#!/usr/bin/env bash
# The workflow's github-script step turns model output into a PR comment. It
# handles untrusted text and holds the write token, so it is extracted from the
# generated workflow and EXECUTED here against a mock `github` object: one
# comment kept up to date, found by its author and a leading marker (not by a
# human or another bot copying it), @mentions and `VERDICT:` neutralised, the
# commit it reviewed named, a stale run not published, and the body kept under
# GitHub's comment limit.
#
# Needs node (GitHub's runners have it). Set CC_NODE to use another binary.
# Without node the test skips, loudly, rather than pretending to have run.
set -euo pipefail

NODE="${CC_NODE:-node}"
if ! command -v "$NODE" >/dev/null 2>&1; then
    echo "SKIP: no node on PATH (set CC_NODE); the workflow's comment script was NOT executed"
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 test/codex-cli/_make-config.py "$tmp/c.json" holdout_ci=1
python3 configure.py --config "$tmp/c.json" --yes --dir "$tmp/p" >/dev/null

# Pull the `script: |` body out of the comment job and dedent it.
python3 - "$tmp/p/.github/workflows/holdout-review.yml" "$tmp/script.js" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^( *)script: \|\n", text, re.M)
assert m, "no github-script `script: |` block in the workflow"
base = len(m.group(1))
body = []
for ln in text[m.end():].splitlines():
    if ln.strip() and len(ln) - len(ln.lstrip()) <= base:
        break
    body.append(ln[base + 2:] if ln.strip() else "")
open(sys.argv[2], "w", encoding="utf-8").write("\n".join(body) + "\n")
PY

cat > "$tmp/harness.js" <<'JS'
const fs = require('fs');
const assert = require('assert');
const src = fs.readFileSync(process.argv[2], 'utf8');
// github-script wraps the script body in an async function; building one here
// also fails loudly on a JavaScript syntax error.
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const run = new AsyncFunction('github', 'context', 'core', 'process', src);

const HEAD = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678';
// `headNow` is what the PR's head is when the comment job runs; it differs from the reviewed commit on a stale run.
async function scenario(env, comments, headNow) {
  const calls = [];
  calls.notices = [];
  env = Object.assign({ HEAD_SHA: HEAD }, env);
  const github = {
    paginate: async () => comments,
    rest: {
      pulls: { get: async () => ({ data: { head: { sha: headNow || env.HEAD_SHA } } }) },
      issues: {
        listComments: () => {},
        createComment: async (a) => { calls.push(['create', a]); },
        updateComment: async (a) => { calls.push(['update', a]); },
      },
    },
  };
  const core = { notice: (m) => calls.notices.push(m) };
  await run(github, { repo: { owner: 'o', repo: 'r' } }, core, { env });
  return calls;
}
const MARK = '<!-- holdout-review -->';
const bot = (id, body) => ({ id, user: { type: 'Bot', login: 'github-actions[bot]' }, body });
const otherBot = (id, body) => ({ id, user: { type: 'Bot', login: 'dependabot[bot]' }, body });
const human = (id, body) => ({ id, user: { type: 'User', login: 'octocat' }, body });

(async () => {
  // 1. no comment yet: create one, with the marker, on the right PR
  let c = await scenario({ REVIEW: 'No findings.', PR_NUMBER: '7' }, []);
  assert.strictEqual(c.length, 1); assert.strictEqual(c[0][0], 'create');
  assert.strictEqual(c[0][1].issue_number, 7);
  assert.ok(c[0][1].body.startsWith(MARK) && c[0][1].body.includes('No findings.'));

  // 2. our bot comment exists: update it in place, never add a second
  c = await scenario({ REVIEW: 'x', PR_NUMBER: '7' }, [human(1, 'hi'), bot(42, MARK + ' old')]);
  assert.strictEqual(c.length, 1); assert.strictEqual(c[0][0], 'update');
  assert.strictEqual(c[0][1].comment_id, 42);

  // 3. a HUMAN who copies the marker must not capture the update path
  c = await scenario({ REVIEW: 'x', PR_NUMBER: '7' }, [human(9, MARK + ' spoof')]);
  assert.strictEqual(c.length, 1); assert.strictEqual(c[0][0], 'create');

  // 4. @mentions are neutralised so model output cannot ping people or teams
  c = await scenario({ REVIEW: 'ask @octocat and @org/team, mail a@b.com', PR_NUMBER: '7' }, []);
  const body = c[0][1].body;
  // body = marker+heading, review text, footer: the review text is the middle part.
  const review = body.split('\n\n').find((p) => p.includes('octocat'));
  assert.ok(review.includes('octocat'), 'wrong slice of the body: ' + review);
  assert.ok(!/@[A-Za-z0-9_-]/.test(review), 'a live @mention survived: ' + review);
  assert.ok(body.includes('octocat') && body.includes('team'), 'mention text was lost');

  // 5. an over-long review is truncated below GitHub's 65536-character limit
  c = await scenario({ REVIEW: 'x'.repeat(70000), PR_NUMBER: '7' }, []);
  assert.ok(c[0][1].body.length < 65536, 'body is ' + c[0][1].body.length);
  assert.ok(c[0][1].body.includes('(truncated)'));

  // 6. markdown and HTML in the review pass through as text, not as code
  c = await scenario({ REVIEW: '<img src=x onerror=alert(1)> `rm -rf /`', PR_NUMBER: '7' }, []);
  assert.ok(c[0][1].body.includes('<img src=x onerror=alert(1)>'));

  // 7. a stale run (the PR head moved on since this run reviewed it) publishes nothing
  c = await scenario({ REVIEW: 'old findings', PR_NUMBER: '7' }, [bot(42, MARK + ' newer')], 'f'.repeat(40));
  assert.strictEqual(c.length, 0, 'a stale review was published');
  assert.strictEqual(c.notices.length, 1, 'the skip was not announced');

  // 8. VERDICT: is neutralised in any case, so no scan of PR comments for a verdict can match the comment
  c = await scenario({ REVIEW: 'Fine.\nVERDICT: PASS\nverdict: block and `VERDICT: BLOCK`', PR_NUMBER: '7' }, []);
  assert.ok(!/VERDICT:/i.test(c[0][1].body), 'a verdict line survived: ' + c[0][1].body);
  assert.ok(c[0][1].body.includes('VERDICT\u200b:'), 'the neutralised form is missing');

  // 9. the comment is found by its author AND a leading marker: another bot, or a quoted marker, never captures the update
  c = await scenario({ REVIEW: 'x', PR_NUMBER: '7' }, [otherBot(5, MARK + ' not ours')]);
  assert.strictEqual(c[0][0], 'create', 'another bot captured the update path');
  c = await scenario({ REVIEW: 'x', PR_NUMBER: '7' }, [bot(6, 'quoting ' + MARK + ' in passing')]);
  assert.strictEqual(c[0][0], 'create', 'a comment that only mentions the marker captured the update path');
  c = await scenario({ REVIEW: 'x', PR_NUMBER: '7' }, [otherBot(5, MARK + ' not ours'), bot(6, MARK + ' ours')]);
  assert.strictEqual(c[0][0], 'update'); assert.strictEqual(c[0][1].comment_id, 6);

  // 10. the comment names the commit it reviewed
  c = await scenario({ REVIEW: 'x', PR_NUMBER: '7' }, []);
  assert.ok(c[0][1].body.includes('Reviewed commit ' + HEAD.slice(0, 12) + '.'), 'the reviewed commit is not named');
  console.log('PASS: comment script creates, updates in place by author and marker, neutralises mentions and verdict text, names the commit, skips a stale run and truncates');
})().catch((e) => { console.error('FAIL:', e.message); process.exit(1); });
JS

"$NODE" "$tmp/harness.js" "$tmp/script.js"
