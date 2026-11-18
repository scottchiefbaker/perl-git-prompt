# AGENTS.md

Perl git prompt: `git-prompt.pl` is a single script that prints the git branch
and status for a bash `PS1`. It is the whole product.

## Layout

- `git-prompt.pl`: the script. Everything lives here.
- `utils/term-colors.pl`: standalone helper that prints the 256-color palette
  so color codes can be chosen. Not used by the prompt.
- `README.md`: user-facing install and output docs.

## Versioning

- Versions are `MAJOR.MINOR.PATCH`. An odd PATCH (`0.3.1`, `0.3.3`) is
  development; an even PATCH (`0.3.0`, `0.3.2`) is a release. Tags are `vMAJOR.MINOR.PATCH`.
- The version lives in the script header comment (`# Version 0.2.1`). Keep it
  in sync with the tag when cutting a release.

## Commands

- There is no build, test suite, linter, or CI. Verify by running the script.
- Syntax check: `perl -c git-prompt.pl`
- Run the prompt: `perl git-prompt.pl` (`--no-color` and `--json` are options).
- Check color escapes without a tty: `script -qc "perl git-prompt.pl" /dev/null | cat -v`
- Prompt-path check, the one that matters most: run the script inside
  `$()` in a real capture (`script -qc 'bash -c "x=\$(perl git-prompt.pl); printf %s \"\$x\" | cat -v"' /dev/null`).

## Constraints

- Color must stay on by default. `$()` in PS1 captures STDOUT, so **never gate
  color on `-t STDOUT`**: that strips color from the prompt. This was tried and
  reverted (commit `2e1a931`).
- Color is controlled by `--no-color` and the `NO_COLOR` env var only.
- Color escapes are wrapped in `\x01`/`\x02` (readline ignore markers). Keep
  them when adding color output, or prompt line-length math breaks.
- Keep the newline before the final reset escape. `$()` strips trailing
  newlines, so the reset must come after it.
- Git output is raw bytes. Decode once with `decode('UTF-8', ...)`; the
  `:utf8` STDOUT layer encodes once. Do not double-encode.
- Git is called once per prompt (`git status --porcelain=v2 --branch`). Avoid
  adding forks; the prompt runs on every command.
- Git 2.15+ is required (`--no-optional-locks`, `--porcelain=v2`).
- JSON uses `JSON::PP` (core), not `JSON`, so `--json` works on stock perl.

## Behavior notes

- `DETACHED_HEAD` is the sentinel for detached HEAD. A branch literally named
  `(detached)` would collide with it (known, not fixed).
- `git am` is detected as a rebase because it shares `.git/rebase-apply`
  (known, not fixed).
- Rebase detection resolves the git dir itself (`find_gitdir()`), so it works
  in subdirectories, linked worktrees, and submodules without forking git.

## Docs

- When changing output or options, update the matching section in `README.md`.
