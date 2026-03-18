Write-Host "Starting Veeam feed fetch..."

$global:items = @()
$global:seenLinks = @{}

# -----------------------------
# VERIFIED VEEAM FEEDS
# -----------------------------
$feeds = @(
    @{ url="https://www.veeam.com/blog/feed"; category="blog"; source="Veeam Blog" },
    @{ url="https://www.veeam.com/kb_rss2.xml"; category="kb"; source="Veeam KB" },
    @{ url="https://www.veeam.com/kb_rss2_security.xml"; category="advisory"; source="Veeam Security Advisory" }
)

# -----------------------------
# ADD ITEM (DEDUPED)
# -----------------------------
function Add-Item {
    param($title, $link, $date, $source, $category, $severity="")

    if ($global:seenLinks.ContainsKey($link)) {
        return
    }

    $global:seenLinks[$link] = $true

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
# RSS + ATOM PARSER
# -----------------------------
function Parse-Rss {
    param($xml, $category, $source)

    # RSS <item> OR Atom <entry>
    $nodes = $xml.SelectNodes("//item")
    if (-not $nodes -or $nodes.Count -eq 0) {
        $nodes = $xml.SelectNodes("//*[local-name()='entry']")
    }

    foreach ($n in $nodes) {

        # TITLE
        $title = $n.SelectSingleNode("*[local-name()='title']")?.InnerText

        # LINK (RSS or ATOM)
        $link = $n.SelectSingleNode("link")?.InnerText

        # ATOM <link href="...">
        if (-not $link) {
            $linkNode = $n.SelectSingleNode("*[local-name()='link'][@href]")
            if ($linkNode) {
                $link = $linkNode.GetAttribute("href")
            }
        }

        # DATE
        $date = $n.SelectSingleNode("pubDate")?.InnerText
        if (-not $date) { $date = $n.SelectSingleNode("*[local-name()='updated']")?.InnerText }
        if (-not $date) { $date = $n.SelectSingleNode("*[local-name()='published']")?.InnerText }

        try { $date = (Get-Date $date).ToString("R") } catch {}

        # -----------------------------
        # STRICT CATEGORY RULES (Option A)
        # -----------------------------

        # RELEASE DETECTION (KB ONLY)
        $releaseKeywords = @(
            "Release Information",
            "Patch",
            "Hotfix",
            "Cumulative Update",
            "Rollup",
            "GA",
            "RTM"
        )

        $isRelease = $false
        if ($category -eq "kb") {
            foreach ($kw in $releaseKeywords) {
                if ($title -match $kw) { $isRelease = $true; break }
            }
        }

        if ($isRelease) {
            Add-Item $title $link $date $source "release"
        }
        else {
            Add-Item $title $link $date $source $category
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
