param(
    [switch]$SkipPrepare
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Invoke-Python {
    param(
        [string[]]$Args
    )

    $venvPython = Join-Path $root '.venv\Scripts\python.exe'

    if (Test-Path $venvPython) {
        & $venvPython @Args
        return
    }

    if (Get-Command py -ErrorAction SilentlyContinue) {
        & py -3 @Args
        return
    }

    if (Get-Command python -ErrorAction SilentlyContinue) {
        & python @Args
        return
    }

    throw 'Python was not found. Install Python 3.10+ or create .venv first.'
}

function Start-PythonProcess {
    param(
        [string[]]$Args
    )

    $venvPython = Join-Path $root '.venv\Scripts\python.exe'

    if (Test-Path $venvPython) {
        Start-Process -FilePath $venvPython -ArgumentList $Args -WorkingDirectory $root | Out-Null
        return
    }

    if (Get-Command py -ErrorAction SilentlyContinue) {
        Start-Process -FilePath 'py' -ArgumentList @('-3') + $Args -WorkingDirectory $root | Out-Null
        return
    }

    if (Get-Command python -ErrorAction SilentlyContinue) {
        Start-Process -FilePath 'python' -ArgumentList $Args -WorkingDirectory $root | Out-Null
        return
    }

    throw 'Python was not found. Install Python 3.10+ or create .venv first.'
}

Write-Output 'Installing Python dependencies...'
Invoke-Python -Args @('-m', 'pip', 'install', '-r', 'AI/requirements.txt')

$modelPath = Join-Path $root 'AI\artifacts\nepal_crop_nutrient_model.joblib'

if (-not $SkipPrepare) {
    if (-not (Test-Path $modelPath)) {
        Write-Output 'Model artifact not found. Running MATLAB pipeline to generate data and train model...'
        & matlab -batch "run_nepal_matlab_python_pipeline"
    }
}

Write-Output 'Starting Smart AgroSense API server...'
Start-PythonProcess -Args @('AI/api_server.py')

Write-Output 'Opening dashboard in browser...'
Start-Process 'http://127.0.0.1:8000'

Write-Output 'Pitch demo started.'
Write-Output 'If model already exists and you want a faster startup next time, run: .\launch_pitch_demo.ps1 -SkipPrepare'
