$sebFile = "c:\Users\Garvit\Projects\seb\seb-win-refactoring\DevEnvironment\build\session\remote-exam.seb"
$bytes = [System.IO.File]::ReadAllBytes($sebFile)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
$sr = New-Object System.IO.StreamReader($gz)
$xml = $sr.ReadToEnd()
$idx = $xml.IndexOf("startURL")
if ($idx -ge 0) {
    Write-Host "Found startURL in remote-exam.seb:"
    Write-Host $xml.Substring($idx, 150)
} else {
    Write-Host "startURL not found in xml"
}
