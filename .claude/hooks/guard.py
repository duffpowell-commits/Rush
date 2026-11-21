#!/usr/bin/env python3
"""PreToolUse guard: blocks the mistakes Duff's sessions have had to be corrected on more than once.
Rules live here, not in prose, because a hook can't drift (Reddit r/ClaudeCode tip, Nov 2026:
"corrected twice = a hook"). Copy .claude/ into every game repo; per-repo settings sit in
.claude/hooks/guard.cfg. Each rule names the lesson it comes from. Delete a rule nobody trips.

  1. No force push (house rule in every repo). --force-with-lease stays allowed.
  2. No direct push to main: main ships to players, so it only moves by a merged PR with green CI.
  3. No push of code that hasn't passed the tests on exactly this tree (run tools/test.sh first).
     "Run the tests before every push" was prose for weeks and red builds still shipped.
  4. Signing keys: never written, generated or committed in plain form (one keystone for all
     games; Lethemoor keeps its own; a lost or changed key breaks in-app updates forever).
  5. No secrets in commits (.env, tokens, unencrypted keystores).
Exit 2 + a reason on stderr = the call is blocked and the reason goes back to Claude.
"""
import json, os, re, subprocess, sys

def deny(msg):
    sys.stderr.write("BLOCKED by .claude/hooks/guard.py: " + msg + "\n")
    sys.exit(2)

def git(repo, *args):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""

def repo_of(cmd, cwd):
    """The repo a command acts on: a leading `cd X` or `git -C X` wins over the session cwd."""
    m = re.search(r"(?:^|&&|;)\s*cd\s+([^\s;&]+)", cmd) or re.search(r"git\s+-C\s+([^\s]+)", cmd)
    path = os.path.expanduser(m.group(1)) if m else cwd
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    top = git(path, "rev-parse", "--show-toplevel")
    return top or None

def cfg(repo):
    out = {}
    p = os.path.join(repo, ".claude/hooks/guard.cfg")
    if os.path.exists(p):
        for line in open(p):
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip()
    return out

def code_changed(repo, c):
    """True if this push carries files that the tests cover (default: Godot code and data)."""
    pat = re.compile(c.get("code_files", r"\.(gd|tscn|tres|cfg|godot|gdshader|json|txt)$"))
    base = git(repo, "merge-base", "HEAD", "origin/main") or git(repo, "rev-parse", "HEAD~1")
    files = git(repo, "diff", "--name-only", base, "HEAD").splitlines() if base else []
    return any(pat.search(f) and not f.startswith((".claude/", "docs/", ".github/")) for f in files)

def check_bash(cmd, cwd):
    if re.search(r"\bgit\b[^|;&]*\bpush\b", cmd):
        if re.search(r"\s(--force(?!-with-lease)|-f\b)|\s\+\S+", cmd):
            deny("force push. House rule: never force push. Merge the remote branch in instead "
                 "(git fetch origin <branch> && git merge --no-edit FETCH_HEAD).")
        if re.search(r"\bpush\b.*\s(\S+:)?(refs/heads/)?(main|master)\b(?!-)", cmd):
            deny("direct push to main. main ships to players: push your branch, open a PR, "
                 "let CI go green, then merge the PR.")
        repo = repo_of(cmd, cwd)
        if repo:
            c = cfg(repo)
            if c.get("test_cmd") and code_changed(repo, c):
                tree = git(repo, "rev-parse", "HEAD^{tree}")
                mark = os.path.join(repo, ".claude/state/tests_pass")
                passed = open(mark).read().strip() if os.path.exists(mark) else ""
                if tree != passed:
                    deny("tests have not passed on this exact commit. Run `tools/test.sh` in %s "
                         "(it runs: %s), commit, then push." % (repo, c["test_cmd"]))
    if re.search(r"keytool\b.*-genkey", cmd):
        deny("generating a signing key. Every game signs with the keystone (docs/SIGNING.md in "
             "godot-game-starter); Lethemoor keeps its own. Never make another key.")
    if re.search(r"\bgit\b[^|;&]*\bcommit\b", cmd):
        repo = repo_of(cmd, cwd)
        if repo:
            staged = git(repo, "diff", "--cached", "--name-only").splitlines()
            if "-a" in cmd.split() or "--all" in cmd:
                staged += git(repo, "diff", "--name-only").splitlines()
            bad = [f for f in staged if re.search(r"(^|/)\.env(\.|$)|\.(jks|p12|pem)$|\.keystore$|(^|/)secrets?\.", f)]
            if bad:
                deny("secret-looking files staged: %s. Keys only go in as *.keystore.enc; "
                     "secrets live in GitHub Actions secrets, which Duff sets himself." % ", ".join(bad))

def check_write(path):
    if re.search(r"(^|/)signing/[^/]*\.(keystore|enc|sha256|jks)$", path or ""):
        deny("writing a signing key file (%s). Keys are made once by make_keystone.yml and never "
             "change; Lethemoor's key never goes into another repo." % path)

def main():
    try:
        e = json.load(sys.stdin)
    except Exception:
        return
    tool, inp, cwd = e.get("tool_name", ""), e.get("tool_input", {}) or {}, e.get("cwd") or os.getcwd()
    if tool == "Bash":
        check_bash(inp.get("command", ""), cwd)
    elif tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        check_write(inp.get("file_path", ""))

if __name__ == "__main__":
    main()
