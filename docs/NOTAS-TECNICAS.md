# Notas técnicas

Detalle de cada componente del instalador y de cómo se distribuye. Para usarlo alcanza con el `README.md`.

## Despliegue masivo (GPO / Intune / SCCM)

No hace falta el `.exe`: `build/build.ps1` deja el paquete sin empaquetar en `dist\paquetes\Extensiones\`, que
corre en contexto SYSTEM, sin UAC. En modo silencioso **no reinicia**: devuelve 3010 y el reinicio lo programa
la herramienta de despliegue.

| Vía | Comando / configuración |
| --- | --- |
| **Intune** (Win32 app) | Empaquetar la carpeta con IntuneWinAppUtil (`-s Invoke-AppDeployToolkit.exe`). Instalar: `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent`. Desinstalar: `Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Silent`. Contexto System. Detección: MSI `{B8A8BA6C-F8FA-4551-86C3-449375C60103}`. |
| **SCCM** | Los mismos comandos, con "Run with administrative rights". |
| **GPO** | Script de inicio de equipo que ejecute `Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent` desde un recurso compartido. |

Tratar 0 y 3010 como éxito (3010 = reinicio pendiente), 1641 como reinicio iniciado y cualquier 69000–69999 o
60000–68999 como fallo (detalle en `AGENTS.md`).

## MSI del token

1. **Escribe el native messaging host en HKCU** del usuario que instala; en SYSTEM o con credenciales de otro
   administrador la firma no andaría. **Resuelto**: el script escribe las mismas claves en HKLM (vistas 64 y
   32), apuntando a `C:\Program Files (x86)\GCBA Firma Digital\`, y las verifica. También las escribe para
   Edge, que el MSI no contempla (`cnmtoken.json`, el mismo de Chrome).
2. **Compilado con licencia *trial* de Advanced Installer** (`ARPCOMMENTS` dice `(Evaluation Installer)`).
3. **Branding y UpgradeCode**: `GDE Firma Digital Service Firefox Catamarca`, carpeta `GCBA Firma Digital`,
   ProductVersion `2.0.0`, UpgradeCode placeholder `{00000001-0001-0001-0001-000000000001}`; por eso la
   detección de versiones previas es por nombre y carpeta.

## Java 8

- `tokensign.exe` es un wrapper **Launch4j**: Java mínimo 1.6.0, sin máximo, prefiere 32 bits y acepta 64,
  prefiere JDK sobre JRE, y busca el runtime en `HKLM\SOFTWARE\JavaSoft`.
- El firmador (JAR de everis compilado para Java 6) usa `new SunPKCS11(InputStream)`, que **no existe desde
  Java 9**. Por eso Java 8 y no la última versión.
- Instalador de Oracle provisto por Modernización. Deja también `Java Auto Updater` en Programas y características.
- Riesgo: en PCs con JDK 9+ instalado, Launch4j podría elegir ese JDK antes que el JRE 8.

## Certificados de las AC

- Instalador oficial Inno Setup 5.5 (sin firma digital, `Uninstallable=no`): 22 certificados y un `script.bat`
  con `certutil -addstore -enterprise`. AC Raíz 2007 y 2016 en Root; AC ONTI, AC Modernización-PFDR, AFIP,
  ANSES, Box Custodia, Digilogix, Encode, Lakaut, Banelco y Train Solutions en CA.
- Inno no propaga el resultado de `certutil`: el script verifica las dos AC Raíz por thumbprint.
- **La AC Raíz 2007 vence el 2027-11-17.**

## Drivers de token

| Driver | Modelos | Origen | En Programas y características |
| --- | --- | --- | --- |
| SafeNet Authentication Client 10.8.259.0 | eToken 5110, 5110+ | MSI x64 y licencia extraídos sin modificar de `WINDOWS - SafeNet5110+-SAC_10_8.exe` (SITEPRO S.A.) | `SafeNet Authentication Client 10.8` |
| Feitian ePass2003 1.1.22.831 | ePass2003 | Instalador NSIS firmado por Feitian | `ePass2003` |
| Longmai mToken CryptoID 2.2.26.324 | mToken FIPS 140-3 | Instalador Inno firmado por Century Longmai | `LMCryptoIDE versión 2.2.26.324` |

- SafeNet 10.8 reconoce eToken 5110 FIPS/CC y 5300 (igual que la 10.5) **más IDPrime 930, el chip del
  5110+**, que la 10.5 no reconoce. Las dos comparten UpgradeCode: la 10.8 reemplaza a la 10.5.
- **Licencia SafeNet**: el `.txt` de SITEPRO figura a nombre del *Colegio de Abogados de la Provincia de Buenos
  Aires* (1 puesto). Se usa por decisión del área porque es lo que entregó el proveedor; conviene regularizarla.
- Longmai agrega `CryptoIDEMon.exe` al inicio de Windows para todos los usuarios.

## Extensiones de los navegadores

| Navegador | Extensión | Origen | Directiva |
| --- | --- | --- | --- |
| Chrome | "Firma con Token GDE" `maddemndndajaiilmnjoocajgkpmlael` | Chrome Web Store (2.0.1) | `HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist` |
| Edge | la misma (no está en la tienda de Edge) | Chrome Web Store | `HKLM\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist` |
| Firefox | "Firma con token GDE" `firma.token@gde.gob.ar` | addons.mozilla.org (3.2.0) | `HKLM\SOFTWARE\Policies\Mozilla\Firefox` → `ExtensionSettings` |

- Son los IDs que acepta el host del token (`allowed_origins` de `cnmtoken.json`, `allowed_extensions` de
  `main.json`). De los cuatro IDs de Chrome que admite el MSI, solo este está publicado.
- El instalador agrega solo su entrada: si ya hay otras extensiones forzadas, las respeta. La desinstalación
  quita solo esa entrada.
- Se ve en `chrome://policy`, `edge://policy` y `about:policies`.
- **A verificar:** en PCs fuera de un dominio, Edge podría no aceptar la instalación forzada de una extensión
  de la Chrome Web Store.

## Firma digital del `.exe` (pendiente)

Hoy se publica sin firmar: SmartScreen (solo en archivos descargados) y UAC muestran "Editor desconocido".

- **Gratis, válido en el dominio**: certificado de firma de código propio (CA interna o autofirmado)
  distribuido por GPO a "Entidades raíz de confianza" y "Editores de confianza".
- **Pago, válido en cualquier PC**: certificado OV a nombre de la Secretaría (Certum OV en la nube, el más
  económico; comparar con Sectigo). Se agregaría al build: `signtool sign /fd SHA256 /tr <timestamp> /td SHA256`.
- No sirven: el token de firma digital (AC ONTI/Modernización, no es de firma de código), Let's Encrypt, ni
  SignPath Foundation (exige proyecto open source; el paquete lleva software de terceros).
