# Footgun review: `git-prompt.pl`

Findings from an evaluation of `git-prompt.pl` (v0.2). Every item below was
verified with a live repro unless noted otherwise. Line numbers refer to the
current version of the script.

**TL;DR:** The scary-looking parts are actually correct (readline markers,
UTF-8 round-trip, malformed-byte handling — all verified in a real pty). The
real footguns are in rebase detection, diverged-branch display, and a few
Perl falsiness traps. Highest-value fixes are #1, #2, #3, and the falsy-`0`
guard — all small, local changes.

## Verified correct (don't touch)

- **`\x01/\x02` readline wrapping** (lines 139–155): rendered a real prompt in a
  pty — markers stripped, ANSI escapes intact, zero control bytes leaked. The
  comment's explanation is accurate.
- **UTF-8 round-trip** (lines 8, 181, 248): branch `café-à` JSON output
  contained `c3 a9 c3 a0` exactly once — no double encoding. `decode()` on
  malformed bytes yields U+FFFD without dying, as the comment claims.
- **Empty repo**: porcelain v2 still prints `# branch.head <name>` and exits 0,
  so the prompt works on unborn branches.
- **Missing git binary**: silent, clean exit 127, empty output.
- **One git call**, `LC_ALL=C`, `--no-optional-locks`, newline *before* the
  reset escape (so `$()` doesn't strip it and the two-line prompt survives) —
  all deliberate and correct.

## Real footguns

### 1. Rebase detection breaks in subdirectories — HIGH ✅ FIXED

Location: lines 234, 240.

`.git/rebase-*` is checked relative to the CWD. Repro: repo mid-rebase with
conflict:

```
repo root:    Git Branch: (topic) [⇄1]        ← correct, recovered from head-name
repo/subdir:  Git Branch: (DETACHED_HEAD) [⇄1] ← broken
```

The comment only acknowledges the worktree-file limitation; `cd`-ing into any
subdirectory during a rebase silently degrades the branch name. Same failure
in linked worktrees and submodules (`.git` is a file there).

**Fix:** without extra forks — walk up parent dirs until `-d "$found/.git"`,
and if `.git` is a *file* read `gitdir: <path>` from it.

**Status (2026-11-18):** fixed. A new `find_gitdir()` resolves the git dir with
no extra forks: GIT_DIR from the environment if set (git itself honors it),
otherwise a walk up from the CWD to the nearest `.git`, following the
`gitdir: <path>` indirection when `.git` is a *file* (absolute paths in
linked worktrees, relative ones resolved against the dir containing the
`.git` file, as in submodules). Verified mid-rebase with a conflict from:
repo root, nested subdirs (several levels), a linked worktree (root and
subdir), a submodule (root and subdir), and with GIT_DIR exported — all now
recover the branch from head-name, including `--json`. Clean, dirty,
detached-HEAD, empty-repo, non-repo, root-mid-rebase, and conflicted-`git am`
outputs are byte-identical to the old script, with no new warnings on STDERR.
`git am` is still misdetected as a rebase (#3, out of scope here).

### 2. Diverged branches show only the ahead count — HIGH ✅ FIXED

Location: lines 193–202.

The `if ($ahead) { } elsif ($behind)` dropped the other number. On `+2 -3` the
prompt shows `+2` — the user believes a push will work when it will actually
be rejected.

**Fix:** show both when both are nonzero (e.g. `+2 -3`).

**Status (2026-11-18):** fixed. Both counts are now parsed independently and
a diverged branch renders `[+2 -3]` with each count in its own color
(ahead cyan 117, behind red 196). Note: `ahead`/`behind` in the `--json`
output are now the actual counts instead of `1`. Verified against in-sync,
ahead-only, behind-only, diverged, and diverged+dirty repos; clean, dirty,
conflict, empty-repo, and mid-rebase outputs unchanged.

### 3. `git am` misdetected as a rebase — MEDIUM

Location: line 234.

`git am` reuses `.git/rebase-apply`. Verified: a conflicted `git am` leaves
the dir present and the script paints the branch merge-orange with
`rebasing=1`.

**Fix:** git's own `__git_ps1` distinguishes these by checking for
`rebase-apply/applying` (present = `am`, absent = rebase) — same one-stat
check fixes this. Related: an apply-backend rebase has no `head-name`, so it
still shows `DETACHED_HEAD`.

### 4. Perl falsiness traps — MEDIUM

Location: line 64.

- A branch literally named `0` is creatable (`git checkout -b 0` works) and
  falsy → `$i && $i->{'branch'}` fails → **the prompt vanishes entirely** on
  that branch.
- Same class in `argv()`: `--json 0` consumes `0` as the flag's value, which
  is falsy → **JSON mode silently disabled** (verified).
- A branch named `(detached)` is a legal refname, and porcelain v2 prints it
  literally → collides with the sentinel → shows `DETACHED_HEAD` (verified).
  Absurd edge case, but the falsy-`0` bug is worth fixing.

**Fix:** use `defined && length` instead of truthiness for the branch check;
`exists`-based flag checks in `argv()`.

### 5. Any git failure == silent vanishing — MEDIUM

Location: lines 170–175.

Exit-code-only check with `2>/dev/null`: git < 2.11 (no `--porcelain=v2`),
git < 2.15 (no `--no-optional-locks`), dubious-ownership `safe.directory`
errors, or a corrupt index all exit nonzero — indistinguishable from "not a
repo," so the user just loses the prompt with zero hint.

**Fix:** document a git version floor, or emit a one-time stderr note.

### 6. Warnings leak onto the terminal — LOW

Location: line 245.

In PS1 usage, STDERR lands in the prompt area. If
`.git/rebase-merge/head-name` exists but is empty: `$head_name = <$fh>` →
undef → verified `Use of uninitialized value in chomp` warning printed to the
terminal, then `branch` ends up undef → no output.

**Fix:** guard the read.

### 7. `require JSON` isn't core — LOW

Location: line 55.

`JSON::PP` has been core since Perl 5.14; the `JSON` frontend is not. On a
stock perl, `--json` dies with `Can't locate JSON.pm`.

**Fix:** fall back to `JSON::PP` (identical `->new->encode` API). Also decide
whether `--json` outside a repo should print `0` (current) or `null`/`{}`.

### 8. `argv()` parser quirks — LOW

Location: lines 256–274.

Verified: `--debug --` produces a phantom key `-`; `--json -5` produces a
phantom key `5`; option values can't start with `-`. Only two flags exist
today, so impact is low.

**Fix:** support `--` termination and an `exists`-based check.

### 9. Shell/terminal coupling — LOW

No `isatty` gate and no `--no-color`: piped output or use under zsh/fish emits
raw SOH/STX + 256-color escapes (zsh uses `%{ %}`, not `\001`). The `⇄`
(U+21C4, line 124) also assumes a UTF-8 terminal; there's a commented-out
ASCII fallback. README is bash-only, so this is documentation more than bug.

**Fix:** optional `--no-color` flag or isatty gating.

### 10. Per-prompt cost — CONTEXTUAL

Measured ~10 ms in a small repo (bash→perl→sh→git chain on every prompt).
Scales with `git status` cost — huge worktrees, NFS, and untracked-file scans
can make the prompt lag. No timeout guard exists.

**Mitigations for slow repos:** `status.showUntrackedFiles`, untracked cache.

## Minor doc drift

- The header snippet's guard (`[[ -z $GIT_PROMPT ]]`, line 19) differs from
  the README's (`[[ ! "$PS1" =~ "$GIT_PROMPT_PATH" ]]`). Both work; keep them
  in sync so users don't mix the two.
- README text says "It's 2013" — stale.

## Suggested fix order

1. Subdir gitdir resolution (footgun #1) — ✅ done
2. Show both ahead and behind (footgun #2) — ✅ done
3. `rebase-apply/applying` stat to distinguish `git am` (footgun #3)
4. Falsy-`0` guard on branch + argv flags (footgun #4)
