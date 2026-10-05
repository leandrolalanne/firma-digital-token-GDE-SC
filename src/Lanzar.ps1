<#
    Punto de entrada del autoextraible FirmaDigital-Instalador.exe.
    El .exe ya corre elevado (manifiesto requireAdministrator) y extrae el paquete PSADT
    a una carpeta temporal; este script lanza el despliegue con interfaz y espera.

    Por que se espera a los procesos PSADT.ClientServer.*: la ventana de reinicio (y la de
    error) corren desde la carpeta temporal y en segundo plano. Si este script terminara
    antes, el SFX borraria la carpeta y la ventana podria caerse sin reiniciar.
#>
$ErrorActionPreference = 'Stop'

try {
    $exe = Join-Path $PSScriptRoot 'Invoke-AppDeployToolkit.exe'
    $proc = Start-Process -FilePath $exe -ArgumentList '-DeploymentType Install -DeployMode Interactive' -Wait -PassThru
}
catch {
    # Esta consola corre oculta: sin este cartel una falla aca seria invisible para el usuario.
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show(
        "No se pudo iniciar el instalador de Firma Digital.`n`n$($_.Exception.Message)`n`n$exe",
        'Firma Digital - Instalador', 'OK', 'Error')
    exit 69006
}

Get-Process -Name 'PSADT.ClientServer.Client', 'PSADT.ClientServer.Client.Launcher' -ErrorAction SilentlyContinue |
    Wait-Process -ErrorAction SilentlyContinue

exit $proc.ExitCode
