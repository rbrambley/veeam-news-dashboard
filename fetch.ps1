Write-Host "Starting Veeam feed fetch..."

$feeds = @(
    @{ url="https://www.veeam.com/blog/feed"; category="blog" },
    @{ url="https://www.veeam.com/kb_rss2.xml"; category="kb" },
    @{ url="https://www.veeam.com/services/veeam-security-advisories.xml"; category="advisory" },
    @{ url="https://www.veeam.com/services/veeam-product-updates.xml"; category="release" },
    @{ url="https://www.jorgedelacruz.es/feed/"; category="community" },
    @{ url="https://www.reddit.com/r/Veeam/.rss"; category="community" }
)

# Always an array
$items = @()

function Add-Rss {
    param($xml, $category)
    $nodes = $xml.SelectNodes("//item")
    if ($nodes) {
        foreach ($n in $nodes) {
            $items += [PSCustomObject]@{
                title    = $n.title
                link     = $n.link
                date     = $n.pubDate
                source   = $xml.SelectSingleNode("//channel/title")?.InnerText
                category = $category
                severity = ""
            }
        }
    }
}

function Add-Atom {
    param($xml, $category)
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("a", $xml.DocumentElement.NamespaceURI)

    $entries = $xml.SelectNodes("//a:entry", $ns)
    if ($entries) {
        foreach ($e in $entries) {
            $items += [PSCustomObject]@{
                title    = $e.SelectSingleNode("a:title", $ns)?.InnerText
                link     = $e.SelectSingleNode("a:link", $ns)?.href
                date     = $e.SelectSingleNode("a:updated", $ns)?.InnerText
                source   = $xml.SelectSingleNode("//a:title", $ns)?.InnerText
                category = $category
                severity = ""
            }
        }
    }
}

function Add-VeeamCustom {
    param($xml, $category)
    $nodes = $xml.SelectNodes("//item")
    if ($nodes) {
        foreach ($n in $nodes) {
            $items += [PSCustomObject]@{
                title    = $n.title
                link     = $n.link
                date     = $n.pubDate
                source   = $xml.SelectSingleNode("//channel/title")?.InnerText
                category = $category
                severity = ""
            }
        }
    }
}

foreach ($feed in $feeds) {
    Write-Host "Fetching $($feed.url)"
    try {
        $response = Invoke-WebRequest -Uri $feed.url -Headers @{ "User-Agent" = "Mozilla/5.0" }
        $xml = [xml]$response.Content

        if ($xml.rss) { Add-Rss -xml $xml -category $feed.category }
        elseif ($xml.feed) { Add-Atom -xml $xml -category $feed.category }
        else { Add-VeeamCustom -xml $xml -category $feed.category }
    }
    catch {
        Write-Host "ERROR fetching $($feed.url)"
    }
}

# Timestamp
$timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

# Severity for advisories
foreach ($i in $items) {
    if ($i.category -eq "advisory") {
        if ($i.title -match "Critical") { $i.severity = "critical" }
        elseif ($i.title -match "High") { $i.severity = "high" }
        elseif ($i.title -match "Medium") { $i.severity = "medium" }
        else { $i.severity = "low" }
    }
}

# Final JSON (never null)
$final = [PSCustomObject]@{
    lastUpdated = $timestamp
    items       = @($items)
}

$final | ConvertTo-Json -Depth 10 | Out-File "news.json"

Write-Host "news.json written"
