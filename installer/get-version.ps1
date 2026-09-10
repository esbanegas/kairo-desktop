param(
    [string]$version,
    [string]$channel,
    [switch]$localOnly
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$validChannels = @("alpha", "beta", "production")
if ($validChannels -notcontains $channel) {
    [Console]::Error.WriteLine("ERROR: Canal '$channel' invalido. Debe ser uno de: alpha, beta, production.")
    exit 1
}

# Strip any existing prerelease or build suffix (e.g. -alpha.1)
$baseVersion = $version -replace '-[a-zA-Z0-9.-]+$', ''

if ($channel -eq "production") {
    if ($version -match '-[a-zA-Z0-9.-]+$') {
        [Console]::Error.WriteLine("ADVERTENCIA: version.json tenia el sufijo '$version' que sera descartado para Production. Se publicara como '$baseVersion'.")
    }

    if (-not $localOnly) {
        try {
            git fetch --prune --prune-tags 2>$null
        } catch {}
    }
    $exists = git tag -l "v$baseVersion"
    if ($exists) {
        [Console]::Error.WriteLine("ERROR: El tag v$baseVersion ya existe en el repositorio.")
        exit 1
    }
    Write-Output $baseVersion
} else {
    if (-not $localOnly) {
        try {
            git fetch --prune --prune-tags 2>$null
        } catch {}
    }

    $prefix = "v$baseVersion-$channel."
    $tags = git tag -l "$prefix*"
    $max = 0
    foreach ($t in $tags) {
        if ($t -match "^v\d+\.\d+\.\d+-$channel\.(\d+)$") {
            $num = [int]$matches[1]
            if ($num -gt $max) { $max = $num }
        }
    }
    $next = $max + 1
    Write-Output "$baseVersion-$channel.$next"
}
