Write-Host "Starting Veeam feed fetch..."

$feeds = @(
    @{ url="https://www.veeam.com/blog/feed"; category="blog" },
    @{ url="https://www.veeam.com/kb_rss2.xml"; category="kb" },
    @{ url="https://www.veeam.com/services/veeam-security-advisories.xml"; category="advisory" },
    @{ url="https://www.veeam.com/services/veeam-product-updates.xml"; category="release" },
    @{ url="https://www.jorgedelacruz.es/feed/"; category="community" },
    @{ url="https://www.reddit.com/r/Veeam/.rss"; category="community" }
)

$items = @()

foreach ($feed in $feeds) {
    Write-Host "Fetching $($feed.url)"
    try {
        $response = Invoke-WebRequest -Uri $feed.url -Headers @{ "User-Agent" = "Mozilla/5.0" }
        $xml = [xml]$response.Content

        if ($xml.rss.channel.item) {
            foreach ($i in $xml.rss.channel.item) {
                $items += [PSCustomObject]@{
                    title     = $i.title
                    link      = $i.link
                    date      = $i.pubDate
                    source    = $xml.rss.channel.title
                    category  = $feed.category
                    severity  = ""   # filled later for advisories
                }
            }
        } else {
            Write-Host "No items returned for $($feed.url)"
        }
    } catch {
        Write-Host "ERROR fetching $($feed.url)"
        Write-Host $_
    }
}

# Add timestamp
$timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Add severity for advisories (simple keyword match)
foreach ($item in $items) {
    if ($item.category -eq "advisory") {
        if ($item.title -match "Critical") { $item.severity = "critical" }
        elseif ($item.title -match "High") { $item.severity = "high" }
        elseif ($item.title -match "Medium") { $item.severity = "medium" }
        else { $item.severity = "low" }
    }
}

# Build final JSON
$final = [PSCustomObject]@{
    lastUpdated = $timestamp
    items       = $items | Sort-Object date -Descending
}

$final | ConvertTo-Json -Depth 10 | Out-File "news.json"

Write-Host "news.json written"
