"""Security lint for the generated holdout-review workflow.

No YAML library (the project is stdlib-only), so this reads the text. It is
deliberately strict about the SHAPE the template promises, because every rule
here is a way a "review the PR with a model" workflow turns into a way to leak
the API key or let a PR steer its own reviewer. lint(text) returns a list of
problems; empty means clean. test-holdout-workflow-lint.sh runs it on the
shipped template AND on mutations of it, to prove each rule can fail.
"""
import re

# Expression contexts an attacker controls. None may appear in the prompt.
UNTRUSTED = (
    "github.event.pull_request.title", "github.event.pull_request.body",
    "github.event.pull_request.head.ref", "github.event.pull_request.head.label",
    "github.event.pull_request.head.repo", "github.head_ref", "github.event.head_commit",
    "github.event.commits", "github.event.comment", "github.event.issue",
    "github.event.review", "github.event.pages",
)


def _job(text, name, nxt=None):
    start = text.index(f"\n  {name}:\n")
    end = text.index(f"\n  {nxt}:\n", start + 1) if nxt else len(text)
    return text[start:end]


def _mapping(job, header):
    """The non-blank lines of the block mapping under `header` (an exact line such as
    "    permissions:"), or None when there is no such line. A blank line does not end a YAML
    mapping; a non-blank line indented no deeper than the header does."""
    lines = job.splitlines()
    try:
        i = next(k for k, ln in enumerate(lines) if ln == header)
    except StopIteration:
        return None
    base = len(header) - len(header.lstrip())
    out = []
    for ln in lines[i + 1:]:
        if not ln.strip():
            continue
        if len(ln) - len(ln.lstrip()) <= base:
            break
        out.append(ln.strip())
    return out


def _checkouts(job):
    """Every checkout step of a job as a dict of its inputs (quoted keys unquoted). A layout this
    cannot read gives an input named "?...", which no rule allows, so it fails instead of passing."""
    out = []
    for step in re.split(r"\n      - ", job):
        if not re.search(r"uses:\s*actions/checkout@", step):
            continue
        mapping = _mapping(step, "        with:")
        inputs = {} if mapping is not None else {"?no plain `with:` mapping": ""}
        for ln in mapping or []:
            k = re.match(r"(?:\"([^\"]+)\"|'([^']+)'|([A-Za-z0-9_-]+))\s*:\s*(.*)$", ln)
            if k:
                inputs[next(g for g in k.groups()[:3] if g)] = k.group(4).strip()
            else:
                inputs["?" + ln] = ""
        out.append(inputs)
    return out


def _block(text, key, min_indent):
    """Lines of the `key: |` block scalar: every following line indented deeper
    than the key itself."""
    m = re.search(rf"^( *){re.escape(key)}: \|\n", text, re.M)
    if not m:
        return None
    base = len(m.group(1))
    out = []
    for ln in text[m.end():].splitlines():
        if ln.strip() and len(ln) - len(ln.lstrip()) <= base:
            break
        out.append(ln)
    return "\n".join(out)


def lint(text):
    # Judge the workflow's code. Its header comments name the dangerous triggers on purpose
    # ("never `pull_request_target`"), which must not count as using them.
    text = "\n".join(ln for ln in text.splitlines() if not ln.lstrip().startswith("#")) + "\n"
    problems = []

    def need(cond, msg):
        if not cond:
            problems.append(msg)

    # -- triggers: the only trigger is pull_request ------------------------------
    need(re.search(r"^on:\n  pull_request:\n", text, re.M), "trigger is not `pull_request`")
    for bad in ("pull_request_target", "workflow_run", "issue_comment", "pull_request_review", "workflow_dispatch"):
        need(bad not in text, f"uses the `{bad}` trigger, which changes who controls the code and the secrets")

    # -- permissions: none by default; each job asks for what it needs -----------
    need(re.search(r"^permissions: \{\}\s*$", text, re.M), "top-level `permissions: {}` is missing")
    try:
        review, comment = _job(text, "review", "comment"), _job(text, "comment")
    except ValueError:
        return problems + ["expected jobs `review` and `comment`"]
    need(_mapping(review, "    permissions:") == ["contents: read"], "the review job must have exactly `contents: read`")
    need(_mapping(comment, "    permissions:") == ["pull-requests: write"],
         "the comment job must have exactly `pull-requests: write`")
    need("codex-action" not in comment and "secrets." not in comment,
         "the comment job must neither run Codex nor read secrets")

    # -- the review job only runs for same-repo, non-draft PRs --------------------
    cond = " ".join(_mapping(review, "    if: >-") or [])      # the job's own condition, not a step's
    need("github.event.pull_request.head.repo.full_name == github.repository" in cond,
         "no same-repository guard on the review job")
    need("github.event.pull_request.draft == false" in cond, "drafts are not excluded")
    need("github.actor != 'dependabot[bot]'" in cond,
         "Dependabot PRs are not skipped by the job's own condition: their runs get no Actions secrets, so the review could only fail")
    need(re.search(r"^concurrency:\n  group: .+\n  cancel-in-progress: true", text, re.M),
         "no concurrency group with cancel-in-progress")
    need("timeout-minutes:" in review, "the review job has no timeout")

    # -- every action pinned to a full commit SHA ---------------------------------
    uses = re.findall(r"uses:\s*(\S+)", text)
    need(uses, "no actions at all?")
    for u in uses:
        need(re.search(r"@[0-9a-f]{40}$", u), f"`{u}` is not pinned to a 40-character commit SHA")

    # -- checkout: this event's merge commit, no credentials left behind -------------
    need("persist-credentials: false" in review, "checkout must set persist-credentials: false")
    co = _checkouts(review)
    need(len(co) == 1, "the review job must have exactly one checkout step: a second one can replace the worktree Codex reads")
    need(co == [{"fetch-depth": "0", "persist-credentials": "false"}],
         "checkout may only set `fetch-depth: 0` (the diff needs both commits) and `persist-credentials: false`, exactly those: a `ref`, "
         "`repository`, `token` or `path` changes what Codex reads (refs/pull/N/merge moves; with no `ref` the default is this event's merge commit)")

    # -- Codex: read-only, key out of reach, reviewer cannot be rewritten ----------
    need(re.search(r'permission-profile: ":read-only"', review), "permission-profile must be \":read-only\"")
    need("safety-strategy: drop-sudo" in review, "safety-strategy must be drop-sudo")
    need("unsafe" not in review, "`unsafe` appears in the review job")
    need("project_doc_max_bytes=0" in review, "Codex's own AGENTS.md loading is not switched off")
    need('git show "$BASE_SHA:AGENTS.md"' in review, "review rules are not read from the base commit")
    need("--yolo" not in text and "--full-auto" not in text and "danger-full-access" not in text
         and "--dangerously-bypass" not in text, "a flag that disables the sandbox is present")

    # -- the prompt: no attacker-controlled text ------------------------------------
    prompt = _block(review, "prompt", 12)
    need(prompt, "no inline prompt found")
    for bad in UNTRUSTED:
        need(prompt is None or bad not in prompt, f"the prompt contains attacker-controlled `{bad}`")

    # -- no ${{ }} expansion inside shell or script bodies ---------------------------
    for key in ("run", "script"):
        for m in re.finditer(rf"^( *){key}: \|\n", text, re.M):
            base = len(m.group(1))
            body = []
            for ln in text[m.end():].splitlines():
                if ln.strip() and len(ln) - len(ln.lstrip()) <= base:
                    break
                body.append(ln)
            need("${{" not in "\n".join(body),
                 f"a `{key}:` body expands ${{{{ }}}} inline (script injection); pass it through env")

    # -- secrets only as `KEY: ${{ secrets.X }}` mapping values ------------------------
    for ln in text.splitlines():
        if "secrets." in ln and not ln.lstrip().startswith("#"):
            need(re.match(r"^\s+[A-Za-z_-]+: \$\{\{ secrets\.[A-Z_]+( \|\| vars\.[A-Z_]+)? \}\}\s*$", ln),
                 f"secret used outside an env/with mapping value: {ln.strip()}")

    # -- the Azure endpoint is read from a SECRET first ------------------------------
    # A variable's value is printed in the run log, and a public repository's logs are public.
    pair = "secrets.CODEX_RESPONSES_ENDPOINT || vars.CODEX_RESPONSES_ENDPOINT"
    need(f"responses-api-endpoint: ${{{{ {pair} }}}}" in review,
         "the endpoint must be read from a secret first: a variable is printed in the run log, which is public in a public repository")
    need(text.count("vars.CODEX_RESPONSES_ENDPOINT") == text.count(pair),
         "the endpoint is read from a variable somewhere without the secret in front of it")

    # -- the comment: its author, a leading marker, the commit it reviewed, and no verdict text ------
    need("github-actions[bot]" in comment and "startsWith(marker)" in comment,
         "the comment lookup must match the posting bot and the marker at the start of the body")
    need("VERDICT\\u200b:" in comment,
         "the comment must neutralise `VERDICT:` so a scan of PR comments for a verdict cannot match it")
    gh_step = next((s for s in re.split(r"\n      - ", comment) if re.search(r"uses:\s*actions/github-script@", s)), "")
    script = _block(gh_step, "script", 12) or ""
    used = set(re.findall(r"process\.env\.([A-Z_]+)", script))
    mapped = {ln.split(":", 1)[0].strip() for ln in (_mapping(gh_step, "        env:") or [])}
    need(used and used <= mapped,
         f"the comment script reads env vars its step does not map: {sorted(used - mapped)} (the fixture supplies its own, so only this check sees it)")
    need("pulls.get" in comment and "process.env.HEAD_SHA" in comment
         and "pr.data.base.ref" in comment and "process.env.BASE_REF" in comment,
         "the comment job must skip a review whose PR head or base branch has moved on")
    # -- a key that is not an OpenAI key is never sent to the default endpoint ----------------------
    need('case "$CODEX_API_KEY" in' in review and "sk-*)" in review,
         "the key-shape guard is missing: a non-OpenAI key with no endpoint would be sent to api.openai.com")
    return problems
