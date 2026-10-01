<#
.SYNOPSIS
    Reemplaza el paquete de Firma Digital (token-service): desinstala toda version
    previa detectada e instala el MSI que viene junto a este script. Reinicia al final.

.DESCRIPTION
    Pensado para despliegue masivo (GPO / SCCM / Intune / psexec) en Windows 10/11.
    - Se autoeleva por UAC si se ejecuta sin privilegios de administrador.
    - No usa Win32_Product (dispara reparaciones MSI).
    - Detecta por registro en HKLM (vistas 64 y 32) y HKCU.
    - Log verboso en C:\Windows\Logs\Software\

.PARAMETER MsiPath
    Ruta al MSI. Por defecto busca token-service_v4.msi junto al script, o en .\Files\.

.PARAMETER DisplayNamePattern
    Regex contra DisplayName de "Programas y caracteristicas" para decidir que desinstalar.

.PARAMETER DryRun
    Solo detecta y reporta. No desinstala, no instala, no reinicia.

.PARAMETER NoReboot
    Hace todo el trabajo pero no reinicia el equipo.

.PARAMETER RebootDelay
    Segundos antes del reinicio. Por defecto 60.

.EXAMPLE
    .\Deploy-TokenService.ps1 -DryRun
    .\Deploy-TokenService.ps1
    .\Deploy-TokenService.ps1 -NoReboot
#>
[CmdletBinding()]
param(
    [string] $MsiPath,
    [string] $DisplayNamePattern = 'Firma Digital|tokensign|token.?service',
    [switch] $DryRun,
    [switch] $NoReboot,
    [int]    $RebootDelay = 60,
    [string] $LogDir      = "$env:SystemRoot\Logs\Software",
    [switch] $Elevated
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# ---------------------------------------------------------------- codigos de salida
$EXIT_OK              = 0
$EXIT_REBOOT_REQUIRED = 3010
$EXIT_MSI_NO_ENCONTRADO = 69001
$EXIT_FALLO_DESINSTALACION = 69002
$EXIT_FALLO_INSTALACION    = 69003
$EXIT_SIN_PRIVILEGIOS      = 69004
$EXIT_FALLO_REGISTRO       = 69005

# ---------------------------------------------------------------- native messaging host
# El MSI registra el host en HKCU (Root=1), asi que solo vale para el usuario que corre
# el instalador: en contexto SYSTEM las claves caen en el hive de SYSTEM y la firma no
# funciona para nadie. Se replican en HKLM, que Chrome y Firefox tambien leen, para que
# valgan en todo el equipo sin depender de quien instalo ni de un logon script.
$NmhCarpeta = 'GCBA Firma Digital'
$NmhEntradas = @(
    @{ Navegador = 'Chrome';  Key = 'SOFTWARE\Google\Chrome\NativeMessagingHosts\gcbatoken'; Json = 'cnmtoken.json' }
    @{ Navegador = 'Firefox'; Key = 'SOFTWARE\Mozilla\NativeMessagingHosts\gcbatoken';        Json = 'main.json'     }
)

# ---------------------------------------------------------------- rutas del script
$script:ScriptPath = $PSCommandPath
$script:ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# ---------------------------------------------------------------- logging
$script:LogFile      = $null
$script:LogDirActual = $LogDir

function Initialize-Log {
    # Sin privilegios no se puede escribir en C:\Windows\Logs. Ojo: el directorio
    # puede existir y NO ser escribible, asi que hay que probar la escritura real.
    $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
    $equipo  = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'PC' }
    $nombre  = 'TokenService-Deploy_{0}_{1}.log' -f $equipo, $stamp

    foreach ($dir in @($LogDir, [System.IO.Path]::GetTempPath())) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        try {
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            $destino = Join-Path $dir $nombre
            [System.IO.File]::AppendAllText($destino, '')   # prueba de escritura
            $script:LogDirActual = $dir
            $script:LogFile      = $destino
            return
        } catch {
            continue
        }
    }
    # Ultimo recurso: seguir adelante logueando solo por consola.
    $script:LogFile = $null
}

function Write-Log {
    param(
        [Parameter(Mandatory)] [string] $Message,
        [ValidateSet('INFO','WARN','ERROR')] [string] $Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line }
    }
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
    }
}

# ---------------------------------------------------------------- privilegios
function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-Elevation {
    # Relanza el script con -Verb RunAs conservando los parametros originales.
    if ([string]::IsNullOrWhiteSpace($script:ScriptPath)) {
        throw 'No se puede autoelevar: ejecutar el script con -File, no dot-sourced.'
    }
    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy','Bypass'
        '-File', ('"{0}"' -f $script:ScriptPath)
        '-Elevated'
    )
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Key -eq 'Elevated') { continue }
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { $argList += ('-{0}' -f $kv.Key) }
        } else {
            $argList += ('-{0}' -f $kv.Key)
            $argList += ('"{0}"' -f $kv.Value)
        }
    }
    Write-Log "Sin privilegios de administrador. Solicitando elevacion (UAC)..." 'WARN'
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $proc  = Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs -Wait -PassThru
    exit $proc.ExitCode
}

# ---------------------------------------------------------------- deteccion
function Get-MatchedField {
    <#
        Decide si una entrada de appwiz.cpl corresponde al producto buscado.
        No alcanza con DisplayName: un paquete puede figurar con otro nombre y
        delatarse por la carpeta donde se instalo o por su comando de desinstalacion.
        Devuelve el nombre del campo que coincidio, o $null si no coincide ninguno.
    #>
    param(
        [Parameter(Mandatory)] [string] $Pattern,
        [string] $DisplayName,
        [string] $InstallLocation,
        [string] $UninstallString,
        [string] $DisplayIcon
    )
    $campos = [ordered]@{
        DisplayName     = $DisplayName
        InstallLocation = $InstallLocation
        DisplayIcon     = $DisplayIcon
        UninstallString = $UninstallString
    }
    foreach ($campo in $campos.Keys) {
        if ($campos[$campo] -and $campos[$campo] -match $Pattern) { return $campo }
    }
    return $null
}

function Get-InstalledMatch {
    param([Parameter(Mandatory)] [string] $Pattern)

    $found = @()
    $scopes = @(
        @{ Hive = 'LocalMachine'; View = 'Registry64'; Tag = 'HKLM:64' }
        @{ Hive = 'LocalMachine'; View = 'Registry32'; Tag = 'HKLM:32' }
        @{ Hive = 'CurrentUser';  View = 'Default';    Tag = 'HKCU'    }
    )

    foreach ($scope in $scopes) {
        $base = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]$scope.Hive,
                [Microsoft.Win32.RegistryView]$scope.View)
        } catch {
            continue
        }

        try {
            $uninstall = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if (-not $uninstall) { continue }

            foreach ($name in $uninstall.GetSubKeyNames()) {
                $key = $uninstall.OpenSubKey($name)
                if (-not $key) { continue }
                try {
                    $displayName = [string]$key.GetValue('DisplayName')
                    if (-not $displayName) { continue }
                    # Ignorar parches y actualizaciones, solo productos
                    if ($key.GetValue('SystemComponent') -eq 1) { continue }

                    $installLocation = [string]$key.GetValue('InstallLocation')
                    $uninstallString = [string]$key.GetValue('UninstallString')
                    $displayIcon     = [string]$key.GetValue('DisplayIcon')

                    $matchedOn = Get-MatchedField -Pattern $Pattern -DisplayName $displayName `
                        -InstallLocation $installLocation -UninstallString $uninstallString `
                        -DisplayIcon $displayIcon
                    if (-not $matchedOn) { continue }

                    $isGuid = $name -match '^\{[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}$'
                    $found += [pscustomobject]@{
                        DisplayName     = $displayName
                        DisplayVersion  = [string]$key.GetValue('DisplayVersion')
                        Publisher       = [string]$key.GetValue('Publisher')
                        ProductCode     = $(if ($isGuid) { $name } else { $null })
                        UninstallString = $uninstallString
                        InstallLocation = $installLocation
                        MatchedOn       = $matchedOn
                        Scope           = $scope.Tag
                    }
                } finally {
                    $key.Close()
                }
            }
            $uninstall.Close()
        } finally {
            $base.Close()
        }
    }

    # Un mismo producto aparece en HKLM:64 y HKLM:32; quedarse con una sola entrada.
    $unique = @()
    $seen   = @{}
    foreach ($item in $found) {
        $id = if ($item.ProductCode) { $item.ProductCode } else { "$($item.DisplayName)|$($item.DisplayVersion)" }
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $unique += $item
    }
    return ,$unique
}

# ---------------------------------------------------------------- msiexec
function Invoke-MsiExec {
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string]   $Etiqueta
    )
    $msiexec = Join-Path $env:SystemRoot 'System32\msiexec.exe'
    Write-Log ("Ejecutando: msiexec.exe {0}" -f ($Arguments -join ' '))
    $proc = Start-Process -FilePath $msiexec -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    $code = $proc.ExitCode
    Write-Log ("{0} -> codigo de salida {1} ({2})" -f $Etiqueta, $code, (Get-MsiExitDescription $code))
    return $code
}

function Get-MsiExitDescription {
    param([int] $Code)
    switch ($Code) {
        0     { 'OK' }
        1605  { 'El producto no esta instalado (nada que hacer)' }
        1618  { 'Otra instalacion en curso' }
        1619  { 'No se pudo abrir el paquete MSI' }
        1641  { 'OK, el instalador inicio el reinicio' }
        3010  { 'OK, requiere reinicio' }
        default { 'Ver documentacion de Windows Installer' }
    }
}

function Test-MsiSuccess {
    param([int] $Code)
    return ($Code -eq 0 -or $Code -eq 1605 -or $Code -eq 1641 -or $Code -eq 3010)
}

# ---------------------------------------------------------------- resolucion del MSI
function Resolve-MsiPath {
    param(
        [string] $Provided,
        [string] $ScriptRoot = $script:ScriptRoot
    )

    if ($Provided) {
        if (-not (Test-Path -LiteralPath $Provided -PathType Leaf)) {
            throw "No existe el MSI indicado: $Provided"
        }
        return (Resolve-Path -LiteralPath $Provided).Path
    }

    $root = $ScriptRoot
    $candidatos = @(
        (Join-Path $root 'token-service_v4.msi')
        (Join-Path $root 'Files\token-service_v4.msi')
    )
    foreach ($c in $candidatos) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return (Resolve-Path -LiteralPath $c).Path }
    }
    # Ultimo recurso: cualquier .msi junto al script o en Files\
    foreach ($dir in @($root, (Join-Path $root 'Files'))) {
        if (Test-Path -LiteralPath $dir) {
            $msi = Get-ChildItem -LiteralPath $dir -Filter '*.msi' -File -ErrorAction SilentlyContinue |
                   Select-Object -First 1
            if ($msi) { return $msi.FullName }
        }
    }
    throw "No se encontro ningun .msi junto al script ni en .\Files\"
}

# ---------------------------------------------------------------- native messaging host
function Resolve-InstallDirectory {
    param([object[]] $Instalado)

    # 1) Lo que haya declarado el propio MSI.
    foreach ($app in $Instalado) {
        if ($app.InstallLocation -and (Test-Path -LiteralPath $app.InstallLocation)) {
            return $app.InstallLocation.TrimEnd('\')
        }
    }
    # 2) Sondeo. El MSI es de 32 bits, asi que en Windows x64 ProgramFilesFolder
    #    resuelve a "Program Files (x86)", no a "Program Files".
    $raices = @(${env:ProgramFiles(x86)}, $env:ProgramFiles) | Where-Object { $_ }
    foreach ($raiz in $raices) {
        $candidata = Join-Path $raiz $NmhCarpeta
        if (Test-Path -LiteralPath (Join-Path $candidata 'main.json')) { return $candidata }
    }
    return $null
}

function Register-NativeMessagingHost {
    param([Parameter(Mandatory)] [string] $InstallDir)

    $escritas = 0
    foreach ($entrada in $NmhEntradas) {
        $json = Join-Path $InstallDir $entrada.Json
        if (-not (Test-Path -LiteralPath $json)) {
            Write-Log ("No existe {0}; no se registra el host de {1}." -f $json, $entrada.Navegador) 'WARN'
            continue
        }
        # Las dos vistas: un navegador de 64 bits lee SOFTWARE\, uno de 32 lee WOW6432Node\.
        foreach ($view in @('Registry64', 'Registry32')) {
            $base = $null
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                    [Microsoft.Win32.RegistryHive]::LocalMachine,
                    [Microsoft.Win32.RegistryView]$view)
                $sub = $base.CreateSubKey($entrada.Key)
                $sub.SetValue('', $json, [Microsoft.Win32.RegistryValueKind]::String)
                $sub.Close()
                Write-Log ("  HKLM\{0} [{1}] = {2}" -f $entrada.Key, $view, $json)
                $escritas++
            } catch {
                Write-Log ("  No se pudo escribir HKLM\{0} [{1}]: {2}" -f $entrada.Key, $view, $_.Exception.Message) 'WARN'
            } finally {
                if ($base) { $base.Close() }
            }
        }
    }
    return $escritas
}

function Test-NativeMessagingHost {
    param([Parameter(Mandatory)] [string] $InstallDir)

    $ok = $true
    foreach ($entrada in $NmhEntradas) {
        $esperado = Join-Path $InstallDir $entrada.Json
        $leido = $null
        foreach ($view in @('Registry64', 'Registry32')) {
            $base = $null
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                    [Microsoft.Win32.RegistryHive]::LocalMachine,
                    [Microsoft.Win32.RegistryView]$view)
                $sub = $base.OpenSubKey($entrada.Key)
                if ($sub) { $leido = [string]$sub.GetValue(''); $sub.Close() }
            } catch {
            } finally {
                if ($base) { $base.Close() }
            }
            if ($leido) { break }
        }
        if ($leido -eq $esperado -and (Test-Path -LiteralPath $esperado)) {
            Write-Log ("  {0}: OK -> {1}" -f $entrada.Navegador, $leido)
        } else {
            Write-Log ("  {0}: registro HKLM incorrecto o faltante (leido: '{1}')" -f $entrada.Navegador, $leido) 'ERROR'
            $ok = $false
        }
    }
    return $ok
}

# ================================================================== MAIN
$exitCode = $EXIT_OK
try {
    Initialize-Log
    Write-Log '============================================================'
    Write-Log 'Despliegue Token Service / Firma Digital'
    Write-Log ("Equipo: {0}   Usuario: {1}\{2}" -f $env:COMPUTERNAME, $env:USERDOMAIN, $env:USERNAME)
    Write-Log ("PowerShell {0}   64-bit: {1}" -f $PSVersionTable.PSVersion, [Environment]::Is64BitProcess)
    Write-Log ("Log: {0}" -f $script:LogFile)
    Write-Log '============================================================'

    if (-not (Test-Administrator)) {
        if ($Elevated) {
            Write-Log 'La elevacion no otorgo privilegios de administrador. Abortando.' 'ERROR'
            exit $EXIT_SIN_PRIVILEGIOS
        }
        Request-Elevation
    }
    Write-Log 'Privilegios de administrador: OK'

    try {
        $msi = Resolve-MsiPath -Provided $MsiPath
    } catch {
        Write-Log $_.Exception.Message 'ERROR'
        exit $EXIT_MSI_NO_ENCONTRADO
    }
    Write-Log ("MSI a instalar: {0}" -f $msi)

    # Quitar la marca "archivo descargado de internet" que puede bloquear la ejecucion.
    try { Unblock-File -LiteralPath $msi -ErrorAction SilentlyContinue } catch { }

    # ---------- 1. Deteccion
    Write-Log '--- Fase 1: deteccion de versiones instaladas ---'
    $instalados = Get-InstalledMatch -Pattern $DisplayNamePattern

    if ($instalados.Count -eq 0) {
        Write-Log 'No se detecto ninguna version previa instalada.'
    } else {
        Write-Log ("Se detectaron {0} entrada(s):" -f $instalados.Count)
        foreach ($app in $instalados) {
            Write-Log ("  - {0} | version {1} | {2} | {3}" -f `
                $app.DisplayName, $app.DisplayVersion, $app.ProductCode, $app.Scope)
            # Por que matcheo: imprescindible para auditar un -DryRun antes de desinstalar.
            $detalle = switch ($app.MatchedOn) {
                'DisplayName'     { $app.DisplayName }
                'InstallLocation' { $app.InstallLocation }
                'UninstallString' { $app.UninstallString }
                default           { '' }
            }
            Write-Log ("      coincide por {0}: {1}" -f $app.MatchedOn, $detalle)
        }
    }

    if ($DryRun) {
        Write-Log 'Modo -DryRun: no se desinstala, no se instala y no se reinicia.' 'WARN'
        exit $EXIT_OK
    }

    # ---------- 2. Desinstalacion
    Write-Log '--- Fase 2: desinstalacion de versiones previas ---'
    foreach ($app in $instalados) {
        if (-not $app.ProductCode) {
            Write-Log ("'{0}' no tiene ProductCode MSI; se omite (desinstalar a mano si corresponde)." -f $app.DisplayName) 'WARN'
            continue
        }
        $logU = Join-Path $script:LogDirActual ("TokenService-Uninstall_{0}.log" -f $app.ProductCode.Trim('{','}'))
        $code = Invoke-MsiExec -Etiqueta ("Desinstalacion de '{0}'" -f $app.DisplayName) -Arguments @(
            '/x', $app.ProductCode, '/qn', '/norestart', '/l*v', ('"{0}"' -f $logU)
        )
        if (-not (Test-MsiSuccess $code)) {
            Write-Log ("Fallo la desinstalacion de '{0}'." -f $app.DisplayName) 'ERROR'
            exit $EXIT_FALLO_DESINSTALACION
        }
        if ($code -eq 3010 -or $code -eq 1641) { $exitCode = $EXIT_REBOOT_REQUIRED }
    }

    # Verificacion: no debe quedar nada
    $restantes = Get-InstalledMatch -Pattern $DisplayNamePattern
    $restantesMsi = @($restantes | Where-Object { $_.ProductCode })
    if ($restantesMsi.Count -gt 0) {
        foreach ($r in $restantesMsi) {
            Write-Log ("Quedo instalado tras desinstalar: {0} ({1})" -f $r.DisplayName, $r.ProductCode) 'ERROR'
        }
        exit $EXIT_FALLO_DESINSTALACION
    }
    Write-Log 'Desinstalacion verificada: no quedan entradas MSI coincidentes.'

    # ---------- 3. Instalacion
    Write-Log '--- Fase 3: instalacion de la version nueva ---'
    $logI = Join-Path $script:LogDirActual ("TokenService-Install_{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $code = Invoke-MsiExec -Etiqueta 'Instalacion' -Arguments @(
        '/i', ('"{0}"' -f $msi), '/qn', '/norestart', 'ALLUSERS=1', 'REBOOT=ReallySuppress',
        '/l*v', ('"{0}"' -f $logI)
    )
    if (-not (Test-MsiSuccess $code) -or $code -eq 1605) {
        Write-Log 'Fallo la instalacion.' 'ERROR'
        exit $EXIT_FALLO_INSTALACION
    }
    if ($code -eq 3010 -or $code -eq 1641) { $exitCode = $EXIT_REBOOT_REQUIRED }

    # ---------- 4. Verificacion post-instalacion
    Write-Log '--- Fase 4: verificacion ---'
    $final = Get-InstalledMatch -Pattern $DisplayNamePattern
    if ($final.Count -eq 0) {
        Write-Log 'La instalacion reporto exito pero no aparece en el registro de desinstalacion.' 'ERROR'
        exit $EXIT_FALLO_INSTALACION
    }
    foreach ($app in $final) {
        Write-Log ("  OK -> {0} | version {1} | {2}" -f $app.DisplayName, $app.DisplayVersion, $app.Scope)
    }
    if ($final.Count -gt 1) {
        Write-Log 'Hay mas de una entrada en appwiz.cpl. Revisar el patron de deteccion.' 'WARN'
    }

    # ---------- 5. Registro del native messaging host en HKLM
    # Sin esto la instalacion "funciona" pero la firma no anda para el usuario.
    Write-Log '--- Fase 5: registro del host de mensajeria nativa en HKLM ---'
    $installDir = Resolve-InstallDirectory -Instalado $final
    if (-not $installDir) {
        Write-Log 'No se pudo determinar la carpeta de instalacion; no se puede registrar el host.' 'ERROR'
        exit $EXIT_FALLO_REGISTRO
    }
    Write-Log ("Carpeta de instalacion: {0}" -f $installDir)

    $escritas = Register-NativeMessagingHost -InstallDir $installDir
    if ($escritas -eq 0) {
        Write-Log 'No se escribio ninguna clave de mensajeria nativa.' 'ERROR'
        exit $EXIT_FALLO_REGISTRO
    }
    if (-not (Test-NativeMessagingHost -InstallDir $installDir)) {
        Write-Log 'La verificacion del host de mensajeria nativa fallo.' 'ERROR'
        exit $EXIT_FALLO_REGISTRO
    }
    Write-Log 'Host de mensajeria nativa registrado y verificado en HKLM para todos los usuarios.'

    Write-Log ("Despliegue completado. Codigo de salida: {0}" -f $exitCode)

    # ---------- 6. Reinicio
    if ($NoReboot) {
        Write-Log 'Modo -NoReboot: el equipo NO se reinicia.' 'WARN'
    } else {
        Write-Log ("Reiniciando el equipo en {0} segundos. Cancelar con: shutdown /a" -f $RebootDelay) 'WARN'
        $msg = 'Actualizacion de Firma Digital completada. El equipo se reiniciara.'
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\shutdown.exe') `
                      -ArgumentList @('/r','/t', $RebootDelay, '/f', '/c', ('"{0}"' -f $msg)) `
                      -WindowStyle Hidden | Out-Null
    }
}
catch {
    Write-Log ("ERROR NO CONTROLADO: {0}" -f $_.Exception.Message) 'ERROR'
    Write-Log ($_.ScriptStackTrace) 'ERROR'
    $exitCode = $EXIT_FALLO_INSTALACION
}

exit $exitCode
