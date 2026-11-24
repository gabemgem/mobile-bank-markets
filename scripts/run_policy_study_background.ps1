param(
    [string]$StudyRoot = 'results/v2-policy-study-final',
    [string]$Python = 'python',
    [string]$Java = 'java',
    [string]$Javac = 'javac',
    [string]$NetLogoHome = 'C:/Program Files/NetLogo 7.0.3',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
$studyPath = (Resolve-Path -LiteralPath $StudyRoot).Path
$plan = Get-Content -LiteralPath (Join-Path $studyPath 'plan.json') -Raw | ConvertFrom-Json
$batches = @($plan.batches)
if (-not $batches.Count -or @($batches | Group-Object batch | Where-Object Count -ne 1).Count) {
    throw 'The plan must contain unique batch IDs.'
}
if ($DryRun) {
    $batches | Select-Object batch,runs,requests_per_tick | Format-Table
    Write-Output "Validated $($batches.Count) batches; no simulations launched."
    exit 0
}

# Holding the file open prevents two supervisors from running the same study.
$lock = [System.IO.File]::Open((Join-Path $studyPath 'background.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
$log = Join-Path $studyPath 'background.log'
$statusPath = Join-Path $studyPath 'background-status.json'
$status = [ordered]@{
    state = 'starting'
    runner_pid = $PID
    started_utc = [DateTime]::UtcNow.ToString('o')
    updated_utc = ''
    planned_runs = $plan.planned_runs
    total_batches = $batches.Count
    completed_batches = @()
    current_batch = ''
    error = ''
}
function Save-Status {
    $status.updated_utc = [DateTime]::UtcNow.ToString('o')
    $temporary = $statusPath + '.tmp'
    $status | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $statusPath -Force
}
try {
    foreach ($batch in $batches) {
        $status.state = 'running'
        $status.current_batch = $batch.batch
        Save-Status
        Add-Content -LiteralPath $log -Value "$([DateTime]::UtcNow.ToString('o')) Starting $($batch.batch)"
        $arguments = @('experiments/policy_study.py', 'run', '--out', $studyPath,
                       '--batch', $batch.batch, '--resume', '--java', $Java, '--javac', $Javac,
                       '--netlogo-home', $NetLogoHome)
        & $Python @arguments *>> $log
        if ($LASTEXITCODE -ne 0) { throw "Batch $($batch.batch) exited with code $LASTEXITCODE. See background.log and the batch run.log." }
        $status.completed_batches += $batch.batch
        Save-Status
    }
    $status.state = 'complete'
    $status.current_batch = ''
    Save-Status
    Add-Content -LiteralPath $log -Value "$([DateTime]::UtcNow.ToString('o')) All batches completed."
} catch {
    $status.state = 'failed'
    $status.error = $_.Exception.Message
    Save-Status
    Add-Content -LiteralPath $log -Value "$([DateTime]::UtcNow.ToString('o')) FAILED: $($status.error)"
    throw
} finally {
    $lock.Dispose()
}
