# Firma Digital / Token Service — reemplazo masivo de MSI (v3)

Desinstala toda versión previa del token de firma digital, instala lo que el firmador necesita
(Java 8, los certificados de las AC de Firma Digital de Argentina y los drivers de token SafeNet,
Feitian ePass2003 y Longmai mToken), instala `token-service_v4.msi`, con log, y reinicia el equipo.

| Versión | Carpeta | Etiqueta | Qué instala |
| --- | --- | --- | --- |
| v1 | `instalador-msi` | `v1.0.0` | Token (MSI) |
| v2 | `instalador-msi-v2` | `v2.0.0` | v1 + Java 8 + certificados de las AC |
| **v3 (esta)** | `instalador-msi-v3` | pendiente `v3.0.0` | v2 + drivers de token SafeNet, Feitian, Longmai |

Reglas del proyecto y criterios de aceptación: `AGENTS.md`. Estado de pruebas: `PRUEBAS.md`.

## Instalador de un solo archivo

**`Salida\FirmaDigital-Instalador.exe`**: un único archivo de unos 85 MB. Se le da doble clic y
el usuario solo tiene que aceptar el permiso de Windows.

1. **SmartScreen** (el `.exe` no está firmado): *Más información → Ejecutar de todas formas*.
2. **UAC**: *Sí*. El `.exe` pide administrador por manifiesto.
3. El asistente PSADT muestra el progreso, sin preguntas:
   - cierra `tokensign.exe` si está abierto;
   - desinstala **todo MSI que diga `GDE` o `Firma Digital`** (nombre en appwiz.cpl o
     carpeta de instalación; regex `\bGDE\b|Firma\s*Digital`);
   - instala **Java 8 x64** (`jre-8u503-windows-x64.exe`) **solo si no hay un Java 8** registrado;
     no toca otros Java. Tiene que ser Java 8: el firmador usa una API de PKCS#11 que no existe
     desde Java 9. Log: `Java8_Install.log`;
   - instala los **certificados de las AC de Firma Digital** con el instalador oficial
     (`Certificados AC Firma Digital Argentina.exe`, en silencio; durante unos segundos se ve
     una consola con `certutil`) y verifica que estén las dos AC Raíz. Log: `CertificadosAC_Install.log`;
   - instala los **drivers de token** que falten (cada uno se saltea si ya está esa versión o una
     mayor; uno más viejo se actualiza):
     - **SafeNet Authentication Client 10.8**, el MSI y la licencia del paquete del proveedor SITEPRO;
     - **Feitian ePass2003 1.1.22.831**;
     - **Longmai mToken CryptoID 2.2.26.324** (también aquí se ve un momento una consola: instala
       el minidriver con un `.bat`; además deja un monitor que arranca con Windows);
   - instala `token-service_v4.msi` y verifica que quede registrado;
   - registra el host de mensajería nativa en HKLM (Chrome y Firefox, 64 y 32 bits).
4. Muestra la ventana de reinicio: **cuenta regresiva de 60 s**, botón "Reiniciar ahora";
   al llegar a cero reinicia aunque nadie toque nada.

En una PC sin nada instalado tarda alrededor de 1 minuto y 15 segundos (más el reinicio).
Si algo falla, aparece un cartel de error y el detalle queda en `C:\Windows\Logs\Software\`.
Códigos de salida: `AGENTS.md`.

Las ventanas muestran el isotipo de Modernización y el subtítulo "Secretaría de Estado de
Modernización de Santa Cruz" (`Toolkit.CompanyName` en `Certificados/Config/config.psd1`). Los
logos salen de `logo/isotipo-blanco.png`: `Assets/Isotipo-Modernizacion-Blanco.png` para Windows
en tema oscuro y `Assets/Isotipo-Modernizacion.png` (gris oscuro) para tema claro, porque el
blanco no se vería sobre fondo claro.

### Cómo está armado

| Pieza | Qué es |
| --- | --- |
| `Certificados/` | Paquete PSAppDeployToolkit 4.1.8. La lógica está en `Invoke-AppDeployToolkit.ps1`; los instaladores en `Files/` y `Files/Drivers/`. |
| `Empaquetado/Build-Instalador.ps1` | Genera el `.exe`: comprime `Certificados/` + `Lanzar.ps1` y lo pega a `7zSD.sfx` con un manifiesto `requireAdministrator`. Corta si falta algún instalador. |
| `Empaquetado/Lanzar.ps1` | Lo que ejecuta el `.exe` después de extraer: lanza el asistente y espera a que cierre la ventana de reinicio (si no, el SFX borraría la carpeta temporal antes de tiempo). |
| `Token Drivers/` | Originales del proveedor que **no** se empaquetan ni se versionan en git: el envoltorio de SITEPRO (origen del MSI y la licencia de SafeNet) y el SafeNet 10.5, que no se usa. |

Regenerar el `.exe` después de cambiar algo (requiere 7-Zip instalado):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Empaquetado\Build-Instalador.ps1
```

## Despliegue masivo (GPO / Intune / SCCM)

No hace falta el `.exe`: se distribuye la carpeta `Certificados/` y corre en contexto SYSTEM, sin UAC.
En modo Silent **no reinicia**: devuelve 3010 y el reinicio lo programa la herramienta de despliegue.

| Vía | Comando / configuración |
| --- | --- |
| **Intune** (Win32 app) | Empaquetar `Certificados/` con IntuneWinAppUtil (`-s Invoke-AppDeployToolkit.exe`). Install: `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent`. Uninstall: `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent`. Contexto System. Detección: MSI `{B8A8BA6C-F8FA-4551-86C3-449375C60103}` (las dependencias se verifican durante la instalación). |
| **SCCM** | Los mismos comandos, "Run with administrative rights". |
| **GPO** | Script de inicio de equipo que ejecute `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent` desde un recurso compartido. |

Tratar 0 y 3010 como éxito (3010 = reinicio pendiente), 1641 como reinicio iniciado y cualquier
69000–69999 o 60000–68999 como fallo (ver `AGENTS.md`).

## Notas sobre los componentes

### MSI del token

1. **Escribe el native messaging host en HKCU** del usuario que instala. En SYSTEM o con credenciales
   de otro administrador, la firma no andaría para el usuario real. **Resuelto**: en Post-Install el
   script escribe las mismas claves en HKLM (vistas 64 y 32), apuntando a
   `C:\Program Files (x86)\GCBA Firma Digital\`, y las verifica. Edge no está contemplado.
2. **Compilado con licencia *trial* de Advanced Installer**: `ARPCOMMENTS` dice `(Evaluation Installer)`.
3. **Branding y UpgradeCode**: `GDE Firma Digital Service Firefox Catamarca`, carpeta `GCBA Firma Digital`,
   ProductVersion `2.0.0` y UpgradeCode placeholder `{00000001-0001-0001-0001-000000000001}`; por eso la
   detección es por nombre/carpeta.

### Java 8

- `tokensign.exe` es un wrapper **Launch4j**: Java mínimo 1.6.0, sin máximo, prefiere 32 bits y acepta 64,
  prefiere JDK sobre JRE, y busca el runtime en `HKLM\SOFTWARE\JavaSoft`.
- El firmador (JAR de everis compilado para Java 6) usa `new SunPKCS11(InputStream)`, que **no existe
  desde Java 9**: con Java 17/21/25 la firma por PKCS#11 fallaría. Por eso Java 8.
- Se usa el instalador de Oracle provisto por Modernización. El instalador de Oracle deja también
  `Java Auto Updater` en `appwiz.cpl`, aunque se pasa `AUTO_UPDATE=0`.
- Riesgo: en PCs con JDK 9+ instalado, Launch4j podría elegir ese JDK antes que el JRE 8.

### Certificados de las AC

- Instalador oficial Inno Setup 5.5 (sin firma digital, `Uninstallable=no`). Trae 22 certificados y
  un `script.bat` con `certutil -addstore -enterprise`: AC Raíz 2007 y 2016 en Root; AC ONTI, AC
  Modernización-PFDR, AFIP, ANSES, Box Custodia, Digilogix, Encode, Lakaut, Banelco, Train Solutions en CA.
- Inno no propaga el resultado de `certutil`: el script verifica las dos AC Raíz por thumbprint.
- **La AC Raíz 2007 vence el 2027-11-17.**

### Drivers de token

| Driver | Origen | Instalación | En `appwiz.cpl` |
| --- | --- | --- | --- |
| SafeNet Authentication Client 10.8.259.0 | MSI x64 y licencia extraídos sin modificar de `WINDOWS - SafeNet5110+-SAC_10_8.exe` (SITEPRO S.A., re-firmado por SITEPRO) | `Start-ADTMsiProcess` + `PROP_LICENSE_FILE` | `SafeNet Authentication Client 10.8` |
| Feitian ePass2003 1.1.22.831 | Instalador NSIS firmado por Feitian | `/S` | `ePass2003` |
| Longmai mToken CryptoID 2.2.26.324 | Instalador Inno firmado por Century Longmai | `/VERYSILENT` | `LMCryptoIDE versión 2.2.26.324` |

- **Licencia SafeNet**: el `.txt` de SITEPRO figura a nombre del *Colegio de Abogados de la Provincia de
  Buenos Aires* (1 puesto). Se usa por decisión del área porque es lo que entregó el proveedor; conviene
  regularizarla con SITEPRO o Thales.
- SAC 10.5 y 10.8 comparten UpgradeCode: la 10.8 reemplaza a la 10.5 (actualización pendiente de probar).
- Longmai agrega `CryptoIDEMon.exe` al inicio de Windows (`HKLM\...\Run`) para todos los usuarios.

## Firma del `.exe` (pendiente)

Hoy sale sin firmar: SmartScreen (solo en archivos descargados) y UAC muestran "Editor desconocido".

- **Gratis, válido en el dominio**: certificado de firma de código propio (CA interna o autofirmado)
  distribuido por GPO a "Entidades raíz de confianza" y "Editores de confianza".
- **Pago, válido en cualquier PC**: certificado OV a nombre de la Secretaría (Certum OV en la nube es el
  más económico; comparar con Sectigo). Firmar con `signtool sign /fd SHA256 /tr <timestamp> /td SHA256`.
- No sirven: el token de firma digital (AC ONTI/Modernización, no es de firma de código), Let's Encrypt,
  ni SignPath Foundation (exige proyecto open source; el paquete lleva software de terceros).

## Archivos heredados

De la etapa anterior a PSADT (desarrollada en Linux). **No se usan**; quedan como referencia.

| Archivo | Qué era |
| --- | --- |
| `Deploy-TokenService.ps1` | Script propio: desinstalaba, instalaba, registraba HKLM y reiniciaba, con `msiexec` directo. |
| `Instalar.bat` | Lanzador con elevación de ese script. |
| `PSADT/Invoke-AppDeployToolkit.ps1` | Primer borrador de la variante PSADT. |
| `TokenService-Deploy.zip` | Paquete de esa etapa. |
| `token-service_v4.msi` (raíz) | Copia del MSI; el que se empaqueta es `Certificados/Files/token-service_v4.msi`. |

Su documentación original: `git show v1.0.0:README.md`, `git show v1.0.0:PRUEBAS.md`,
`git show v1.0.0:MIGRAR-A-WINDOWS.md`.
