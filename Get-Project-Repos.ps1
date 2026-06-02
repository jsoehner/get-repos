# Get-Projects-Repos-v8.2.ps1
#requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Credential')]
param (
    # Explicit project key(s)
    [string[]]$Project,

    # Pattern-based project selection
    [string]$ProjectPattern,
    [switch]$ProjectPatternIsRegex,

    [string]$BitbucketBaseUrl = "https://bitbucket.agile.bns",
    [string]$Branch = "master",
    [string[]]$FallbackBranches = @("main"),

    [Parameter(Mandatory = $true, ParameterSetName = 'Credential')]
    [PSCredential]$Credential,

    [Parameter(Mandatory = $true, ParameterSetName = 'PAT')]
    [string]$PersonalAccessToken,

    [string]$RepoNameRegex,
    [datetime]$FromDate,
    [datetime]$ToDate,

    # Central export outputs
    [string]$ExportCsv,
    [string]$ExportJson,

    # Also write one file per project
    [switch]$SplitExportByProject,

    [switch]$AsJson,
    [switch]$CompactOutput,
    [switch]$Quiet,

    # Parallel / API-safety knobs
    [ValidateRange(1, 64)]
    [int]$ThrottleLimit = 4,

    [ValidateRange(0, 60000)]
    [int]$ApiThrottleDelayMs = 250,

    [ValidateRange(0, 10)]
    [int]$MaxApiRetries = 5
)

# =====================================================================
# Validation
# =====================================================================

$cleanProjects = @()
if ($null -ne $Project) {
    $cleanProjects = @(
        $Project |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
    )
}

$hasProject = $cleanProjects.Count -gt 0
$hasPattern = -not [string]::IsNullOrWhiteSpace($ProjectPattern)

if (-not $hasProject -and -not $hasPattern) {
    throw "You must supply either -Project or -ProjectPattern."
}

if ($hasProject -and $hasPattern) {
    throw "Use either -Project or -ProjectPattern, not both."
}

# =====================================================================
# Import Utility Functions
# =====================================================================

$modulePath = Join-Path $PWD "BitbucketUtils.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
} else {
    Write-Warning "Could not find utility module at $modulePath"
}

# =====================================================================
# Setup
# =====================================================================

$headers = Get-AuthHeader -ParameterSetName $PSCmdlet.ParameterSetName -PersonalAccessToken $PersonalAccessToken -Credential $Credential
$base    = $BitbucketBaseUrl.TrimEnd('/')

$fromUtc = if ($FromDate) { $FromDate.ToUniversalTime() } else { $null }
$toUtc   = if ($ToDate)   { $ToDate.ToUniversalTime() }   else { $null }

$branches = @($Branch) + $FallbackBranches | Select-Object -Unique

# =====================================================================
# Resolve target projects
# =====================================================================

$targetProjects = @()

if ($hasProject) {
    $targetProjects = @(
        $cleanProjects | ForEach-Object {
            [pscustomobject]@{
                key  = $_
                name = $_
            }
        }
    )
}
else {
    $allProjects = Get-BitbucketProjects -BaseUrl $base `
                                         -Headers $headers `
                                         -ThrottleDelayMs $ApiThrottleDelayMs `
                                         -Retries $MaxApiRetries

    if ($ProjectPatternIsRegex) {
        $targetProjects = @(
            $allProjects | Where-Object {
                $_.key  -match $ProjectPattern -or
                $_.name -match $ProjectPattern
            }
        )
    }
    else {
        $targetProjects = @(
            $allProjects | Where-Object {
                $_.key  -like $ProjectPattern -or
                $_.name -like $ProjectPattern
            }
        )
    }
}

if ($targetProjects.Count -eq 0) {
    throw "No projects matched the supplied selector."
}

$targetProjects = @($targetProjects | Sort-Object key -Unique)
$totalProjects  = $targetProjects.Count

if (-not $Quiet -and -not $CompactOutput) {
    Write-Host "Resolved $totalProjects project(s)." -ForegroundColor Cyan
    Write-Host "Branches: $($branches -join ', ')"
    Write-Host "ThrottleLimit: $ThrottleLimit"
    Write-Host "API Throttle Delay: ${ApiThrottleDelayMs}ms per request per worker"
    if ($hasProject) {
        Write-Host "Projects: $($targetProjects.key -join ', ')"
    }
    else {
        Write-Host "ProjectPattern: $ProjectPattern"
        Write-Host "Matched Projects: $($targetProjects.key -join ', ')"
    }
    Write-Host ""
}

# =====================================================================
# Parallel worker
# =====================================================================

$scanStart = Get-Date

$job = $targetProjects.key | ForEach-Object -Parallel {
    # Capture current pipeline item immediately
    $currentProject = $_

    # Safely localize cross-runspace thread variables locally
    $localBase               = $using:base
    $localHeaders            = $using:headers
    $localApiThrottleDelayMs = $using:ApiThrottleDelayMs
    $localMaxApiRetries      = $using:MaxApiRetries
    $localBranches           = $using:branches
    $localRepoNameRegex      = $using:RepoNameRegex
    $localFromUtc            = $using:fromUtc
    $localToUtc              = $using:toUtc

    $localModulePath = Join-Path $using:PWD "BitbucketUtils.psm1"
    if (Test-Path $localModulePath) {
        Import-Module $localModulePath
    }

    $projectStart = Get-Date
    $projectResults = [System.Collections.Generic.List[object]]::new()
    $projectSkipped = [System.Collections.Generic.List[object]]::new()

    # Repos (paged)
    $repoBase = "$localBase/rest/api/1.0/projects/$currentProject/repos?limit=1000"
    $repos = Get-PagedValues -UriWithoutStart $repoBase `
                             -Headers $localHeaders `
                             -ThrottleDelayMs $localApiThrottleDelayMs `
                             -Retries $localMaxApiRetries

    if ($null -eq $repos) {
        $projectEnd = Get-Date
        return [pscustomobject]@{
            Project = $currentProject
            Results = @()
            Skipped = @(
                [pscustomobject]@{
                    Project    = $currentProject
                    Repository = $null
                    Reason     = "Failed to retrieve repositories"
                }
            )
            Summary = [pscustomobject]@{
                Project          = $currentProject
                RepoCount        = 0
                SkippedRepoCount = 1
                CommitCount      = 0
                StartedUtc       = $projectStart.ToUniversalTime()
                FinishedUtc      = $projectEnd.ToUniversalTime()
                DurationSeconds  = [math]::Round(($projectEnd - $projectStart).TotalSeconds, 2)
                Status           = "Repository retrieval failed"
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($localRepoNameRegex)) {
        $repos = @($repos | Where-Object { $_.name -match $localRepoNameRegex })
    }
    else {
        $repos = @($repos)
    }

    $skippedRepoCount = 0
    $commitCount = 0

    foreach ($repo in $repos) {
        $repoCommits = $null
        $usedBranch = $null

        foreach ($b in $localBranches) {
            $ref = [Uri]::EscapeDataString("refs/heads/$b")
            $commitBase = "$localBase/rest/api/1.0/projects/$currentProject/repos/$($repo.slug)/commits?until=$ref&limit=1000"

            $commitValues = Get-PagedValues -UriWithoutStart $commitBase `
                                            -Headers $localHeaders `
                                            -ThrottleDelayMs $localApiThrottleDelayMs `
                                            -Retries $localMaxApiRetries

            if ($null -ne $commitValues) {
                $repoCommits = @($commitValues)
                $usedBranch  = $b
                break
            }
        }

        if (-not $repoCommits) {
            $skippedRepoCount++
            $projectSkipped.Add([pscustomobject]@{
                Project    = $currentProject
                Repository = $repo.name
                Reason     = "No commits / branch not found / API failure"
            })
            continue
        }

        foreach ($c in $repoCommits) {
            $dt = Convert-TS -ts $c.committerTimestamp

            if ($null -ne $localFromUtc -and $dt -lt $localFromUtc) { continue }
            if ($null -ne $localToUtc   -and $dt -gt $localToUtc)   { continue }

            $projectResults.Add([pscustomobject]@{
                Project        = $currentProject
                Repository     = $repo.name
                BranchUsed     = $usedBranch
                CommitDateUtc  = $dt
                Message        = $c.message
                ScotiaID       = $c.author.name
                Email          = $c.author.emailAddress
                CommitId       = $c.id
            })

            $commitCount++
        }
    }

    $projectEnd = Get-Date

    return [pscustomobject]@{
        Project = $currentProject
        Results = @($projectResults)
        Skipped = @($projectSkipped)
        Summary = [pscustomobject]@{
            Project          = $currentProject
            RepoCount        = $repos.Count
            SkippedRepoCount = $skippedRepoCount
            CommitCount      = $commitCount
            StartedUtc       = $projectStart.ToUniversalTime()
            FinishedUtc      = $projectEnd.ToUniversalTime()
            DurationSeconds  = [math]::Round(($projectEnd - $projectStart).TotalSeconds, 2)
            Status           = "Completed"
        }
    }
} -ThrottleLimit $ThrottleLimit -AsJob

# =====================================================================
# Progress + ETA monitor
# =====================================================================

while ($job.State -in @('NotStarted', 'Running')) {
    $childJobs = @($job.ChildJobs)

    $completedCount = @(
        $childJobs | Where-Object { $_.State -in @('Completed', 'Failed', 'Stopped') }
    ).Count

    $runningCount = @(
        $childJobs | Where-Object { $_.State -eq 'Running' }
    ).Count

    $failedCount = @(
        $childJobs | Where-Object { $_.State -in @('Failed', 'Stopped') }
    ).Count

    $percent = if ($totalProjects -gt 0) {
        [math]::Round(($completedCount / $totalProjects) * 100, 2)
    }
    else {
        100
    }

    $elapsed = (Get-Date) - $scanStart

    $remainingText = "Calculating..."
    $etaText       = "Calculating..."

    if ($completedCount -gt 0) {
        $avgSecondsPerProject = $elapsed.TotalSeconds / $completedCount
        $remainingProjects    = $totalProjects - $completedCount
        $remainingTime        = [TimeSpan]::FromSeconds($avgSecondsPerProject * $remainingProjects)
        $eta                  = (Get-Date).Add($remainingTime)

        $remainingText = Format-RemainingTime -TimeSpan $remainingTime
        $etaText       = $eta.ToString("yyyy-MM-dd HH:mm:ss")
    }

    Write-Progress -Id 1 `
        -Activity "Processing Bitbucket Projects" `
        -Status "Completed: $completedCount / $totalProjects | Running: $runningCount | Failed: $failedCount | Remaining: $remainingText | ETA: $etaText" `
        -PercentComplete $percent

    Start-Sleep -Seconds 1
}

Write-Progress -Id 1 -Activity "Processing Bitbucket Projects" -Completed

# =====================================================================
# Collect results
# =====================================================================

$payloads = Receive-Job -Job $job -Wait -AutoRemoveJob

$results = [System.Collections.Generic.List[object]]::new()
$skipped = [System.Collections.Generic.List[object]]::new()
$projectSummaries = [System.Collections.Generic.List[object]]::new()

foreach ($payload in @($payloads | Sort-Object Project)) {
    foreach ($r in @($payload.Results)) {
        [void]$results.Add($r)
    }

    foreach ($s in @($payload.Skipped)) {
        [void]$skipped.Add($s)
    }

    if ($null -ne $payload.Summary) {
        [void]$projectSummaries.Add($payload.Summary)
    }
}

$scanEnd = Get-Date

# =====================================================================
# Summary
# =====================================================================

$uniqueRepos = @(
    $results |
    Select-Object -ExpandProperty Repository -Unique
)

$summary = [pscustomobject]@{
    ProjectsRequested  = if ($hasProject) { $cleanProjects.Count } else { $null }
    ProjectPattern     = if ($hasPattern) { $ProjectPattern } else { $null }
    ProjectCount       = $totalProjects
    RepoCount          = $uniqueRepos.Count
    SkippedRepoCount   = $skipped.Count
    CommitCount        = $results.Count
    BranchesTried      = ($branches -join ', ')
    ParallelThrottle   = $ThrottleLimit
    ApiThrottleDelayMs = $ApiThrottleDelayMs
    FromDateUtc        = $fromUtc
    ToDateUtc          = $toUtc
    StartedUtc         = $scanStart.ToUniversalTime()
    FinishedUtc        = $scanEnd.ToUniversalTime()
    DurationSeconds    = [math]::Round(($scanEnd - $scanStart).TotalSeconds, 2)
}

# =====================================================================
# Export
# =====================================================================

# Central CSV
if (-not [string]::IsNullOrWhiteSpace($ExportCsv)) {
    Ensure-ParentDirectory -Path $ExportCsv
    $results | Export-Csv -Path $ExportCsv -NoTypeInformation

    if (-not $Quiet) {
        Write-Host "Central CSV exported: $ExportCsv" -ForegroundColor Green
    }
}

# Central JSON
if (-not [string]::IsNullOrWhiteSpace($ExportJson)) {
    Ensure-ParentDirectory -Path $ExportJson
    @{
        Summary          = $summary
        ProjectSummaries = @($projectSummaries)
        Results          = @($results)
        Skipped          = @($skipped)
    } |
    ConvertTo-Json -Depth 8 |
    Set-Content -Path $ExportJson

    if (-not $Quiet) {
        Write-Host "Central JSON exported: $ExportJson" -ForegroundColor Green
    }
}

# Per-project export
$shouldSplit = $SplitExportByProject -or $hasPattern -or ($totalProjects -gt 1)

if ($shouldSplit) {
    foreach ($proj in @($projectSummaries | Sort-Object Project)) {
        $currentProject = $proj.Project
        $projectRows    = @($results | Where-Object { $_.Project -eq $currentProject })
        $projectSkipped = @($skipped | Where-Object { $_.Project -eq $currentProject })

        if (-not [string]::IsNullOrWhiteSpace($ExportCsv)) {
            $projectCsvPath = Get-ProjectExportPath -Path $ExportCsv -ProjectKey $currentProject
            Ensure-ParentDirectory -Path $projectCsvPath

            $projectRows | Export-Csv -Path $projectCsvPath -NoTypeInformation

            if (-not $Quiet) {
                Write-Host "Per-project CSV exported: $projectCsvPath" -ForegroundColor DarkGreen
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($ExportJson)) {
            $projectJsonPath = Get-ProjectExportPath -Path $ExportJson -ProjectKey $currentProject
            Ensure-ParentDirectory -Path $projectJsonPath

            @{
                Summary = $proj
                Results = $projectRows
                Skipped = $projectSkipped
            } |
            ConvertTo-Json -Depth 8 |
            Set-Content -Path $projectJsonPath

            if (-not $Quiet) {
                Write-Host "Per-project JSON exported: $projectJsonPath" -ForegroundColor DarkGreen
            }
        }
    }
}

# =====================================================================
# Output
# =====================================================================

if (-not $Quiet) {
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Cyan
    $summary | Format-List

    Write-Host ""
    Write-Host "Project Summaries:" -ForegroundColor Cyan
    $projectSummaries | Sort-Object Project | Format-Table -AutoSize
}

if ($AsJson) {
    @{
        Summary          = $summary
        ProjectSummaries = @($projectSummaries)
        Results          = @($results)
        Skipped          = @($skipped)
    } | ConvertTo-Json -Depth 8
}
else {
    $results
}
