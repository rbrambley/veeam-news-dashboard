$feeds = @(
    "https://www.veeam.com/blog/feed",
    "https://www.veeam.com/kb_rss2.xml"
)

$items = foreach ($feed in $feeds) {
    try {
        $rss = Invoke-RestMethod -Uri $feed -UseBasicParsing
        foreach ($i in $rss.rss.channel.item) {
            [PSCustomObject]@{
                title = $i.title
                link  = $i.link
                date  = $i.pubDate
                source = $rss.rss.channel.title
            }
        }
    } catch {
        Write-Host "Failed to load $feed"
    }
}

$items | Sort-Object date -Descending | ConvertTo-Json -Depth 5 | Out-File "news.json"
