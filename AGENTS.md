# AGENTS.md

## Proyecto

**Firma Digital con Token GDE — Santa Cruz**: instalador que deja una PC con Windows 10/11 x64 lista para
firmar con token en GDE. Es un paquete **PSAppDeployToolkit 4.1.8 (PSADT)** empaquetado como un único
autoextraíble (7-Zip SFX) que se ejecuta con doble clic, pide UAC, muestra el asistente con el isotipo de la
Secretaría de Estado de Modernización de Santa Cruz y reinicia con cuenta regresiva.

Repositorio privado: `github.com/leandrolalanne/firma-digital-token-GDE-SC`. Documentación para usuarios:
`README.md` (en español; el proyecto solo aplica en Santa Cruz).

## Versiones y releases

- **Versionado Semántico** (`MAYOR.MENOR.PARCHE`). Cada versión es un tag anotado `vX.Y.Z` y un release de
  GitHub con **un** instalador: `firma-digital-token-GDE-SC-X.Y.Z.exe`.
- **`CHANGELOG.md`** en formato *Keep a Changelog* (en español). Las notas del release salen de su sección.
- Publicar: anotar en `CHANGELOG.md` → commit → `git tag -a vX.Y.Z -m "X.Y.Z"` → `git push origin main vX.Y.Z`
  → `gh release create vX.Y.Z dist\firma-digital-token-GDE-SC-X.Y.Z.exe --title vX.Y.Z --notes-file <sección del CHANGELOG>`,
  agregando el SHA-256 del `.exe` al final de las notas. Un tag con sufijo (`vX.Y.Z-rc.1`) sale como pre-release.
- **Publicación automática pendiente de activar:** `build/release.yml` es el workflow que hace lo anterior en
  `windows-latest` al subir el tag (notas desde el CHANGELOG, SHA-256 incluido). No está en
  `.github/workflows/` porque la sesión de `gh` no tiene el permiso `workflow`, que GitHub exige para subir
  workflows. Para activarlo: `gh auth refresh -h github.com -s workflow`, copiarlo a
  `.github/workflows/release.yml` y subirlo.
- Una versión que no se probó en una PC real se marca **pre-release** hasta probarla; la recomendada en el
  README es la última probada.

| Versión | Qué agregó | Estado |
| --- | --- | --- |
| 1.0.0 | Token GDE | Probada 2026-10-01 |
| 2.0.0 | Java 8 y certificados de las AC | Probada 2026-10-01 |
| 3.0.0 | Drivers de token | Probada 2026-10-01 (recomendada) |
| 4.0.0 | Extensiones de Chrome, Edge y Firefox; repositorio reorganizado | Pre-release: falta probar |

Las versiones 1.0.0 a 3.0.0 se desarrollaron con otra estructura (carpetas `Certificados/`, `Empaquetado/`,
`Salida/`); sus releases publican los `.exe` originales que se probaron. Desde la 4.0.0 rige la estructura de
abajo.

## Capas (`variantes/`)

El script es uno solo y ejecuta cada paso según los componentes de la capa con la que se arma. Las capas son
acumulativas, una por versión en la que se agregó cada componente. **El release publica la capa completa
(`extensiones`).** Las otras se pueden generar para uso interno con `-Variantes`.

| Capa | Componentes | Agregada en |
| --- | --- | --- |
| `basico` | Token | 1.0.0 |
| `java` | basico + Java8 + CertificadosAC | 2.0.0 |
| `tokens` | java + DriversToken | 3.0.0 |
| `extensiones` | tokens + Extensiones | 4.0.0 |

- Cada capa se define en `variantes/<nombre>/variante.psd1`: `Base` (de cuál hereda), `Componentes` y
  `Archivos` (instaladores que suma, de `instaladores/` a `Files/` del paquete).
- `build/build.ps1` resuelve la herencia, arma `dist/paquetes/<Nombre>/`, escribe `SupportFiles/Variante.psd1`
  (Nombre, Version, Componentes) y genera el `.exe`.

### Componentes (en este orden)

1. **Token** (siempre, Pre-Install). Desinstala versiones previas: todo MSI cuyo `DisplayName` o
   `InstallLocation` coincida con `\bGDE\b|Firma\s*Digital` (en el parque: `GDE Firma Digital Service Firefox
   Catamarca`, `GDE Firma Digital Service Firefox`, `GCBA Firma Digital`). No se usa el `UpgradeCode`: es el
   placeholder de Advanced Installer `{00000001-0001-0001-0001-000000000001}`.
2. **Java8**: `jre-8u503-windows-x64.exe` (Oracle, provisto por Modernización), solo si no hay un Java 1.8
   registrado en `HKLM\SOFTWARE\JavaSoft` (vistas 64 y 32) con `bin\java.exe`. No toca otros Java. Tiene que
   ser Java 8: `tokensign.exe` es un wrapper Launch4j y el firmador usa `new SunPKCS11(InputStream)`, que no
   existe desde Java 9.
3. **CertificadosAC**: `Certificados AC Firma Digital Argentina.exe` (Inno Setup oficial, sin firma), siempre,
   con `/VERYSILENT`: `certutil -addstore -enterprise` (2 raíz en Root, 20 en CA). Se verifican las dos AC
   Raíz por thumbprint en `Cert:\LocalMachine\Root`.
4. **DriversToken**: 3 instaladores que cubren 4 modelos. Cada uno se saltea si en `appwiz.cpl` ya está esa
   versión o una mayor; si hay una menor, se actualiza.

   | Driver | Modelos | Archivo | Detección |
   | --- | --- | --- | --- |
   | SafeNet Authentication Client 10.8.259.0 | eToken 5110 y 5110+ | `drivers/sac-10.8-x64-10.8.msi` + licencia `.txt` (`PROP_LICENSE_FILE`) | `DisplayName` `SafeNet Authentication Client*` |
   | Feitian ePass2003 1.1.22.831 | ePass2003 | `drivers/MSePass2003_Win_Spanish_V1.1.22.831.exe` (NSIS, `/S`) | `DisplayName` contiene `ePass2003` |
   | Longmai mToken CryptoID 2.2.26.324 | mToken FIPS 140-3 | `drivers/MSCryptoID-FIPS140-3_Win_Spanish_V2.2.26.324.exe` (Inno, `/VERYSILENT`) | clave `{F72BDB06-FA8C-4B07-89A0-ADB1ADC791F7}_is1` |

5. **Token** `token-service_v4.msi` (ProductCode `{B8A8BA6C-F8FA-4551-86C3-449375C60103}`, 2.0.0, x86) y
   registro del native messaging host en HKLM (Chrome, Edge y Firefox, vistas 64 y 32), porque el MSI lo
   escribe en HKCU de quien instala (y nunca para Edge). Edge usa `cnmtoken.json`, igual que Chrome.
6. **Extensiones** (Post-Install): la extensión "Firma con Token GDE" **forzada por directiva**; cada
   navegador la baja de su tienda al abrirse (hace falta internet). No lleva archivos.

   | Navegador | Extensión | Directiva (HKLM\SOFTWARE\Policies\...) |
   | --- | --- | --- |
   | Chrome | `maddemndndajaiilmnjoocajgkpmlael` (Chrome Web Store, 2.0.1) | `Google\Chrome\ExtensionInstallForcelist`, valor `<n>` = `<id>;https://clients2.google.com/service/update2/crx` |
   | Edge | la misma de la Chrome Web Store (no está en la tienda de Edge) | `Microsoft\Edge\ExtensionInstallForcelist`, igual que Chrome |
   | Firefox | `firma.token@gde.gob.ar` (addons.mozilla.org, 3.2.0) | `Mozilla\Firefox`, valor `ExtensionSettings` (JSON) con `force_installed` y `.../firma-con-token-gde/latest.xpi` |

   Se agrega solo la entrada propia: en las listas de Chrome/Edge en el primer número libre; en Firefox se
   fusiona el JSON. Uninstall quita solo esas entradas.

Detalle de cada componente: `docs/NOTAS-TECNICAS.md`.

## Estructura

```
src/
├── paquete/                        # Paquete PSADT común.
│   ├── Invoke-AppDeployToolkit.exe # Lanzador. No modificar.
│   ├── Invoke-AppDeployToolkit.ps1 # ÚNICO script de lógica a editar.
│   ├── Config/                     # config.psd1: logos y CompanyName.
│   ├── Assets/, Strings/           # UI y textos. No tocar salvo pedido.
│   ├── PSAppDeployToolkit/         # Módulo 4.1.8 (firmado). NUNCA modificar.
│   └── PSAppDeployToolkit.Extensions/
└── Lanzar.ps1                      # Punto de entrada del .exe. Solo lanza y espera; sin lógica.
instaladores/                       # Binarios de terceros: token/, java/, certificados/, drivers/.
variantes/{basico,java,tokens,extensiones}/variante.psd1
build/
├── build.ps1                       # -Version → dist/firma-digital-token-GDE-SC-<version>.exe
├── release.yml                     # Workflow de release (tag → build → release); activar en .github/workflows/.
└── 7zSD.sfx                        # Módulo SFX del LZMA SDK 23.01 (7-zip.org). No modificar.
docs/NOTAS-TECNICAS.md              # Componentes, despliegue masivo, firma del .exe.
logo/                               # Isotipo original de Modernización.
dist/                               # Salida del build (en .gitignore).
```

## Reglas

1. Toda la lógica va en `src/paquete/Invoke-AppDeployToolkit.ps1`, dentro de las fases existentes
   (Pre-Install, Install, Post-Install, Pre-Uninstall, Uninstall, Post-Uninstall, Repair). Las funciones
   auxiliares se definen en la sección Variables y se llaman desde las fases.
2. Lo específico de una capa va en su `variante.psd1` (componentes e instaladores), nunca en copias del
   script. Un componente nuevo = un nombre en `Componentes`, sus `Archivos` y un `if` en la fase que corresponda.
3. Usar **solo funciones ADT** del módulo. No llamar `msiexec.exe` directo ni usar `Start-Process`.
   - Desinstalar: `Uninstall-ADTApplication -FilterScript { ... }`
   - Instalar MSI: `Start-ADTMsiProcess`; instaladores `.exe`: `Start-ADTProcess`
   - Consultar instalado: `Get-ADTApplication`; registro: `Get-/Set-/Remove-ADTRegistryKey`
   - Logging: `Write-ADTLogEntry`; rutas: `$adtSession.DirFiles`, `$adtSession.LogPath`
   - Única excepción: `src/Lanzar.ps1` (fuera del paquete PSADT) usa `Start-Process` para lanzarlo.
4. Prohibido `Win32_Product` / `Get-WmiObject Win32_Product` (dispara reparaciones MSI).
5. Compatible con **Windows PowerShell 5.1**. Los `.ps1` propios en ASCII (sin acentos); los `.psd1` de
   Config/Strings pueden llevar UTF-8. `.gitattributes` tiene `* -text`: git no toca finales de línea
   (los archivos del módulo PSADT están firmados).
6. Sin rutas absolutas a la máquina del desarrollador. Todo relativo al repo o al paquete.
7. Reinicio (pedido explícito): en Interactive, `Show-ADTInstallationRestartPrompt` con cuenta regresiva de
   60 s que reinicia al llegar a cero. En Silent no reinicia: devuelve 3010.
8. `$adtSession`: completar `AppVendor`, `AppName`, `AppVersion`, `AppScriptDate`, `AppScriptAuthor`.
   `AppScriptVersion` sale de `Variante.psd1` (la pone el build desde el tag).
9. No agregar pasos, dependencias ni funciones que no se pidieron.
10. Antes de integrar un instalador nuevo: verificar firma, abrirlo sin ejecutarlo (7-Zip, innoextract,
    innounp), confirmar parámetros silenciosos y qué deja en `appwiz.cpl`. Ningún archivo > 100 MB (límite
    de GitHub); hoy el mayor es Java, 69 MB.
11. Cada cambio publicado lleva su entrada en `CHANGELOG.md` y su versión según SemVer: corrección → PARCHE,
    componente o función nueva compatible → MENOR, cambio que altera lo que ya hacía el instalador → MAYOR.

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
| 69010 | Falta `SupportFiles\Variante.psd1` (paquete no generado con `build/build.ps1`) |
| 69011 | No se pudo forzar la extensión en Chrome, Edge o Firefox (o `ExtensionSettings` de Firefox no es JSON válido) |

## Comandos

Build local (requiere 7-Zip):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\build.ps1 -Version 4.0.0
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\build.ps1 -Version 4.0.0 -Variantes basico
```

Probar un paquete armado (consola como administrador, desde `dist\paquetes\<Capa>\`):

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install   -DeployMode Silent
.\Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent
.\Invoke-AppDeployToolkit.exe -DeploymentType Install   -DeployMode Interactive
```

Logs en `C:\Windows\Logs\Software\`: `FirmaDigitalService_PSAppDeployToolkit_Install.log` (incluye la línea
"Variante ... - componentes: ...") y uno por instalador.

PSADT: la plantilla vino del release oficial `PSAppDeployToolkit_Template_v4.zip` 4.1.8 de GitHub. Para
actualizarlo: reemplazar `src/paquete/PSAppDeployToolkit/` y ajustar `ModuleVersion` en el script.

## Criterios de aceptación (4.0.0)

Detalle y evidencia en `PRUEBAS.md`.

- [x] Release `v4.0.0` publicado (pre-release) con el `.exe` y su SHA-256.
- [ ] Activar `build/release.yml` en `.github/workflows/` y verificar un release generado por Actions.
- [ ] PC con versión previa del token: queda una sola entrada en `appwiz.cpl`, la nueva.
- [ ] PC sin nada: instala todo sin ventanas que pidan clics; una 2.ª corrida saltea Java, drivers y extensiones.
- [ ] Tras reiniciar, Chrome, Edge y Firefox muestran "Firma con Token GDE" instalada y no se puede quitar;
      las extensiones forzadas por otras directivas siguen ahí.
- [ ] Edge en una PC **fuera de dominio**: confirmar que instala la extensión de la Chrome Web Store.
- [ ] Uninstall: no queda entrada del token en `appwiz.cpl` y se quitan solo las entradas propias de las
      directivas (no probado en ninguna versión).
- [ ] Código de salida 0 o 3010 en todos los casos; log sin severidad 3.
- [ ] Firma real en GDE desde Chrome, Edge y Firefox con un usuario común y un token de cada marca.

Cuando se cumplan: quitar la marca de pre-release (`gh release edit v4.0.0 --prerelease=false --latest`) y
poner la 4.0.0 como recomendada en el README.

## Pendientes y observaciones

- **Firma del `.exe`**: se publica sin firmar. Opciones en `docs/NOTAS-TECNICAS.md`.
- **Licencia SafeNet**: el `.txt` de SITEPRO está a nombre del Colegio de Abogados de la Provincia de Buenos
  Aires (1 puesto). Se usa por decisión del área; conviene regularizarla.
- **Licencias de redistribución** (Java de Oracle, drivers, MSI del token): verificar si el repo deja de ser privado.
- **Java Auto Updater**: Oracle lo instala aunque se pase `AUTO_UPDATE=0`.
- **AC Raíz 2007 vence el 2027-11-17**; actualizar el instalador de certificados cuando haya uno nuevo.
- **Riesgo**: en PCs con JDK 9+ instalado, Launch4j (`preferJdk`) podría elegirlo antes que el JRE 8.
- **MSI del token**: compilado con licencia *trial* de Advanced Installer y con branding Catamarca/GCBA.
- **Edge fuera de dominio**: Chrome y Edge pueden limitar la instalación forzada en PCs no unidas a un
  dominio a extensiones de su propia tienda; la de Edge viene de la Chrome Web Store.
- Las extensiones necesitan internet la primera vez que se abre cada navegador.
- Uninstall y Repair no tocan Java, certificados ni drivers (los pueden usar otras aplicaciones). Repair
  tampoco vuelve a forzar las extensiones.

## Al entregar cambios

Indicar: qué fase y qué componente se modificó, qué se probó (de la lista anterior), el código de salida
obtenido y la entrada agregada en `CHANGELOG.md`.
