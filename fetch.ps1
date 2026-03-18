Write-Host "Starting Veeam feed fetch..."

$feeds = @(
    @{ url="https://www.veeam.com/blog/feed"; category="blog" },
    @{ url="https://www.veeam.com/kb_rss2.xml"; category="kb" },
    @{ url="https://www.veeam.com/services/veeam-security-advisories.xml"; category="advisory" },
    @{ url="https://www.veeam.com/services/veeam-product-updates.xml"; category="release" },
    @{ url="https://www.jorgedelacruz.es/feed/"; category="community" },
    @{ url="https://www.reddit.com/r/Veeam/.rss"; category="community" }
)

# Force items to always be an array
$items = New-Object System.Collections.ArrayList

function Add-RssItems {
    param($xml, $category)
    $nodes = $xml.SelectNodes("//item")
    if ($nodes) {
        foreach ($i in $nodes) {
            $null = $items.Add([PSCustomObject]@{
                title     = $i.title
                link      = $i.link
                date      = $i.pubDate
                source    = ($xml.SelectSingleNode("//channel/title")?.InnerText)
                category  = $category
                severity  = ""
            })
        }
    }
}

function Add-AtomItems {
    param($xml, $category)
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("a", $xml.DocumentElement.NamespaceURI)

    $entries = $xml.SelectNodes("//a:entry", $ns)
    if ($entries) {
        foreach ($e in $entries) {
            $link = $e.SelectSingleNode("a:link", $ns)?.href
            $date = $e.SelectSingleNode("a:updated", $ns)?.InnerText
            if (-not $date) { $date = $e.SelectSingleNode("a:published", $ns)?.InnerText }

            $null = $items.Add([PSCustomObject]@{
                title     = $e.SelectSingleNode("a:title", $ns)?.InnerText
                link      = $link
                date      = $date
                source    = $xml.SelectSingleNode("//a:title", $ns)?.InnerText
                category  = $category
                severity  = ""
            })
        }
    }
}

function Add-VeeamCustom {
    param($xml, $category)

    # Veeam custom feeds still use <item> nodes
    $nodes = $xml.SelectNodes("//item")
    if ($nodes) {
        foreach ($i in $nodes) {
            $null = $items.Add([PSCustomObject]@{
                title     = $i.title
                link      = $i.link
                date      = $i.pubDate
                source    = ($xml.SelectSingleNode("//channel/title")?.InnerText)
                category  = $category
                severity  = ""
            })
        }
    }
}

foreach ($feed in $feeds) {
    Write-Host "Fetching $($feed.url)"
    try {
        $response = Invoke-WebRequest -Uri $feed.url -Headers @{ "User-Agent" = "Mozilla/5.0" }
        $xml = [xml]$response.Content

        if ($xml.rss) {
            Add-RssItems -xml $xml -category $feed.category
        }
        elseif ($xml.feed) {
            Add-AtomItems -xml $xml -category $feed.category
        }
        else {
            Add-VeeamCustom -xml $xml -category $feed.category
        }
    }
    catch {
        Write-Host "ERROR fetching $($feed.url)"
    }
}

$timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

foreach ($item in $items) {
    if ($item.category -eq "advisory") {
        if ($item.title -match "Critical") { $item.severity = "critical" }
        elseif ($item.title -match "High") { $item.severity = "high" }
        elseif ($item.title -match "Medium") { $item.severity = "medium" }
        else { $item.severity = "low" }
    }
}

$final = [PSCustomObject]@{
    lastUpdated = $timestamp
    items       = @($items | Sort-Object date -Descending)
}

$final | ConvertTo-Json -Depth 10 | Out-File "news.json"

Write-Host "news.json written"
