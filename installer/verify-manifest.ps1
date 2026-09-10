param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("alpha", "beta", "production")]
    [string]$channel
)

# ============================================================
# Verifica consistencia entre: manifest publicado (main) <-> Git tag
# <-> GitHub Release <-> assets. Es una herramienta de solo lectura
# (no borra ni publica nada) pensada para correr antes de anunciar
# una actualizacion a un canal, especialmente Production, o cuando
# un cliente reporta que no encuentra una actualizacion.
#
# Uso: powershell -File verify-manifest.ps1 -channel production
# Exit code 0 = todo consistente. Exit code 1 = se encontro un problema.
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$problems = @()

function Write-Check($ok, $message) {
    if ($ok) {
        Write-Host "  [OK] $message" -ForegroundColor Green
    } else {
        Write-Host "  [FALLO] $message" -ForegroundColor Red
        $script:problems += $message
    }
}

$config = Get-Content (Join-Path $scriptDir "build.config.json") | ConvertFrom-Json
$repoOwner = $config.repo_owner
$repoName = $config.repo_name

Write-Host ""
Write-Host "============================================================"
Write-Host " Verificacion de consistencia - canal: $channel"
Write-Host " Repo: $repoOwner/$repoName"
Write-Host "============================================================"
Write-Host ""

# ── 1. Descargar el manifest EXACTAMENTE como lo hace un cliente real ──────
$manifestUrl = "https://raw.githubusercontent.com/$repoOwner/$repoName/main/installer/updates/latest-$channel.json?_nocache=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
Write-Host "[1/4] Descargando manifest: $manifestUrl"

$manifest = $null
try {
    $response = Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -TimeoutSec 20
    $manifest = $response.Content | ConvertFrom-Json
    Write-Check $true "Manifest accesible (HTTP $($response.StatusCode))."
} catch {
    Write-Check $false "No se pudo descargar el manifest: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "RESULTADO: 1 problema encontrado." -ForegroundColor Red
    exit 1
}

# ── 2. Validar forma/consistencia interna del manifest ─────────────────────
Write-Host "[2/4] Validando contenido del manifest..."
Write-Check ($manifest.schema -eq "kairo.update.manifest") "schema == kairo.update.manifest"
Write-Check ($manifest.app.channel -eq $channel) "app.channel ('$($manifest.app.channel)') coincide con el canal solicitado ('$channel')"

$version = $manifest.app.version
$baseUrl = $manifest.distribution.base_url
Write-Host "       version: $version"
Write-Host "       base_url: $baseUrl"

if ($channel -eq "production") {
    Write-Check ($version -notmatch '-[a-zA-Z0-9.-]+$') "version de Production no lleva sufijo de prerelease"
} else {
    Write-Check ($version -match "-$channel\.\d+$") "version lleva el sufijo esperado para el canal '$channel'"
}

# ── 3. Verificar que el tag y el Release existan en GitHub ─────────────────
Write-Host "[3/4] Verificando tag y Release en GitHub (v$version)..."

$ghAvailable = $true
try { gh --version | Out-Null } catch { $ghAvailable = $false }

$releaseAssets = $null
if ($ghAvailable) {
    $releaseJson = gh release view "v$version" --repo "$repoOwner/$repoName" --json tagName,isDraft,isPrerelease,assets 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $releaseJson) {
        Write-Check $false "No existe un GitHub Release para el tag v$version (o no es accesible). El manifest anuncia una version cuyo Release no se encuentra."
    } else {
        $release = $releaseJson | ConvertFrom-Json
        Write-Check $true "GitHub Release v$version existe."
        Write-Check (-not $release.isDraft) "El Release no esta en borrador (draft)."
        $releaseAssets = $release.assets
    }
} else {
    Write-Host "  [INFO] GitHub CLI (gh) no disponible - se omite el chequeo de Release/tag, solo se validan los assets por HTTP." -ForegroundColor Yellow
}

# ── 4. Verificar que cada asset listado en el manifest exista de verdad ────
Write-Host "[4/4] Verificando assets referenciados por el manifest..."

foreach ($fileKey in $manifest.files.PSObject.Properties.Name) {
    $file = $manifest.files.$fileKey
    $assetUrl = "$baseUrl/$($file.name)"

    try {
        $head = Invoke-WebRequest -Uri $assetUrl -Method Head -UseBasicParsing -TimeoutSec 20 -MaximumRedirection 5
        Write-Check ($head.StatusCode -eq 200) "Asset '$($file.name)' descargable en: $assetUrl"
    } catch {
        Write-Check $false "Asset '$($file.name)' NO accesible en: $assetUrl ($($_.Exception.Message))"
    }

    if ($releaseAssets) {
        $matchingAsset = $releaseAssets | Where-Object { $_.name -eq $file.name }
        if (-not $matchingAsset) {
            Write-Check $false "El Release de GitHub no contiene el asset '$($file.name)' que el manifest anuncia."
        } elseif ($matchingAsset.digest -and ($matchingAsset.digest -ne "sha256:$($file.sha256)")) {
            Write-Check $false "SHA256 del asset '$($file.name)' en GitHub no coincide con el del manifest."
        } else {
            Write-Check $true "Asset '$($file.name)' presente en el Release con SHA256 consistente."
        }
    }
}

Write-Host ""
if ($problems.Count -eq 0) {
    Write-Host "RESULTADO: todo consistente para el canal '$channel' (version $version)." -ForegroundColor Green
    exit 0
} else {
    Write-Host "RESULTADO: $($problems.Count) problema(s) encontrado(s) para el canal '$channel':" -ForegroundColor Red
    foreach ($p in $problems) { Write-Host "  - $p" -ForegroundColor Red }
    exit 1
}
