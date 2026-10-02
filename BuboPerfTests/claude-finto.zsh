#!/bin/zsh
# Il claude finto di OnboardingPerfTests: risponde a --version, a auth status e a ogni prompt dell'Agent SDK con una
# parola, subito. Parla quanto basta dello stream-json dell'SDK: successo a ogni control_request; init, un text_delta,
# il messaggio e un result a ogni messaggio dell'utente. Ogni esecuzione aggiunge ora, processo padre e
# argomenti a $HOME/claude-invocations.log. La versione sta sopra la minima di bridge/compat.json.
zmodload zsh/datetime
print -r -- "$EPOCHREALTIME ppid=$PPID $*" >> "$HOME/claude-invocations.log"
case $1 in
  --version) print '2.1.285 (Claude Code)'; exit 0 ;;
  auth) print '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"max"}'; exit 0 ;;
esac
session=
for argument in "$@"; do [[ $argument == --session-id=* ]] && session=${argument#--session-id=}; done
: ${session:=$(/usr/bin/uuidgen)}
envelope="\"parent_tool_use_id\":null,\"session_id\":\"$session\""
while IFS= read -r line; do
  case $line in
    *'"type":"control_request"'*)
      request=${${line#*\"request_id\":\"}%%\"*}
      print -r -- "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"$request\",\"response\":{}}}" ;;
    *'"type":"user"'*)
      print -r -- "{\"type\":\"system\",\"subtype\":\"init\",\"cwd\":\"$PWD\",\"session_id\":\"$session\",\"tools\":[],\"mcp_servers\":[],\"model\":\"claude-finto\",\"permissionMode\":\"default\",\"slash_commands\":[],\"apiKeySource\":\"none\",\"claude_code_version\":\"2.1.285\",\"output_style\":\"default\",\"agents\":[],\"skills\":[],\"plugins\":[],\"capabilities\":[],\"uuid\":\"$(/usr/bin/uuidgen)\"}"
      print -r -- "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"pronto\"}},$envelope,\"uuid\":\"$(/usr/bin/uuidgen)\"}"
      print -r -- "{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_stop\",\"index\":0},$envelope,\"uuid\":\"$(/usr/bin/uuidgen)\"}"
      print -r -- "{\"type\":\"assistant\",\"message\":{\"id\":\"msg_finto\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-finto\",\"content\":[{\"type\":\"text\",\"text\":\"pronto\"}],\"stop_reason\":\"end_turn\",\"stop_sequence\":null,\"usage\":{\"input_tokens\":1,\"output_tokens\":1}},$envelope,\"uuid\":\"$(/usr/bin/uuidgen)\"}"
      print -r -- "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"duration_ms\":1,\"duration_api_ms\":1,\"num_turns\":1,\"result\":\"pronto\",\"total_cost_usd\":0,\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0},\"modelUsage\":{},\"permission_denials\":[],\"session_id\":\"$session\",\"uuid\":\"$(/usr/bin/uuidgen)\"}" ;;
  esac
done
