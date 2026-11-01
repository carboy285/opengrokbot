#!/bin/sh
if [ "$1" = "--version" ]; then printf 'codex-cli fixture\n'; exit 0; fi
if [ "$1" = "login" ]; then exit 0; fi
cat >/dev/null
printf '%s\n' '{"type":"thread.started","thread_id":"ui-test-session"}'
printf '%s\n' '{"type":"item.completed","item":{"id":"reply","type":"agent_message","text":"CLI fixture reply"}}'
