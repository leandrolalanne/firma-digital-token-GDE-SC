# Firma Digital / Token Service — reemplazo masivo de MSI (v2)

Desinstala toda versión previa del token de firma digital, instala lo que el firmador necesita
(Java 8 y los certificados de las AC de Firma Digital de Argentina), instala
`token-service_v4.msi`, con log, y reinicia el equipo.

> La v1 (solo el token) está en el repositorio `instalador-msi`, etiqueta `v1.0.0`.

## Instalador de un solo archivo (vía actual)

**`Salida\FirmaDigital-Instalador.exe`**: un único archivo de unos 74 MB. Se le da doble clic y
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
   - instala `token-service_v4.msi` y verifica que quede registrado;
   - registra el host de mensajería nativa en HKLM (Chrome y Firefox, 64 y 32 bits).
4. Muestra la ventana de reinicio: **cuenta regresiva de 60 s**, botón "Reiniciar ahora";
   al llegar a cero reinicia aunque nadie toque nada.

Si algo falla, aparece un cartel de error y el detalle queda en `C:\Windows\Logs\Software\`.

Las ventanas muestran el isotipo de Modernización y el subtítulo "Secretaría de Estado de
Modernización de Santa Cruz" (`Toolkit.CompanyName` en `Certificados/Config/config.psd1`). Los
logos salen de `logo/isotipo-blanco.png`: `Assets/Isotipo-Modernizacion-Blanco.png` para Windows
en tema oscuro y `Assets/Isotipo-Modernizacion.png` (gris oscuro) para tema claro, porque el
blanco no se vería sobre fondo claro.

Cómo está armado:

| Pieza | Qué es |
| --- | --- |
| `Certificados/` | Paquete PSAppDeployToolkit 4.1.8. La lógica está en `Invoke-AppDeployToolkit.ps1`. |
| `Empaquetado/Build-Instalador.ps1` | Genera el `.exe`: comprime `Certificados/` + `Lanzar.ps1` y lo pega a `7zSD.sfx` con un manifiesto `requireAdministrator`. |
| `Empaquetado/Lanzar.ps1` | Lo que ejecuta el `.exe` después de extraer: lanza el asistente y espera a que cierre la ventana de reinicio (si no, el SFX borraría la carpeta temporal antes de tiempo). |

Regenerar el `.exe` después de cambiar algo (requiere 7-Zip instalado):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Empaquetado\Build-Instalador.ps1
```

Para GPO / Intune / SCCM no hace falta el `.exe`: distribuir la carpeta `Certificados/` y ejecutar
`Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent` (no reinicia, devuelve 3010).

---

> **Lo que sigue documenta la versión anterior** (`Deploy-TokenService.ps1` + `Instalar.bat`),
> hecha en Linux antes de pasar a PSADT. Queda como referencia; el patrón de detección y el
> paquete vigentes son los de arriba. Las notas sobre el MSI (HKCU, licencia trial, branding)
> siguen valiendo.

## Archivos

| Archivo | Para qué |
| --- | --- |
| `Deploy-TokenService.ps1` | Script principal. Autosuficiente, sin dependencias. |
| `Instalar.bat` | Doble clic → UAC → ejecuta el script. Para instalación a mano. |
| `token-service_v4.msi` | El paquete a instalar. |
| `PSADT/Invoke-AppDeployToolkit.ps1` | Variante PSAppDeployToolkit v4 (ver más abajo). |
| `MIGRAR-A-WINDOWS.md` | Cómo seguir en Windows: empaquetar en un archivo único y validar. |
| `PRUEBAS.md` | Qué está validado y qué no. |

Los `.ps1` y el `.bat` están en **ASCII puro con finales de línea CRLF**: se abren bien
en cualquier editor de Windows y no dependen de la codificación del equipo. Windows
PowerShell 5.1 lee los `.ps1` sin BOM como ANSI, no como UTF-8, y por eso no llevan
ningún carácter acentuado.

## Uso

Los tres archivos de la tabla tienen que viajar juntos en la misma carpeta.

```powershell
# 1. Primero SIEMPRE en una máquina de prueba: solo reporta, no toca nada
.\Deploy-TokenService.ps1 -DryRun

# 2. Despliegue real (desinstala, instala, reinicia a los 60s)
.\Deploy-TokenService.ps1

# 3. Igual pero sin reiniciar
.\Deploy-TokenService.ps1 -NoReboot

# 4. Cancelar un reinicio ya lanzado
shutdown /a
```

Logs: `C:\Windows\Logs\Software\TokenService-*.log` (cae a `%TEMP%` si no hay permiso).

### Parámetros

| Parámetro | Default | Para qué |
| --- | --- | --- |
| `-DryRun` | — | Detecta y reporta. No desinstala, no instala, no reinicia. |
| `-NoReboot` | — | Hace todo pero no reinicia. |
| `-RebootDelay` | `60` | Segundos antes del reinicio. |
| `-MsiPath` | autodetecta | Ruta a otro MSI. |
| `-DisplayNamePattern` | `Firma Digital\|tokensign\|token.?service` | Regex contra `DisplayName` de appwiz.cpl. |
| `-LogDir` | `C:\Windows\Logs\Software` | Carpeta de logs. |

## Despliegue en las 500 máquinas

**No hay forma legítima de suprimir UAC desde el script.** La solución para volumen
es no pasar por UAC: ejecutar en contexto SYSTEM, que ya es administrador.

| Vía | Cómo | UAC |
| --- | --- | --- |
| **GPO** | Computer Config → Windows Settings → Scripts → **Startup** → `Instalar.bat` | No aparece |
| **SCCM** | Programa: `powershell.exe -ExecutionPolicy Bypass -File Deploy-TokenService.ps1`, "Run with administrative rights" | No aparece |
| **Intune** | Win32 app, install command igual al de SCCM, contexto **System** | No aparece |
| **PsExec** | `psexec \\PC -s -h powershell -ExecutionPolicy Bypass -File \\srv\share\Deploy-TokenService.ps1` | No aparece |
| **A mano** | Doble clic en `Instalar.bat` | Un prompt |

El script se autoeleva por UAC solo si lo ejecutan sin privilegios; en contexto
SYSTEM ese camino no se usa. `-ExecutionPolicy Bypass` resuelve la política de
ejecución sin tocar la configuración de la máquina, y el MSI se desmarca con
`Unblock-File` por si quedó con marca de "descargado de internet".

### Códigos de salida

| Código | Significado |
| --- | --- |
| 0 | OK |
| 3010 | OK, requiere reinicio |
| 69001 | No se encontró el MSI |
| 69002 | Falló la desinstalación, o quedó una versión previa |
| 69003 | Falló la instalación, o no quedó registrada |
| 69004 | No se pudieron obtener privilegios de administrador |
| 69005 | No se pudo registrar el host de mensajería nativa en HKLM |

En GPO/SCCM/Intune, tratar 0 y 3010 como éxito y cualquier valor ≥ 69000 como fallo.

---

## ⚠️ Tres cosas del MSI

Salieron de inspeccionar `token-service_v4.msi` directamente. Ninguna es un problema
del script: son propiedades del MSI. La primera está resuelta desde el script; las
otras dos necesitan que alguien toque el MSI.

### 1. El MSI escribe en HKCU — RESUELTO en el script

El MSI registra el *native messaging host* de Chrome y Firefox en `HKCU`, o sea en
el hive del usuario **que ejecuta el instalador**:

```
HKCU\Software\Google\Chrome\NativeMessagingHosts\gcbatoken   -> cnmtoken.json
HKCU\Software\Mozilla\NativeMessagingHosts\gcbatoken          -> main.json
```

Desplegado en contexto SYSTEM (GPO/SCCM/Intune) esas claves caen en el hive de
SYSTEM: el MSI reporta éxito, aparece en appwiz.cpl, los archivos quedan en disco
**y la firma digital no funciona para ningún usuario**. Sería un fallo silencioso
y simultáneo en las 500 máquinas.

**Solución aplicada (Fase 5 del script):** después de instalar, el script escribe
las mismas dos claves en `HKLM`, que Chrome y Firefox también leen. Una sola
escritura sirve para todos los usuarios del equipo, funciona igual en contexto
SYSTEM, y no depende de un logon script ni de Active Setup ni de que el usuario
vuelva a iniciar sesión.

```
HKLM\SOFTWARE\Google\Chrome\NativeMessagingHosts\gcbatoken
HKLM\SOFTWARE\Mozilla\NativeMessagingHosts\gcbatoken
```

Detalles de la implementación:

- Se escribe en **las dos vistas del registro** (`Registry64` y `Registry32`),
  porque un navegador de 64 bits lee `SOFTWARE\...` y uno de 32 bits lee
  `SOFTWARE\WOW6432Node\...`.
- La carpeta de instalación **no se hardcodea**: se toma del `InstallLocation` que
  dejó el MSI y, si no está, se sondean `%ProgramFiles(x86)%` y `%ProgramFiles%`
  buscando los `.json`. Importa porque el MSI es de 32 bits y en Windows x64
  instala en `Program Files (x86)`, no en `Program Files`.
- Después de escribir, **se verifica leyendo de vuelta** que el valor apunte a un
  archivo que existe. Si falla, el script corta con 69005 y no reinicia.

Queda un detalle menor: las claves `HKCU` que el MSI viejo haya dejado en el perfil
de algún usuario no se borran. Como apuntan a la misma carpeta de instalación, son
inofensivas. Si en alguna máquina quedaran apuntando a una ruta que ya no existe,
hay que borrarlas a mano en ese perfil.

> Esto cubre Chrome y Firefox, que es lo que registra el MSI. **Edge no está
> contemplado** (usaría `SOFTWARE\Microsoft\Edge\NativeMessagingHosts\`). Si en el
> parque se usa Edge para firmar, decímelo y lo agrego.

### 2. El MSI está compilado con una licencia *trial* de Advanced Installer

```
ARPCOMMENTS       " (Evaluation Installer)"
AI_TRIAL_MESSAGE  "This package was created with a trial version of Advanced Installer..."
CreatingApp       "GDE Firma Digital Service Firefox Catamarca (Evaluation Installer)"
```

En `/qn` no debería mostrar el cartel de evaluación, pero va a quedar
`(Evaluation Installer)` visible en Programas y características de las 500
máquinas. Conviene conseguir el MSI recompilado con licencia antes del rollout.

### 3. El branding no coincide con Santa Cruz

| Campo | Valor real en el MSI |
| --- | --- |
| ProductName | `GDE Firma Digital Service Firefox Catamarca` |
| Carpeta de instalación | `C:\Program Files (x86)\GCBA Firma Digital` |
| Clave de registro | `...\NativeMessagingHosts\gcbatoken` |
| ProductVersion | `2.0.0` (el archivo se llama `v4`) |
| UpgradeCode | `{00000001-0001-0001-0001-000000000001}` ← placeholder de Advanced Installer |

Es una cadena de rebrands GCBA → Catamarca. Funcionar va a funcionar, pero los
usuarios van a ver "Catamarca" en appwiz.cpl. Y el `UpgradeCode` es el placeholder
por defecto de Advanced Installer, así que **no sirve para detectar versiones
previas** (podría colisionar con cualquier otro MSI trial). Por eso el script
detecta por `DisplayName` y no por `UpgradeCode`.

### Qué se desinstala

El script desinstala **cualquier paquete que "diga" token-service**, no solo los que
lo lleven en el nombre visible. Para cada entrada de appwiz.cpl compara el patrón
contra cuatro campos, en este orden:

1. `DisplayName` — el nombre que se ve en Programas y características
2. `InstallLocation` — la carpeta donde se instaló
3. `DisplayIcon` — la ruta del ejecutable o ícono
4. `UninstallString` — el comando de desinstalación

Alcanza con que **uno** coincida. Así cae también un paquete renombrado que se
instaló en `...\token-service\` o cuyo desinstalador referencia el MSI.

El log dice siempre **por qué** matcheó cada entrada:

```
  - Componente de seguridad | version 1.5.0 | {BBBB...} | HKCU
      coincide por InstallLocation: C:\token-service\
```

> Correr `-DryRun` en 2 o 3 máquinas representativas y **leer esa línea** antes del
> rollout. Si aparece algo que no corresponde desinstalar, ajustar
> `-DisplayNamePattern`. El patrón por defecto es
> `Firma Digital|tokensign|token.?service`, que cubre `token-service`,
> `token service`, `tokenservice` y `token_service`.

---

## Variante PSAppDeployToolkit

`PSADT/Invoke-AppDeployToolkit.ps1` cumple el `AGENTS.md`: toda la lógica en las
fases, solo funciones ADT (`Get-ADTApplication`, `Uninstall-ADTApplication`,
`Start-ADTMsiProcess`, `Write-ADTLogEntry`), sin `msiexec` directo y sin
`Win32_Product`.

No la podés usar tal cual todavía: falta el módulo, que se genera en Windows.

```powershell
Install-Module -Name PSAppDeployToolkit -Scope CurrentUser
Import-Module PSAppDeployToolkit
New-ADTTemplate -Destination 'C:\Paquetes' -Name 'Certificados'

# luego:
#   copiar PSADT\Invoke-AppDeployToolkit.ps1 sobre el del template
#   copiar token-service_v4.msi a C:\Paquetes\Certificados\Files\
```

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Silent -AllowRebootPassThru
```

Esta variante **no reinicia por sí sola**: devuelve 3010 y deja el reinicio al
sistema de despliegue, que es la regla 6 del `AGENTS.md`. El reinicio automático
que pediste está en `Deploy-TokenService.ps1`.

## Paquete en un solo archivo

Pedido pero **todavía no hecho**: hace falta Windows. `MIGRAR-A-WINDOWS.md` tiene los
cuatro caminos (Intune `.intunewin`, IExpress, SFX de 7-Zip, WiX Burn), cuál conviene
según cómo distribuyan, y el tema de la firma del ejecutable.

Se puede armar un `.exe` desde Linux concatenando un módulo SFX a mano, pero sale sin
firmar y con la pinta exacta de lo que marcan SmartScreen y los antivirus. Para 500
máquinas de gobierno no vale la pena el riesgo: se hace en Windows y se firma.

> Antes de empaquetar, conviene preguntarse si hace falta. Si el despliegue va por
> GPO/SCCM/Intune, esas herramientas copian la carpeta entera solas y el archivo único
> no agrega nada. Gana cuando hay que instalar **a mano**, máquina por máquina.

## Qué falta probar

Lo que se validó y lo que no está en `PRUEBAS.md`. El plan de validación en Windows
está en `MIGRAR-A-WINDOWS.md`.
