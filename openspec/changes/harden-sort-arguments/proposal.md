---
change_type: implementation
priority: high
dependencies: []
references:
  - GHSA-74g6-ch7r-v7jr
  - src/mcp_shell_server/command_validator.py
  - tests/test_command_validator.py
  - tests/test_shell_executor.py
  - CHANGELOG.md
verifications:
  - id: sort-argument-policy
    requirement: Allowlisted sort invocations cannot launch external programs or bypass working-directory file containment through argv options
    phase: pre-integration
    owner: conflux-acceptance
    trigger: pull-request-validation
    automation: pyproject.toml
    evidence: Validator and executor regressions reject dangerous sort options before subprocess or file side effects while preserving ordinary sorting
    rerun: uv run pytest tests/test_command_validator.py tests/test_shell_executor.py && uv run pytest
    prerequisites: []
    execution_class: repository-local
    completion_role: change-blocking
---

# Harden Sort Arguments

**Change Type**: implementation

## Problem / Context

When `sort` is allowlisted, version `1.1.8` accepts GNU Coreutils options that escape the command-name allowlist or the requested working-directory boundary. `--compress-program` can launch a non-allowlisted executable when temporary files are processed. `-o` and `--output` can write directly to an arbitrary process-accessible path without passing through the server's contained redirection handler. `--files0-from` can read an attacker-selected file containing input paths, and `-T` or `--temporary-directory` can place temporary files outside the requested working directory.

This conflicts with the existing best-effort default argument hardening and contained-redirection guarantees. The narrow fix is a conservative `sort` argument policy, not a general sandbox for every executable.

## Proposed Solution

- Add a command-specific `sort` policy in `CommandValidator`, and map the GNU Coreutils alias `gsort` to the same policy.
- Reject `--compress-program`, `-o`/`--output`, `--files0-from`, and `-T`/`--temporary-directory` in separated, attached, equals, uniquely abbreviated long-option, and clustered short-option forms accepted by GNU option parsing. Covered examples include `--comp`, `--out`, `--files`, `--temp`, `-oFILE`, `-T/tmp`, `-roFILE`, and `-rT/tmp`.
- Stop option parsing at a discrete `--`; later tokens are operands and MUST NOT be rejected merely because their filenames resemble prohibited options.
- Reject direct output options rather than duplicating redirection containment inside `sort` option parsing. Reject file-list and temporary-directory options because they introduce file access outside the validated argv/redirection boundary.
- Do not reject `-S` or `--buffer-size` solely because it influences temporary-file use; it does not itself name a path or executable.
- Preserve ordinary allowlisted sorting, harmless ordering options, and option-like filenames after `--`.
- Add validator and executor regressions proving rejection occurs before subprocess creation and before external files or marker processes can be created.
- Record the security fix under `Unreleased > Security`, identifying versions through `1.1.8` as affected and version `1.1.9` as patched.

These behaviors remain one proposal because the option policy, no-side-effect regressions, and release metadata form one atomic security fix.

## Acceptance Criteria

- `sort` and `gsort` reject full and uniquely abbreviated dangerous long options, including separated and equals forms such as `--compress-program`, `--comp`, `--output`, `--out`, `--files0-from`, `--files`, `--temporary-directory`, and `--temp`.
- Direct-output and temporary-directory short options are rejected in separated, attached, and clustered forms including `-o FILE`, `-oFILE`, `-roFILE`, `-T DIR`, `-TDIR`, and `-rTDIR`.
- An executor-level regression proves rejection occurs before `ProcessManager.create_process`; marker and outside-output files remain absent. A GNU/Linux smoke test forces temporary-file spill with a small sort buffer and sufficient input so the external-program assertion cannot pass vacuously.
- Ordinary commands such as `sort input`, `sort -r input`, and `sort -S 1M input` remain allowed subject to existing policy.
- `sort -- --output=/tmp/name` treats the option-like token as a filename operand rather than a prohibited option.
- The full test suite and repository lint/type checks pass.
- `CHANGELOG.md` states that `<=1.1.8` is affected and that version `1.1.9` contains the fix.

## Explicit Completion Conditions

- `src/mcp_shell_server/command_validator.py` maps `gsort` to `sort` and contains option-aware parsing that covers separated, attached, clustered, equals, and uniquely abbreviated prohibited forms while stopping at `--`.
- `tests/test_command_validator.py` covers those forms for `sort` and `gsort`, plus ordinary sorting, `-S`, and option-like operands after `--`.
- `tests/test_shell_executor.py` proves representative advisory payloads are rejected before process creation and that process/file side effects are absent; a GNU/Linux smoke path forces spill before asserting external-program suppression.
- `CHANGELOG.md` records the fix specifically under `Unreleased > Security` with a GHSA link, affected range, patched version, and upgrade guidance.
- `uv run pytest`, `uv run black --check .`, `uv run isort --check .`, `uv run ruff check .`, and `uv run mypy src/mcp_shell_server tests` succeed.
- `cflx openspec validate harden-sort-arguments --archive-gate` succeeds after implementation.

## Out of Scope

- Building a complete sandbox for every allowlisted executable.
- Implementing contained support for `sort -o`; clients can use the server's existing `>` redirection syntax.
- Rejecting `sort -S` or every resource-control option that does not itself select a path or executable.
- Publishing package version `1.1.9`, its GitHub Release, or the advisory before the patched artifact has been built and verified; tracked by follow-up change `release-sort-hardening`.
- Remediating unrelated command-specific argument policies in this change.
