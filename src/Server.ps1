# ============================================================================
#  Sortinghat - local HTTP server
#
#  Deliberately built on System.Net.Sockets.TcpListener rather than
#  System.Net.HttpListener: HttpListener needs a URL reservation (netsh /
#  administrator rights) on Windows, which a lecturer on a managed machine
#  will not have. A raw TCP socket bound to 127.0.0.1 needs no privileges.
#
#  The server is single threaded and handles one request at a time, which is
#  exactly what we want: the Teams cmdlets are not thread safe and the sign-in
#  state lives in this process.
# ============================================================================

$script:ShMimeTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'text/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.svg'  = 'image/svg+xml'
    '.png'  = 'image/png'
    '.ico'  = 'image/x-icon'
    '.json' = 'application/json; charset=utf-8'
}

function New-ShSessionKey {
    $bytes = New-Object byte[] 24
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return (-join ($bytes | ForEach-Object { $_.ToString('x2') }))
}

function Find-ShByteSequence {
    param([byte[]]$Buffer, [int]$Length, [byte[]]$Needle)
    $limit = $Length - $Needle.Length
    for ($i = 0; $i -le $limit; $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Buffer[$i + $j] -ne $Needle[$j]) { $match = $false; break }
        }
        if ($match) { return $i }
    }
    return -1
}

function ConvertFrom-ShQueryString {
    param([string]$Query)
    $result = @{}
    if ([string]::IsNullOrEmpty($Query)) { return $result }
    foreach ($pair in $Query.Split('&')) {
        if ([string]::IsNullOrEmpty($pair)) { continue }
        $idx = $pair.IndexOf('=')
        if ($idx -lt 0) {
            $result[[System.Uri]::UnescapeDataString($pair.Replace('+', ' '))] = ''
        } else {
            $k = [System.Uri]::UnescapeDataString($pair.Substring(0, $idx).Replace('+', ' '))
            $v = [System.Uri]::UnescapeDataString($pair.Substring($idx + 1).Replace('+', ' '))
            $result[$k] = $v
        }
    }
    return $result
}

function Read-ShRequest {
    param($Stream)

    $terminator = [byte[]](13, 10, 13, 10)
    $ms = New-Object System.IO.MemoryStream
    $buffer = New-Object byte[] 8192
    $headerEnd = -1

    try {
        while ($headerEnd -lt 0) {
            $read = $Stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { return $null }
            $ms.Write($buffer, 0, $read)
            $so_far = $ms.ToArray()
            $headerEnd = Find-ShByteSequence -Buffer $so_far -Length $so_far.Length -Needle $terminator
            if ($ms.Length -gt 262144) { return $null }   # runaway header, drop it
        }
    } catch {
        return $null
    }

    $all = $ms.ToArray()
    $headerText = [System.Text.Encoding]::ASCII.GetString($all, 0, $headerEnd)
    $lines = $headerText -split "`r`n"
    if ($lines.Count -lt 1 -or [string]::IsNullOrWhiteSpace($lines[0])) { return $null }

    $requestLine = $lines[0].Split(' ')
    if ($requestLine.Count -lt 2) { return $null }

    $method = $requestLine[0].ToUpperInvariant()
    $target = $requestLine[1]
    $path = $target
    $query = ''
    $qIdx = $target.IndexOf('?')
    if ($qIdx -ge 0) {
        $path = $target.Substring(0, $qIdx)
        $query = $target.Substring($qIdx + 1)
    }

    $headers = @{}
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $c = $line.IndexOf(':')
        if ($c -gt 0) {
            $headers[$line.Substring(0, $c).Trim().ToLowerInvariant()] = $line.Substring($c + 1).Trim()
        }
    }

    # Body
    $bodyStart = $headerEnd + 4
    $have = $all.Length - $bodyStart
    $contentLength = 0
    if ($headers.ContainsKey('content-length')) {
        [void][int]::TryParse($headers['content-length'], [ref]$contentLength)
    }

    $bodyStream = New-Object System.IO.MemoryStream
    if ($have -gt 0) { $bodyStream.Write($all, $bodyStart, [Math]::Min($have, $contentLength)) }

    try {
        while ($bodyStream.Length -lt $contentLength) {
            $want = [Math]::Min($buffer.Length, $contentLength - $bodyStream.Length)
            $read = $Stream.Read($buffer, 0, $want)
            if ($read -le 0) { break }
            $bodyStream.Write($buffer, 0, $read)
        }
    } catch { }

    $bodyText = ''
    if ($bodyStream.Length -gt 0) {
        $bodyText = [System.Text.Encoding]::UTF8.GetString($bodyStream.ToArray())
    }

    return @{
        Method  = $method
        Path    = $path
        Query   = (ConvertFrom-ShQueryString -Query $query)
        Headers = $headers
        Body    = $bodyText
    }
}

function Send-ShResponse {
    param(
        $Stream,
        [int]$Status = 200,
        [string]$StatusText = 'OK',
        [string]$ContentType = 'text/plain; charset=utf-8',
        [byte[]]$Body = $null,
        [hashtable]$ExtraHeaders = $null
    )
    if ($null -eq $Body) { $Body = New-Object byte[] 0 }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("HTTP/1.1 $Status $StatusText`r`n")
    [void]$sb.Append("Content-Type: $ContentType`r`n")
    [void]$sb.Append("Content-Length: $($Body.Length)`r`n")
    [void]$sb.Append("Cache-Control: no-store`r`n")
    [void]$sb.Append("X-Content-Type-Options: nosniff`r`n")
    [void]$sb.Append("Connection: close`r`n")
    if ($ExtraHeaders) {
        foreach ($k in $ExtraHeaders.Keys) { [void]$sb.Append("$k`: $($ExtraHeaders[$k])`r`n") }
    }
    [void]$sb.Append("`r`n")

    $head = [System.Text.Encoding]::ASCII.GetBytes($sb.ToString())
    try {
        $Stream.Write($head, 0, $head.Length)
        if ($Body.Length -gt 0) { $Stream.Write($Body, 0, $Body.Length) }
        $Stream.Flush()
    } catch { }
}

function Send-ShJson {
    param($Stream, $Data, [int]$Status = 200, [string]$StatusText = 'OK')
    $json = $Data | ConvertTo-Json -Depth 12 -Compress
    if ($null -eq $json) { $json = 'null' }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    Send-ShResponse -Stream $Stream -Status $Status -StatusText $StatusText `
        -ContentType 'application/json; charset=utf-8' -Body $bytes
}

function Send-ShText {
    param($Stream, [string]$Text, [int]$Status = 200, [string]$StatusText = 'OK', [string]$ContentType = 'text/plain; charset=utf-8')
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    Send-ShResponse -Stream $Stream -Status $Status -StatusText $StatusText -ContentType $ContentType -Body $bytes
}

function Send-ShStaticFile {
    param($Stream, [string]$Root, [string]$Path)

    $relative = $Path.TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($relative)) { $relative = 'index.html' }
    $relative = $relative -replace '/', [System.IO.Path]::DirectorySeparatorChar

    $full = [System.IO.Path]::GetFullPath((Join-Path $Root $relative))
    $rootFull = [System.IO.Path]::GetFullPath($Root)

    # Directory traversal guard
    if (-not $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        Send-ShText -Stream $Stream -Text 'Forbidden' -Status 403 -StatusText 'Forbidden'
        return
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        Send-ShText -Stream $Stream -Text 'Not found' -Status 404 -StatusText 'Not Found'
        return
    }

    $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
    $type = 'application/octet-stream'
    if ($script:ShMimeTypes.ContainsKey($ext)) { $type = $script:ShMimeTypes[$ext] }

    $bytes = [System.IO.File]::ReadAllBytes($full)
    Send-ShResponse -Stream $Stream -Status 200 -ContentType $type -Body $bytes
}

function Start-ShServer {
    <#
      Binds to a free port on the loopback interface and serves requests until
      Stop-ShServer is requested (POST /api/quit) or the console is closed.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$UiRoot,
        [Parameter(Mandatory = $true)][string]$SessionKey,
        [Parameter(Mandatory = $true)][scriptblock]$OnReady,
        [int]$Port = 0
    )

    $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), $Port
    $listener.Start()
    $actualPort = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $script:ShRunning = $true

    & $OnReady $actualPort

    try {
        while ($script:ShRunning) {
            $client = $null
            try {
                $client = $listener.AcceptTcpClient()
                $client.ReceiveTimeout = 5000
                $client.SendTimeout = 30000
                $stream = $client.GetStream()

                $request = Read-ShRequest -Stream $stream
                if ($null -eq $request) { continue }

                # --- Same-origin / loopback guards -------------------------------
                $host_header = ''
                if ($request.Headers.ContainsKey('host')) { $host_header = $request.Headers['host'] }
                if ($host_header -and -not ($host_header -like '127.0.0.1:*' -or $host_header -like 'localhost:*')) {
                    Send-ShText -Stream $stream -Text 'Bad host' -Status 400 -StatusText 'Bad Request'
                    continue
                }

                if ($request.Path -like '/api/*') {
                    $presented = ''
                    if ($request.Headers.ContainsKey('x-sortinghat-key')) { $presented = $request.Headers['x-sortinghat-key'] }
                    if ($presented -ne $SessionKey) {
                        Send-ShJson -Stream $stream -Status 403 -StatusText 'Forbidden' -Data @{ ok = $false; error = 'Session key missing or wrong. Close this tab and use the link in the Sortinghat console window.' }
                        continue
                    }
                    if ($request.Headers.ContainsKey('origin')) {
                        $origin = $request.Headers['origin']
                        if ($origin -notlike 'http://127.0.0.1:*' -and $origin -notlike 'http://localhost:*') {
                            Send-ShJson -Stream $stream -Status 403 -StatusText 'Forbidden' -Data @{ ok = $false; error = 'Cross-origin request refused.' }
                            continue
                        }
                    }

                    $body = $null
                    if ($request.Body) {
                        try { $body = $request.Body | ConvertFrom-Json } catch { $body = $null }
                    }

                    $result = $null
                    try {
                        $result = Invoke-ShRoute -Method $request.Method -Path $request.Path -Query $request.Query -Body $body
                    } catch {
                        $result = @{ ok = $false; error = ("$($_.Exception.Message)") }
                    }
                    Send-ShJson -Stream $stream -Data $result
                    continue
                }

                if ($request.Method -ne 'GET') {
                    Send-ShText -Stream $stream -Text 'Method not allowed' -Status 405 -StatusText 'Method Not Allowed'
                    continue
                }

                Send-ShStaticFile -Stream $stream -Root $UiRoot -Path $request.Path
            } catch {
                # A dropped connection must never take the server down.
            } finally {
                if ($client) { try { $client.Close() } catch { } }
            }
        }
    } finally {
        try { $listener.Stop() } catch { }
    }
}

function Stop-ShServer { $script:ShRunning = $false }
