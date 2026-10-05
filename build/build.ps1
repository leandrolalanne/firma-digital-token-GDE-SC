<#
.SYNOPSIS
    Genera el instalador de la version en dist\firma-digital-token-GDE-SC-<version>.exe.

.DESCRIPTION
    El instalador publicado es la variante 'extensiones' (instalacion completa). Las variantes son capas
    acumulativas, una por version en la que se agrego cada componente: basico (1.0.0, token), java (2.0.0,
    Java 8 y certificados), tokens (3.0.0, drivers), extensiones (4.0.0, extensiones de los navegadores).
    Con -Variantes se puede generar otra capa para uso interno: dist\firma-digital-token-GDE-SC-<version>-<capa>.exe.

    Por cada variante (variantes\<nombre>\variante.psd1; Base indica de cual hereda):
      1. copia el paquete PSADT comun (src\paquete) a dist\paquetes\<Nombre>\
      2. agrega a Files\ solo los instaladores de la variante y de sus bases (desde instaladores\)
      3. escribe SupportFiles\Variante.psd1 (Nombre, Version, Componentes) y copia src\Lanzar.ps1
      4. lo comprime con 7-Zip y lo pega a build\7zSD.sfx con un manifiesto requireAdministrator
      5. verifica el .exe con 7z t
    dist\paquetes\<Nombre>\ queda listo para GPO/Intune/SCCM (Invoke-AppDeployToolkit.exe, modo Silent).
    Sale con codigo 1 si alguna variante no se genera.
    El numero de version (SemVer) sale del tag del release (v4.0.0 -> 4.0.0) y queda como AppScriptVersion.

    - 7zSD.sfx sale del LZMA SDK 23.01 de 7-zip.org (dominio publico). No trae manifiesto, asi que se
      le incrusta uno con requireAdministrator: sin eso el .exe correria sin privilegios y PSADT cortaria.
    - Config del SFX: Directory="" es obligatorio; por defecto el SFX antepone ".\" a RunProgram y busca
      powershell.exe dentro de la carpeta extraida ("El sistema no puede encontrar el archivo").
    - Requiere Windows PowerShell 5.1 y 7-Zip. Los .exe salen SIN FIRMAR.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build\build.ps1 -Version 4.0.0

.EXAMPLE
    .\build\build.ps1 -Version v4.0.0 -Variantes basico
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Version,

    [string[]] $Variantes = @('extensiones'),

    [string] $SevenZip = "$env:ProgramFiles\7-Zip\7z.exe"
)

$ErrorActionPreference = 'Stop'
$Programa = 'firma-digital-token-GDE-SC'
$VariantePublicada = 'extensiones'

# Con "powershell -File" una lista llega como un solo texto ("basico,java"): se separa por comas.
$Variantes = @($Variantes | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# Acepta el tag tal cual (v1.2.3) o el numero solo (1.2.3).
$Version = $Version.TrimStart('v')
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version invalida: '$Version' (se espera 1.2.3 o v1.2.3)." }

$raiz         = Split-Path -Parent $PSScriptRoot
$dist         = Join-Path $raiz 'dist'
$instaladores = Join-Path $raiz 'instaladores'
foreach ($f in @($SevenZip, (Join-Path $PSScriptRoot '7zSD.sfx'), (Join-Path $raiz 'src\Lanzar.ps1'), (Join-Path $raiz 'src\paquete\Invoke-AppDeployToolkit.exe'))) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "Falta: $f" }
}

# ---------------------------------------------------------------- variantes
function Get-Variante {
    # Devuelve la variante con los componentes y archivos de toda su cadena de bases (base primero).
    param([string] $Nombre, [int] $Profundidad = 0)
    if ($Profundidad -gt 5) { throw "Herencia de variantes demasiado profunda o circular en '$Nombre'." }
    $path = Join-Path $raiz "variantes\$Nombre\variante.psd1"
    if (-not (Test-Path -LiteralPath $path)) { throw "No existe la variante '$Nombre' ($path)." }
    $def = Import-PowerShellDataFile -LiteralPath $path

    $componentes = @(); $archivos = @()
    if ($def.Base) {
        $base = Get-Variante -Nombre $def.Base -Profundidad ($Profundidad + 1)
        $componentes += $base.Componentes
        $archivos    += $base.Archivos
    }
    $componentes += $def.Componentes
    $archivos    += $def.Archivos
    return @{ Clave = $Nombre; Nombre = $def.Nombre; Componentes = $componentes; Archivos = $archivos }
}

# ---------------------------------------------------------------- modulo SFX con manifiesto de administrador
function New-SfxModule {
    param([string] $Destino)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '7zSD.sfx') -Destination $Destino -Force
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
    [SfxResource]::SetManifest($Destino, [System.Text.Encoding]::UTF8.GetBytes($manifest))
}

# ---------------------------------------------------------------- una variante
function Build-Variante {
    param([hashtable] $V, [string] $Modulo, [string] $Tmp)

    # 1. Paquete PSADT comun
    $paquete = Join-Path $dist "paquetes\$($V.Nombre)"
    if (Test-Path -LiteralPath $paquete) { Remove-Item -LiteralPath $paquete -Recurse -Force }
    New-Item -ItemType Directory -Path (Split-Path $paquete) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $raiz 'src\paquete') -Destination $paquete -Recurse

    # 2. Instaladores de la variante
    foreach ($a in $V.Archivos) {
        $origen = Join-Path $instaladores $a.Origen
        if (-not (Test-Path -LiteralPath $origen -PathType Leaf)) { throw "Falta el instalador: instaladores\$($a.Origen)" }
        $destino = Join-Path $paquete "Files\$($a.Destino)"
        New-Item -ItemType Directory -Path (Split-Path $destino) -Force | Out-Null
        Copy-Item -LiteralPath $origen -Destination $destino
    }

    # 3. Variante, version y lanzador
    New-Item -ItemType Directory -Path (Join-Path $paquete 'SupportFiles') -Force | Out-Null
    $componentes = ($V.Componentes | ForEach-Object { "'$_'" }) -join ', '
    $variantePsd1 = "@{`r`n    Nombre      = '$($V.Nombre)'`r`n    Version     = '$Version'`r`n    Componentes = @($componentes)`r`n}`r`n"
    [System.IO.File]::WriteAllText((Join-Path $paquete 'SupportFiles\Variante.psd1'), $variantePsd1, [System.Text.Encoding]::ASCII)
    Copy-Item -LiteralPath (Join-Path $raiz 'src\Lanzar.ps1') -Destination $paquete

    # 4. Comprimir y ensamblar: modulo SFX + config + archivo 7z
    $payload = Join-Path $Tmp "$($V.Nombre).7z"
    & $SevenZip a -t7z -mx=5 $payload (Join-Path $paquete '*') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z.exe fallo con codigo $LASTEXITCODE al comprimir." }

    $config = ";!@Install@!UTF-8!`r`nTitle=`"Firma Digital con Token GDE $Version`"`r`nDirectory=`"`"`r`n" +
              "RunProgram=`"powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File Lanzar.ps1`"`r`n;!@InstallEnd@!`r`n"
    # El instalador publicado lleva solo programa y version; las otras capas, ademas, su nombre.
    $archivo = if ($V.Clave -eq $VariantePublicada) { '{0}-{1}.exe' -f $Programa, $Version } else { '{0}-{1}-{2}.exe' -f $Programa, $Version, $V.Clave }
    $exe = Join-Path $dist $archivo
    $out = [System.IO.File]::Create($exe)
    try {
        foreach ($parte in @([System.IO.File]::ReadAllBytes($Modulo), (New-Object System.Text.UTF8Encoding $false).GetBytes($config), [System.IO.File]::ReadAllBytes($payload))) {
            $out.Write($parte, 0, $parte.Length)
        }
    } finally {
        $out.Dispose()
    }

    # 5. Verificacion del archivo generado
    & $SevenZip t $exe | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z t fallo con codigo ${LASTEXITCODE}; el .exe generado esta danado." }
    return $exe
}

# ---------------------------------------------------------------- main
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("$Programa-build-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$resultados = @()
try {
    $modulo = Join-Path $tmp '7zSD-admin.sfx'
    New-SfxModule -Destino $modulo

    foreach ($nombre in $Variantes) {
        try {
            $v = Get-Variante -Nombre $nombre
            Write-Host ("[{0}] componentes: {1}" -f $v.Nombre, ($v.Componentes -join ', '))
            $exe = Build-Variante -V $v -Modulo $modulo -Tmp $tmp
            $resultados += [pscustomobject]@{ Variante = $v.Nombre; Estado = 'OK'; MB = [math]::Round((Get-Item -LiteralPath $exe).Length / 1MB, 1); Archivo = (Split-Path $exe -Leaf) }
        } catch {
            $resultados += [pscustomobject]@{ Variante = $nombre; Estado = 'ERROR'; MB = $null; Archivo = $_.Exception.Message }
        }
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$resultados | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
if (@($resultados | Where-Object Estado -ne 'OK').Count -gt 0) {
    Write-Host 'Build con errores.'
    exit 1
}
Write-Host ("Build OK: {0} instaladores en {1}" -f $resultados.Count, $dist)
exit 0
