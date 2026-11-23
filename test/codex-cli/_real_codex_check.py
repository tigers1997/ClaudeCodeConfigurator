#!/usr/bin/env python3
"""The codex-cli module against the REAL Codex CLI (run from the repo root by test-real-codex.sh).

usage: _real_codex_check.py PATH-TO-CODEX

Renders the module's own docs and script with configure.py and feeds them to the real binary. No
credentials and a throwaway HOME per case. Each case starts Codex, reads only what it prints first
(a config error, or the session header), then stops it, so a missing network or a 401 from the API
changes nothing. Where a case pins today's behaviour of Codex rather than a promise, the failure
message says what to revisit.
"""
import os
import queue
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time

REPO = os.getcwd()
CODEX = sys.argv[1]
TMP = tempfile.mkdtemp(prefix="real-codex.")
sys.path.insert(0, REPO)


def fail(case, message, text=""):
    print("FAIL: %s: %s" % (case, message))
    shown = [line for line in text.splitlines() if line.strip()][-14:]
    if shown:
        print("  last output lines:")
        for line in shown:
            print("    | " + line[:200])
    sys.exit(1)


def run(args, home, cwd, until=(), deadline=40, stdin=subprocess.DEVNULL, grace=1.0):
    """Start args, collect its output until a pattern in `until` matches (then `grace` more seconds), the
    process exits or `deadline` passes, then kill its whole process group. Returns the text."""
    env = {"HOME": home, "PATH": os.environ["PATH"], "TERM": "dumb"}
    proc = subprocess.Popen(args, cwd=cwd, env=env, stdin=stdin, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, start_new_session=True)
    lines = queue.Queue()

    def pump():
        for raw in iter(proc.stdout.readline, b""):
            lines.put(raw.decode("utf-8", "replace"))
        lines.put(None)

    threading.Thread(target=pump, daemon=True).start()
    patterns = [re.compile(p, re.S) for p in until]
    text, end, matched = "", time.time() + deadline, None
    while time.time() < end:
        try:
            line = lines.get(timeout=0.25)
        except queue.Empty:
            if proc.poll() is not None and lines.empty():
                break
            line = ""
        if line is None:
            break
        text += line
        if matched is None and any(p.search(text) for p in patterns):
            matched = time.time()
        if matched is not None and time.time() - matched >= grace:
            break
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    proc.wait()
    while True:
        try:
            line = lines.get_nowait()
        except queue.Empty:
            break
        text += line or ""
    return text


def make_home(name, files):
    home = os.path.join(TMP, name)
    os.makedirs(os.path.join(home, ".codex"))
    for fname, content in files.items():
        with open(os.path.join(home, ".codex", fname), "w", encoding="utf-8") as fh:
            fh.write(content)
    return home


def git(cwd, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false"] + list(args),
                   cwd=cwd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def render(provider):
    """Scaffold the module for a provider; return (scaffold dir, [config.toml, review overlay, bulk overlay])."""
    cfg, out = os.path.join(TMP, provider + ".json"), os.path.join(TMP, "scaffold-" + provider)
    subprocess.run([sys.executable, "test/codex-cli/_make-config.py", cfg, "provider=" + provider], check=True, cwd=REPO)
    subprocess.run([sys.executable, "configure.py", "--config", cfg, "--yes", "--dir", out], check=True, cwd=REPO,
                   stdout=subprocess.DEVNULL)
    with open(os.path.join(out, "docs", "codex-setup.md"), encoding="utf-8") as fh:
        blocks = re.findall(r"```toml\n(.*?)```", fh.read(), flags=re.S)
    if len(blocks) != 3:
        fail("render", "expected three TOML blocks in docs/codex-setup.md, got %d" % len(blocks))
    return out, blocks


def toml_value(block, key):
    m = re.search(r'^%s\s*=\s*"([^"]+)"' % re.escape(key), block, flags=re.M)
    return m.group(1) if m else None


def header(text, key):
    m = re.search(r"^%s:\s*(.+?)\s*$" % re.escape(key), text, flags=re.M)
    return m.group(1) if m else None


def ok(message):
    print("  ok  " + message)


# ---- the version and the flags the module relies on
version = subprocess.run([CODEX, "--version"], capture_output=True, text=True, timeout=120).stdout.strip()
print("real Codex CLI: " + version)
exec_help = subprocess.run([CODEX, "exec", "--help"], capture_output=True, text=True, timeout=120, stdin=subprocess.DEVNULL).stdout
for flag in ("--sandbox", "--ephemeral", "--output-last-message", "--profile", "--config", "--skip-git-repo-check"):
    if flag not in exec_help:
        fail("flags", "`codex exec --help` no longer lists %s, which cross-review.sh or the workflow uses" % flag)
if "read-only" not in exec_help or "<name>.config.toml" not in exec_help:
    fail("flags", "`codex exec --help` no longer says --sandbox takes read-only or that --profile layers <name>.config.toml")
ok("exec has --sandbox read-only, --ephemeral, -o, --profile (an overlay file), -c, --skip-git-repo-check")

scaffold_openai, (cfg_openai, review, bulk) = render("openai")
_, (cfg_azure, _r, _b) = render("azure")
review_model, review_effort = toml_value(review, "model"), toml_value(review, "model_reasoning_effort")
base_model = toml_value(cfg_openai, "model")
work = os.path.join(TMP, "work")
os.makedirs(work)
git(work, "init", "-q")
out_file = os.path.join(TMP, "last-message.txt")
EXEC = [CODEX, "exec", "--sandbox", "read-only", "--ephemeral", "--skip-git-repo-check"]
HEADER_END = r"session id:"

# ---- the rendered docs are accepted, and the overlay is what applies
home = make_home("openai", {"config.toml": cfg_openai, "review.config.toml": review, "bulk.config.toml": bulk})
t = run(EXEC + ["--profile", "review", "-o", out_file, "say ok"], home, work, until=[HEADER_END, "Error loading config"])
if "Error loading config" in t:
    fail("overlay", "Codex rejects the config.toml or review.config.toml that docs/codex-setup.md tells users to write", t)
got = (header(t, "model"), header(t, "reasoning effort"), header(t, "provider"), header(t, "sandbox"))
if got != (review_model, review_effort, "openai", "read-only"):
    fail("overlay", "--profile review did not apply the review overlay (model, effort, provider, sandbox) = %r, wanted %r"
         % (got, (review_model, review_effort, "openai", "read-only")), t)
ok("--profile review layers review.config.toml over config.toml (%s, effort %s), read-only sandbox" % (review_model, review_effort))

# ---- a typo in the profile name is NOT an error (this is why cross-review.sh checks the file itself)
t = run(EXEC + ["--profile", "reveiw", "-o", out_file, "say ok"], home, work, until=[HEADER_END, "Error loading config"])
if "Error loading config" in t:
    fail("typo", "Codex now errors on a profile with no file; the guard in cross-review.sh and its comment may be unnecessary", t)
if header(t, "model") != base_model:
    fail("typo", "a profile with no file no longer falls back to config.toml's model (%s)" % base_model, t)
ok("a profile name with no file falls back to the base config silently")

# ---- a broken overlay and the removed [profiles.*] form are errors
bad = make_home("bad-overlay", {"config.toml": cfg_openai, "review.config.toml": "model = \n"})
t = run(EXEC + ["--profile", "review", "say ok"], bad, work, until=["Error loading config", HEADER_END])
if "Error loading config" not in t or "review.config.toml" not in t:
    fail("broken overlay", "a malformed review.config.toml no longer produces an error naming the file", t)
old = make_home("old-profiles", {"config.toml": cfg_openai + '\n[profiles.review]\nmodel = "x"\n', "review.config.toml": review})
t = run(EXEC + ["--profile", "review", "say ok"], old, work, until=["Error loading config", HEADER_END])
if "Error loading config" not in t or "profiles" not in t:
    fail("old profiles", "--profile with a [profiles.*] table in config.toml no longer errors, which /verify-setup check 19 relies on", t)
ok("a broken overlay and the removed [profiles.*] form both error")

# ---- the Azure block loads, names its env var, and wire_api = chat is rejected
az = make_home("azure", {"config.toml": cfg_azure, "review.config.toml": review})
t = run(EXEC + ["--profile", "review", "say ok"], az, work, until=["AZURE_OPENAI_API_KEY", "Error loading config"])
if "Error loading config" in t or header(t, "provider") != "azure" or "AZURE_OPENAI_API_KEY" not in t:
    fail("azure", "the rendered Azure block no longer loads as provider azure with env_key AZURE_OPENAI_API_KEY", t)
chat = make_home("azure-chat", {"config.toml": cfg_azure.replace('wire_api = "responses"', 'wire_api = "chat"')})
t = run(EXEC + ["say ok"], chat, work, until=["Error loading config", HEADER_END])
if "Error loading config" not in t or "wire_api" not in t:
    fail("azure", 'wire_api = "chat" is no longer rejected; the doc says "responses" is the only value', t)
ok('the Azure block loads (provider azure, env_key named) and wire_api = "chat" is rejected')

# ---- provider keys in a trusted project's .codex/config.toml are ignored
proj = os.path.join(TMP, "proj")
os.makedirs(os.path.join(proj, ".codex"))
git(proj, "init", "-q")
with open(os.path.join(proj, ".codex", "config.toml"), "w", encoding="utf-8") as fh:
    fh.write(cfg_azure)
trusted = make_home("project", {"config.toml": cfg_openai + '\n[projects."%s"]\ntrust_level = "trusted"\n' % proj})
t = run(EXEC + ["-o", out_file, "say ok"], trusted, proj, until=["Ignored unsupported project-local config keys"])
if "Ignored unsupported project-local config keys" not in t or "model_provider" not in t or header(t, "provider") != "openai":
    fail("project config", "a provider block in a trusted project's .codex/config.toml is no longer ignored; the module ships none because it was", t)
ok("a provider block in a trusted project's .codex/config.toml is ignored, with a warning")

# ---- project_doc_max_bytes is a real key, and 0 keeps AGENTS.md out of the prompt
t = run(EXEC + ["-c", "project_doc_max_bytes=abc", "say ok"], home, work, until=["Error loading config", HEADER_END])
if "Error loading config" not in t or "project_doc_max_bytes" not in t:
    fail("project_doc_max_bytes", "-c project_doc_max_bytes=abc is no longer a type error, so the key may have been renamed or removed", t)
debug_help = subprocess.run([CODEX, "debug", "--help"], capture_output=True, text=True, timeout=120, stdin=subprocess.DEVNULL).stdout
if "prompt-input" not in debug_help:
    print("  skip  `codex debug prompt-input` does not exist in this version; the AGENTS.md switch-off was not checked")
else:
    docs = os.path.join(TMP, "docrepo")
    os.makedirs(docs)
    git(docs, "init", "-q")
    marker = "ROOT_MARK_6c1f"
    with open(os.path.join(docs, "AGENTS.md"), "w", encoding="utf-8") as fh:
        fh.write("# Rules\n%s: text a pull request wrote\n" % marker)

    def prompt(extra):
        return subprocess.run([CODEX, "debug", "prompt-input"] + extra + ["hello"], cwd=docs, capture_output=True, text=True, timeout=120,
                              stdin=subprocess.DEVNULL, env={"HOME": home, "PATH": os.environ["PATH"], "TERM": "dumb"}).stdout
    if marker not in prompt([]):
        fail("AGENTS.md", "the default prompt no longer contains the repository's AGENTS.md, so this check proves nothing")
    if marker in prompt(["-c", "project_doc_max_bytes=0"]):
        fail("AGENTS.md", "-c project_doc_max_bytes=0 no longer keeps AGENTS.md out of the prompt: holdout-review.yml relies on it")
    ok("-c project_doc_max_bytes=0 removes the repository's AGENTS.md from the model-visible prompt")

# ---- the shipped script starts even when its caller's stdin is an open pipe
script = os.path.join(scaffold_openai, ".claude", "skills", "cross-review", "scripts", "cross-review.sh")
repo = os.path.join(TMP, "xr")
os.makedirs(repo)
git(repo, "init", "-q", "-b", "main")
with open(os.path.join(repo, "calc.py"), "w", encoding="utf-8") as fh:
    fh.write("def add(a, b):\n    return a + b\n")
git(repo, "add", "calc.py")
git(repo, "commit", "-q", "-m", "calc")
git(repo, "switch", "-q", "-c", "feature")
with open(os.path.join(repo, "calc.py"), "w", encoding="utf-8") as fh:
    fh.write("def add(a, b):\n    return a - b\n")
git(repo, "commit", "-q", "-am", "oops")
t = run(["bash", script], home, repo, until=[r"OpenAI Codex v\d"], deadline=60, stdin=subprocess.PIPE)
if "OpenAI Codex v" not in t:
    fail("cross-review.sh", "with an open stdin the shipped script never got Codex to start a session (it waits for stdin to end)", t)
ok("the shipped cross-review.sh starts a Codex session with an open stdin pipe")

print("PASS: the codex-cli module's docs, flags and script behave as documented against the real %s" % version)
