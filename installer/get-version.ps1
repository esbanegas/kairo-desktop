param(
    [string]$version,
    [string]$channel,
    [switch]$localOnly
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if ($channel -eq "stable") {
    if (-not $localOnly) {
        try {
            git fetch --tags --force 2>$null
        } catch {}
    }
    $exists = git tag -l "v$version"
    if ($exists) {
        [Console]::Error.WriteLine("ERROR: El tag v$version ya existe en el repositorio.")
        exit 1
    }
    Write-Output $version
} else {
    if (-not $localOnly) {
        try {
            git fetch --tags --force 2>$null
        } catch {}
    }

    $prefix = "v$version-$channel."
    $tags = git tag -l "$prefix*"
    $max = 0
    foreach ($t in $tags) {
        if ($t -match "^v\d+\.\d+\.\d+-$channel\.(\d+)$") {
            $num = [int]$matches[1]
            if ($num -gt $max) { $max = $num }
        }
    }
    $next = $max + 1
    Write-Output "$version-$channel.$next"
}
