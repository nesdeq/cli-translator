# CLI Translator

Zsh plugin that translates natural language into shell commands using OpenAI's GPT-5-mini with reasoning.

## Features

- Natural language to CLI translation
- Permission-based execution
- Auto-repair failed commands
- File/directory analysis

## Requirements

- Zsh
- OpenAI API key
- curl, jq, file, stat

## Installation

```bash
git clone https://github.com/nesdeq/cli-translator ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/cli-translator
```

Add to `.zshrc`:
```bash
plugins=(... cli-translator)
export OPENAI_API_KEY=your_key
```

## Usage

```bash
nl <description>        # translate and run
nl analyze <files>      # analyze files
```

Aliases: `translate`, `cmd`

## Examples

```bash
nl list all python files
nl find largest files in home directory
nl analyze *.py
```

## Configuration

Edit in plugin file:
```bash
CT_MODEL="gpt-5-mini"
CT_REASONING="medium"           # low, medium, high
CT_MAX_COMPLETION_TOKENS="2048"
```

## License

GPLv3 - See LICENSE file