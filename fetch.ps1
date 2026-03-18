Write-Host "Starting Veeam feed fetch..."

$global:items = @()

$feeds = @(
    @{ url="https://www.veeam.com/blog/feed"; category="blog" },
    @{ url="https://www.veeam.com/kb_rss2.xml"; category="kb" },

    # Updated Veeam URLs (old ones returned 404)
    @{ url="https://www.veeam.com/services/support/security-advisories.xml"; category="advisory" },
    @{ url="https://www.veeam.com/services/support/product-updates.xml"; category="release" },

    @{ url="https://www.jorgedelacruz.es/feed/"; category="community" },

    # Reddit JSON API (RSS is blocked by Cloudflare)
    @{ url="https://www.reddit.com/r/Veeam.json"; category="community-json" }
)

function Add-Rss {
    param($xml, $category)
    $nodes = $xml.SelectNodes("//item")
    if ($nodes) {
        foreach ($n in $nodes) {
            $global:items += [PSCustomObject]@{
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
            $global:items += [PSCustomObject]@{
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
            $global:items += [PSCustomObject]@{
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

function Add-RedditJson {
    param($json, $category)
    foreach ($post in $json.data.children) {
        $data = $post.data
        $global:items += [PSCustomObject]@{
            title    = $data.title
            link     = "https://reddit.com" + $data.permalink
            date     = (Get-Date -Date $data.created_utc -UFormat "%Y-%m-%dT%H:%M:%SZ")
            source   = "Reddit /r/Veeam"
            category = $category
            severity = ""
        }
    }
}

foreach ($feed in $feeds) {
    Write-Host "Fetching $($feed.url)"

    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            "Accept"     = "text/xml,application/xml,application/json"
        }

        $response = Invoke-WebRequest -Uri $feed.url -Headers $headers -ErrorAction Stop

        if ($feed.category -eq "community-json") {
            $json = $response.Content | ConvertFrom-Json
            Add-RedditJson -json $json -category "community"
        }
        else {
            $xml = [xml]$response.Content

            if ($xml.rss) { Add-Rss -xml $xml -category $feed.category }
            elseif ($xml.feed) { Add-Atom -xml $xml -category $feed.category }
            else { Add-VeeamCustom -xml $xml -category $feed.category }
        }
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

$timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

foreach ($i in $global:items) {
    if ($i.category -eq "advisory") {
        if ($i.title -match "Critical") { $i.severity = "critical" }
        elseif ($i.title -match "High") { $i.severity = "high" }
        elseif ($i.title -match "Medium") { $i.severity = "medium" }
        else { $i.severity = "low" }
    }
}

$final = [PSCustomObject]@{
    lastUpdated = $timestamp
    items       = @($global:items)
}

$final | ConvertTo-Json -Depth 10 | Out-File "news.json"

Write-Host "news.json written"
