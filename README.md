# CLI Translator

An Oh My Zsh plugin that translates natural language descriptions into command-line commands using OpenAI's GPT-4o.

## Features

- Translates natural language to CLI commands
- Asks for permission before executing commands
- Auto-fixes failed commands with one retry attempt
- Sanitizes commands for safe execution
- Colorized command output for better readability

## Requirements

- Oh My Zsh
- OpenAI API key
- curl (usually pre-installed)
- jq (for JSON parsing)

## Installation

1. Clone this repository to your Oh My Zsh plugins directory:

   ```bash
   git clone https://github.com/nesdeq/cli-translator ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/cli-translator
   ```

2. Add the plugin to your `.zshrc` file:

   ```bash
   # Edit your .zshrc file
   nano ~/.zshrc
   
   # Add cli-translator to your plugins list
   plugins=(... cli-translator)
   ```

3. Set your OpenAI API key in your `.zshrc` file or another appropriate place:

   ```bash
   export OPENAI_API_KEY=your_api_key_here
   ```

4. Restart your terminal or run `source ~/.zshrc`

## Usage

Translate a natural language description to a command:

```bash
nl <your description>
```

Or use one of the aliases:

```bash
translate <your description>
cmd <your description>
```

The plugin will:
1. Translate your request to a command
2. Show you the command (highlighted in green)
3. Ask for your permission before executing it
4. If the command fails, attempt to fix it and ask for permission again

## Examples

### File operations

```bash
# Create a directory
nl create a directory called test
run mkdir test [y/n]? y

# Find files
nl find all .jpg files in the current directory
run find . -name "*.jpg" [y/n]? y

# Count lines in all Python files
nl count the number of lines in all python files recursively
run find . -name "*.py" | xargs wc -l [y/n]? y
```

### System information

```bash
# Show open ports
nl show all listening ports
run lsof -i -P | grep LISTEN [y/n]? y

# Check disk space
nl show disk usage in human-readable format
run df -h [y/n]? y

# Find largest files
nl find the 10 largest files in the current directory
run find . -type f -exec du -sh {} \; | sort -rh | head -n 10 [y/n]? y
```

### Git operations

```bash
# Set global git config from local
nl set current local git user name and email to global as well
run git config --global user.name "$(git config --local user.name)"; git config --global user.email "$(git config --local user.email)" [y/n]? y

# Show commit history
nl show git commit history with date and author
run git log --pretty=format:"%h %ad | %s [%an]" --date=short [y/n]? y
```

### Text processing

```bash
# Search for a pattern in files
nl find all files containing the word "TODO"
run grep -r "TODO" . [y/n]? y

# Replace text in multiple files
nl replace all occurrences of foo with bar in all text files
run find . -type f -name "*.txt" -exec sed -i 's/foo/bar/g' {} \; [y/n]? y
```

### Network operations

```bash
# Test connection
nl check if google.com is reachable
run ping -c 4 google.com [y/n]? y

# Download a file
nl download the latest version of a file from example.com/file.zip
run curl -L -o file.zip example.com/file.zip [y/n]? y
```

## Error Handling

If a command fails, the plugin will attempt to fix it based on the error message:

```bash
nl find files modified in the last 24 horus
run find . -mtime -1 [y/n]? y
Command failed with exit code 1
find: unknown option -- 1

run find . -mtime -1d [y/n]? y
```

## License

MIT