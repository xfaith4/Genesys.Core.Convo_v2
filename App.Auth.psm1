#Requires -Version 5.1
Set-StrictMode -Version Latest

# Gate E: All auth logic isolated here. Invoke-RestMethod only against login.{region} OAuth endpoints.

Add-Type -AssemblyName System.Security

$script:AuthDir  = [System.IO.Path]::Combine($env:LOCALAPPDATA, 'GenesysConversationAnalysis')
$script:AuthFile = [System.IO.Path]::Combine($script:AuthDir, 'auth.dat')

$script:StoredHeaders  = $null
$script:ConnectionInfo = $null

# ── DPAPI helpers ────────────────────────────────────────────────────────────

function _ProtectString {
    param([string]$Plain)
    $bytes     = [System.Text.Encoding]::UTF8.GetBytes($Plain)
    $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes, $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [System.Convert]::ToBase64String($encrypted)
}

function _UnprotectString {
    param([string]$Cipher)
    $encrypted = [System.Convert]::FromBase64String($Cipher)
    $bytes     = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $encrypted, $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function _SaveTokenPayload {
    param([hashtable]$Payload)
    if (-not [System.IO.Directory]::Exists($script:AuthDir)) {
        [System.IO.Directory]::CreateDirectory($script:AuthDir) | Out-Null
    }
    $json      = $Payload | ConvertTo-Json -Compress
    $protected = _ProtectString -Plain $json
    [System.IO.File]::WriteAllText($script:AuthFile, $protected, [System.Text.Encoding]::ASCII)
}

function _LoadTokenPayload {
    if (-not [System.IO.File]::Exists($script:AuthFile)) { return $null }
    try {
        $protected = [System.IO.File]::ReadAllText($script:AuthFile, [System.Text.Encoding]::ASCII)
        $json      = _UnprotectString -Cipher $protected
        return $json | ConvertFrom-Json
    } catch {
        return $null
    }
}

# ── Public functions ─────────────────────────────────────────────────────────

function Connect-GenesysCloudApp {
    <#
    .SYNOPSIS
        Authenticates using OAuth 2.0 client credentials flow.
    .DESCRIPTION
        POSTs to login.{Region}/oauth/token with Basic credentials.
        Stores the resulting bearer token via DPAPI.
    #>
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret,
        [Parameter(Mandatory)][string]$Region
    )
    $loginUrl = "https://login.$($Region)/oauth/token"
    $encoded  = [System.Convert]::ToBase64String(
        [System.Text.Encoding]::ASCII.GetBytes("$($ClientId):$($ClientSecret)"))
    $body     = 'grant_type=client_credentials'
    $headers  = @{
        Authorization  = "Basic $encoded"
        'Content-Type' = 'application/x-www-form-urlencoded'
    }

    $response  = Invoke-RestMethod -Uri $loginUrl -Method Post -Headers $headers -Body $body -ErrorAction Stop
    $token     = $response.access_token
    $expiresAt = [datetime]::UtcNow.AddSeconds([int]$response.expires_in - 30)

    _SaveTokenPayload @{
        token     = $token
        expiresAt = $expiresAt.ToString('o')
        region    = $Region
        flow      = 'client_credentials'
    }
    $script:StoredHeaders  = @{ Authorization = "Bearer $token" }
    $script:ConnectionInfo = [pscustomobject]@{
        Region    = $Region
        Flow      = 'client_credentials'
        ExpiresAt = $expiresAt
    }
    return $script:StoredHeaders
}

function Connect-GenesysCloudPkce {
    <#
    .SYNOPSIS
        Authenticates using OAuth 2.0 Authorization Code + PKCE flow (browser login).
    .DESCRIPTION
        Launches the system browser to login.{Region}/oauth/authorize, listens on the
        redirect URI for the authorization code, then exchanges it for a token.
        Supports cancellation via CancellationToken.
    #>
    param(
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$Region,
        [string]$RedirectUri                                    = 'http://localhost:8080/callback',
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    # Build PKCE verifier + challenge
    $verifierBytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($verifierBytes)
    $verifier = [System.Convert]::ToBase64String($verifierBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    $sha256         = [System.Security.Cryptography.SHA256]::Create()
    $challengeBytes = $sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($verifier))
    $challenge      = [System.Convert]::ToBase64String($challengeBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    $state   = [System.Guid]::NewGuid().ToString('N')
    $authUrl = "https://login.$($Region)/oauth/authorize" +
               "?response_type=code" +
               "&client_id=$($ClientId)" +
               "&redirect_uri=$([System.Uri]::EscapeDataString($RedirectUri))" +
               "&code_challenge=$($challenge)" +
               "&code_challenge_method=S256" +
               "&state=$($state)"

    Start-Process $authUrl

    # Listen for callback on redirect URI
    $listener = New-Object System.Net.HttpListener
    $prefix   = if ($RedirectUri.EndsWith('/')) { $RedirectUri } else { "$RedirectUri/" }
    $listener.Prefixes.Add($prefix)
    $listener.Start()

    $code = $null
    try {
        while (-not $CancellationToken.IsCancellationRequested) {
            $ctxTask = $listener.GetContextAsync()
            while (-not $ctxTask.IsCompleted -and -not $CancellationToken.IsCancellationRequested) {
                Start-Sleep -Milliseconds 150
            }
            if ($CancellationToken.IsCancellationRequested) { break }

            $ctx      = $ctxTask.Result
            $rawQuery = $ctx.Request.Url.Query.TrimStart('?')
            $pairs    = $rawQuery -split '&'
            $qp       = @{}
            foreach ($p in $pairs) {
                $kv = $p -split '=', 2
                if ($kv.Count -eq 2) { $qp[$kv[0]] = [System.Uri]::UnescapeDataString($kv[1]) }
            }
            $code = $qp['code']

            $respHtml  = '<html><body><h2>Authentication complete. You may close this tab.</h2></body></html>'
            $respBytes = [System.Text.Encoding]::UTF8.GetBytes($respHtml)
            $ctx.Response.ContentType       = 'text/html'
            $ctx.Response.ContentLength64   = $respBytes.Length
            $ctx.Response.OutputStream.Write($respBytes, 0, $respBytes.Length)
            $ctx.Response.OutputStream.Close()
            break
        }
    } finally {
        $listener.Stop()
    }

    if (-not $code) { throw 'PKCE authorization was cancelled or did not return a code.' }

    $tokenUrl = "https://login.$($Region)/oauth/token"
    $body     = "grant_type=authorization_code" +
                "&code=$($code)" +
                "&redirect_uri=$([System.Uri]::EscapeDataString($RedirectUri))" +
                "&client_id=$($ClientId)" +
                "&code_verifier=$($verifier)"
    $headers  = @{ 'Content-Type' = 'application/x-www-form-urlencoded' }

    $response  = Invoke-RestMethod -Uri $tokenUrl -Method Post -Headers $headers -Body $body -ErrorAction Stop
    $token     = $response.access_token
    $expiresAt = [datetime]::UtcNow.AddSeconds([int]$response.expires_in - 30)

    _SaveTokenPayload @{
        token     = $token
        expiresAt = $expiresAt.ToString('o')
        region    = $Region
        flow      = 'pkce'
    }
    $script:StoredHeaders  = @{ Authorization = "Bearer $token" }
    $script:ConnectionInfo = [pscustomobject]@{
        Region    = $Region
        Flow      = 'pkce'
        ExpiresAt = $expiresAt
    }
    return $script:StoredHeaders
}

function Get-StoredHeaders {
    <#
    .SYNOPSIS
        Returns cached or stored-on-disk bearer headers if the token has not expired.
    #>
    if ($null -ne $script:StoredHeaders) { return $script:StoredHeaders }

    $payload = _LoadTokenPayload
    if ($null -eq $payload) { return $null }

    try {
        $expiresAt = [datetime]::Parse($payload.expiresAt)
    } catch {
        return $null
    }
    if ([datetime]::UtcNow -ge $expiresAt) { return $null }

    $script:StoredHeaders  = @{ Authorization = "Bearer $($payload.token)" }
    $script:ConnectionInfo = [pscustomobject]@{
        Region    = $payload.region
        Flow      = $payload.flow
        ExpiresAt = $expiresAt
    }
    return $script:StoredHeaders
}

function Test-GenesysConnection {
    <#
    .SYNOPSIS
        Returns $true if a valid (non-expired) stored token exists.
    #>
    $h = Get-StoredHeaders
    return ($null -ne $h)
}

function Get-ConnectionInfo {
    <#
    .SYNOPSIS
        Returns connection metadata (Region, Flow, ExpiresAt) or $null.
    #>
    Get-StoredHeaders | Out-Null
    return $script:ConnectionInfo
}

function Clear-StoredToken {
    <#
    .SYNOPSIS
        Removes the in-memory token and deletes the DPAPI-encrypted auth.dat file.
    #>
    $script:StoredHeaders  = $null
    $script:ConnectionInfo = $null
    if ([System.IO.File]::Exists($script:AuthFile)) {
        [System.IO.File]::Delete($script:AuthFile)
    }
}

Export-ModuleMember -Function Connect-GenesysCloudApp, Connect-GenesysCloudPkce, `
    Get-StoredHeaders, Test-GenesysConnection, Get-ConnectionInfo, Clear-StoredToken
