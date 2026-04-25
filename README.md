# Ask

**Ask** is a PowerShell wrapper around `pi` that makes it easier to interact with an LLM from the command line.

It adds convenient session handling, optional file context, pipeline support, and a small persistent state file so you can keep using the same session and model across calls.

## Features

- Named sessions with `-s`
- Persistent default session with `-r`
- Optional model persistence
- File context with `-f`
- Pipeline support
- Session reset and one-off mode
- PowerShell profile integration

## Requirements

- PowerShell 7 or Windows PowerShell 5.1
- `pi` available in your `PATH`
- A compatible model/provider configured in `pi`

## Installation

1. Copy `Ask-Function.ps1` to:
   `C:\Users\xquis\Documents\PowerShell\Scripts\Ask-Function.ps1`

2. Make sure your PowerShell profile loads it:

```powershell
. "$HOME\Documents\PowerShell\Scripts\Ask-Function.ps1"
```

3. Restart PowerShell.

## Usage

```powershell
ask [question] [options]
cat file | ask [question]
```

### Options

- `-f`, `--File`  Path to a file to include in the context.
- `-m`, `--Model`  Sets the model and saves it as the last one used by `ask`.
- `-s`, `--Session`  Uses a named session stored in the user profile.
- `-r`, `--RememberSession`  Reuses the current session; if none exists, creates a random one and makes it the default.
- `--ClearSession`  Removes the saved default session.
- `--ResetSession`  Clears the current named session before asking again.
- `--ResetModel`  Resets the last saved model to the automatic default.
- `--NoSession`  Ignores any saved session and does not reuse context.
- `-h`, `--Help`  Shows the help menu.

## Examples

```powershell
ask how to format a disk in pwsh
ask -m openai/gpt-4o "use this model and save it for next time"
ask -s abc123 "let's continue this conversation"
ask -s abc123 -r "make this session the default"
ask -r "start a new persistent session"
ask -f .\.env "check for exposed secrets"
cat .\script.py | ask explain this code -m openai/gpt-4o
ask -NoSession "one-off question"
ask -ResetModel "go back to the automatic default model"
ask -s abc123 -ResetSession "start over in this session"
```

## How it works

`ask` stores its state in:

- `Documents\PowerShell\Ask-Function.state.json`
- `Documents\PowerShell\Ask-Function-pi-sessions\`

This is how it remembers:

- the default session
- the last used model
- session folders for `pi`

## Suggested description

If you want a short GitHub description, I would use:

> A PowerShell wrapper for `pi` that makes command-line AI conversations easier, with persistent sessions, model memory, and file/pipeline context.

## Notes

- `-r` creates a random session when needed and saves it as the default session.
- `-s <name>` lets you pick a specific session name.
- `-NoSession` bypasses any saved default session.
