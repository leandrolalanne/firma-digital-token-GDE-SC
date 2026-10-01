<#
.SYNOPSIS
    PSAppDeployToolkit v4 - Firma Digital / Token Service.
    Desinstala toda version previa e instala token-service_v4.msi.

.NOTES
    Este archivo REEMPLAZA al Invoke-AppDeployToolkit.ps1 que genera New-ADTTemplate.
    Copiar el MSI a .\Files\token-service_v4.msi
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType = 'Install',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode = 'Interactive',

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$AllowRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)


##================================================
## MARK: Variables
##================================================

$adtSession = @{
    # App variables.
    AppVendor                   = 'GDE'
    AppName                     = 'Firma Digital Service'
    AppVersion                  = '2.0.0'
    AppArch                     = 'x86'
    AppLang                     = 'ES'
    AppRevision                 = '01'
    AppSuccessExitCodes         = @(0)
    AppRebootExitCodes          = @(1641, 3010)
    AppScriptVersion            = '1.0.0'
    AppScriptDate               = '2026-09-30'
    AppScriptAuthor             = 'Modernizacion del Estado - Santa Cruz'

    # Install Titles.
    InstallName                 = 'Firma Digital Service'
    InstallTitle                = 'Firma Digital - Token Service'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters   = $PSBoundParameters
}

# Nombre del MSI dentro de .\Files\
$MsiFileName = 'token-service_v4.msi'

# Patron de deteccion de versiones previas en appwiz.cpl.
$PreviousAppPattern = 'Firma Digital|tokensign|token.?service'


##================================================
## MARK: Install
##================================================

function Install-ADTDeployment
{
    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    Write-ADTLogEntry -Message "Buscando versiones previas que coincidan con: $PreviousAppPattern"

    $previas = Get-ADTApplication -FilterScript { $_.DisplayName -match $PreviousAppPattern }

    if (-not $previas)
    {
        Write-ADTLogEntry -Message 'No se detectaron versiones previas instaladas.'
    }
    else
    {
        foreach ($app in $previas)
        {
            Write-ADTLogEntry -Message "Detectado: $($app.DisplayName) version $($app.DisplayVersion) [$($app.ProductCode)]"
        }

        Write-ADTLogEntry -Message 'Desinstalando versiones previas...'
        Uninstall-ADTApplication -FilterScript { $_.DisplayName -match $PreviousAppPattern }

        $restantes = Get-ADTApplication -FilterScript { $_.DisplayName -match $PreviousAppPattern }
        if ($restantes)
        {
            foreach ($r in $restantes)
            {
                Write-ADTLogEntry -Message "Quedo instalado tras desinstalar: $($r.DisplayName)" -Severity 3
            }
            Close-ADTSession -ExitCode 69002
        }
        Write-ADTLogEntry -Message 'Desinstalacion de versiones previas verificada.'
    }

    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Write-ADTLogEntry -Message "Instalando $MsiFileName"
    Start-ADTMsiProcess -Action Install -FilePath $MsiFileName -ArgumentList 'ALLUSERS=1'

    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    $instalado = Get-ADTApplication -FilterScript { $_.DisplayName -match $PreviousAppPattern }
    if (-not $instalado)
    {
        Write-ADTLogEntry -Message 'La instalacion no aparece registrada en appwiz.cpl.' -Severity 3
        Close-ADTSession -ExitCode 69003
    }
    foreach ($app in $instalado)
    {
        Write-ADTLogEntry -Message "Instalado OK: $($app.DisplayName) version $($app.DisplayVersion)"
    }
    if (@($instalado).Count -gt 1)
    {
        Write-ADTLogEntry -Message 'Hay mas de una entrada en appwiz.cpl. Revisar $PreviousAppPattern.' -Severity 2
    }

    # El reinicio lo resuelve el sistema de despliegue via codigo 3010.
    # Ejecutar con -AllowRebootPassThru para que 3010 llegue a GPO/SCCM/Intune.
    Write-ADTLogEntry -Message 'Despliegue finalizado. Se solicita reinicio (3010).'
    Close-ADTSession -ExitCode 3010
}


##================================================
## MARK: Uninstall
##================================================

function Uninstall-ADTDeployment
{
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    $adtSession.InstallPhase = $adtSession.DeploymentType

    Write-ADTLogEntry -Message "Desinstalando todo lo que coincida con: $PreviousAppPattern"
    Uninstall-ADTApplication -FilterScript { $_.DisplayName -match $PreviousAppPattern }

    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    $restantes = Get-ADTApplication -FilterScript { $_.DisplayName -match $PreviousAppPattern }
    if ($restantes)
    {
        Write-ADTLogEntry -Message 'Quedaron entradas instaladas tras la desinstalacion.' -Severity 3
        Close-ADTSession -ExitCode 69002
    }
    Write-ADTLogEntry -Message 'Desinstalacion completa verificada.'
}


##================================================
## MARK: Repair
##================================================

function Repair-ADTDeployment
{
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    $adtSession.InstallPhase = $adtSession.DeploymentType

    Write-ADTLogEntry -Message "Reparando la instalacion con $MsiFileName"
    Start-ADTMsiProcess -Action Repair -FilePath $MsiFileName -ArgumentList 'ALLUSERS=1'

    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
}


##================================================
## MARK: Initialization
##================================================

# Set strict error handling across entire operation.
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

# Import the module and instantiate a new session.
try
{
    $moduleName = if ([System.IO.File]::Exists("$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"))
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"
    }
    else
    {
        'PSAppDeployToolkit'
    }
    Import-Module -FullyQualifiedName @{ ModuleName = $moduleName; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.0.6' } -Force
    try
    {
        $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
        $adtSession = Open-ADTSession -SessionState $ExecutionContext.SessionState @adtSession @iadtParams -PassThru
    }
    catch
    {
        Remove-Module -Name PSAppDeployToolkit* -Force
        throw
    }
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}


##================================================
## MARK: Invocation
##================================================

try
{
    Get-Item -Path $PSScriptRoot\PSAppDeployToolkit.* | & {
        process
        {
            Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
            Import-Module -Name $_.FullName -Force
        }
    }
    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    Write-ADTLogEntry -Message ($mainErrorMessage = Resolve-ADTErrorRecord -ErrorRecord $_) -Severity 3
    Show-ADTDialogBox -Text $mainErrorMessage -Icon Stop | Out-Null
    Close-ADTSession -ExitCode 60001
}
finally
{
    Remove-Module -Name PSAppDeployToolkit* -Force
}
