Write-Host "Starting Veeam feed fetch..."

$global:items = @()

# -----------------------------
# FEED DEFINITIONS
# -----------------------------
$feeds = @(
    @{ url="https://www.veeam.com/blog/feed"; category="blog"; type="rss" },
    @{ url="https://www.veeam.com/kb_rss2.xml"; category="kb"; type="rss" },

    # HTML scrapers
    @{ url="https://www.veeam.com/kb/security"; category="advisory"; type="html-advisory" },
    @{ url="https://www.veeam.com/kb/updates"; category="release"; type="html-updates" },

    # Jorge feed (HTML)
    @{ url="https://www.jorgedelacruz.es/feed/"; category="community"; type="rss-or-html" },

    # Reddit JSON API
    @{ url="https://www.reddit.com/r/Veeam.json"; category="community"; type="reddit-json" }
)

# -----------------------------
# HELPERS
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
    param($xml, $category)

    $nodes = $xml.SelectNodes("//item")
    if ($nodes) {
        foreach ($n in $nodes) {
            Add-Item `
                $n.title `
                $n.link `
                $n.pubDate `
                ($xml.SelectSingleNode("//channel/title")?.InnerText) `
                $category
        }
    }
}

# -----------------------------
# HTML SCRAPER: SECURITY ADVISORIES
# -----------------------------
function Scrape-Advisories {
    param($html, $category)

    $matches = Select-String -InputObject $html -Pattern '<a href="([^"]+)"[^>]*>([^<]+)</a>' -AllMatches

    foreach ($m in $matches.Matches) {
        $link = $m.Groups[1].Value
        $title = $m.Groups[2].Value

        if ($link -match "/kb/") {
            Add-Item $title ("https://www.veeam.com" + $link) (Get-Date).ToString("R") "Veeam Security Advisory" $category
        }
    }
}

# -----------------------------
# HTML SCRAPER: PRODUCT UPDATES
# -----------------------------
function Scrape-Updates {
    param($html, $category)

    $matches = Select-String -InputObject $html -Pattern '<a href="([^"]+)"[^>]*>([^<]+)</a>' -AllMatches

    foreach ($m in $matches.Matches) {
        $link = $m.Groups[1].Value
        $title = $m.Groups[2].Value

        if ($link -match "/kb/") {
            Add-Item $title ("https://www.veeam.com" + $link) (Get-Date).ToString("R") "Veeam Product Update" $category
        }
    }
}

# -----------------------------
# REDDIT JSON PARSER
# -----------------------------
function Parse-RedditJson {
    param($json, $category)

    foreach ($post in $json.data.children) {
        $d = $post.data
        Add-Item `
            $d.title `
            ("https://reddit.com" + $d.permalink) `
            ([DateTimeOffset]::FromUnixTimeSeconds($d.created_utc).UtcDateTime.ToString("R")) `
            "Reddit /r/Veeam" `
            $category
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
            "Accept"     = "text/xml,application/xml,application/json,text/html"
        }

        $response = Invoke-WebRequest -Uri $feed.url -Headers $headers -ErrorAction Stop

        switch ($feed.type) {

            "rss" {
                $xml = [xml]$response.Content
                Parse-Rss -xml $xml -category $feed.category
            }

            "reddit-json" {
                $json = $response.Content | ConvertFrom-Json
                Parse-RedditJson -json $json -category $feed.category
            }

            "html-advisory" {
                Scrape-Advisories -html $response.Content -category $feed.category
            }

            "html-updates" {
                Scrape-Updates -html $response.Content -category $feed.category
            }

            "rss-or-html" {
                if ($response.Content.TrimStart().StartsWith("<html")) {
                    Scrape-Updates -html $response.Content -category $feed.category
                }
                else {
                    $xml = [xml]$response.Content
                    Parse-Rss -xml $xml -category $feed.category
                }
            }
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
