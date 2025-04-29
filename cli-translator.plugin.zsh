#!/usr/bin/env zsh
# cli-translator: Translate natural language into CLI commands
# Version: 2.5

# Configuration
API_MODEL="gpt-4.1-mini"
API_TEMP=0.0
API_MAX_TOKENS=512

# Colors for output - only keeping GREEN for commands
GREEN="\033[32m"
RESET="\033[0m"

SYSTEM=$(uname -a)

# Description of the system, optional and can leave empty ""
# DESCRIPTION="macOS 15.3.2 on a MacBook Pro M4 Pro 14-inch system"
DESCRIPTION=""

COMMON="You are an expert sys admin, running $DESCRIPTION, uname -a is $SYSTEM. Your task is to produce effective and efficient, executable shell commands. IMPORTANT: Return ONLY the raw command as plain text with no formatting, no markdown, no code blocks, and no explanations. Your output will be momentarily executed directly in the terminal."

# Print message (no color)
print_msg() {
  local msg=$1
  echo "$msg"
}

# Print error message
print_error() {
  local msg=$1
  echo "Error: $msg"
}

# Check prerequisites
check_prereqs() {
  if [[ -z "$OPENAI_API_KEY" ]]; then
    print_error "OPENAI_API_KEY environment variable is not set."
    echo "Set it with: export OPENAI_API_KEY=your_api_key"
    return 1
  fi

  for cmd in curl jq; do
    if ! command -v $cmd &>/dev/null; then
      print_error "$cmd is required but not installed."
      return 1
    fi
  done
  
  return 0
}

# Call OpenAI API
call_api() {
  local prompt="$1"
  local system="$2"
  local temp="${3:-$API_TEMP}"
  local max_tokens="${4:-$API_MAX_TOKENS}"
  
  # Create temporary files for request and response
  local req_file=$(mktemp)
  local resp_file=$(mktemp)
  
  # Create simple JSON without relying on complex escaping
  cat > "$req_file" <<EOF
{
  "model": "$API_MODEL",
  "messages": [
    {"role": "system", "content": "$system"},
    {"role": "user", "content": "$prompt"}
  ],
  "temperature": $temp,
  "max_tokens": $max_tokens
}
EOF

  # Make API request
  curl -s -S "https://api.openai.com/v1/chat/completions" \
       -H "Content-Type: application/json" \
       -H "Authorization: Bearer $OPENAI_API_KEY" \
       -d @"$req_file" > "$resp_file"
       
  local curl_status=$?
  
  # Clean up request file
  rm "$req_file"
  
  # Check for curl errors
  if [[ $curl_status -ne 0 ]]; then
    rm "$resp_file"
    return 1
  fi
  
  # Extract content or error
  if grep -q "\"error\":" "$resp_file"; then
    local error=$(grep -o '"message": *"[^"]*"' "$resp_file" | cut -d'"' -f4)
    rm "$resp_file"
    echo "ERROR: $error"
    return 1
  fi
  
  # Extract response content without processing escapes
  local content=""
  content=$(cat "$resp_file" | jq -r '.choices[0].message.content')
  rm "$resp_file"
  
  if [[ -z "$content" ]]; then
    echo "ERROR: Empty response"
    return 1
  fi
  
  echo "$content"
  return 0
}

# Sanitize command of ANSI escape sequences and other unwanted characters
sanitize_command() {
  local cmd="$1"
  
  # Remove both forms of ANSI escape sequences
  # 1. Literal form (as they appear in strings)
  cmd=${cmd//\\033\[[0-9;]*[a-zA-Z]/}
  
  # 2. Actual escape characters
  cmd=${cmd//$'\e'\[[0-9;]*[a-zA-Z]/}
  
  # 3. Additional form with backslashes
  cmd=${cmd//\\\e\[[0-9;]*[a-zA-Z]/}
  
  # 4. The specific case observed
  cmd=${cmd//\\033\[0m/}
  
  echo "$cmd"
}

# Get command from natural language
get_command() {
  local nl_request="$1"
  local system="$COMMON Act as a command-line tool that converts natural language requests into executable shell commands."
  local response=$(call_api "$nl_request" "$system")
  
  # Return error if API call failed
  if [[ "$response" == ERROR:* ]]; then
    echo "$response"
    return 1
  fi
  
  # Sanitize the response
  local sanitized=$(sanitize_command "$response")
  echo "$sanitized"
  return 0
}

# Fix a failed command
fix_command() {
  local failed_cmd="$1"
  local error_msg="$2"
  local orig_request="$3"
  
  local system="$COMMON Given a failed command, its error message, and the user's intent, provide the corrected command without commentary. If dependencies are missing, include installation commands with appropriate && chaining. Check for command alternatives when possible, using conditional execution patterns like 'command || alternative_command'. Verify file/directory existence with tests where needed. Always provide a complete, executable solution that can be run directly in terminal with all necessary preparations and fallbacks included." 
  local prompt="Intent: $orig_request\nFailed command: $failed_cmd\nError: $error_msg\nProvide correct command:"
  
  local response=$(call_api "$prompt" "$system")
  
  # Return error if API call failed
  if [[ "$response" == ERROR:* ]]; then
    echo "$response"
    return 1
  fi
  
  # Sanitize the response
  local sanitized=$(sanitize_command "$response")
  echo "$sanitized"
  return 0
}

# Run a command and handle output
run_command() {
  local cmd="$1"
  
  # refuse empty
  if [[ -z "$cmd" ]]; then
    print_error "Empty command"
    return 1
  fi
  
  # 1) Detect destructive rm and offer backup
  if [[ "$cmd" =~ ^rm[[:space:]] ]]; then
    echo "WARNING: This will delete files/directories:"
    echo "  $cmd"
    echo -n "Backup targets before deletion? [y/N]: "
    read -r _bk
    if [[ "$_bk" =~ ^[Yy] ]]; then
      local TSTAMP=$(date +'%Y%m%d_%H%M%S')
      local BACKUP_DIR="${HOME}/.cli_translator_backups/${TSTAMP}"
      mkdir -p "$BACKUP_DIR"
      # extract arguments after 'rm'
      local args=${cmd#rm*}
      for tgt in $args; do
        cp -r -- "$tgt" "$BACKUP_DIR"/ 2>/dev/null || :
      done
      echo "Backed up targets to $BACKUP_DIR"
    fi
  fi
  
  # 2) Stream and capture both stdout & stderr
  local out_file=$(mktemp)
  local err_file=$(mktemp)
  # live‐stream to screen, but also tee into files
  eval "$cmd" 2> >(tee "$err_file" >&2) | tee "$out_file"
  local exit_code=$?
  
  # 3) export paths & exit code for later fix_command usage
  export RUN_CMD_OUT_FILE="$out_file"
  export RUN_CMD_ERR_FILE="$err_file"
  export RUN_CMD_EXIT_CODE=$exit_code

  return $exit_code
}

# Main function
nl() {
  # Check if arguments are provided
  if [[ $# -eq 0 ]]; then
    echo "Usage: nl <description of command>"
    echo "Example: nl list all files sorted by size"
    return 1
  fi
  
  # Check prerequisites
  check_prereqs || return 1
  
  # Get natural language request
  local request="$*"
  
  # Get command from API
  local cmd
  cmd=$(get_command "$request")
  
  # Check for API errors
  if [[ "$cmd" == ERROR:* ]]; then
    print_error "API Error: ${cmd#ERROR: }"
    return 1
  fi
  
  # Confirm command execution with new format - only command in green
  echo -ne "run ${GREEN}${cmd}${RESET} [y/n]? "
  read -r answer
  
  if [[ ! "$answer" =~ ^[yY](es)?$ ]]; then
    return 0
  fi

  # run the command (streams output live, captures it)
  run_command "$cmd"
  local exit_code=$RUN_CMD_EXIT_CODE

  # on failure, feed back stderr and propose a fix
  if (( exit_code != 0 )); then
    echo "→ Command failed with exit code $exit_code"
    local error
    error=$(<"$RUN_CMD_ERR_FILE")
    local fixed_cmd
    fixed_cmd=$(fix_command "$cmd" "$error" "$request")
    
    # Check for API errors
    if [[ "$fixed_cmd" == ERROR:* ]]; then
      print_error "Couldn't fix: ${fixed_cmd#ERROR: }"
      return 1
    fi
    
    # Confirm fixed command execution with only command in green
    echo -ne "run ${GREEN}${fixed_cmd}${RESET} [y/n]? "
    read -r fix_answer
    
    # clean up temp files
    rm -f "$RUN_CMD_OUT_FILE" "$RUN_CMD_ERR_FILE"

    if [[ "$fix_answer" =~ ^[yY](es)?$ ]]; then
      run_command "$fixed_cmd"
      local final_code=$RUN_CMD_EXIT_CODE
      rm -f "$RUN_CMD_OUT_FILE" "$RUN_CMD_ERR_FILE"
      return $final_code
    else
      return 0
    fi
  fi
  
  return 0
}

# Aliases
alias translate="nl"
alias cmd="nl"