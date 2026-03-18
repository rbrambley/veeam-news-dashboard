Write-Host "Starting Veeam feed fetch..."

$global:items = @()

# -----------------------------
# REAL, VERIFIED VEEAM FEEDS
# -----------------------------
$feeds = @(
    @{ url="https://www.veeam.com/blog/feed"; category="blog"; source="Veeam Blog" },
    @{ url="https://www.veeam.com/kb_rss2.xml"; category="kb"; source="Veeam KB" },
    @{ url="https://www.veeam.com/kb_rss2_security.xml"; category="advisory"; source="Veeam Security Advisory" }
)

# -----------------------------
# ADD ITEM HELPER
# -----------------------------
function Add-Item {
    param($title, $link, $date, $source, $category, $severity="")
    $global:items += [PSCustomObject]@{
        title    = $title
        link     = $link
        date     = $date
        source   = $source
        category = $category
        severity = $severity
    }
}

# -----------------------------
# RSS PARSER
# -----------------------------
function Parse-Rss {
    param($xml, $category, $source)

    $nodes = $xml.SelectNodes("//item")
    if ($nodes) {
        foreach ($n in $nodes) {
            Add-Item `
                $n.title `
                $n.link `
                $n.pubDate `
                $source `
                $category
        }
    }
}

# -----------------------------
# MAIN LOOP
# -----------------------------
foreach ($feed in $feeds) {
    Write-Host "Fetching $($feed.url)"

    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            "Accept"     = "text/xml,application/xml"
        }

        $response = Invoke-WebRequest -Uri $feed.url -Headers $headers -ErrorAction Stop
        $xml = [xml]$response.Content

        Parse-Rss -xml $xml -category $feed.category -source $feed.source
    }
    catch {
        Write-Host "ERROR fetching $($feed.url)"
        Write-Host "Message: $($_.Exception.Message)"
        if ($_.Exception.InnerException) {
            Write-Host "Inner: $($_.Exception.InnerException.Message)"
        }
        if ($_.Exception.Response) {
            Write-Host "StatusCode: $($_.Exception.Response.StatusCode.value__)"
            Write-Host "StatusDescription: $($_.Exception.Response.StatusDescription)"
        }
    }
}

# -----------------------------
# SEVERITY TAGGING FOR ADVISORIES
# -----------------------------
foreach ($i in $global:items) {
    if ($i.category -eq "advisory") {
        if ($i.title -match "Critical") { $i.severity = "critical" }
        elseif ($i.title -match "High") { $i.severity = "high" }
        elseif ($i.title -match "Medium") { $i.severity = "medium" }
        else { $i.severity = "low" }
    }
}

# -----------------------------
# FINAL OUTPUT
# -----------------------------
$timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

$final = [PSCustomObject]@{
    lastUpdated = $timestamp
    items       = @($global:items)
}

$final | ConvertTo-Json -Depth 10 | Out-File "news.json"

Write-Host "news.json written"
