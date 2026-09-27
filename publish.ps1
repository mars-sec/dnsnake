<#
  publish.ps1 - Turns a script into DNS TXT records.
  Deflates + base64-encodes the input, splits it into chunks, and prints
  exactly what to paste into your DNS provider (Squarespace) plus the
  bootstrap one-liner to play it.

  Usage:
    .\publish.ps1                                  # defaults to snake.ps1
    .\publish.ps1 -InputFile .\snake.ps1 -ChunkSize 200 -Namespace game
#>
param(
    [string]$InputFile = "$PSScriptRoot\snake.ps1",
    [string]$Namespace = 'dnsnake',
    [int]$ChunkSize = 200
)

$bytes = [System.IO.File]::ReadAllBytes($InputFile)

# Raw Deflate (no gzip header/footer) -> smallest payload
$ms = [System.IO.MemoryStream]::new()
$ds = [System.IO.Compression.DeflateStream]::new($ms, [System.IO.Compression.CompressionLevel]::Optimal)
$ds.Write($bytes, 0, $bytes.Length)
$ds.Dispose()
$compressed = $ms.ToArray()

$b64 = [Convert]::ToBase64String($compressed)

# Integrity hash (first 16 hex chars of SHA-256 of the base64 payload)
$sha = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($b64))
$hashShort = ((($hashBytes | ForEach-Object { $_.ToString('x2') }) -join '')).Substring(0, 16)

# Source hash (first 16 hex chars of SHA-256 of the *decompressed source*). This
# is the "read-the-code" pin: anyone can inspect the source, hash it, and match.
$srcHashBytes = $sha.ComputeHash($bytes)
$srcHash = ((($srcHashBytes | ForEach-Object { $_.ToString('x2') }) -join '')).Substring(0, 16)

# Chunk the base64 string
$chunks = for ($i = 0; $i -lt $b64.Length; $i += $ChunkSize) {
    $len = [Math]::Min($ChunkSize, $b64.Length - $i)
    $b64.Substring($i, $len)
}
$chunks = @($chunks)

Write-Host ""
Write-Host "=== Publish report ===" -ForegroundColor Cyan
Write-Host ("Original size : {0} bytes" -f $bytes.Length)
Write-Host ("Compressed    : {0} bytes ({1:P0} of original)" -f $compressed.Length, ($compressed.Length / $bytes.Length))
Write-Host ("Base64 length : {0} chars" -f $b64.Length)
Write-Host ("Chunk size    : {0} chars" -f $ChunkSize)
Write-Host ("Chunk count   : {0} records (+1 manifest)" -f $chunks.Count)

# Two-stage loader record: fetches all chunks, inflates, and runs. Stored in DNS
# so the thing you TYPE stays tiny (just pull this record and iex it). Uses $d,
# which the play command sets, so the loader value stays under the 255-char
# single-string DNS limit.
$maxIdx = $chunks.Count - 1
$loader = "`$b=-join(0..$maxIdx|%{(Resolve-DnsName `"c`$_.`$d`" TXT).Strings});iex([IO.StreamReader]::new([IO.Compression.DeflateStream]::new([IO.MemoryStream]::new([convert]::FromBase64String(`$b)),[IO.Compression.CompressionMode]::Decompress)).ReadToEnd())"

Write-Host ""
Write-Host "=== TXT records to create  (Type = TXT for all) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host ("  HOST".PadRight(18) + "VALUE")
Write-Host ("  ----".PadRight(18) + "-----")
Write-Host ("  run.$Namespace".PadRight(18) + $loader)
for ($i = 0; $i -lt $chunks.Count; $i++) {
    Write-Host ("  c$i.$Namespace".PadRight(18) + $chunks[$i])
}
Write-Host ("  loader length   : {0} chars (DNS single-string limit is 255)" -f $loader.Length)
Write-Host ("  manifest.$Namespace".PadRight(18) + " " + ("c={0};h={1};s={2}" -f $chunks.Count, $hashShort, $srcHash))
Write-Host "    (manifest carries: chunk count c, payload hash h, source hash s -- used by the verify commands below)"

Write-Host ""
Write-Host "=== Play command ===" -ForegroundColor Cyan
$play = @'
$d='{NS}.marshallyanis.com';iex(-join(Resolve-DnsName "run.$d" TXT).Strings)
'@
Write-Host ($play.Replace('{NS}', $Namespace))

Write-Host ""
Write-Host "=== INSPECT command -- prints the exact game source, runs NOTHING ===" -ForegroundColor Cyan
Write-Host "    (share this so skeptics can read the code before ever running it)"
$inspect = @'
$d='{NS}.marshallyanis.com';[IO.StreamReader]::new([IO.Compression.DeflateStream]::new([IO.MemoryStream]::new([convert]::FromBase64String((-join(0..{MAX}|%{(Resolve-DnsName "c$_.$d" TXT).Strings})))),[IO.Compression.CompressionMode]::Decompress)).ReadToEnd()
'@
Write-Host ($inspect.Replace('{NS}', $Namespace).Replace('{MAX}', $maxIdx))

Write-Host ""
Write-Host "=== VERIFY command -- confirms the live payload matches the pinned source hash ===" -ForegroundColor Cyan
$verify = @'
$d='{NS}.marshallyanis.com';$b=-join(0..{MAX}|%{(Resolve-DnsName "c$_.$d" TXT).Strings});$ms=[IO.MemoryStream]::new();[IO.Compression.DeflateStream]::new([IO.MemoryStream]::new([convert]::FromBase64String($b)),[IO.Compression.CompressionMode]::Decompress).CopyTo($ms);$m=@{};((Resolve-DnsName "manifest.$d" TXT).Strings-join'')-split';'|%{$k,$val=$_-split'=';$m[$k]=$val};$h=((([Security.Cryptography.SHA256]::Create().ComputeHash($ms.ToArray()))|%{$_.ToString('x2')})-join'').Substring(0,16);"source hash: $h  pinned: $($m.s)  match: $($h -eq $m.s)"
'@
Write-Host ($verify.Replace('{NS}', $Namespace).Replace('{MAX}', $maxIdx))

Write-Host ""
Write-Host "=== Confirm the run.$Namespace loader survived DNS entry ===" -ForegroundColor Cyan
$loadercheck = @'
$d='{NS}.marshallyanis.com';$v=-join(Resolve-DnsName "run.$d" TXT).Strings;"loader length in DNS: $($v.Length) (want {LEN}); intact: $($v.Length -eq {LEN})"
'@
Write-Host ($loadercheck.Replace('{NS}', $Namespace).Replace('{LEN}', $loader.Length))
Write-Host ""
