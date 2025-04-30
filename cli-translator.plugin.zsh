#!/usr/bin/env zsh
# ┌───────────────────────────────────────────────────────────────────────────┐
# │ cli-translator.plugin.zsh                                                │
# │ Translate natural language into CLI commands and analyze files           │
# │ Version: 2.6                                                              │
# └───────────────────────────────────────────────────────────────────────────┘

# -------------------- Configuration ----------------------------------------
typeset -g CT_MODEL="gpt-4.1-mini"
typeset -g CT_TEMP="0.0"
typeset -g CT_MAX_TOKENS="512"
typeset -g CT_BACKUP_DIR="${HOME}/.cli_translator_backups"

# Colors (ANSI escape codes for echo -e)
typeset -g CT_COLOR_CMD="\033[32m"      # green
typeset -g CT_COLOR_FILE="\033[32m"     # green
typeset -g CT_COLOR_BULLET="\033[33m"   # yellow
typeset -g CT_COLOR_ERROR="\033[31m"    # red
typeset -g CT_COLOR_RESET="\033[0m"

# -------------------- Helpers ------------------------------------------------
_ct::print() { echo -e "$@"; }
_ct::error() { echo -e "${CT_COLOR_ERROR}Error:${CT_COLOR_RESET} $1"; }

_ct::check_prereqs() {
  [[ -n "$OPENAI_API_KEY" ]] || { _ct::error "OPENAI_API_KEY not set."; return 1; }
  for cmd in curl jq file stat; do
    command -v $cmd &>/dev/null || { _ct::error "$cmd is required."; return 1; }
  done
  return 0
}

# -------------------- OpenAI API caller -------------------------------------
_ct::call_api() {
  local prompt="$1" system_msg="$2"
  local temp=${3:-$CT_TEMP} max_tok=${4:-$CT_MAX_TOKENS}
  local req=$(mktemp) res=$(mktemp)

  # Build JSON safely via jq
  jq -n \
    --arg m   "$CT_MODEL" \
    --arg sys "$system_msg" \
    --arg usr "$prompt" \
    --argjson t "$temp" \
    --argjson mt "$max_tok" \
  '{
     model:       $m,
     temperature: $t,
     max_tokens:  $mt,
     messages: [
       {role:"system", content:$sys},
       {role:"user",   content:$usr}
     ]
   }' >"$req"

  curl -sS https://api.openai.com/v1/chat/completions \
       -H "Content-Type: application/json" \
       -H "Authorization: Bearer $OPENAI_API_KEY" \
       -d @"$req" >"$res" || { rm -f "$req" "$res"; return 1; }

  rm -f "$req"

  if grep -q '"error":' "$res"; then
    local msg=$(jq -r '.error.message' <"$res")
    rm -f "$res"
    echo "ERROR: $msg"
    return 1
  fi

  jq -r '.choices[0].message.content // empty' <"$res"
  rm -f "$res"
}

# -------------------- Sanitizer ------------------------------------------------
_ct::sanitize() {
  local s="$1"
  s=${s//\\033\[[0-9;]*[mK]/}
  s=${s//$'\e'*\[[0-9;]*[mK]/}
  echo "$s"
}

# -------------------- Execute & Repair ---------------------------------------
_ct::run_cmd() {
  local cmd="$1"
  _ct::print "${CT_COLOR_CMD}→ $cmd${CT_COLOR_RESET}"
  mkdir -p "$CT_BACKUP_DIR"

  # Backup before destructive rm
  if [[ $cmd == rm\ * ]]; then
    echo -n "Backup targets before rm? [y/N] "
    read -r ans
    if [[ $ans =~ ^[Yy] ]]; then
      local ts=$(date +%Y%m%d_%H%M%S)
      local bdir="$CT_BACKUP_DIR/$ts"
      mkdir -p "$bdir"
      for f in ${cmd#rm }; do cp -r -- "$f" "$bdir"/ &>/dev/null; done
      echo "Saved backup → $bdir"
    fi
  fi

  CT_LAST_OUT=$(mktemp)
  CT_LAST_ERR=$(mktemp)
  eval "$cmd" \
    > >(tee "$CT_LAST_OUT") \
    2> >(tee "$CT_LAST_ERR" >&2)
  CT_LAST_CODE=$?
}

_ct::repair() {
  local cmd="$1" intent="$2"
  local err; err=$(<"$CT_LAST_ERR")
  local system_msg="You are an expert sysadmin. Given the failed command, its error, and the user's intent, provide a corrected one-line shell command without commentary."
  local prompt
  prompt=$(printf 'Intent: %s\nCommand: %s\nError: %s\nFix:' "$intent" "$cmd" "$err")
  local fix=$(_ct::call_api "$prompt" "$system_msg")
  echo "${fix##*$'\n'}"
}

# -------------------- File Analysis ------------------------------------------
_ct::format_analysis() {
  while IFS= read -r L; do
    if [[ $L == '====='* ]]; then
      echo -e "${CT_COLOR_FILE}$L${CT_COLOR_RESET}"
    elif [[ $L == '-'* ]]; then
      echo -e "  ${CT_COLOR_BULLET}$L${CT_COLOR_RESET}"
    else
      echo "$L"
    fi
  done
}

analyze() {
  (( $# )) || { _ct::error "Usage: analyze <file|dir|glob> [...]"; return 1; }
  local -a all blob_lines
  for pat in "$@"; do
    local -a m=( ${(N)~pat} )
    (( ${#m} )) && all+=( "${m[@]}" ) || _ct::error "No match: $pat"
  done
  (( ${#all[@]} )) || { _ct::error "No files to analyze."; return 1; }

  for f in "${all[@]}"; do
    local mime sz mt
    mime=$(file --mime-type -b -- "$f" 2>/dev/null)
    if stat --version &>/dev/null; then
      sz=$(stat -c '%s' -- "$f" 2>/dev/null||echo "?")
      mt=$(stat -c '%y' -- "$f" 2>/dev/null||echo "?")
    else
      sz=$(stat -f '%z' -- "$f" 2>/dev/null||echo "?")
      mt=$(stat -f '%Sm' -- "$f" 2>/dev/null||echo "?")
    fi
    blob_lines+=( "===== $f | size=${sz} | modified=$mt =====" )

    if [[ -d $f ]]; then
      local cnt; cnt=$(ls -A -- "$f" | wc -l)
      blob_lines+=( "[Directory: $cnt entries]" )
    elif [[ $mime == text/* ]]; then
      while IFS= read -r L; do
        blob_lines+=( "$L" )
      done < "$f"
    else
      blob_lines+=( "[Binary: $mime]" )
    fi
  done

  local blob out
  blob=$(printf '%s\n' "${blob_lines[@]}")
  local system_msg="You are a concise code analyst. For each file, give max 2 bullet points describing purpose and issues."
  out=$(_ct::call_api "$blob" "$system_msg")
  echo -e "$out" | _ct::format_analysis
}

# -------------------- Natural Language → Command -----------------------------
nl() {
  if [[ $1 == analyze || $1 == inspect ]]; then
    shift; analyze "$@"; return
  fi
  (( $# )) || { _ct::print "Usage: nl <natural language>"; return 1; }
  _ct::check_prereqs || return
  local intent="$*"
  local system_msg="Act as a CLI translator. Return only a single line command without commentary."
  local cmd=$(_ct::call_api "$intent" "$system_msg")
  [[ $cmd == ERROR:* ]] && _ct::error "${cmd#ERROR: }" && return 1
  cmd=$(_ct::sanitize "$cmd")

  echo -e -n "${CT_COLOR_CMD}run $cmd${CT_COLOR_RESET} [y/n] "; read -r ans
  [[ $ans =~ ^[Yy] ]] || return
  _ct::run_cmd "$cmd"

  if (( CT_LAST_CODE != 0 )); then
    _ct::print "${CT_COLOR_ERROR}Command failed (exit $CT_LAST_CODE). Fixing...${CT_COLOR_RESET}"
    local fixed
    fixed=$(_ct::repair "$cmd" "$intent")
    fixed=$(_ct::sanitize "$fixed")
    echo -e -n "${CT_COLOR_CMD}run $fixed${CT_COLOR_RESET} [y/n] "; read -r ans2
    [[ $ans2 =~ ^[Yy] ]] && _ct::run_cmd "$fixed"
  fi
}

# Aliases
alias translate='nl'
alias cmd='nl'

# vim: ft=zsh ts=2 sw=2 sts=2 et