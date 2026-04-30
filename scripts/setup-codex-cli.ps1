param(
    [string] $BaseUrl = "",
    [string] $ApiKey = "",
    [switch] $NoStoreKey,
    [switch] $InstallCodex,
    [switch] $NoInstallCodex
)

$ErrorActionPreference = "Stop"

$DefaultBaseUrl = "__CODEX_LLM_HUB_BASE_URL__"
$ModelCatalogFileName = "llm-hub-model-catalog.json"

function Write-Info {
    param([string] $Message)
    Write-Host $Message
}

function Set-Utf8NoBomFile {
    param(
        [string] $Path,
        [object] $Value
    )
    $encoding = New-Object System.Text.UTF8Encoding $false
    if ($Value -is [array]) {
        $content = [string]::Join([Environment]::NewLine, [string[]] $Value)
    } else {
        $content = [string] $Value
    }
    [System.IO.File]::WriteAllText($Path, $content + [Environment]::NewLine, $encoding)
}

function Normalize-BaseUrl {
    param([string] $Url)
    $normalized = $Url.TrimEnd("/")
    if ($normalized.EndsWith("/codex/v1")) {
        return $normalized
    }
    if ($normalized.EndsWith("/v1")) {
        return $normalized.Substring(0, $normalized.Length - 3) + "/codex/v1"
    }
    if ($normalized.EndsWith("/codex")) {
        return "$normalized/v1"
    }
    return "$normalized/codex/v1"
}

function ConvertTo-TomlString {
    param([string] $Value)
    $escaped = $Value.Replace("\", "\\").Replace('"', '\"')
    return '"' + $escaped + '"'
}

function ConvertTo-PowerShellSingleQuotedString {
    param([string] $Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-ConfigHome {
    if (-not [string]::IsNullOrWhiteSpace($env:XDG_CONFIG_HOME)) {
        return $env:XDG_CONFIG_HOME
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        return $env:LOCALAPPDATA
    }
    return (Join-Path $HOME ".config")
}

$BaseUrlSource = "arg"
if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrlSource = "default"
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_LLM_HUB_BASE_URL)) {
        $BaseUrl = $env:CODEX_LLM_HUB_BASE_URL
        $BaseUrlSource = "env"
    } elseif (-not [string]::IsNullOrWhiteSpace($env:OPENAI_BASE_URL)) {
        $BaseUrl = $env:OPENAI_BASE_URL
        $BaseUrlSource = "env"
    } elseif ($DefaultBaseUrl -ne "__CODEX_LLM_HUB_BASE_URL__") {
        $BaseUrl = $DefaultBaseUrl
    }
}

if ($BaseUrlSource -eq "default" -and -not [string]::IsNullOrWhiteSpace($BaseUrl)) {
    $enteredBaseUrl = Read-Host "Codex gateway URL [$BaseUrl]"
    if (-not [string]::IsNullOrWhiteSpace($enteredBaseUrl)) {
        $BaseUrl = $enteredBaseUrl
    }
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = Read-Host "Codex gateway URL, for example https://host/codex/v1"
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    throw "Base URL missing."
}

$BaseUrl = Normalize-BaseUrl $BaseUrl

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    if (-not [string]::IsNullOrWhiteSpace($env:LLM_HUB_API_KEY)) {
        $ApiKey = $env:LLM_HUB_API_KEY
    } elseif (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
        $ApiKey = $env:OPENAI_API_KEY
    }
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $secret = Read-Host "LiteLLM API key" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    try {
        $ApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "API key missing."
}

if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    if ($NoInstallCodex) {
        Write-Info "Codex CLI is not installed; skipping because -NoInstallCodex was set."
    } elseif (Get-Command npm -ErrorAction SilentlyContinue) {
        Write-Info "Installing Codex CLI with npm..."
        & npm install -g "@openai/codex"
    } else {
        Write-Info "Codex CLI is not installed and npm was not found."
        Write-Info "Install Node.js/npm, then run: npm install -g @openai/codex"
    }
}

$CodexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    Join-Path $HOME ".codex"
} else {
    $env:CODEX_HOME
}
$BinDir = Join-Path $HOME ".local\bin"
$ConfigFile = Join-Path $CodexHome "config.toml"
$CatalogFile = Join-Path $CodexHome $ModelCatalogFileName
$EnvDir = Join-Path (Get-ConfigHome) "llm-hub"
$EnvFile = Join-Path $EnvDir "codex.env.ps1"

New-Item -ItemType Directory -Force -Path $CodexHome, $BinDir, $EnvDir | Out-Null

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = @()
if (-not [string]::IsNullOrWhiteSpace($userPath)) {
    $pathParts = $userPath.Split(";") | Where-Object { $_ }
}
if ($pathParts -notcontains $BinDir) {
    $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $BinDir } else { "$BinDir;$userPath" }
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
}
$currentProcessPath = if ([string]::IsNullOrWhiteSpace($env:Path)) { "" } else { $env:Path }
if (($currentProcessPath.Split(";") | Where-Object { $_ }) -notcontains $BinDir) {
    $env:Path = if ([string]::IsNullOrWhiteSpace($currentProcessPath)) { $BinDir } else { "$BinDir;$currentProcessPath" }
}

$catalog = @'
{
  "models": [
    {
      "slug": "qwen3.6-27b",
      "display_name": "Local Qwen 27B",
      "description": "Local Qwen3.6-27B through llm-hub, non-thinking mode.",
      "default_reasoning_level": "minimal",
      "supported_reasoning_levels": [
        {
          "effort": "minimal",
          "description": "Use the non-thinking local model route."
        }
      ],
      "shell_type": "shell_command",
      "visibility": "list",
      "supported_in_api": true,
      "priority": 100,
      "additional_speed_tiers": [],
      "availability_nux": null,
      "upgrade": null,
      "base_instructions": "You are Codex, a coding agent. Work carefully, use tools when useful, and keep responses concise.",
      "model_messages": {
        "instructions_template": "You are Codex, a coding agent. Work carefully, use tools when useful, and keep responses concise.\n\n{{ personality }}",
        "instructions_variables": {
          "personality_default": "",
          "personality_friendly": "",
          "personality_pragmatic": ""
        }
      },
      "supports_reasoning_summaries": false,
      "default_reasoning_summary": "none",
      "support_verbosity": false,
      "default_verbosity": "low",
      "apply_patch_tool_type": "freeform",
      "web_search_tool_type": "text",
      "truncation_policy": {
        "mode": "tokens",
        "limit": 28000
      },
      "supports_parallel_tool_calls": false,
      "supports_image_detail_original": false,
      "context_window": 32768,
      "max_context_window": 32768,
      "effective_context_window_percent": 85,
      "experimental_supported_tools": [],
      "input_modalities": [
        "text"
      ],
      "supports_search_tool": false
    },
    {
      "slug": "qwen3.6-27b-thinking",
      "display_name": "Local Qwen 27B Thinking",
      "description": "Local Qwen3.6-27B through llm-hub with llama.cpp thinking enabled.",
      "default_reasoning_level": "minimal",
      "supported_reasoning_levels": [
        {
          "effort": "minimal",
          "description": "Thinking is controlled by this model alias."
        }
      ],
      "shell_type": "shell_command",
      "visibility": "list",
      "supported_in_api": true,
      "priority": 101,
      "additional_speed_tiers": [],
      "availability_nux": null,
      "upgrade": null,
      "base_instructions": "You are Codex, a coding agent. Work carefully, use tools when useful, and keep responses concise.",
      "model_messages": {
        "instructions_template": "You are Codex, a coding agent. Work carefully, use tools when useful, and keep responses concise.\n\n{{ personality }}",
        "instructions_variables": {
          "personality_default": "",
          "personality_friendly": "",
          "personality_pragmatic": ""
        }
      },
      "supports_reasoning_summaries": false,
      "default_reasoning_summary": "none",
      "support_verbosity": false,
      "default_verbosity": "low",
      "apply_patch_tool_type": "freeform",
      "web_search_tool_type": "text",
      "truncation_policy": {
        "mode": "tokens",
        "limit": 28000
      },
      "supports_parallel_tool_calls": false,
      "supports_image_detail_original": false,
      "context_window": 32768,
      "max_context_window": 32768,
      "effective_context_window_percent": 85,
      "experimental_supported_tools": [],
      "input_modalities": [
        "text"
      ],
      "supports_search_tool": false
    }
  ]
}
'@
Set-Utf8NoBomFile -Path $CatalogFile -Value $catalog

$existingConfig = @()
if (Test-Path $ConfigFile) {
    $existingConfig = Get-Content -Path $ConfigFile
}

$filteredConfig = New-Object System.Collections.Generic.List[string]
$skip = $false
foreach ($line in $existingConfig) {
    if ($line -match '^\[profiles\."llm-hub"\]$' -or
        $line -match '^\[profiles\."llm-hub-thinking"\]$' -or
        $line -match '^\[model_providers\."llm-hub"\]$') {
        $skip = $true
        continue
    }
    if ($line -match '^\[') {
        $skip = $false
    }
    if (-not $skip) {
        $filteredConfig.Add($line)
    }
}

$catalogToml = ConvertTo-TomlString $CatalogFile
$baseUrlToml = ConvertTo-TomlString $BaseUrl
$llmHubConfig = @"

[profiles."llm-hub"]
model = "qwen3.6-27b"
model_provider = "llm-hub"
model_catalog_json = $catalogToml
model_context_window = 32768
model_auto_compact_token_limit = 28000
model_reasoning_effort = "minimal"
personality = "none"
web_search = "disabled"
tools_view_image = false

[profiles."llm-hub-thinking"]
model = "qwen3.6-27b-thinking"
model_provider = "llm-hub"
model_catalog_json = $catalogToml
model_context_window = 32768
model_auto_compact_token_limit = 28000
model_reasoning_effort = "minimal"
personality = "none"
web_search = "disabled"
tools_view_image = false

[model_providers."llm-hub"]
name = "Local LLM Hub"
base_url = $baseUrlToml
env_key = "OPENAI_API_KEY"
wire_api = "responses"
"@

$newConfig = @($filteredConfig) + ($llmHubConfig -split "`r?`n")
Set-Utf8NoBomFile -Path $ConfigFile -Value $newConfig

if (-not $NoStoreKey) {
    $envContent = @(
        '$env:OPENAI_API_KEY = ' + (ConvertTo-PowerShellSingleQuotedString $ApiKey),
        '$env:CODEX_LLM_HUB_BASE_URL = ' + (ConvertTo-PowerShellSingleQuotedString $BaseUrl)
    )
    Set-Utf8NoBomFile -Path $EnvFile -Value $envContent
    try {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        & icacls $EnvFile /inheritance:r /grant:r "${currentUser}:F" | Out-Null
    } catch {
        Write-Info "Could not tighten permissions on $EnvFile; continuing."
    }
}

$wrapper = @'
$ErrorActionPreference = "Stop"

function Normalize-BaseUrl {
    param([string] $Url)
    $normalized = $Url.TrimEnd("/")
    if ($normalized.EndsWith("/codex/v1")) { return $normalized }
    if ($normalized.EndsWith("/v1")) { return $normalized.Substring(0, $normalized.Length - 3) + "/codex/v1" }
    if ($normalized.EndsWith("/codex")) { return "$normalized/v1" }
    return "$normalized/codex/v1"
}

if (-not [string]::IsNullOrWhiteSpace($env:CODEX_LLM_HUB_ENV_FILE)) {
    $envFile = $env:CODEX_LLM_HUB_ENV_FILE
} elseif (-not [string]::IsNullOrWhiteSpace($env:XDG_CONFIG_HOME)) {
    $envFile = Join-Path $env:XDG_CONFIG_HOME "llm-hub\codex.env.ps1"
} elseif (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $envFile = Join-Path $env:LOCALAPPDATA "llm-hub\codex.env.ps1"
} else {
    $envFile = Join-Path $HOME ".config\llm-hub\codex.env.ps1"
}

if (Test-Path $envFile) {
    . $envFile
}

if ([string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) {
    Write-Error "OPENAI_API_KEY is not set. Rerun setup-codex-cli.ps1 or export your LiteLLM user key first."
    exit 1
}

$extraConfig = @()
$baseUrl = $env:CODEX_LLM_HUB_BASE_URL
if ([string]::IsNullOrWhiteSpace($baseUrl)) {
    $baseUrl = $env:OPENAI_BASE_URL
}
if (-not [string]::IsNullOrWhiteSpace($baseUrl)) {
    $baseUrl = Normalize-BaseUrl $baseUrl
    $extraConfig = @("-c", "model_providers.llm-hub.base_url=`"$baseUrl`"")
}
Remove-Item Env:OPENAI_BASE_URL -ErrorAction SilentlyContinue

& codex --profile __PROFILE__ --disable apps --disable image_generation --disable multi_agent --disable plugins --disable tool_suggest -c "analytics.enabled=false" @extraConfig @args
exit $LASTEXITCODE
'@

$normalWrapper = $wrapper.Replace("__PROFILE__", "llm-hub")
$thinkingWrapper = $wrapper.Replace("__PROFILE__", "llm-hub-thinking")
Set-Utf8NoBomFile -Path (Join-Path $BinDir "codex-llm-hub.ps1") -Value $normalWrapper
Set-Utf8NoBomFile -Path (Join-Path $BinDir "codex-llm-hub-thinking.ps1") -Value $thinkingWrapper

$cmdNormal = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-llm-hub.ps1" %*
exit /b %ERRORLEVEL%
'@
$cmdThinking = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-llm-hub-thinking.ps1" %*
exit /b %ERRORLEVEL%
'@
Set-Content -Path (Join-Path $BinDir "codex-llm-hub.cmd") -Value $cmdNormal -Encoding ascii
Set-Content -Path (Join-Path $BinDir "codex-llm-hub-thinking.cmd") -Value $cmdThinking -Encoding ascii

Write-Info "Codex llm-hub setup complete."
Write-Info "Base URL: $BaseUrl"
Write-Info "Config: $ConfigFile"
Write-Info "Helpers: $(Join-Path $BinDir 'codex-llm-hub.cmd') and $(Join-Path $BinDir 'codex-llm-hub-thinking.cmd')"
if (-not $NoStoreKey) {
    Write-Info "Key env file: $EnvFile"
} else {
    Write-Info "Key was not stored; set OPENAI_API_KEY before running Codex."
}
Write-Info ""
Write-Info "Open a new terminal, then try: codex-llm-hub"
