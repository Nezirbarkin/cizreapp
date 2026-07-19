$url = 'https://play.google.com/store/apps/details?id=com.cizreapp.com&hl=tr'
$h = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent 'Mozilla/5.0 (Linux; Android 10)'
$content = $h.Content

Write-Output ('--- Length: ' + $content.Length)

# 1) "Geliştirici" ile başlayan ve sonrasında web sitesi URL'si geçen pattern
$devMatches = [regex]::Matches($content, 'Geli[^<]{0,200}')
Write-Output ('--- Geli-prefixed matches: ' + $devMatches.Count)

# 2) cizreapp.com içeren herhangi bir URL
$siteMatches = [regex]::Matches($content, 'https?://(?:www\.)?cizreapp\.com[^\"\\<>]*')
Write-Output ('--- cizreapp.com URLs found: ' + $siteMatches.Count)
foreach ($m in $siteMatches) {
  Write-Output ('  URL: ' + $m.Value)
}

# 3) Play Store'un developer URL formatını ara: [\"https://www.cizreapp.com?...\"]
$devUrl = [regex]::Matches($content, '\\\"https?://(?:www\.)?cizreapp\.com[^\"\\]*\\\"')
Write-Output ('--- Escaped dev URL hits: ' + $devUrl.Count)
foreach ($m in $devUrl) {
  Write-Output ('  Esc: ' + $m.Value)
}
