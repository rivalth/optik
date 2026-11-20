#!/bin/sh
# Lets Optik answer through Claude Code (your Claude subscription) when there is
# no API key. Optik runs it from its Application Scripts folder (a leftover of
# the App Sandbox, which Optik left on 2026-11-20). Install:
#
#   mkdir -p ~/Library/Application\ Scripts/io.github.rivalth.optik
#   cp scripts/optik-claude-code.sh ~/Library/Application\ Scripts/io.github.rivalth.optik/
#   chmod +x ~/Library/Application\ Scripts/io.github.rivalth.optik/optik-claude-code.sh
#
# Arguments from Optik: $1 the model, $2 the system prompt, $3 "new" or "resume",
# $4 the conversation's session id, $5 (optional) the config of Optik's computer
# tools. Optik keeps one conversation going, so it remembers earlier talks.
# Everything else is fixed here: Claude Code gets web search, reading a web page
# (for match times, weather, news) and Optik's own computer tools (reading the
# screen, clicking and typing with Optik's pointer, files in the home folder),
# which run inside Optik and ask before anything hard to undo. No settings and no
# other MCP servers. It cannot run commands or read files itself.

model="$1"
system_prompt="$2"
mode="$3"
session_id="$4"
tools_config="$5"
[ -n "$model" ] && [ -n "$system_prompt" ] || { echo "usage: $0 <model> <system prompt> new|resume <session id>" >&2; exit 64; }
echo "$session_id" | grep -Eq '^[0-9a-fA-F-]{36}$' || { echo "bad session id" >&2; exit 64; }
case "$mode" in
    new) session_flag="--session-id" ;;
    resume) session_flag="--resume" ;;
    *) echo "bad mode" >&2; exit 64 ;;
esac

for candidate in "$HOME/.local/bin/claude" /opt/homebrew/bin/claude /usr/local/bin/claude; do
    if [ -x "$candidate" ]; then claude="$candidate"; break; fi
done
[ -n "$claude" ] || claude="$(command -v claude)"
[ -n "$claude" ] || { echo "claude not found" >&2; exit 127; }

# Its own folder, so no project's CLAUDE.md is picked up and the conversation
# is found again after a restart.
workdir="$HOME/Library/Application Support/Optik Claude Code"
mkdir -p "$workdir" && cd "$workdir" || exit 1

allowed="WebSearch,WebFetch"
set --
case "$tools_config" in
    "$HOME/Library/Application Support/Optik/"*.json)
        [ -f "$tools_config" ] && { set -- --mcp-config "$tools_config"; allowed="$allowed,mcp__optik"; } ;;
esac

exec "$claude" -p \
    --model "$model" \
    --system-prompt "$system_prompt" \
    "$session_flag" "$session_id" \
    --tools "WebSearch,WebFetch" \
    --allowedTools "$allowed" \
    "$@" \
    --setting-sources "" \
    --strict-mcp-config \
    --disable-slash-commands \
    --input-format stream-json \
    --output-format stream-json \
    --include-partial-messages \
    --verbose
