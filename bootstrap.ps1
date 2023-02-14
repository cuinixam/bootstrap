# About preference variables: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variable

# Stop execution on first non-terminating error (an error that doesn't stop the cmdlet processing)
$ErrorActionPreference = "Stop"

# Write-Information always displays the informational message, and continues running
$InformationPreference = "Continue"

Function Edit-Env {
    # workaround for GithubActions
    if ($Env:INVERT_PATH_VARIABLE -eq "true") {
        $Env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    }
    else {
        $Env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    }
}

Function Invoke-CommandLine {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Usually this statement must be avoided (https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/avoid-using-invoke-expression?view=powershell-7.3), here it is OK as it does not execute unknown code.')]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$CommandLine,
        [Parameter(Mandatory = $false, Position = 1)]
        [bool]$StopAtError = $true,
        [Parameter(Mandatory = $false, Position = 2)]
        [bool]$Silent = $false
    )
    if (-Not$Silent) {
        Write-Information -MessageData "Executing: $CommandLine"
    }
    Invoke-Expression $CommandLine
    if ($LASTEXITCODE -ne 0) {
        if ($StopAtError) {
            Write-Error "Command line call `"$CommandLine`" failed with exit code $LASTEXITCODE"
            exit 1
        }
        else {
            if (-Not$Silent) {
                Write-Information -MessageData  "Command line call `"$CommandLine`" failed with exit code $LASTEXITCODE, continuing ..."
            }
        }
    }
}

Function Import-Dot-Env {
    if (Test-Path -Path '.env') {
        # load environment properties
        $envProps = ConvertFrom-StringData (Get-Content '.env' -raw)
    }

    Return $envProps
}

Function Initialize-Proxy {
    $envProps = Import-Dot-Env
    if ($envProps.'HTTP_PROXY') {
        $Env:HTTP_PROXY = $envProps.'HTTP_PROXY'
        $Env:HTTPS_PROXY = $Env:HTTP_PROXY
        if ($envProps.'NO_PROXY') {
            $Env:NO_PROXY = $envProps.'NO_PROXY'
            $WebProxy = New-Object System.Net.WebProxy($Env:HTTP_PROXY, $true, ($Env:NO_PROXY).split(','))
        }
        else {
            $WebProxy = New-Object System.Net.WebProxy($Env:HTTP_PROXY, $true)
        }

        [net.webrequest]::defaultwebproxy = $WebProxy
        [net.webrequest]::defaultwebproxy.credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    }
}

Function Install-Scoop {
    if (Test-Path -Path 'scoopfile.json') {
        # Initial Scoop installation
        if (-Not (Get-Command 'scoop' -ErrorAction SilentlyContinue)) {
            Invoke-RestMethod 'https://raw.githubusercontent.com/xxthunder/ScoopInstall/master/install.ps1' -outfile "$PSScriptRoot\bootstrap.scoop.ps1"
            if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                & $PSScriptRoot\bootstrap.scoop.ps1 -RunAsAdmin
            }
            else {
                & $PSScriptRoot\bootstrap.scoop.ps1
            }
            Edit-Env

            Invoke-CommandLine -CommandLine "scoop bucket rm main" -Silent $true -StopAtError $false
            Invoke-CommandLine -CommandLine "scoop bucket add main" -Silent $true
        }

        # install needed tools
        Invoke-CommandLine -CommandLine "scoop update"
        Invoke-CommandLine -CommandLine "scoop install lessmsi"

        # Some old tweak to get 7zip installed correctly
        Invoke-CommandLine -CommandLine "scoop config use_lessmsi $true"

        # avoid deadlocks while updating scoop buckets
        Invoke-CommandLine -CommandLine "scoop config autostash_on_conflict $true"

        Invoke-CommandLine -CommandLine "scoop install 7zip"
        Invoke-CommandLine -CommandLine "scoop install innounp"
        Invoke-CommandLine -CommandLine "scoop install dark"
        Invoke-CommandLine -CommandLine "scoop import scoopfile.json"
        Edit-Env
    }
}

Function Install-Python-Dependency {
    if ((Test-Path -Path 'requirements.txt') -or (Test-Path -Path 'Pipfile')) {
        # Prepare python environment
        Invoke-CommandLine -CommandLine "python -m pip install pipenv pip-system-certs"

        if ($clean) {
            # Start with a fresh virtual environment
            if (Test-Path -Path '.venv') {
                Invoke-CommandLine -CommandLine "python -m pipenv --rm" -StopAtError $false
            }
        }
        if (-Not (Test-Path -Path '.venv')) {
            New-Item -ItemType Directory '.venv'
        }
        if (Test-Path -Path 'requirements.txt') {
            Invoke-CommandLine -CommandLine "python -m pipenv install --requirements requirements.txt"
        }
        else {
            Invoke-CommandLine -CommandLine "python -m pipenv install"
        }
    }
}

Function Install-West {
    if ((Test-Path -Path '.west/config')) {
        # install west into pipenv or pip
        if (Test-Path -Path '.venv') {
            Invoke-CommandLine -CommandLine "python -m pipenv install west"
        }
        else {
            Invoke-CommandLine -CommandLine "python -m pip install west"
        }
        Invoke-CommandLine -CommandLine "west update"
    }
}

if (-Not $TestExecution) {
    Initialize-Proxy
    Install-Scoop
    Install-Python-Dependency
    Install-West
}
