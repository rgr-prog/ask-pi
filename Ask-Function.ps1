$script:AskProfileRoot = Join-Path $HOME 'Documents\PowerShell'
$script:AskStatePath = Join-Path $script:AskProfileRoot 'Ask-Function.state.json'
$script:AskSessionRoot = Join-Path $script:AskProfileRoot 'Ask-Function-pi-sessions'

if (-not (Test-Path -LiteralPath $script:AskProfileRoot)) {
    New-Item -ItemType Directory -Path $script:AskProfileRoot -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $script:AskSessionRoot)) {
    New-Item -ItemType Directory -Path $script:AskSessionRoot -Force | Out-Null
}

$script:AskState = [ordered]@{
    DefaultSession = $null
    LastModel      = $null
}

if (Test-Path -LiteralPath $script:AskStatePath) {
    try {
        $loadedState = Get-Content -Raw -LiteralPath $script:AskStatePath | ConvertFrom-Json
        if ($null -ne $loadedState.DefaultSession -and $loadedState.DefaultSession.ToString().Trim()) {
            $script:AskState.DefaultSession = $loadedState.DefaultSession.ToString().Trim()
        }

        if ($null -ne $loadedState.LastModel -and $loadedState.LastModel.ToString().Trim()) {
            $script:AskState.LastModel = $loadedState.LastModel.ToString().Trim()
        }
    }
    catch {
        # Ignore corrupted state and continue with default values.
    }
}

function Save-AskState {
    param(
        [string]$DefaultSession = $script:AskState.DefaultSession,
        [string]$LastModel = $script:AskState.LastModel
    )

    $state = [ordered]@{
        DefaultSession = $DefaultSession
        LastModel      = $LastModel
    }

    $state | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $script:AskStatePath -Encoding UTF8
    $script:AskState.DefaultSession = $DefaultSession
    $script:AskState.LastModel = $LastModel
}

function Get-AskActiveSession {
    return $script:AskState.DefaultSession
}

function Get-AskDefaultModel {
    $openAiKey = [System.Environment]::GetEnvironmentVariable('OPENAI_API_KEY')
    if ($openAiKey -and $openAiKey.Trim()) {
        return 'openai/gpt-5.4-mini'
    }

    return 'opencode-go/kimi-k2.6'
}

function Get-AskActiveModel {
    if ($script:AskState.LastModel -and $script:AskState.LastModel.ToString().Trim()) {
        return $script:AskState.LastModel
    }

    return Get-AskDefaultModel
}

function Reset-AskModel {
    $defaultModel = Get-AskDefaultModel
    Save-AskState -LastModel $defaultModel
    return $defaultModel
}

function Normalize-AskSessionName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName
    )

    return ($SessionName.Trim() -replace '[^a-zA-Z0-9._-]', '_')
}

function Get-AskSessionDir {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName
    )

    $safeSessionName = Normalize-AskSessionName -SessionName $SessionName
    $sessionDir = Join-Path $script:AskSessionRoot $safeSessionName

    if (-not (Test-Path -LiteralPath $sessionDir)) {
        New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
    }

    return $sessionDir
}

function Reset-AskSession {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName
    )

    $sessionDir = Get-AskSessionDir -SessionName $SessionName
    if (Test-Path -LiteralPath $sessionDir) {
        Remove-Item -LiteralPath $sessionDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
    return $sessionDir
}

function Get-AskSessionSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName
    )

    $sessionDir = Join-Path $script:AskSessionRoot (Normalize-AskSessionName -SessionName $SessionName)
    if (-not (Test-Path -LiteralPath $sessionDir)) {
        return $null
    }

    $sessionFile = Get-ChildItem -LiteralPath $sessionDir -File -Filter *.jsonl -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $sessionFile) {
        return $null
    }

    foreach ($line in Get-Content -LiteralPath $sessionFile.FullName -ErrorAction SilentlyContinue) {
        if (-not $line -or -not $line.Trim()) { continue }

        try {
            $entry = $line | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            continue
        }

        if ($entry.type -ne 'message' -or $entry.message.role -ne 'user') {
            continue
        }

        $contentParts = @()
        foreach ($block in @($entry.message.content)) {
            if ($block.type -eq 'text' -and $block.text) {
                $contentParts += $block.text
            }
        }

        $summary = ($contentParts -join ' ').Trim()
        if (-not $summary) {
            return $null
        }

        $summary = $summary -replace '^PERGUNTA:\s*', ''
        $summary = ($summary -replace '\s+', ' ').Trim()

        if ($summary.Length -gt 80) {
            $summary = $summary.Substring(0, 77).TrimEnd() + '...'
        }

        return $summary
    }

    return $null
}

function Ask {
    <#
    .SYNOPSIS
        Friendly interface for pi with pipeline support, file context, and persistent named sessions per user.
    .EXAMPLE
        ask how to list processes by memory usage
    .EXAMPLE
        cat error.log | ask "how do I fix this?" -m gpt-4o
    .EXAMPLE
        ask -s abc123 "first question"
    .EXAMPLE
        ask -r "continue the conversation"
    .EXAMPLE
        ask -s abc123 -r "continue the conversation"
    .EXAMPLE
        ask -s abc123 -RememberSession "continue the conversation"
    .EXAMPLE
        ask -NoSession "one-off question without reusing context"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $false, ValueFromRemainingArguments = $true)]
        [string[]]$QuestionParts,

        [Parameter(ValueFromPipeline = $true)]
        $InputObject,

        [Alias("f")]
        [string]$File,

        [Alias("m")]
        [string]$Model,

        [Alias("s")]
        [string]$Session,

        [Alias("r")]
        [switch]$RememberSession,

        [switch]$ClearSession,

        [switch]$ResetSession,

        [switch]$ResetModel,

        [switch]$NoSession,

        [Alias("l")]
        [switch]$ListSessions,

        [Alias("h")]
        [switch]$Help
    )

    begin {
        $script:AskShowHelp = $Help -or ($QuestionParts -contains '--help') -or ($QuestionParts -contains '-h') -or ($QuestionParts -contains '-?') -or ($QuestionParts -contains '/?')

        if ($script:AskShowHelp) {
            Write-Host @"

USAGE:
  ask [question] [options]
  cat file | ask [question]

OPTIONS:
  -f, --File             Path to a file to include in the context.
  -m, --Model            Sets the model and saves it as the last one used by ask.
                         If omitted, uses the last saved model; if none exists, lets pi decide.
  -s, --Session          Uses a named session (e.g. abc123) stored in the user profile.
  -r, --RememberSession  Uses the current session; if none exists, creates a random one and makes it the default for the user.
  --ClearSession         Removes the saved default session from the user profile.
  --ResetSession         Clears the current named session before asking again.
  --ResetModel           Resets the last saved model to the automatic default.
  --NoSession            Ignores any saved session and does not reuse context.
  -l, --ListSessions     Lists saved session folders with one-line summaries and exits.
  -h, --Help             Shows this help menu.

EXAMPLES:
  ask how to format a disk in pwsh
  cat script.py | ask explain this code -m openai/gpt-4o
  ask -f .\.env "check for exposed secrets"
  ask -m openai/gpt-4o "use this model and save it for next time"
  ask -s abc123 "let's continue this conversation"
  ask -s abc123 -r "make this session the default"
  ask -s abc123 -ResetSession "start over in this session"
  ask -ResetModel "go back to the automatic default model"
  ask -NoSession "one-off question"
  ask -l
"@
            return
        }

        $pipelineData = New-Object System.Collections.Generic.List[string]
    }

    process {
        if ($null -ne $InputObject) {
            $pipelineData.Add($InputObject.ToString())
        }
    }

    end {
        if ($script:AskShowHelp) { return }

        if ($ListSessions) {
            $defaultSession = $script:AskState.DefaultSession
            $sessionNames = @()

            if (Test-Path -LiteralPath $script:AskSessionRoot) {
                $sessionNames = Get-ChildItem -LiteralPath $script:AskSessionRoot -Directory -ErrorAction SilentlyContinue |
                    Sort-Object Name |
                    Select-Object -ExpandProperty Name
            }

            if (-not $sessionNames -or $sessionNames.Count -eq 0) {
                Write-Host "No saved sessions found."
                return
            }

            foreach ($name in $sessionNames) {
                $summary = Get-AskSessionSummary -SessionName $name
                if (-not $summary) {
                    $summary = "(sem resumo)"
                }

                if ($defaultSession -and $name -eq $defaultSession) {
                    Write-Host "* $name - $summary"
                }
                else {
                    Write-Host "  $name - $summary"
                }
            }

            return
        }

        $Question = ($QuestionParts -join ' ').Trim()

        if ($ClearSession) {
            Save-AskState -DefaultSession $null
        }

        $effectiveModel = $null
        if ($ResetModel) {
            $effectiveModel = Reset-AskModel
        }
        elseif ($PSBoundParameters.ContainsKey('Model') -and $Model -and $Model.Trim()) {
            $effectiveModel = $Model.Trim()
            Save-AskState -LastModel $effectiveModel
        }
        elseif ($script:AskState.LastModel) {
            $effectiveModel = $script:AskState.LastModel
        }
        else {
            $effectiveModel = Get-AskDefaultModel
            Save-AskState -LastModel $effectiveModel
        }

        $effectiveSession = $null
        if ($Session) {
            $effectiveSession = (Normalize-AskSessionName -SessionName $Session)
        }
        elseif (-not $NoSession -and $script:AskState.DefaultSession) {
            $effectiveSession = $script:AskState.DefaultSession
        }

        $shouldRememberSession = $RememberSession
        if ($shouldRememberSession -and -not $effectiveSession) {
            $effectiveSession = ('ask-' + ([guid]::NewGuid().ToString('N').Substring(0, 12)))
        }

        if ($ResetSession) {
            if (-not $effectiveSession) {
                Write-Warning "Use -Session or set a default session before using -ResetSession."
            }
            else {
                Reset-AskSession -SessionName $effectiveSession | Out-Null
            }
        }

        if ($shouldRememberSession) {
            if (-not $effectiveSession) {
                Write-Warning "Use -Session or -r together with -RememberSession to save a default session."
            }
            else {
                Save-AskState -DefaultSession $effectiveSession
            }
        }

        $finalContextParts = New-Object System.Collections.Generic.List[string]

        if ($Question) {
            $finalContextParts.Add("PERGUNTA: $Question")
        }

        if ($File) {
            if (Test-Path -LiteralPath $File) {
                $fileContent = Get-Content -Raw -LiteralPath $File
                $finalContextParts.Add("CONTEXTO DO ARQUIVO ($File):`n$fileContent")
            }
            else {
                Write-Warning "File not found: $File"
            }
        }

        if ($pipelineData.Count -gt 0) {
            $pipeContent = $pipelineData -join "`n"
            $finalContextParts.Add("CONTEXTO DO PIPELINE:`n$pipeContent")
        }

        $fullPrompt = ($finalContextParts -join "`n`n").Trim()

        if (-not $fullPrompt) {
            Write-Warning "No question or context provided. Use 'ask -h' for help."
            return
        }

        $piArgs = @('-p')

        if ($effectiveSession) {
            $sessionDir = Get-AskSessionDir -SessionName $effectiveSession
            $piArgs += @('-c', '--session-dir', $sessionDir)
        }

        if ($effectiveModel) {
            $piArgs += @('--model', $effectiveModel)
        }

        $piArgs += $fullPrompt

        $global:AskPromptInitialized = $true
        & pi @piArgs
    }
}
