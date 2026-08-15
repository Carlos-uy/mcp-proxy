## Implementation Tasks

- [ ] Add a dedicated `sort` policy in `src/mcp_shell_server/command_validator.py`, map `gsort` to it, reject dangerous full and uniquely abbreviated long options plus separated/attached/clustered short forms, and stop option parsing at `--` without rejecting `-S`/`--buffer-size`. (verification-id: sort-argument-policy) (verification: unit - `uv run pytest tests/test_command_validator.py`)
- [ ] Add `tests/test_command_validator.py` regressions for `sort` and `gsort`: full, equals, separated, uniquely abbreviated long forms (`--comp`, `--out`, `--files`, `--temp`), attached/clustered short forms (`-oFILE`, `-roFILE`, `-TDIR`, `-rTDIR`), and compatibility cases for ordinary sorting, `-r`, `-S 1M`, and option-like operands after `--`. (verification-id: sort-argument-policy) (verification: unit - `uv run pytest tests/test_command_validator.py`)
- [ ] Add `tests/test_shell_executor.py` regressions that submit representative `--compress-program` and outside-output payloads, assert rejection before `ProcessManager.create_process`, and assert marker/outside files remain absent; add a GNU/Linux spill-forcing smoke path using a small sort buffer and sufficient input. (verification-id: sort-argument-policy) (verification: integration - `uv run pytest tests/test_shell_executor.py`)
- [ ] Update `CHANGELOG.md` specifically under `Unreleased > Security` with a GHSA link, affected range `<=1.1.8`, patched version `1.1.9`, and upgrade guidance without publishing the advisory prematurely. (verification-id: sort-argument-policy) (verification: unit - `python3 -c "from pathlib import Path; section=Path('CHANGELOG.md').read_text().split('## [1.1.8]',1)[0]; assert '### Security' in section and 'GHSA-74g6-ch7r-v7jr' in section and '<=1.1.8' in section and '1.1.9' in section"`)
- [ ] Run the complete repository test, lint, formatting-check, and type-check commands and resolve failures attributable to this change. (verification-id: sort-argument-policy) (verification: integration - `uv run pytest && uv run black --check . && uv run isort --check . && uv run ruff check . && uv run mypy src/mcp_shell_server tests`)

## Future Work

- Follow-up change `release-sort-hardening` prepares version `1.1.9`, builds and installs the exact artifact, publishes the package and GitHub Release, verifies the registry artifact, then sets and publishes GHSA-74g6-ch7r-v7jr with affected range `<=1.1.8` and patched version `1.1.9`.
- Audit other allowlisted command families separately; do not expand this security fix without their own evidence and proposal scope.

## Final Validation

Archive validation is the authoritative final OpenSpec gate.
Expected archive gate: `cflx openspec validate harden-sort-arguments --archive-gate`
