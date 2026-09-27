# DNSnake

A playable game of Snake delivered entirely through **DNS TXT records** and executed **in memory**. The delivery mechanism is a minimal demonstration of how **fileless malware** stages a payload over DNS, and of how a defender (or a cautious user) can **inspect and verify** such a payload *before* running it.

> The payload here is a harmless terminal Snake game. The point of the project is the transport and the verification around the payload.

---

## TL;DR

```powershell
# Play it (fetches + runs in memory):
iex(-join(Resolve-DnsName "run.dnsnake.marshallyanis.com" TXT).Strings)
```

Before you run *anyone's* "just paste this" command, you should be able to read the code and prove it hasn't changed.

---

## Files

| File | Role |
|------|------|
| `snake.ps1` | The payload: a ~60-line in-memory Snake game. |
| `publish.ps1` | The **author** side: compresses `snake.ps1`, hashes it, chunks it, and prints the TXT records + the play/inspect/verify commands. |
| `bootstrap.ps1` | The **player** side (long form): fetches the chunks, verifies payload integrity, decompresses, and runs. The one-line play command is a compact version of this. |

---

## How the TXT records are generated

`publish.ps1` turns a script into DNS records in a few steps:

1. **Read** the raw bytes of `snake.ps1`.
2. **Compress** with raw Deflate (`CompressionLevel.Optimal`): no gzip header, smallest payload. (2484 B → 916 B, ~37%.)
3. **Base64-encode** the compressed bytes (1224 chars).
4. **Chunk** the base64 into 200-char pieces (DNS TXT strings cap at 255). That yields records `c0` … `c6`.
5. **Hash twice:**
   - **payload hash `h`** = first 16 hex of `SHA-256(base64 string)`: proves the records reassembled without corruption or staleness.
   - **source hash `s`** = first 16 hex of `SHA-256(raw source bytes)`: the "read-the-code" pin, anyone can hash the decompressed source and match it.
6. **Emit** the records:
   - `c0…c6`: the payload chunks.
   - `manifest`: `c=<chunk count>;h=<payload hash>;s=<source hash>`.
   - `run`: a small loader one-liner (kept under the 255-char DNS limit) so the thing you *type* stays tiny.

Regenerate the records for this deployment with:

```powershell
.\publish.ps1 -InputFile .\snake.ps1 -Namespace dnsnake -ChunkSize 200
```

Then paste the printed records into your DNS provider as `Type = TXT`.

---

## How to verify before running

Two independent checks, matching the two hashes above.

### 1. Inspect: print the source, run nothing

```powershell
$d='dnsnake.marshallyanis.com';[IO.StreamReader]::new([IO.Compression.DeflateStream]::new([IO.MemoryStream]::new([convert]::FromBase64String((-join(0..6|%{(Resolve-DnsName "c$_.$d" TXT).Strings})))),[IO.Compression.CompressionMode]::Decompress)).ReadToEnd()
```

This reassembles and decompresses the payload and prints it to your terminal. It executes nothing: read it like any other script.

### 2. Verify: confirm the live payload matches the pinned source hash

```powershell
$d='dnsnake.marshallyanis.com';$b=-join(0..6|%{(Resolve-DnsName "c$_.$d" TXT).Strings});$ms=[IO.MemoryStream]::new();[IO.Compression.DeflateStream]::new([IO.MemoryStream]::new([convert]::FromBase64String($b)),[IO.Compression.CompressionMode]::Decompress).CopyTo($ms);$m=@{};((Resolve-DnsName "manifest.$d" TXT).Strings-join'')-split';'|%{$k,$val=$_-split'=';$m[$k]=$val};$h=((([Security.Cryptography.SHA256]::Create().ComputeHash($ms.ToArray()))|%{$_.ToString('x2')})-join'').Substring(0,16);"source hash: $h  pinned: $($m.s)  match: $($h -eq $m.s)"
```

Expected:

```
source hash: ac5ca110c6dbea66  pinned: ac5ca110c6dbea66  match: True
```

> **Paste each command as a single line.** Terminal display-wrapping can insert real newlines into a copied one-liner and break it mid-token.

**Why the verify command hashes the decompressed *bytes*, not the decoded text:** the pinned `s` is `SHA-256` over the raw source bytes. An earlier version recomputed the hash over `UTF8.GetBytes(decodedString)`, which only matches when the source is saved as BOM-less UTF-8: a UTF-8 BOM or UTF-16 save would make a clean payload falsely fail verification. Hashing the raw decompressed bytes is encoding-agnostic and always matches the pin. The repo also ships a `.gitattributes` pinning `snake.ps1` to UTF-8 so the pinned hash stays stable across edits.

---

## How this maps to fileless malware

The mechanism here is not hypothetical: DNS is a well-documented covert staging and C2 channel, and every property that makes DNSnake tidy is also what makes the malicious version hard to catch:

- **No file on disk.** The payload lives in TXT records and runs from memory (`iex` of a decompressed string), so on-disk AV signatures never see it.
- **DNS looks benign.** TXT lookups are ordinary, ubiquitous traffic that most egress policies allow outright. Chunking the payload across many records mimics legitimate encoded TXT data (SPF, DKIM, verification tokens).
- **Living off the land.** `Resolve-DnsName` and `Invoke-Expression` are built-in; nothing is dropped or installed.
- **Two-stage loading.** A tiny typed/loaded command (`run`) pulls a larger second stage from other records: the same indirection real loaders use to keep the initial footprint minimal.


---

## Detection & mitigation

If you defend Windows environments, this is the shape to watch for:

- **PowerShell Script Block Logging** (Event ID 4104) and **Module Logging**: capture `iex`/`Invoke-Expression` of decompressed or DNS-sourced content.
- **AMSI**: inspects the deobfuscated script content at execution time, even for in-memory payloads.
- **Behavioral alerting** on the pattern `Resolve-DnsName ... -Type TXT` feeding into `Invoke-Expression` / `iex`, or `DeflateStream` + `FromBase64String` + `iex` in the same scope.
- **DNS monitoring**: high volumes of TXT queries to a single domain, high-entropy/base64-looking TXT answers, or lookups to newly-registered domains.
- **Constrained Language Mode** and **execution policy** / application control (WDAC): constrain what in-memory scripts can do.
- **Egress DNS control**: force clients through a logging resolver; block or alert on direct external DNS.

---
