## Implementation Tasks

- [x] Add a dedicated `sort` policy in `src/mcp_shell_server/command_validator.py`, map `gsort` to it, scan options after operands until discrete `--`, reject dangerous full and uniquely abbreviated long options plus separated/attached/clustered short forms, and correctly consume values for benign value-taking short options such as `-k`, `-t`, and `-S`. (verification-id: sort-argument-policy) (verification: unit - `uv run pytest tests/test_command_validator.py`)
- [x] Add `tests/test_command_validator.py` regressions for `sort`, `gsort`, and one absolute-path command: full and shortest unique long forms (`--co`, `--o`, `--fil`, `--t`) in equals/separated forms; longer abbreviations; short forms (`-o FILE`, `-oFILE`, `-ro FILE`, `-roFILE`, `-T DIR`, `-TDIR`, `-rT DIR`, `-rTDIR`); GNU permutation (`sort input -o /tmp/outside`); and compatibility for ordinary sorting, `-r`, `-S 1M`, `-S1T`, `-tT`, `-k2,2`, and operands after `--`. (verification-id: sort-argument-policy) (verification: unit - `uv run pytest tests/test_command_validator.py`)
- [x] Add real-`ShellExecutor` regressions following the existing Git PoC pattern that submit representative `--compress-program` and outside-output payloads, assert rejection before `ProcessManager.create_process`, and assert marker/outside files remain absent; add a GNU/Linux spill-forcing smoke path using a small sort buffer and sufficient input. (verification-id: sort-argument-policy) (verification: integration - `uv run pytest tests/test_shell_executor.py`)
- [x] Update `README.md` and `SECURITY.md` to list the GNU `sort` argument hardening and safe contained-output alternative consistently with existing hardened-vector documentation. (verification-id: sort-argument-policy) (verification: unit - `python3 -c "from pathlib import Path; text=Path('README.md').read_text()+Path('SECURITY.md').read_text(); assert 'sort' in text and 'compress-program' in text"`)
- [x] Update `CHANGELOG.md` specifically under `Unreleased > Security` with a GHSA link, affected range `<=1.1.8`, patched version `1.1.9`, and upgrade guidance without publishing the advisory prematurely. (verification-id: sort-argument-policy) (verification: unit - `python3 -c "from pathlib import Path; section=Path('CHANGELOG.md').read_text().split('## [1.1.8]',1)[0]; assert '### Security' in section and 'GHSA-74g6-ch7r-v7jr' in section and '<=1.1.8' in section and '1.1.9' in section"`)
- [x] Run the complete repository test, lint, formatting-check, and type-check commands and resolve failures attributable to this change. (verification-id: sort-argument-policy) (verification: integration - `uv run pytest && uv run black --check . && uv run isort --check . && uv run ruff check . && uv run mypy src/mcp_shell_server tests`)

## Future Work

- Follow-up change `release-sort-hardening` prepares version `1.1.9`, builds and installs the exact artifact, publishes the package and GitHub Release, verifies the registry artifact, then sets and publishes GHSA-74g6-ch7r-v7jr with affected range `<=1.1.8` and patched version `1.1.9`.
- Audit other allowlisted command families separately; do not expand this security fix without their own evidence and proposal scope.

## Final Validation

Archive validation is the authoritative final OpenSpec gate.
Expected archive gate: `cflx openspec validate harden-sort-arguments --archive-gate`

## Notes

- evidence: `uv run pytest` passed with 303 tests, including 6 new `sort` executor regressions and 51 new `sort` validator cases.
- evidence: `uv run black --check .`, `uv run isort --check .`, `uv run ruff check .`, and `uv run mypy src/mcp_shell_server tests` all succeeded.
- evidence: the GNU spill smoke path resolved `gsort` locally, confirmed raw GNU `sort --compress-program=... -S 64k` creates the marker (proving the vector is live), then confirmed the server rejects the same argv without creating it.
- decision: `--random-source` and `-S`/`--buffer-size` stay allowed per the proposal's out-of-scope list; neither names an executable, and `--random-source` reads a caller-selected path that ordinary operands already permit.
