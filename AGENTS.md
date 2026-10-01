# AGENTS.md

## Proyecto

Paquete de despliegue con **PSAppDeployToolkit v4 (PSADT)** que reemplaza el MSI de certificados en equipos Windows 10/11:
desinstala cualquier versión previa y luego instala la nueva, en modo silencioso, con log y códigos de salida estándar.

- Nombre del programa en `appwiz.cpl`: `GDE Firma Digital Service Firefox Catamarca`
  (versiones previas del parque pueden figurar como `GCBA Firma Digital`; por eso la
  detección es por regex `\bGDE\b|Firma\s*Digital` contra `DisplayName` e `InstallLocation`,
  solo paquetes MSI, y no por `UpgradeCode`, que en este MSI es el placeholder
  `{00000001-0001-0001-0001-000000000001}`)
- MSI actual: `token-service_v4.msi` — ProductCode `{B8A8BA6C-F8FA-4551-86C3-449375C60103}`, ProductVersion `2.0.0`, x86
- **v2** agrega las dependencias del firmador, ambas provistas por Modernización:
  - **Java 8 x64** (`jre-8u503-windows-x64.exe`, Oracle). Se instala solo si no hay un Java 1.8 registrado
    en `HKLM\SOFTWARE\JavaSoft` (vistas 64 y 32) con `bin\java.exe` presente. No se desinstalan otros Java.
    Tiene que ser Java 8: `tokensign.exe` es un wrapper Launch4j y el firmador usa
    `new SunPKCS11(InputStream)`, que no existe desde Java 9.
  - **Certificados de las AC** (`Certificados AC Firma Digital Argentina.exe`, Inno Setup oficial, sin firma):
    se corre siempre con `/VERYSILENT`; hace `certutil -addstore -enterprise` (2 raíz en Root, 20 en CA).
    Se verifican las dos AC Raíz por thumbprint en `Cert:\LocalMachine\Root`.
- Entregable principal: `Salida\FirmaDigital-Instalador.exe`, un único autoextraíble (7-Zip SFX)
  que se ejecuta con doble clic, pide UAC, muestra el asistente PSADT y reinicia con cuenta regresiva.
- También sirve para GPO / Intune / SCCM (500 equipos) usando la carpeta `Certificados/` en modo Silent.

## Estructura

```
Certificados/
├── Invoke-AppDeployToolkit.exe     # Lanzador. No modificar.
├── Invoke-AppDeployToolkit.ps1     # ÚNICO script de lógica a editar.
├── Files/                          # MSI del token, instalador de Java 8 y de certificados de las AC.
├── SupportFiles/                   # Archivos auxiliares (.cer, transforms .mst).
├── Config/                         # config.psd1 del toolkit.
├── Assets/, Strings/               # UI y textos. No tocar salvo pedido.
├── PSAppDeployToolkit/             # Módulo (v4.1.8). NUNCA modificar.
└── PSAppDeployToolkit.Extensions/  # Funciones propias, solo si hacen falta.
Empaquetado/
├── Build-Instalador.ps1            # Arma Salida\FirmaDigital-Instalador.exe.
├── Lanzar.ps1                      # Punto de entrada del .exe. Solo lanza y espera; sin lógica.
└── 7zSD.sfx                        # Módulo SFX del LZMA SDK 23.01 (7-zip.org). No modificar.
Salida/                             # Generado por el build. No editar a mano.
```

## Reglas

1. Toda la lógica va en `Invoke-AppDeployToolkit.ps1`, dentro de las fases existentes
   (Pre-Install, Install, Post-Install, Pre-Uninstall, Uninstall, Post-Uninstall, Repair).
2. Usar **solo funciones ADT** del módulo. No llamar `msiexec.exe` directo ni usar `Start-Process`.
   - Desinstalar versiones previas: `Uninstall-ADTApplication -FilterScript { $_.DisplayName -match '...' }`
   - Instalar MSI: `Start-ADTMsiProcess -Action Install -FilePath '<archivo>.msi'`
   - Consultar instalado: `Get-ADTApplication`
   - Logging: `Write-ADTLogEntry`
   - Rutas del paquete: `$adtSession.DirFiles`, `$adtSession.DirSupportFiles`
3. Prohibido `Win32_Product` / `Get-WmiObject Win32_Product` (dispara reparaciones MSI).
4. Compatible con **Windows PowerShell 5.1**. No usar sintaxis exclusiva de PowerShell 7.
5. Sin rutas absolutas a la máquina del desarrollador. Todo relativo al paquete.
6. Reinicio (pedido explícito): en modo Interactive, `Show-ADTInstallationRestartPrompt` con
   cuenta regresiva de 60 s que reinicia al llegar a cero. En modo Silent no se reinicia:
   se devuelve 3010 y el reinicio queda a cargo del sistema de despliegue.
7. Completar siempre `AppVendor`, `AppName`, `AppVersion`, `AppScriptDate` y `AppScriptAuthor` en `$adtSession`.
8. No agregar pasos, dependencias ni funciones que no se pidieron.

## Códigos de salida

| Código | Significado |
| --- | --- |
| 0 | OK |
| 3010 | OK, requiere reinicio |
| 1641 | OK, reinicio iniciado por el instalador |
| 60000–68999 | Reservados por PSADT |
| 69000–69999 | Códigos propios del proyecto |
| 69002 | Quedó instalada una versión previa tras desinstalar |
| 69003 | El token no quedó registrado en `appwiz.cpl` |
| 69005 | No se pudo registrar el host de mensajería nativa en HKLM |
| 69006 | `Lanzar.ps1` no pudo iniciar el instalador |
| 69007 | No quedó instalado un Java 8 que `tokensign.exe` pueda encontrar |
| 69008 | No quedaron instalados los certificados raíz de Firma Digital |

## Comandos

Crear plantilla (una sola vez):

```powershell
Install-Module -Name PSAppDeployToolkit -Scope CurrentUser
Import-Module PSAppDeployToolkit
New-ADTTemplate -Destination 'C:\Paquetes' -Name 'Certificados'
```

Probar (consola como administrador, desde la carpeta del paquete):

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install   -DeployMode Silent
.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent
.\Invoke-AppDeployToolkit.exe -DeploymentType Install   -DeployMode Interactive
```

Armar el ejecutable único (requiere 7-Zip instalado):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Empaquetado\Build-Instalador.ps1
```

Logs: `C:\Windows\Logs\Software\`

## Criterios de aceptación

- [ ] Install en PC **con** versión previa: queda una sola entrada en `appwiz.cpl`, con la versión nueva.
- [ ] Install en PC **sin** versión previa: instala sin error.
- [ ] Uninstall: no queda entrada en `appwiz.cpl`.
- [ ] Ejecutar Install dos veces seguidas no falla.
- [ ] Código de salida 0 (o 3010) en todos los casos anteriores.
- [ ] Log sin errores de severidad 3.
- [ ] PC **sin** Java 8: queda Java 8 x64 instalado. PC **con** Java 8: no se reinstala.
- [ ] Quedan las dos AC Raíz en `Cert:\LocalMachine\Root` y los intermedios en CA.
- [ ] Firma real con token en GDE (Chrome y Firefox) con un usuario común.

## Al entregar cambios

Indicar: qué fase se modificó, qué se probó (de la lista anterior) y el código de salida obtenido.
