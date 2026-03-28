# Veeam News Dashboard — Feed Aggregator
# Aggregates Veeam-related articles from official Veeam sources and popular tech outlets.
# Output: news.json (relative to this script)
#
# Run manually or schedule as a recurring task to keep the dashboard fresh.

$ErrorActionPreference = "Continue"
$outputFile  = Join-Path $PSScriptRoot "news.json"
$maxPerFeed  = 25        # maximum articles to import per feed
$maxAgeDays  = 90        # ignore articles older than this

# ── Feed Definitions ──────────────────────────────────────────────────────────
# FilterVeeam=$true  → only keep items whose title/description contains "veeam"
# FilterVeeam=$false → keep all items (feed is already Veeam-specific)
$feeds = @(
    # ─── Official Veeam ───────────────────────────────────────────────────────
    @{ Url="https://www.veeam.com/blog/feed/";
       Category="blog";      Source="Veeam Blog";      FilterVeeam=$false }

    @{ Url="https://www.veeam.com/services/rss/en_US/kb_articles.xml";
       Category="kb";        Source="Veeam KB";        FilterVeeam=$false }

    @{ Url="https://www.veeam.com/services/rss/en_US/security_advisories.xml";
       Category="advisory";  Source="Veeam Security";  FilterVeeam=$false }

    # ─── Popular Tech News Outlets ────────────────────────────────────────────
    @{ Url="https://www.bleepingcomputer.com/tag/veeam/feed/";
       Category="news";      Source="BleepingComputer"; FilterVeeam=$false }

    @{ Url="https://www.theregister.com/tag/veeam/feed.atom";
       Category="news";      Source="The Register";     FilterVeeam=$false }

    @{ Url="https://www.storagereview.com/feed";
       Category="news";      Source="StorageReview";    FilterVeeam=$true }

    @{ Url="https://petri.com/feed/";
       Category="news";      Source="Petri";            FilterVeeam=$true }

    @{ Url="https://searchdatabackup.techtarget.com/rss/SearchDataBackupRSS.xml";
       Category="news";      Source="TechTarget";       FilterVeeam=$true }

    # ─── Community & Aggregated ───────────────────────────────────────────────
    @{ Url="https://news.google.com/rss/search?q=veeam+backup&hl=en-US&gl=US&ceid=US:en";
       Category="news";      Source="Google News";      FilterVeeam=$false }

    @{ Url="https://www.reddit.com/r/Veeam/.rss";
       Category="community"; Source="Reddit r/Veeam";  FilterVeeam=$false }

    @{ Url="https://forums.veeam.com/feed.php?t=&f=&mode=topics";
       Category="community"; Source="Veeam Forums";    FilterVeeam=$false }
)

# ── Helper Functions ──────────────────────────────────────────────────────────

function Get-Severity([string]$title, [string]$desc) {
    $text = "$title $desc".ToLower()
    if ($text -match '\bcritical\b') { return "critical" }
    if ($text -match '\bhigh\b')     { return "high" }
    if ($text -match '\bmedium\b')   { return "medium" }
    if ($text -match '\blow\b')      { return "low" }
    return ""
}

function Resolve-Category([string]$default, [string]$title) {
    # Only reclassify official KB/Blog items — leave news/community as-is
    if ($default -in @("advisory","community","news")) { return $default }
    $t = $title.ToLower()
    if ($t -match "release information|build numbers and versions") { return "release" }
    if ($t -match "vulnerabilit|security advisory|cve-|\badvisory\b") { return "advisory" }
    return $default
}

function Strip-Html([string]$html) {
    if (-not $html) { return "" }
    $s = [System.Net.WebUtility]::HtmlDecode(($html -replace '<[^>]+>', ' '))
    return ($s -replace '\s+', ' ').Trim()
}

function Parse-FeedDate([string]$raw) {
    if (-not $raw) { return $null }
    $ic  = [System.Globalization.CultureInfo]::InvariantCulture
    $adj = [System.Globalization.DateTimeStyles]::AdjustToUniversal
    $formats = @(
        "ddd, dd MMM yyyy HH:mm:ss zzz",
        "ddd, dd MMM yyyy HH:mm:ss 'GMT'",
        "yyyy-MM-ddTHH:mm:sszzz",
        "yyyy-MM-ddTHH:mm:ssZ",
        "yyyy-MM-ddTHH:mm:ss"
    )
    foreach ($fmt in $formats) {
        $d = [datetime]::MinValue
        if ([datetime]::TryParseExact($raw, $fmt, $ic, $adj, [ref]$d)) { return $d }
    }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($raw, [ref]$d)) { return $d.ToUniversalTime() }
    return $null
}

# ── Fetch & Parse ─────────────────────────────────────────────────────────────

$allItems = [System.Collections.Generic.List[PSCustomObject]]::new()
$seen     = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
$cutoff   = (Get-Date).AddDays(-$maxAgeDays).ToUniversalTime()
$headers  = @{
    "User-Agent" = "VeeamNewsDashboard/2.0 (+https://github.com/rbrambley/veeam-news-dashboard)"
}

foreach ($feed in $feeds) {
    Write-Host "Fetching $($feed.Source) ..." -NoNewline
    try {
        $resp = Invoke-WebRequest -Uri $feed.Url -Headers $headers `
                    -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        [xml]$xml = $resp.Content

        # Support both RSS 2.0 and Atom formats
        $rawItems = if ($xml.rss)  { $xml.rss.channel.item } `
                    elseif ($xml.feed) { $xml.feed.entry } `
                    else { @() }

        if (-not $rawItems) { Write-Host " (empty)" -ForegroundColor Yellow; continue }

        $added = 0
        foreach ($ri in $rawItems) {
            if ($added -ge $maxPerFeed) { break }

            # ── Normalise RSS vs Atom fields ───────────────────────────────────
            if ($xml.rss) {
                $title   = [string]$ri.title
                $link    = if ($ri.link -is [string] -and $ri.link) { $ri.link } `
                           else { [string]$ri.guid }
                $dateRaw = [string]$ri.pubDate
                $descRaw = [string]$ri.description
            } else {
                $title   = if ($ri.title -is [string]) { $ri.title } `
                           else { [string]$ri.title.'#text' }
                $linkEl  = @($ri.link) | Where-Object { -not $_.rel -or $_.rel -eq 'alternate' } |
                           Select-Object -First 1
                $link    = if ($linkEl) { [string]$linkEl.href } else { [string]$ri.id }
                $dateRaw = if ($ri.published) { [string]$ri.published } `
                           else { [string]$ri.updated }
                $descRaw = if ($ri.summary)          { [string]$ri.summary } `
                           elseif ($ri.content)      { [string]$ri.content.'#text' } `
                           else                      { "" }
            }

            $title = $title.Trim()
            $link  = $link.Trim()
            if (-not $title -or -not $link) { continue }

            # ── Keyword filter for generic feeds ───────────────────────────────
            if ($feed.FilterVeeam -and "$title $descRaw" -notmatch "(?i)veeam") { continue }

            # ── Dedup by URL (ignore query string) ────────────────────────────
            $key = ($link -split '[?#]')[0].TrimEnd('/')
            if (-not $seen.Add($key)) { continue }

            # ── Date ──────────────────────────────────────────────────────────
            $date = Parse-FeedDate $dateRaw
            if (-not $date) { $date = (Get-Date).ToUniversalTime() }
            if ($date -lt $cutoff) { continue }

            # ── Description excerpt ───────────────────────────────────────────
            $desc = Strip-Html $descRaw
            if ($desc.Length -gt 250) { $desc = $desc.Substring(0, 247) + "..." }

            # ── Category & severity ───────────────────────────────────────────
            $cat = Resolve-Category -default $feed.Category -title $title
            $sev = if ($cat -eq "advisory") { Get-Severity -title $title -desc $desc } else { "" }

            $allItems.Add([PSCustomObject]@{
                title       = $title
                link        = $link
                date        = $date.ToString("yyyy-MM-ddTHH:mm:ssZ")
                source      = $feed.Source
                category    = $cat
                severity    = $sev
                description = $desc
            })
            $added++
        }
        Write-Host " $added items" -ForegroundColor Green
    }
    catch {
        Write-Host " FAILED: $_" -ForegroundColor Red
    }
}

# ── Write Output ──────────────────────────────────────────────────────────────

$sorted = @($allItems | Sort-Object { [datetime]$_.date } -Descending)

[ordered]@{
    lastUpdated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    items       = $sorted
} | ConvertTo-Json -Depth 5 | Set-Content -Path $outputFile -Encoding UTF8

Write-Host ("`nDone. {0} articles saved to news.json" -f $sorted.Count) -ForegroundColor Cyan