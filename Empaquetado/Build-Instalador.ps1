<#
.SYNOPSIS
    Arma FirmaDigital-Instalador.exe: un unico autoextraible (7-Zip SFX) con el paquete PSADT
    de ..\Certificados y Lanzar.ps1. Al hacer doble clic pide UAC, extrae a %TEMP%, muestra
    el asistente PSADT (desinstala, instala Java 8 si falta, certificados de las AC, drivers de
    token que falten y el token, registra) y reinicia con cuenta regresiva.

.DESCRIPTION
    - 7zSD.sfx sale del LZMA SDK 23.01 de 7-zip.org (dominio publico). No trae manifiesto,
      asi que se le incrusta uno con requireAdministrator: sin eso el .exe correria sin
      privilegios y PSADT cortaria con "requires administrative permissions".
    - Requiere 7-Zip instalado (7z.exe) para comprimir el paquete.
    - El .exe sale SIN FIRMAR: SmartScreen va a pedir "Mas informacion > Ejecutar de todas formas".

.EXAMPLE
    .\Empaquetado\Build-Instalador.ps1
#>
[CmdletBinding()]
param(
    [string] $SevenZip   = "$env:ProgramFiles\7-Zip\7z.exe",
    [string] $OutputFile
)

$ErrorActionPreference = 'Stop'

# En PowerShell 5.1 $PSScriptRoot no esta disponible en los valores por defecto de param().
$raiz = Split-Path -Parent $PSScriptRoot
if (-not $OutputFile) { $OutputFile = Join-Path $raiz 'Salida\FirmaDigital-Instalador.exe' }

$paquete = Join-Path $raiz 'Certificados'
$sfx     = Join-Path $PSScriptRoot '7zSD.sfx'
$lanzar  = Join-Path $PSScriptRoot 'Lanzar.ps1'

$requeridos = @(
    $SevenZip, $sfx, $lanzar
    (Join-Path $paquete 'Invoke-AppDeployToolkit.exe')
    (Join-Path $paquete 'Files\token-service_v4.msi')
    (Join-Path $paquete 'Files\jre-8u503-windows-x64.exe')
    (Join-Path $paquete 'Files\Certificados AC Firma Digital Argentina.exe')
    (Join-Path $paquete 'Files\Drivers\sac-10.8-x64-10.8.msi')
    (Join-Path $paquete 'Files\Drivers\SITEPRO_ONE SEAT_End User License Certificate.txt')
    (Join-Path $paquete 'Files\Drivers\MSePass2003_Win_Spanish_V1.1.22.831.exe')
    (Join-Path $paquete 'Files\Drivers\MSCryptoID-FIPS140-3_Win_Spanish_V2.2.26.324.exe')
)
foreach ($f in $requeridos) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "Falta: $f" }
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('FirmaDigital-Build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    # ---------- 1. Contenido: paquete PSADT + lanzador en la raiz
    $staging = Join-Path $tmp 'staging'
    Copy-Item -LiteralPath $paquete -Destination $staging -Recurse
    Copy-Item -LiteralPath $lanzar -Destination $staging

    $payload = Join-Path $tmp 'payload.7z'
    & $SevenZip a -t7z -mx=5 $payload (Join-Path $staging '*') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z.exe fallo con codigo $LASTEXITCODE" }

    # ---------- 2. Modulo SFX con manifiesto requireAdministrator
    $modulo = Join-Path $tmp '7zSD-admin.sfx'
    Copy-Item -LiteralPath $sfx -Destination $modulo

    $manifest = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
</assembly>
'@
    if (-not ('SfxResource' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SfxResource {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr BeginUpdateResource(string pFileName, bool bDeleteExistingResources);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool UpdateResource(IntPtr hUpdate, IntPtr lpType, IntPtr lpName, ushort wLanguage, byte[] lpData, uint cb);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool EndUpdateResource(IntPtr hUpdate, bool fDiscard);

    public static void SetManifest(string file, byte[] data) {
        IntPtr h = BeginUpdateResource(file, false);
        if (h == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        // RT_MANIFEST = 24, id 1 = manifiesto de un .exe, idioma neutro.
        if (!UpdateResource(h, (IntPtr)24, (IntPtr)1, 0, data, (uint)data.Length)) {
            int err = Marshal.GetLastWin32Error();
            EndUpdateResource(h, true);
            throw new System.ComponentModel.Win32Exception(err);
        }
        if (!EndUpdateResource(h, false)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
}
'@
    }
    [SfxResource]::SetManifest($modulo, [System.Text.Encoding]::UTF8.GetBytes($manifest))

    # ---------- 3. Configuracion del SFX (UTF-8 sin BOM). Sin BeginPrompt: no pide clics.
    # Directory="" es obligatorio: por defecto el SFX antepone ".\" a RunProgram y busca
    # powershell.exe dentro de la carpeta extraida ("El sistema no puede encontrar el archivo").
    # Sin prefijo, CreateProcess lo busca en el sistema y en el PATH.
    $config = @'
;!@Install@!UTF-8!
Title="Firma Digital - Instalador"
Directory=""
RunProgram="powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File Lanzar.ps1"
;!@InstallEnd@!
'@
    $configBytes = (New-Object System.Text.UTF8Encoding $false).GetBytes(($config -replace "`r?`n", "`r`n"))

    # ---------- 4. Ensamblar: modulo SFX + config + archivo 7z
    $outDir = Split-Path -Parent $OutputFile
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
    $out = [System.IO.File]::Create($OutputFile)
    try {
        foreach ($parte in @([System.IO.File]::ReadAllBytes($modulo), $configBytes, [System.IO.File]::ReadAllBytes($payload))) {
            $out.Write($parte, 0, $parte.Length)
        }
    } finally {
        $out.Dispose()
    }

    $item = Get-Item -LiteralPath $OutputFile
    Write-Host ("OK: {0} ({1:N1} MB)" -f $item.FullName, ($item.Length / 1MB))
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
