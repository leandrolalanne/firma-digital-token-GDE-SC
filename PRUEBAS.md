# Estado de pruebas — v3

Criterios de aceptación en `AGENTS.md`. Evidencia: `C:\Windows\Logs\Software\FirmaDigitalService_PSAppDeployToolkit_Install.log`,
`Java8_Install.log`, `CertificadosAC_Install.log`, `SafeNetAuthenticationClient10.8_10.8.259.0_Install.log`,
`LongmaimTokenCryptoID_Install.log`.

## Entorno

- Equipo `NOTEBOOK-SEMIT`, Windows 11 Pro (build 26200), x64.
- Ejecución con doble clic en `Salida\FirmaDigital-Instalador.exe` (modo Interactive), aceptando UAC.
- Fecha: 2026-10-01.

## Corridas (script 3.0.0, PSADT 4.1.8)

| Hora | Estado previo | Qué pasó | Salida |
| --- | --- | --- | --- |
| 12:48 | Sin token, sin Java, sin drivers | "No se detectaron versiones previas", instaló Java 8u503, certificados (AC Raíz verificadas), **SafeNet 10.8, ePass2003 y LMCryptoIDE**, el token, registró HKLM. Duración total 72 s | **3010** |

- Ninguna entrada de severidad 2 ni 3 en el log. Sin ventanas que pidieran clics (reportado por el usuario).
- Nombres reales en `appwiz.cpl` (confirman la detección del script):

  | Driver | `DisplayName` | `DisplayVersion` | Clave |
  | --- | --- | --- | --- |
  | SafeNet | `SafeNet Authentication Client 10.8` | `10.8.259.0` | `{13885775-1B2F-40A0-8537-2FD005E3F165}` |
  | Feitian | `ePass2003` | `1.1.22.831` | `ePass2003-4FE7-A218-48BDAE051E2B_std` |
  | Longmai | `LMCryptoIDE versión 2.2.26.324` | `2.2.26.324` | `{F72BDB06-FA8C-4B07-89A0-ADB1ADC791F7}_is1` |

- Observación: el instalador de Oracle deja también `Java Auto Updater` en `appwiz.cpl`, aunque se
  pasa `AUTO_UPDATE=0`.
- El usuario reportó que funcionó; falta confirmar una firma real con un token de cada marca.

## Verificaciones sin ejecutar

- Sintaxis de `Invoke-AppDeployToolkit.ps1` (ASCII puro).
- `Get-TokenDriverInstalled` contra esta PC antes de la corrida: instalaría los tres.
- Casos simulados: misma versión y más nueva -> saltea; más vieja (SafeNet 10.5) -> actualiza;
  versión ilegible -> considera instalado; Longmai por clave `_is1` -> saltea.
- Drivers analizados sin ejecutar: firmas válidas (Feitian, Longmai, Gemalto, SITEPRO); envoltorio SITEPRO
  con `sac-10.8-x64-10.8.msi`, `sac-10.8-x32-10.8.msi` y la licencia; el MSI admite `PROP_LICENSE_FILE`;
  script Inno de Longmai sin `skipifsilent` en el minidriver.
- `.exe` generado (~85 MB) con los cuatro archivos de drivers; el build corta si falta alguno.

## Pendiente

- Segunda corrida seguida: debe saltear Java y los tres drivers.
- PC con SafeNet 10.5 instalado: actualización a 10.8.
- Install en PC con versión previa del token (probado en v2, misma lógica).
- `-DeploymentType Uninstall` (no se probó en ninguna versión).
- Firma real con un token de cada marca (SafeNet, Feitian, Longmai) con un usuario común.

## Histórico

- Pruebas de la v2: `PRUEBAS.md` de `C:\Proyects\SEMIT\instalador-msi-v2`.
- Pruebas de la v1: `PRUEBAS.md` de `C:\Proyects\SEMIT\instalador-msi`.
- Pruebas de la etapa Linux (`Deploy-TokenService.ps1`, sin PSADT): `git show v1.0.0:PRUEBAS.md`.
