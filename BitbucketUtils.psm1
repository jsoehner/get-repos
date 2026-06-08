function Get-AuthHeader {
    param (
        [string]$ParameterSetName,
        [string]$PersonalAccessToken,
        [PSCredential]$Credential
    )
    if ($ParameterSetName -eq 'PAT') {
        return @{ Authorization = "Bearer $PersonalAccessToken" }
    }

    $pair    = "$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"
    $bytes   = [System.Text.Encoding]::UTF8.GetBytes($pair)
    $encoded = [Convert]::ToBase64String($bytes)

    return @{ Authorization = "Basic $encoded" }
}

function Convert-TS {
    param([Nullable[long]]$ts)

    if ($null -eq $ts) {
        return $null
    }

    return [DateTimeOffset]::FromUnixTimeMilliseconds($ts).UtcDateTime
}

function Get-ProjectExportPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ProjectKey
    )

    $dir = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($dir)) {
        $dir = "."
    }

    $leaf     = Split-Path -Leaf $Path
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
    $ext      = [System.IO.Path]::GetExtension($leaf)

    if ([string]::IsNullOrWhiteSpace($ext)) {
        $ext = ".out"
    }

    return (Join-Path $dir "$baseName-$ProjectKey$ext")
}

function Ensure-ParentDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

function Format-RemainingTime {
    param([TimeSpan]$TimeSpan)

    if ($TimeSpan.TotalSeconds -lt 1) {
        return "less than 1 second"
    }

    if ($TimeSpan.TotalHours -ge 1) {
        return "{0:00}h {1:00}m {2:00}s" -f [int]$TimeSpan.TotalHours, $TimeSpan.Minutes, $TimeSpan.Seconds
    }

    if ($TimeSpan.TotalMinutes -ge 1) {
        return "{0:00}m {1:00}s" -f [int]$TimeSpan.TotalMinutes, $TimeSpan.Seconds
    }

    return "{0:00}s" -f [int]$TimeSpan.TotalSeconds
}

function Invoke-Api {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [int]$ThrottleDelayMs = 0,
        [int]$Retries = 5
    )

    if ($ThrottleDelayMs -gt 0) {
        Start-Sleep -Milliseconds $ThrottleDelayMs
    }

    for ($attempt = 0; $attempt -le $Retries; $attempt++) {
        try {
            return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get -ErrorAction Stop
        }
        catch {
            $statusCode = $null
            $retryAfter = $null
            $errorJson  = $null

            try {
                if ($_.Exception.Response) {
                    if ($_.Exception.Response.StatusCode) {
                        $statusCode = [int]$_.Exception.Response.StatusCode
                    }
                    $errorStream = $_.Exception.Response.GetResponseStream()
                    if ($errorStream) {
                        $reader = [System.IO.StreamReader]::new($errorStream)
                        $errorJson = $reader.ReadToEnd()
                    }
                }
            }
            catch {
            }

            try {
                $responseHeaders = $_.Exception.Response.Headers
                if ($responseHeaders -and $responseHeaders['Retry-After']) {
                    $rawRetryAfter = $responseHeaders['Retry-After']
                    if ($rawRetryAfter -is [System.Array]) {
                        $retryAfter = [int]$rawRetryAfter[0]
                    }
                    else {
                        $retryAfter = [int]$rawRetryAfter
                    }
                }
            }
            catch {
            }

            $isTransient = $statusCode -in @(429, 500, 502, 503, 504)

            if (-not $isTransient -or $attempt -ge $Retries) {
                if ($errorJson) {
                    Write-Warning "API Error on URI $Uri : HTTP $statusCode - $errorJson"
                }
                return $null
            }

            $delaySeconds =
                if ($retryAfter -and $retryAfter -gt 0) {
                    $retryAfter
                }
                else {
                    # Exponential backoff + small jitter
                    [Math]::Min(60, [Math]::Pow(2, $attempt) + (Get-Random -Minimum 0 -Maximum 3))
                }

            Start-Sleep -Seconds $delaySeconds
        }
    }

    return $null
}

function Get-PagedValues {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UriWithoutStart,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [int]$ThrottleDelayMs = 0,
        [int]$Retries = 5
    )

    $all        = [System.Collections.Generic.List[object]]::new()
    $start      = 0
    $isLastPage = $false

    while (-not $isLastPage) {
        $separator = if ($UriWithoutStart -match '\?') { '&' } else { '?' }
        $uri       = "$UriWithoutStart${separator}start=$start"

        $resp = Invoke-Api -Uri $uri -Headers $Headers -ThrottleDelayMs $ThrottleDelayMs -Retries $Retries
        if ($null -eq $resp) {
            return $null
        }

        if ($resp.values) {
            foreach ($val in $resp.values) {
                $all.Add($val)
            }
        }

        if ($null -eq $resp.isLastPage) {
            $isLastPage = $true
        }
        else {
            $isLastPage = [bool]$resp.isLastPage
        }

        if (-not $isLastPage) {
            $start = [int]$resp.nextPageStart
        }
    }

    return $all
}

function Get-BitbucketProjects {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [int]$ThrottleDelayMs = 0,
        [int]$Retries = 5
    )

    $projects = Get-PagedValues -UriWithoutStart "$BaseUrl/rest/api/1.0/projects?limit=1000" `
                                -Headers $Headers `
                                -ThrottleDelayMs $ThrottleDelayMs `
                                -Retries $Retries

    if ($null -eq $projects) {
        throw "Failed to retrieve projects from Bitbucket."
    }

    return $projects
}

Export-ModuleMember -Function Get-AuthHeader, Convert-TS, Get-ProjectExportPath, Ensure-ParentDirectory, Format-RemainingTime, Invoke-Api, Get-PagedValues, Get-BitbucketProjects
