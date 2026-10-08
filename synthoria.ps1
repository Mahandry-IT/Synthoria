<#
.SYNOPSIS
    Raccourcis Docker Compose pour Synthoria (équivalent Windows du Makefile).
.EXAMPLE
    ./synthoria.ps1 up
    ./synthoria.ps1 logs api
    ./synthoria.ps1 rollback sha-1a2b3c4
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'up', 'down', 'logs', 'ps', 'pull', 'update', 'rollback')]
    [string]$Command = 'help',

    # logs : service à suivre (optionnel) ; rollback : tag d'image (obligatoire).
    [Parameter(Position = 1)]
    [string]$Arg
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$EnvFile = Join-Path $PSScriptRoot '.env'

function Invoke-Compose {
    & docker compose @args
    if ($LASTEXITCODE -ne 0) { throw "docker compose $($args -join ' ') a échoué (code $LASTEXITCODE)" }
}

function Assert-EnvFile {
    if (-not (Test-Path -LiteralPath $EnvFile)) {
        throw 'Fichier .env absent : Copy-Item .env.example .env puis renseigner les secrets.'
    }
}

function Set-ImageTag([string]$Tag) {
    if ($Tag -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$') {
        throw 'Usage : ./synthoria.ps1 rollback sha-xxxxxxx (ou latest)'
    }
    $lines = [System.Collections.Generic.List[string]](Get-Content -LiteralPath $EnvFile -Encoding UTF8)
    $index = $lines.FindIndex({ param($l) $l -match '^SYNTHORIA_IMAGE_TAG=' })
    if ($index -ge 0) { $lines[$index] = "SYNTHORIA_IMAGE_TAG=$Tag" } else { $lines.Add("SYNTHORIA_IMAGE_TAG=$Tag") }
    # UTF-8 sans BOM, fins de ligne LF : lisible par docker compose et par make.
    [System.IO.File]::WriteAllText($EnvFile, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
    Write-Host "SYNTHORIA_IMAGE_TAG=$Tag"
}

switch ($Command) {
    'help' {
        @(
            '  up               Démarre la stack en arrière-plan'
            '  down             Arrête la stack (les volumes sont conservés)'
            '  logs [service]   Suit les logs'
            '  ps               État des services'
            '  pull             Télécharge les images du tag courant'
            '  update           Télécharge puis recrée les conteneurs modifiés'
            '  rollback <tag>   Fige SYNTHORIA_IMAGE_TAG dans .env puis met à jour'
        ) | Write-Host
    }
    'up'       { Assert-EnvFile; Invoke-Compose up -d }
    'down'     { Invoke-Compose down }
    'logs'     { if ($Arg) { Invoke-Compose logs -f --tail=200 $Arg } else { Invoke-Compose logs -f --tail=200 } }
    'ps'       { Invoke-Compose ps }
    'pull'     { Assert-EnvFile; Invoke-Compose pull }
    'update'   { Assert-EnvFile; Invoke-Compose pull; Invoke-Compose up -d }
    'rollback' {
        Assert-EnvFile
        if (-not $Arg) { throw 'Usage : ./synthoria.ps1 rollback sha-xxxxxxx (ou latest)' }
        Set-ImageTag $Arg
        Invoke-Compose pull
        Invoke-Compose up -d
    }
}
