# Minimal DNS-delivered Snake (PowerShell). Runs entirely in memory.
$W = 24; $H = 14
[Console]::CursorVisible = $false
try {
    $snake = [System.Collections.Generic.List[object]]::new()
    $snake.Add([pscustomobject]@{ X = [int]($W / 2); Y = [int]($H / 2) })
    $dx = 1; $dy = 0
    $rand = [Random]::new()
    $foodX = $rand.Next(0, $W); $foodY = $rand.Next(0, $H)
    $score = 0
    $alive = $true
    Clear-Host
    while ($alive) {
        while ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true).Key
            switch ($key) {
                'UpArrow'    { if ($dy -ne 1)  { $dx = 0; $dy = -1 } }
                'DownArrow'  { if ($dy -ne -1) { $dx = 0; $dy = 1 } }
                'LeftArrow'  { if ($dx -ne 1)  { $dx = -1; $dy = 0 } }
                'RightArrow' { if ($dx -ne -1) { $dx = 1; $dy = 0 } }
                'Q'          { $alive = $false }
            }
        }
        if (-not $alive) { break }
        $hx = $snake[0].X + $dx
        $hy = $snake[0].Y + $dy
        if ($hx -lt 0 -or $hx -ge $W -or $hy -lt 0 -or $hy -ge $H) { break }
        $hit = $false
        foreach ($s in $snake) { if ($s.X -eq $hx -and $s.Y -eq $hy) { $hit = $true; break } }
        if ($hit) { break }
        $snake.Insert(0, [pscustomobject]@{ X = $hx; Y = $hy })
        if ($hx -eq $foodX -and $hy -eq $foodY) {
            $score++
            $foodX = $rand.Next(0, $W); $foodY = $rand.Next(0, $H)
        } else {
            $snake.RemoveAt($snake.Count - 1)
        }
        $occ = @{}
        foreach ($s in $snake) { $occ["$($s.X),$($s.Y)"] = $true }
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.AppendLine("Score: $score   (arrow keys = move, Q = quit)")
        [void]$sb.AppendLine('+' + ('-' * $W) + '+')
        for ($y = 0; $y -lt $H; $y++) {
            [void]$sb.Append('|')
            for ($x = 0; $x -lt $W; $x++) {
                if ($x -eq $foodX -and $y -eq $foodY) { [void]$sb.Append('@') }
                elseif ($occ.ContainsKey("$x,$y")) { [void]$sb.Append('O') }
                else { [void]$sb.Append(' ') }
            }
            [void]$sb.AppendLine('|')
        }
        [void]$sb.AppendLine('+' + ('-' * $W) + '+')
        [Console]::SetCursorPosition(0, 0)
        [Console]::Write($sb.ToString())
        Start-Sleep -Milliseconds 110
    }
} finally {
    [Console]::CursorVisible = $true
    [Console]::SetCursorPosition(0, $H + 4)
    Write-Host "Game over! Final score: $score"
}
