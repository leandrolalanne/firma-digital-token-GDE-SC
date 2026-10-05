# AGENTS.md — v3

## Versiones

Cada versión vive en su propia carpeta y repositorio git. **Este archivo describe la v3.**

| Versión | Carpeta | Etiqueta | Qué instala |
| --- | --- | --- | --- |
| v1 | `C:\Proyects\SEMIT\instalador-msi` | `v1.0.0` | Token (MSI) |
| v2 | `C:\Proyects\SEMIT\instalador-msi-v2` | `v2.0.0` | v1 + Java 8 + certificados de las AC |
| **v3** | `C:\Proyects\SEMIT\instalador-msi-v3` | *(pendiente `v3.0.0`)* | v2 + drivers de token SafeNet, Feitian, Longmai |

## Proyecto

Paquete de despliegue con **PSAppDeployToolkit 4.1.8 (PSADT)** para Windows 10/11 x64 que deja lista una PC
para firmar con token en GDE: desinstala cualquier versión previa del token, instala sus dependencias e
instala la versión nueva, con log, códigos de salida estándar y reinicio con cuenta regresiva.

- Entregable principal: `Salida\FirmaDigital-Instalador.exe` (~85 MB), un único autoextraíble (7-Zip SFX)
  que se ejecuta con doble clic, pide UAC, muestra el asistente PSADT y reinicia con cuenta regresiva.
- También sirve para GPO / Intune / SCCM (500 equipos) con la carpeta `Certificados/` en modo Silent.
- Ventanas con el isotipo y el texto "Secretaría de Estado de Modernización de Santa Cruz".

### Qué instala, en orden (fase Install)

1. **Token** — primero desinstala versiones previas: todo MSI cuyo `DisplayName` o `InstallLocation`
   coincida con `\bGDE\b|Firma\s*Digital` (en el parque figura como `GDE Firma Digital Service Firefox
   Catamarca`, `GDE Firma Digital Service Firefox` o `GCBA Firma Digital`). No se usa el `UpgradeCode`:
   es el placeholder de Advanced Installer `{00000001-0001-0001-0001-000000000001}`.
2. **Java 8 x64** (`jre-8u503-windows-x64.exe`, Oracle, provisto por Modernización). Solo si no hay un
   Java 1.8 registrado en `HKLM\SOFTWARE\JavaSoft` (vistas 64 y 32) con `bin\java.exe`. No se tocan otros
   Java. Tiene que ser Java 8: `tokensign.exe` es un wrapper Launch4j y el firmador usa
   `new SunPKCS11(InputStream)`, que no existe desde Java 9.
3. **Certificados de las AC** (`Certificados AC Firma Digital Argentina.exe`, Inno Setup oficial, sin
   firma). Siempre, con `/VERYSILENT`: hace `certutil -addstore -enterprise` (2 raíz en Root, 20 en CA).
   Se verifican las dos AC Raíz por thumbprint en `Cert:\LocalMachine\Root`.
4. **Drivers de token**, todos (en una PC puede haber usuarios con tokens de distintas marcas). Cada uno
   se saltea si en `appwiz.cpl` ya está esa versión o una mayor; si hay una menor, se actualiza:

   | Driver | Archivo | Detección (`appwiz.cpl`) |
   | --- | --- | --- |
   | SafeNet Authentication Client 10.8.259.0 | `Drivers\sac-10.8-x64-10.8.msi` + licencia `.txt` (`PROP_LICENSE_FILE`) | `DisplayName` `SafeNet Authentication Client*` |
   | Feitian ePass2003 1.1.22.831 | `Drivers\MSePass2003_Win_Spanish_V1.1.22.831.exe` (NSIS, `/S`) | `DisplayName` contiene `ePass2003` |
   | Longmai mToken CryptoID 2.2.26.324 | `Drivers\MSCryptoID-FIPS140-3_Win_Spanish_V2.2.26.324.exe` (Inno, `/VERYSILENT`) | clave `{F72BDB06-FA8C-4B07-89A0-ADB1ADC791F7}_is1` |

   SafeNet: MSI y licencia extraídos sin modificar del paquete del proveedor SITEPRO
   (`Token Drivers\WINDOWS - SafeNet5110+-SAC_10_8.exe`). Decisión del área: se usa esta versión porque
   es la que entregó el proveedor (la licencia del `.txt` figura a nombre de otra institución).
5. **Token** `token-service_v4.msi` — ProductCode `{B8A8BA6C-F8FA-4551-86C3-449375C60103}`,
   ProductVersion `2.0.0`, x86. Luego registra el native messaging host en HKLM (Chrome y Firefox,
   vistas 64 y 32), porque el MSI lo escribe en HKCU de quien instala.

## Estructura

```
Certificados/
├── Invoke-AppDeployToolkit.exe     # Lanzador. No modificar.
├── Invoke-AppDeployToolkit.ps1     # ÚNICO script de lógica a editar.
├── Files/                          # token-service_v4.msi, Java 8, certificados de las AC.
│   └── Drivers/                    # SafeNet (MSI + licencia), Feitian, Longmai.
├── SupportFiles/                   # Archivos auxiliares (vacío).
├── Config/                         # config.psd1: logos y CompanyName.
├── Assets/, Strings/               # UI y textos. No tocar salvo pedido.
├── PSAppDeployToolkit/             # Módulo (v4.1.8, firmado). NUNCA modificar.
└── PSAppDeployToolkit.Extensions/  # Funciones propias, solo si hacen falta.
Empaquetado/
├── Build-Instalador.ps1            # Arma Salida\FirmaDigital-Instalador.exe; corta si falta un instalador.
├── Lanzar.ps1                      # Punto de entrada del .exe. Solo lanza y espera; sin lógica.
└── 7zSD.sfx                        # Módulo SFX del LZMA SDK 23.01 (7-zip.org). No modificar.
Salida/                             # Generado por el build. No editar a mano.
Token Drivers/                      # Originales del proveedor (envoltorio SITEPRO, SAC 10.5). No se empaquetan ni se versionan.
logo/                               # Isotipo original de Modernización.
Deploy-TokenService.ps1, Instalar.bat, PSADT/, TokenService-Deploy.zip   # Heredados (pre-PSADT). No se usan.
```

## Reglas

1. Toda la lógica va en `Invoke-AppDeployToolkit.ps1`, dentro de las fases existentes
   (Pre-Install, Install, Post-Install, Pre-Uninstall, Uninstall, Post-Uninstall, Repair).
   Las funciones auxiliares se definen en la sección Variables y se llaman desde las fases.
2. Usar **solo funciones ADT** del módulo. No llamar `msiexec.exe` directo ni usar `Start-Process`.
   - Desinstalar versiones previas: `Uninstall-ADTApplication -FilterScript { ... }`
   - Instalar MSI: `Start-ADTMsiProcess -Action Install -FilePath '<archivo>.msi'`
   - Instaladores `.exe`: `Start-ADTProcess`
   - Consultar instalado: `Get-ADTApplication`
   - Logging: `Write-ADTLogEntry`
   - Rutas del paquete: `$adtSession.DirFiles`, `$adtSession.DirSupportFiles`, logs en `$adtSession.LogPath`
   - Única excepción: `Empaquetado/Lanzar.ps1` (fuera del paquete PSADT) usa `Start-Process` para lanzarlo.
3. Prohibido `Win32_Product` / `Get-WmiObject Win32_Product` (dispara reparaciones MSI).
4. Compatible con **Windows PowerShell 5.1**. No usar sintaxis exclusiva de PowerShell 7.
   Los `.ps1` propios van en ASCII (sin acentos). Los `.psd1` de Config/Strings pueden llevar UTF-8.
5. Sin rutas absolutas a la máquina del desarrollador. Todo relativo al paquete.
6. Reinicio (pedido explícito): en modo Interactive, `Show-ADTInstallationRestartPrompt` con
   cuenta regresiva de 60 s que reinicia al llegar a cero. En modo Silent no se reinicia:
   se devuelve 3010 y el reinicio queda a cargo del sistema de despliegue.
7. Completar siempre `AppVendor`, `AppName`, `AppVersion`, `AppScriptVersion` (3.0.0), `AppScriptDate`
   y `AppScriptAuthor` en `$adtSession`.
8. No agregar pasos, dependencias ni funciones que no se pidieron.
9. Antes de integrar un instalador nuevo: verificar firma, abrirlo sin ejecutarlo (7-Zip, innoextract,
   innounp) y confirmar parámetros silenciosos y qué deja en `appwiz.cpl`.

## Códigos de salida

| Código | Significado |
| --- | --- |
| 0 | OK |
| 3010 | OK, requiere reinicio (resultado normal de Install) |
| 1641 | OK, reinicio iniciado por el instalador |
| 60000–68999 | Reservados por PSADT (60001: error no controlado, ver log) |
| 69002 | Quedó instalada una versión previa del token tras desinstalar |
| 69003 | El token no quedó registrado en `appwiz.cpl` |
| 69005 | No se pudo registrar el host de mensajería nativa en HKLM |
| 69006 | `Lanzar.ps1` no pudo iniciar el instalador |
| 69007 | No quedó instalado un Java 8 que `tokensign.exe` pueda encontrar |
| 69008 | No quedaron instalados los certificados raíz de Firma Digital |
| 69009 | Un driver de token no aparece en `appwiz.cpl` después de instalarlo |

## Comandos

Plantilla: ya está en `Certificados/` (release oficial `PSAppDeployToolkit_Template_v4.zip` 4.1.8 de
GitHub). Para actualizar PSADT: bajar el template nuevo, reemplazar `PSAppDeployToolkit/` y ajustar
`ModuleVersion` en el bloque de inicialización de `Invoke-AppDeployToolkit.ps1`.

Probar (consola como administrador, desde `Certificados/`):

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install   -DeployMode Silent
.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent
.\Invoke-AppDeployToolkit.exe -DeploymentType Install   -DeployMode Interactive
```

Armar el ejecutable único (requiere 7-Zip instalado):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Empaquetado\Build-Instalador.ps1
```

Logs en `C:\Windows\Logs\Software\`: `FirmaDigitalService_PSAppDeployToolkit_Install.log` y uno por
instalador (`Java8_Install.log`, `CertificadosAC_Install.log`, SafeNet, Longmai, token).

## Criterios de aceptación

Detalle y evidencia en `PRUEBAS.md`.

- [x] Install en PC **sin** versión previa: instala sin error (2026-10-01 12:48, 3010).
- [ ] Install en PC **con** versión previa — no probado en v3 (sí en v2, misma lógica del token).
- [ ] Uninstall: no queda entrada en `appwiz.cpl` — **no probado en ninguna versión**.
- [ ] Ejecutar Install dos veces seguidas no falla (la 2.ª debe saltear Java y los tres drivers) — pendiente.
- [x] Código de salida 0 (o 3010) en los casos probados.
- [x] Log sin errores de severidad 3 (ni advertencias).
- [x] PC **sin** Java 8: queda Java 8 x64 instalado (12:48).
- [x] Quedan las dos AC Raíz en `Cert:\LocalMachine\Root`.
- [x] PC **sin** drivers: quedan SafeNet 10.8, ePass2003 y LMCryptoIDE en `appwiz.cpl`, sin ventanas que pidan clics.
- [ ] PC con SafeNet 10.5: se actualiza a 10.8 — pendiente.
- [ ] Firma real con un token de cada marca (SafeNet, Feitian, Longmai) — reportado OK, falta confirmar por marca.

## Pendientes y observaciones

- **Firma del `.exe`**: hoy sale sin firmar (SmartScreen y UAC muestran "Editor desconocido"). Opciones
  evaluadas: certificado propio (CA interna o autofirmado) distribuido por GPO, gratis y válido en el
  dominio; o certificado comercial OV a nombre de la Secretaría (Certum OV en la nube, el más económico).
  El token de firma digital (AC ONTI/Modernización) no sirve: no es de firma de código.
- **Licencia SafeNet**: el `.txt` de SITEPRO está a nombre del Colegio de Abogados de la Provincia de Buenos
  Aires (1 puesto). Se usa por decisión del área; conviene regularizarla con el proveedor.
- **Java Auto Updater**: el instalador de Oracle lo deja en `appwiz.cpl` aunque se pasa `AUTO_UPDATE=0`.
- **AC Raíz 2007 vence el 2027-11-17**; la de 2016 en 2036. Actualizar el instalador de certificados cuando
  Modernización publique uno nuevo.
- **Riesgo**: en PCs con JDK 9+ instalado, Launch4j (`preferJdk`) podría elegirlo antes que el JRE 8.
- **MSI del token**: compilado con licencia *trial* de Advanced Installer y con branding Catamarca/GCBA.
- Uninstall y Repair no tocan Java, certificados ni drivers (los pueden usar otras aplicaciones).

## Al entregar cambios

Indicar: qué fase se modificó, qué se probó (de la lista anterior) y el código de salida obtenido.
