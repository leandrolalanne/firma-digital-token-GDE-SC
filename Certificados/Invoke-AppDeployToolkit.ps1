<#

.SYNOPSIS
Firma Digital / Token Service - desinstala toda version previa, instala token-service_v4.msi y reinicia.

.DESCRIPTION
- Install:   desinstala todo MSI cuyo nombre o carpeta haga referencia al token, instala el MSI de .\Files,
             registra el host de mensajeria nativa en HKLM y reinicia el equipo.
             Interactive: muestra el progreso y una cuenta regresiva de 60 s antes de reiniciar.
             Silent:      no reinicia; devuelve 3010 para que lo haga el sistema de despliegue.
- Uninstall: desinstala todo lo que coincida y borra las claves HKLM del host.
- Repair:    repara el MSI y vuelve a registrar el host en HKLM.

.PARAMETER DeploymentType
The type of deployment to perform.

.PARAMETER DeployMode
Specifies whether the installation should be run in Interactive (shows dialogs), Silent (no dialogs), NonInteractive (dialogs without prompts) mode, or Auto (shows dialogs if a user is logged on, device is not in the OOBE, and there's no running apps to close).

.PARAMETER SuppressRebootPassThru
Suppresses the 3010 return code (requires restart) from being passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

.PARAMETER TerminalServerMode
Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

.PARAMETER DisableLogging
Disables logging to file for the script.

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent

.EXAMPLE
Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent

.NOTES
Toolkit Exit Code Ranges:
- 60000 - 68999: Reserved for built-in exit codes in Invoke-AppDeployToolkit.ps1, and Invoke-AppDeployToolkit.exe
- 69000 - 69999: Recommended for user customized exit codes in Invoke-AppDeployToolkit.ps1
- 70000 - 79999: Recommended for user customized exit codes in PSAppDeployToolkit.Extensions module.

Codigos propios:
- 69002: quedo instalada una version previa tras desinstalar
- 69003: la instalacion no quedo registrada en appwiz.cpl
- 69005: no se pudo registrar el host de mensajeria nativa en HKLM

.LINK
https://psappdeploytoolkit.com

#>

[CmdletBinding()]
param
(
    # Default is 'Install'.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType,

    # Default is 'Auto'. Don't hard-code this unless required.
    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)


##================================================
## MARK: Variables
##================================================

# Zero-Config MSI support is provided when "AppName" is null or empty.
# By setting the "AppName" property, Zero-Config MSI will be disabled.
$adtSession = @{
    # App variables.
    AppVendor = 'GDE'
    AppName = 'Firma Digital Service'
    AppVersion = '2.0.0'
    AppArch = 'x86'
    AppLang = 'ES'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @()
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2026-10-01'
    AppScriptAuthor = 'Modernizacion del Estado - Santa Cruz'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'Firma Digital Service'
    InstallTitle = 'Firma Digital - Token Service'

    # Script variables.
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

# MSI a instalar, dentro de .\Files\
$MsiFileName = 'token-service_v4.msi'

# Que se considera "version previa": todo MSI que diga GDE o Firma Digital, en el nombre visible
# de appwiz.cpl o en la carpeta de instalacion. Solo se tocan paquetes MSI.
# GDE como palabra suelta (\b) para no matchear textos que la contengan de casualidad.
$PreviousAppPattern = '\bGDE\b|Firma\s*Digital'
$PreviousAppFilter = { $_.WindowsInstaller -and ($_.DisplayName -match $PreviousAppPattern -or $_.InstallLocation -match $PreviousAppPattern) }

# El MSI registra el host de mensajeria nativa en HKCU del usuario que instala; en SYSTEM o
# con credenciales de otro admin la firma no anda para el usuario real. Se replica en HKLM.
$NmhFolderName = 'GCBA Firma Digital'
$NmhEntries = @(
    @{ Browser = 'Chrome'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Google\Chrome\NativeMessagingHosts\gcbatoken'; Json = 'cnmtoken.json' }
    @{ Browser = 'Firefox'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Mozilla\NativeMessagingHosts\gcbatoken'; Json = 'main.json' }
)

function Get-NmhInstallDirectory
{
    # Primero lo que declara el MSI; si no, se sondea. El MSI es x86: en Windows x64 va a Program Files (x86).
    foreach ($app in @(Get-ADTApplication -FilterScript $PreviousAppFilter))
    {
        if ($app.InstallLocation -and (Test-Path -LiteralPath (Join-Path $app.InstallLocation 'main.json')))
        {
            return $app.InstallLocation.TrimEnd('\')
        }
    }
    foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles))
    {
        if ($root -and (Test-Path -LiteralPath (Join-Path (Join-Path $root $NmhFolderName) 'main.json')))
        {
            return (Join-Path $root $NmhFolderName)
        }
    }
    return $null
}

function Register-NmhHost
{
    $installDir = Get-NmhInstallDirectory
    if (-not $installDir)
    {
        Write-ADTLogEntry -Message 'No se encontro la carpeta de instalacion; no se puede registrar el host de mensajeria nativa.' -Severity 3
        Close-ADTSession -ExitCode 69005
    }
    Write-ADTLogEntry -Message "Carpeta de instalacion: $installDir"

    foreach ($entry in $NmhEntries)
    {
        $json = Join-Path $installDir $entry.Json
        # Vista de 64 bits y WOW6432Node: el navegador puede ser de 64 o de 32 bits.
        Set-ADTRegistryKey -LiteralPath $entry.Key -Name '(Default)' -Value $json -Type String
        Set-ADTRegistryKey -LiteralPath $entry.Key -Name '(Default)' -Value $json -Type String -Wow6432Node

        $leido = Get-ADTRegistryKey -LiteralPath $entry.Key -Name '(Default)'
        if (($leido -ne $json) -or -not (Test-Path -LiteralPath $json))
        {
            Write-ADTLogEntry -Message "$($entry.Browser): registro HKLM incorrecto (leido: '$leido', esperado: '$json')." -Severity 3
            Close-ADTSession -ExitCode 69005
        }
        Write-ADTLogEntry -Message "$($entry.Browser): host registrado en HKLM -> $json"
    }
}

function Uninstall-PreviousApps
{
    $previas = @(Get-ADTApplication -FilterScript $PreviousAppFilter)
    if ($previas.Count -eq 0)
    {
        Write-ADTLogEntry -Message "No se detectaron versiones previas ($PreviousAppPattern)."
        return
    }
    foreach ($app in $previas)
    {
        Write-ADTLogEntry -Message "Detectado: $($app.DisplayName) $($app.DisplayVersion) $($app.ProductCode) [$($app.InstallLocation)]"
    }

    Uninstall-ADTApplication -FilterScript $PreviousAppFilter

    $restantes = @(Get-ADTApplication -FilterScript $PreviousAppFilter)
    if ($restantes.Count -gt 0)
    {
        foreach ($r in $restantes)
        {
            Write-ADTLogEntry -Message "Quedo instalado tras desinstalar: $($r.DisplayName) $($r.ProductCode)" -Severity 3
        }
        Close-ADTSession -ExitCode 69002
    }
    Write-ADTLogEntry -Message 'Desinstalacion de versiones previas verificada.'
}

function Install-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Install
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    ## Cerrar el host del token sin preguntar: si esta en uso traba la desinstalacion.
    Show-ADTInstallationWelcome -CloseProcesses @{ Name = 'tokensign'; Description = 'Firma Digital (tokensign)' } -Silent -CheckDiskSpace

    Show-ADTInstallationProgress -StatusMessage 'Desinstalando versiones anteriores de Firma Digital...'
    Uninstall-PreviousApps


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Show-ADTInstallationProgress -StatusMessage 'Instalando Firma Digital - Token Service...'
    Start-ADTMsiProcess -Action Install -FilePath $MsiFileName -ArgumentList 'ALLUSERS=1'


    ##================================================
    ## MARK: Post-Install
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    $instalado = @(Get-ADTApplication -FilterScript $PreviousAppFilter)
    if ($instalado.Count -eq 0)
    {
        Write-ADTLogEntry -Message 'La instalacion no aparece registrada en appwiz.cpl.' -Severity 3
        Close-ADTSession -ExitCode 69003
    }
    foreach ($app in $instalado)
    {
        Write-ADTLogEntry -Message "Instalado: $($app.DisplayName) $($app.DisplayVersion) $($app.ProductCode)"
    }
    if ($instalado.Count -gt 1)
    {
        Write-ADTLogEntry -Message 'Hay mas de una entrada en appwiz.cpl. Revisar $PreviousAppPattern.' -Severity 2
    }

    Show-ADTInstallationProgress -StatusMessage 'Registrando Firma Digital en Chrome y Firefox...'
    Register-NmhHost
    Close-ADTInstallationProgress

    ## Interactive: cuenta regresiva de 60 s y reinicio forzado al terminar (boton "Reiniciar ahora").
    ## Silent: no reinicia; el 3010 le indica al sistema de despliegue que reinicie.
    Show-ADTInstallationRestartPrompt -CountdownSeconds 60 -CountdownNoHideSeconds 60
    Close-ADTSession -ExitCode 3010
}

function Uninstall-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Uninstall
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    Show-ADTInstallationWelcome -CloseProcesses @{ Name = 'tokensign'; Description = 'Firma Digital (tokensign)' } -Silent
    Show-ADTInstallationProgress


    ##================================================
    ## MARK: Uninstall
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Uninstall-PreviousApps


    ##================================================
    ## MARK: Post-Uninstallation
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    foreach ($entry in $NmhEntries)
    {
        Remove-ADTRegistryKey -LiteralPath $entry.Key
        Remove-ADTRegistryKey -LiteralPath $entry.Key -Wow6432Node
    }
    Write-ADTLogEntry -Message 'Claves HKLM del host de mensajeria nativa eliminadas.'
}

function Repair-ADTDeployment
{
    [CmdletBinding()]
    param
    (
    )

    ##================================================
    ## MARK: Pre-Repair
    ##================================================
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    Show-ADTInstallationWelcome -CloseProcesses @{ Name = 'tokensign'; Description = 'Firma Digital (tokensign)' } -Silent
    Show-ADTInstallationProgress


    ##================================================
    ## MARK: Repair
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    Start-ADTMsiProcess -Action Repair -FilePath $MsiFileName -ArgumentList 'ALLUSERS=1'


    ##================================================
    ## MARK: Post-Repair
    ##================================================
    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"

    Register-NmhHost
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
    # Import the module locally if available, otherwise try to find it from PSModulePath.
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf)
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }

    # Open a new deployment session, replacing $adtSession with a DeploymentSession.
    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}


##================================================
## MARK: Invocation
##================================================

# Commence the actual deployment operation.
try
{
    # Import any found extensions before proceeding with the deployment.
    Get-ChildItem -LiteralPath $PSScriptRoot -Directory | & {
        process
        {
            if ($_.Name -match 'PSAppDeployToolkit\..+$')
            {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
                Import-Module -Name $_.FullName -Force
            }
        }
    }

    # Invoke the deployment and close out the session.
    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    # An unhandled error has been caught.
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3

    ## Mensaje simple al usuario; el detalle queda en el log.
    Show-ADTInstallationPrompt -Message "No se pudo completar la instalacion de Firma Digital.`n`n$($_.Exception.Message)`n`nLog: C:\Windows\Logs\Software" -ButtonRightText 'Aceptar' -Icon Error -NoWait

    Close-ADTSession -ExitCode 60001
}
