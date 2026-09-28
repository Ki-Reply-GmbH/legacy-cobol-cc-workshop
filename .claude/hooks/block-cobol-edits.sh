#!/usr/bin/env bash
# PreToolUse hook: hard-blocks Edit/Write on COBOL source files (.cbl, .cob, .cpy, .scb),
# independent of which agent or session is running. Exit 2 = block; stderr is fed back
# to the model as the reason. Exit 0 = allow.
set -euo pipefail

payload="$(cat)"

# Extract tool_input.file_path without a jq dependency (payload is single-line JSON).
file_path="$(printf '%s' "$payload" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)"/\1/')"

if [[ -z "$file_path" ]]; then
  exit 0   # no file_path in this call (shouldn't happen for Edit/Write) — allow
fi

if printf '%s' "$file_path" | grep -qiE '\.(cbl|cob|cpy|scb)$'; then
  echo "Blocked: $file_path is COBOL source. This repo's workshop hook (.claude/hooks/block-cobol-edits.sh) hard-blocks Edit/Write on .cbl/.cob/.cpy/.scb files for every agent and session. If you genuinely need to change COBOL source, do it outside Claude Code, or remove/adjust this hook in .claude/settings.json first." >&2
  exit 2
fi

exit 0
