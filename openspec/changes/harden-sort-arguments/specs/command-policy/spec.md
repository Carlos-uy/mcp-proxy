## MODIFIED Requirements

### Requirement: Command policy MUST reject exec-capable allowlist bypass vectors

The server MUST validate command arguments and reject exec-capable allowlist bypass vectors before process creation, even when the command name itself is allowed. For an allowlisted `git`, the server MUST reject every command-scoped configuration override supplied through either `-c <name=value>` or `-c<name=value>` without attempting to classify the configuration key as safe. The server MUST also reject persistent `git config` invocations, known alternate binary names for hardened command families, and command-wrapper or shell-escape tools that would execute a non-allowlisted command through their arguments. For an allowlisted GNU `sort` or its `gsort` alias, the server MUST reject options that select an external compression program, direct output to a program-selected path, read an external file list, or select an external temporary directory. Rejection MUST cover full and uniquely abbreviated long options and separated, attached, or clustered short-option forms accepted by GNU option parsing. Option parsing MUST stop at a discrete `--` so later option-like filename operands remain data.

#### Scenario: Sort external compression program is rejected

**Given**: `ALLOW_COMMANDS` includes `sort`
**When**: a client executes `['sort', '--compress-program=/tmp/program', 'input']`
**Then**: the server rejects the command before creating a subprocess and the external program is not executed

#### Scenario: Sort direct output is rejected

**Given**: `ALLOW_COMMANDS` includes `sort` and the working directory is `/tmp/work`
**When**: a client executes `['sort', '-o', '/tmp/outside', 'input']`
**Then**: the server rejects the command before creating a subprocess and `/tmp/outside` is not created or modified

#### Scenario: Sort external file-list and temporary-directory options are rejected

**Given**: `ALLOW_COMMANDS` includes `sort`
**When**: a client supplies `--files0-from`, `-T`, or `--temporary-directory` with an attacker-selected path
**Then**: the server rejects the command before creating a subprocess

#### Scenario: GNU alias and abbreviated options use the same policy

**Given**: `ALLOW_COMMANDS` includes `gsort`
**When**: a client supplies an accepted abbreviation or clustered form such as `--comp=/tmp/program`, `--out=/tmp/outside`, `-ro/tmp/outside`, or `-rT/tmp/elsewhere`
**Then**: the server rejects the command before creating a subprocess

#### Scenario: Ordinary sort remains allowed

**Given**: `ALLOW_COMMANDS` includes `sort`
**When**: a client executes ordinary sorting arguments or `['sort', '-S', '1M', 'input']`
**Then**: the command is allowed subject to other policy checks

#### Scenario: Option parsing ends at the operand delimiter

**Given**: `ALLOW_COMMANDS` includes `sort`
**When**: a client executes `['sort', '--', '--output=/tmp/name']`
**Then**: the option-like token after `--` is treated as a filename operand and is allowed subject to other policy checks
