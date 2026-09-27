<#
  bootstrap.ps1 - The "player". Fetches the game from DNS TXT records,
  reassembles + verifies + decompresses it, and runs it entirely in memory.
  Nothing is written to disk.

  Edit $Domain below, then run this file (or paste the one-liner from publish.ps1).
#>

# ---- config ----
$Namespace = 'dnsnake'
$Domain    = 'marshallyanis.com'      # e.g. example.com
$d = "$Namespace.$Domain"

# ---- optional disk hygiene: stop PowerShell saving your command history ----
try { Set-PSReadLineOption -HistorySaveStyle SaveNothing } catch {}

# ---- fetch manifest ----
$manifest = (Resolve-DnsName -Type TXT "manifest.$d" -ErrorAction Stop).Strings -join ''
$parts = @{}
foreach ($kv in $manifest.Split(';')) { $k, $v = $kv.Split('=', 2); $parts[$k] = $v }
$count = [int]$parts['c']
$wantHash = $parts['h']

# ---- fetch chunks in order ----
$b64 = -join (0..($count - 1) | ForEach-Object {
    (Resolve-DnsName -Type TXT "c$_.$d" -ErrorAction Stop).Strings -join ''
})

# ---- integrity check ----
if ($wantHash) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $got = ((($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($b64)) |
              ForEach-Object { $_.ToString('x2') }) -join '')).Substring(0, 16)
    if ($got -ne $wantHash) {
        throw "Integrity check failed (expected $wantHash, got $got). Records may be stale - try: Clear-DnsClientCache"
    }
}

# ---- decompress in memory and run ----
$stream = [System.IO.Compression.DeflateStream]::new(
    [System.IO.MemoryStream]::new([Convert]::FromBase64String($b64)),
    [System.IO.Compression.CompressionMode]::Decompress)
$code = [System.IO.StreamReader]::new($stream).ReadToEnd()
Invoke-Expression $code
