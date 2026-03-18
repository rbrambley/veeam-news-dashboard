Write-Host "Starting Veeam feed fetch..."

$feeds = @(
    "https://www.veeam.com/blog/feed",
    "https://www.veeam.com/kb_rss2.xml"
)

$items = @()

foreach ($feed in $feeds) {
    Write-Host "Fetching $feed"
    try {
        $rss = Invoke-WebRequest -Uri $feed -Headers @{ "User-Agent" = "Mozilla/5.0" }
        $xml = [xml]$rss.Content

        if ($xml.rss.channel.item) {
            $count = $xml.rss.channel.item.Count
            Write-Host "Loaded $count items from $feed"

            foreach ($i in $xml.rss.channel.item) {
                $items += [PSCustomObject]@{
                    title  = $i.title
                    link   = $i.link
                    date   = $i.pubDate
                    source = $xml.rss.channel.title
                }
            }
        } else {
            Write-Host "Feed returned no items: $feed"
        }
    } catch {
        Write-Host "ERROR fetching $feed"
        Write-Host $_
    }
}

Write-Host "Total items collected: $($items.Count)"

$items |
    Sort-Object date -Descending |
    ConvertTo-Json -Depth 5 |
    Out-File "news.json"

Write-Host "news.json written"
