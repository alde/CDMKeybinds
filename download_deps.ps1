$ErrorActionPreference = "Stop"

if (-not (Get-Command svn -ErrorAction SilentlyContinue)) {
    Write-Error "svn is required but not found."
    exit 1
}

New-Item -ItemType Directory -Force -Path Libs | Out-Null

$inExternals = $false
$currentPath = ""
$currentUrl = ""

function Invoke-Checkout {
    if ($currentPath -and $currentUrl) {
        $localPath = $currentPath -replace "/", "\"
        Write-Host "Fetching ${currentPath}..."
        svn checkout $currentUrl $localPath
        Write-Host "Done."
    }
}

foreach ($raw in Get-Content .pkgmeta) {
    $line = ($raw -replace "#.*", "").TrimEnd()

    if ($line -match "^externals:") {
        $inExternals = $true
        continue
    }

    if (-not $inExternals) { continue }
    if ($line -and $line -notmatch "^\s") { break }

    if ($line -match "^  \S" -and $line -match ":") {
        Invoke-Checkout
        $currentPath = $line.Trim().TrimEnd(":")
        $currentUrl = ""
    }

    if ($line -match "^\s+url:\s*(.+)") {
        $currentUrl = $Matches[1]
    }
}

Invoke-Checkout
