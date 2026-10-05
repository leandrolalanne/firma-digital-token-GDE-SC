<#

.SYNOPSIS
FirmaDigitalSC - desinstala toda version previa del token de Firma Digital, instala las dependencias que
correspondan a la variante y token-service_v4.msi, y reinicia.

.DESCRIPTION
Un solo script para las cuatro variantes. build\build.ps1 escribe SupportFiles\Variante.psd1 (nombre,
version y componentes) y copia a .\Files solo los instaladores de esa variante:
- Basico:      Token.
- Java:        Token + Java8 + CertificadosAC.
- Tokens:      Token + Java8 + CertificadosAC + DriversToken.
- Extensiones: Token + Java8 + CertificadosAC + DriversToken + Extensiones.

- Install:   desinstala todo MSI cuyo nombre o carpeta haga referencia al token; [Java8] instala Java 8 x64 si
             no hay un Java 8 que tokensign.exe pueda usar; [CertificadosAC] instala los certificados de las AC
             (instalador oficial); [DriversToken] instala los drivers de token que falten (se saltea cada uno
             si ya esta esa version o una mayor); instala el MSI de .\Files, registra el host de mensajeria
             nativa en HKLM (Chrome, Edge, Firefox); [Extensiones] fuerza por directiva la extension
             "Firma con Token GDE" en Chrome, Edge y Firefox; y reinicia el equipo.
             Interactive: muestra el progreso y una cuenta regresiva de 60 s antes de reiniciar.
             Silent:      no reinicia; devuelve 3010 para que lo haga el sistema de despliegue.
- Uninstall: desinstala todo lo que coincida, borra las claves HKLM del host y quita la extension de las
             directivas de los navegadores (solo su entrada).
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
- 69007: no quedo instalado un Java 8 que tokensign.exe pueda encontrar
- 69008: no quedaron instalados los certificados raiz de Firma Digital de Argentina
- 69009: un driver de token no aparece en appwiz.cpl despues de instalarlo
- 69010: falta SupportFiles\Variante.psd1 (el paquete no se genero con build\build.ps1)
- 69011: no se pudo forzar la extension de Firma Digital en Chrome, Edge o Firefox

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

# Variante del paquete: la escribe build\build.ps1 (Nombre, Version y Componentes).
try
{
    $Variante = Import-PowerShellDataFile -LiteralPath "$PSScriptRoot\SupportFiles\Variante.psd1" -ErrorAction Stop
}
catch
{
    $Host.UI.WriteErrorLine("Falta SupportFiles\Variante.psd1: el paquete se genera con build\build.ps1.")
    exit 69010
}

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
    AppScriptVersion = $Variante.Version
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
# Edge lee su propia clave; usa cnmtoken.json porque instala la extension de la Chrome Web Store (mismo ID).
$NmhFolderName = 'GCBA Firma Digital'
$NmhEntries = @(
    @{ Browser = 'Chrome'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Google\Chrome\NativeMessagingHosts\gcbatoken'; Json = 'cnmtoken.json' }
    @{ Browser = 'Edge'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Edge\NativeMessagingHosts\gcbatoken'; Json = 'cnmtoken.json' }
    @{ Browser = 'Firefox'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Mozilla\NativeMessagingHosts\gcbatoken'; Json = 'main.json' }
)

# Extensiones "Firma con Token GDE", forzadas por directiva: cada navegador la baja de su tienda al abrirse.
# Chrome y Edge: la de la Chrome Web Store (su ID es el que admite cnmtoken.json en allowed_origins).
# Firefox: la de addons.mozilla.org (su ID es el que admite main.json en allowed_extensions).
$ChromeExtensionId = 'maddemndndajaiilmnjoocajgkpmlael'
$ChromeUpdateUrl = 'https://clients2.google.com/service/update2/crx'
$ForcelistKeys = @(
    @{ Browser = 'Chrome'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist' }
    @{ Browser = 'Edge'; Key = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist' }
)
$FirefoxPolicyKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Mozilla\Firefox'
$FirefoxExtensionId = 'firma.token@gde.gob.ar'
$FirefoxInstallUrl = 'https://addons.mozilla.org/firefox/downloads/latest/firma-con-token-gde/latest.xpi'

# Java: tokensign.exe es un wrapper Launch4j (Java >= 1.6, prefiere 32 bits y acepta 64) que busca el
# runtime en HKLM\SOFTWARE\JavaSoft. Tiene que ser Java 8: el firmador crea el proveedor PKCS#11 con
# new SunPKCS11(InputStream), constructor que no existe desde Java 9.
$JavaInstaller = 'jre-8u503-windows-x64.exe'

# Instalador oficial (Inno Setup) de los certificados de las AC de Firma Digital de Argentina. Corre un
# script.bat con certutil -addstore -enterprise (2 raiz en Root, el resto en CA) y no deja entrada en appwiz.
$CertInstaller = 'Certificados AC Firma Digital Argentina.exe'
$RootCertThumbprints = @{
    'D774180508C65136B80130B6AF0F002B131FD76B' = 'AC Raiz (2007)'
    '887A1FE63A485392EA5F1526670ABC81E20009AD' = 'AC Raiz de la Republica Argentina (2016)'
}

function Get-Java8Home
{
    # Donde busca Launch4j: SOFTWARE\JavaSoft (vistas de 64 y 32 bits), JRE o JDK 1.8 con java.exe presente.
    foreach ($base in @('HKEY_LOCAL_MACHINE\SOFTWARE\JavaSoft', 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\JavaSoft'))
    {
        foreach ($tipo in @('Java Runtime Environment', 'Java Development Kit'))
        {
            foreach ($key in @(Get-ChildItem -LiteralPath "Registry::$base\$tipo" -ErrorAction Ignore))
            {
                if ($key.PSChildName -notlike '1.8*') { continue }
                $javaHome = [string]$key.GetValue('JavaHome')
                if ($javaHome -and (Test-Path -LiteralPath (Join-Path $javaHome 'bin\java.exe')))
                {
                    return $javaHome
                }
            }
        }
    }
    return $null
}

function Install-Java8
{
    $javaHome = Get-Java8Home
    if ($javaHome)
    {
        Write-ADTLogEntry -Message "Java 8 ya instalado en $javaHome; no se instala."
        return
    }

    Show-ADTInstallationProgress -StatusMessage 'Instalando Java 8...'
    $log = Join-Path $adtSession.LogPath 'Java8_Install.log'
    Start-ADTProcess -FilePath (Join-Path $adtSession.DirFiles $JavaInstaller) -ArgumentList "/s INSTALL_SILENT=1 AUTO_UPDATE=0 REBOOT=0 SPONSORS=0 WEB_ANALYTICS=0 /L $log"

    $javaHome = Get-Java8Home
    if (-not $javaHome)
    {
        Write-ADTLogEntry -Message "Java 8 no quedo registrado en HKLM\SOFTWARE\JavaSoft (ver $log)." -Severity 3
        Close-ADTSession -ExitCode 69007
    }
    Write-ADTLogEntry -Message "Java 8 instalado en $javaHome."
}

function Install-RootCertificates
{
    # Se corre siempre: certutil -f es idempotente y asi entran las AC nuevas que traiga el instalador.
    Show-ADTInstallationProgress -StatusMessage 'Instalando certificados de las Autoridades Certificantes de Firma Digital...'
    $log = Join-Path $adtSession.LogPath 'CertificadosAC_Install.log'
    Start-ADTProcess -FilePath (Join-Path $adtSession.DirFiles $CertInstaller) -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG=`"$log`""

    # Inno ignora el resultado de certutil: se verifica en el almacen raiz del equipo.
    foreach ($thumb in $RootCertThumbprints.Keys)
    {
        if (-not (Test-Path -LiteralPath "Cert:\LocalMachine\Root\$thumb"))
        {
            Write-ADTLogEntry -Message "Falta el certificado raiz $($RootCertThumbprints[$thumb]) [$thumb]." -Severity 3
            Close-ADTSession -ExitCode 69008
        }
        Write-ADTLogEntry -Message "Certificado raiz presente: $($RootCertThumbprints[$thumb]) [$thumb]."
    }
}

# Drivers de token (todos, porque en una PC puede haber usuarios con tokens de distintas marcas).
# Match identifica la entrada en appwiz.cpl; si ya hay una con version >= Version, se saltea.
# SafeNet: MSI 10.8 y licencia tal cual vienen dentro del paquete del proveedor (SITEPRO,
# "WINDOWS - SafeNet5110+-SAC_10_8.exe"); la licencia se aplica con PROP_LICENSE_FILE.
$TokenDrivers = @(
    @{
        Name = 'SafeNet Authentication Client'
        Version = '10.8.259.0'
        Match = { $_.DisplayName -like 'SafeNet Authentication Client*' }
        Msi = 'Drivers\sac-10.8-x64-10.8.msi'
        License = 'Drivers\SITEPRO_ONE SEAT_End User License Certificate.txt'
    }
    @{
        Name = 'Feitian ePass2003'
        Version = '1.1.22.831'
        Match = { $_.DisplayName -match 'ePass2003' }
        Exe = 'Drivers\MSePass2003_Win_Spanish_V1.1.22.831.exe'
        Arguments = '/S'
    }
    @{
        Name = 'Longmai mToken CryptoID'
        Version = '2.2.26.324'
        Match = { $_.PSChildName -eq '{F72BDB06-FA8C-4B07-89A0-ADB1ADC791F7}_is1' }
        Exe = 'Drivers\MSCryptoID-FIPS140-3_Win_Spanish_V2.2.26.324.exe'
        Arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG="{0}"'
    }
)

function Get-TokenDriverInstalled
{
    param ([Parameter(Mandatory = $true)] [System.Collections.Hashtable]$Driver)

    # Devuelve la entrada de appwiz.cpl si ya esta instalada la version pedida o una mas nueva.
    foreach ($app in @(Get-ADTApplication -FilterScript $Driver.Match))
    {
        $instalada = $null
        if (-not [System.Version]::TryParse([string]$app.DisplayVersion, [ref]$instalada))
        {
            Write-ADTLogEntry -Message "$($Driver.Name): version instalada '$($app.DisplayVersion)' no comparable; se considera instalado."
            return $app
        }
        if ($instalada -ge [System.Version]$Driver.Version)
        {
            return $app
        }
        Write-ADTLogEntry -Message "$($Driver.Name): instalada $($app.DisplayVersion), menor que $($Driver.Version); se actualiza."
    }
    return $null
}

function Install-TokenDrivers
{
    foreach ($driver in $TokenDrivers)
    {
        $app = Get-TokenDriverInstalled -Driver $driver
        if ($app)
        {
            Write-ADTLogEntry -Message "$($driver.Name) ya instalado ($($app.DisplayName) $($app.DisplayVersion)); no se instala."
            continue
        }

        Show-ADTInstallationProgress -StatusMessage "Instalando driver de token: $($driver.Name)..."
        if ($driver.ContainsKey('Msi'))
        {
            $license = Join-Path $adtSession.DirFiles $driver.License
            Start-ADTMsiProcess -Action Install -FilePath (Join-Path $adtSession.DirFiles $driver.Msi) -AdditionalArgumentList "PROP_LICENSE_FILE=`"$license`""
        }
        else
        {
            $log = Join-Path $adtSession.LogPath ('{0}_Install.log' -f ($driver.Name -replace '\s', ''))
            Start-ADTProcess -FilePath (Join-Path $adtSession.DirFiles $driver.Exe) -ArgumentList ($driver.Arguments -f $log)
        }

        $app = Get-TokenDriverInstalled -Driver $driver
        if (-not $app)
        {
            Write-ADTLogEntry -Message "$($driver.Name) no aparece instalado en appwiz.cpl despues de instalar." -Severity 3
            Close-ADTSession -ExitCode 69009
        }
        Write-ADTLogEntry -Message "$($driver.Name) instalado: $($app.DisplayName) $($app.DisplayVersion)."
    }
}

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

function Get-ForcelistEntryName
{
    # Nombre del valor (1, 2, 3...) que ya fuerza la extension en la lista del navegador, o $null.
    param ([Parameter(Mandatory = $true)] [System.String]$Key)

    $valores = Get-ADTRegistryKey -LiteralPath $Key
    if (-not $valores) { return $null }
    foreach ($p in $valores.PSObject.Properties)
    {
        if ([string]$p.Value -like "$ChromeExtensionId*") { return $p.Name }
    }
    return $null
}

function Get-FirefoxExtensionSettings
{
    # Politica ExtensionSettings de Firefox (JSON) como objeto; vacio si no existe. $null si no es JSON valido.
    $actual = @(Get-ADTRegistryKey -LiteralPath $FirefoxPolicyKey -Name 'ExtensionSettings') -join "`n"
    if ([string]::IsNullOrWhiteSpace($actual)) { return New-Object -TypeName PSObject }
    try { return ($actual | ConvertFrom-Json) } catch { return $null }
}

function Install-BrowserExtensions
{
    Show-ADTInstallationProgress -StatusMessage 'Configurando la extension de Firma Digital en Chrome, Edge y Firefox...'

    # Chrome y Edge: lista de extensiones forzadas. Se agrega en el primer numero libre sin tocar otras entradas.
    foreach ($f in $ForcelistKeys)
    {
        $nombre = Get-ForcelistEntryName -Key $f.Key
        if ($nombre)
        {
            Write-ADTLogEntry -Message "$($f.Browser): la extension ya esta forzada ($($f.Key)\$nombre)."
            continue
        }
        $usados = @()
        $valores = Get-ADTRegistryKey -LiteralPath $f.Key
        if ($valores) { $usados = @($valores.PSObject.Properties.Name) }
        $n = 1
        while ($usados -contains [string]$n) { $n++ }
        Set-ADTRegistryKey -LiteralPath $f.Key -Name ([string]$n) -Value "$ChromeExtensionId;$ChromeUpdateUrl" -Type String

        if (-not (Get-ForcelistEntryName -Key $f.Key))
        {
            Write-ADTLogEntry -Message "$($f.Browser): no se pudo forzar la extension en $($f.Key)." -Severity 3
            Close-ADTSession -ExitCode 69011
        }
        Write-ADTLogEntry -Message "$($f.Browser): extension $ChromeExtensionId forzada ($($f.Key)\$n)."
    }

    # Firefox: politica ExtensionSettings (JSON). Se agrega o corrige solo la entrada de la extension.
    $settings = Get-FirefoxExtensionSettings
    if ($null -eq $settings)
    {
        Write-ADTLogEntry -Message "Firefox: ExtensionSettings en $FirefoxPolicyKey no es JSON valido; no se modifica." -Severity 3
        Close-ADTSession -ExitCode 69011
    }
    $entrada = $settings.PSObject.Properties[$FirefoxExtensionId]
    if ($entrada -and $entrada.Value.installation_mode -eq 'force_installed' -and $entrada.Value.install_url -eq $FirefoxInstallUrl)
    {
        Write-ADTLogEntry -Message "Firefox: la extension $FirefoxExtensionId ya esta forzada."
        return
    }
    $settings | Add-Member -NotePropertyName $FirefoxExtensionId -NotePropertyValue ([pscustomobject]@{ installation_mode = 'force_installed'; install_url = $FirefoxInstallUrl }) -Force
    Set-ADTRegistryKey -LiteralPath $FirefoxPolicyKey -Name 'ExtensionSettings' -Value ($settings | ConvertTo-Json -Depth 10 -Compress) -Type String

    $verificado = Get-FirefoxExtensionSettings
    if (-not $verificado -or $verificado.PSObject.Properties[$FirefoxExtensionId].Value.installation_mode -ne 'force_installed')
    {
        Write-ADTLogEntry -Message "Firefox: no se pudo forzar la extension en $FirefoxPolicyKey." -Severity 3
        Close-ADTSession -ExitCode 69011
    }
    Write-ADTLogEntry -Message "Firefox: extension $FirefoxExtensionId forzada ($FirefoxPolicyKey\ExtensionSettings)."
}

function Remove-BrowserExtensions
{
    # Quita solo las entradas de la extension de Firma Digital; las de otras extensiones quedan.
    foreach ($f in $ForcelistKeys)
    {
        $nombre = Get-ForcelistEntryName -Key $f.Key
        if ($nombre)
        {
            Remove-ADTRegistryKey -LiteralPath $f.Key -Name $nombre
            Write-ADTLogEntry -Message "$($f.Browser): extension quitada de la lista forzada ($($f.Key)\$nombre)."
        }
    }

    $settings = Get-FirefoxExtensionSettings
    if ($settings -and $settings.PSObject.Properties[$FirefoxExtensionId])
    {
        $settings.PSObject.Properties.Remove($FirefoxExtensionId)
        if (@($settings.PSObject.Properties).Count -eq 0)
        {
            Remove-ADTRegistryKey -LiteralPath $FirefoxPolicyKey -Name 'ExtensionSettings'
        }
        else
        {
            Set-ADTRegistryKey -LiteralPath $FirefoxPolicyKey -Name 'ExtensionSettings' -Value ($settings | ConvertTo-Json -Depth 10 -Compress) -Type String
        }
        Write-ADTLogEntry -Message "Firefox: extension $FirefoxExtensionId quitada de ExtensionSettings."
    }
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

    Write-ADTLogEntry -Message "Variante $($Variante.Nombre) $($Variante.Version) - componentes: $($Variante.Componentes -join ', ')."

    ## Cerrar el host del token sin preguntar: si esta en uso traba la desinstalacion.
    Show-ADTInstallationWelcome -CloseProcesses @{ Name = 'tokensign'; Description = 'Firma Digital (tokensign)' } -Silent -CheckDiskSpace

    Show-ADTInstallationProgress -StatusMessage 'Desinstalando versiones anteriores de Firma Digital...'
    Uninstall-PreviousApps


    ##================================================
    ## MARK: Install
    ##================================================
    $adtSession.InstallPhase = $adtSession.DeploymentType

    ## Dependencias del firmador segun la variante: Java 8 (solo si falta), certificados de las AC y
    ## drivers de token (los que falten).
    if ($Variante.Componentes -contains 'Java8') { Install-Java8 }
    if ($Variante.Componentes -contains 'CertificadosAC') { Install-RootCertificates }
    if ($Variante.Componentes -contains 'DriversToken') { Install-TokenDrivers }

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

    Show-ADTInstallationProgress -StatusMessage 'Registrando Firma Digital en Chrome, Edge y Firefox...'
    Register-NmhHost
    if ($Variante.Componentes -contains 'Extensiones') { Install-BrowserExtensions }
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

    Remove-BrowserExtensions
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
