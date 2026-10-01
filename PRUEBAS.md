# Estado de pruebas

> **El proyecto se muda a Windows.** Esta es la foto de lo que quedó validado desde
> Linux. La lista de "SIN PROBAR" de más abajo es el trabajo a hacer allá; los pasos
> concretos están en `MIGRAR-A-WINDOWS.md`.

## Entorno

El desarrollo se hizo en Linux. **No hubo ninguna máquina Windows en el circuito**,
así que todo lo que toca el registro de Windows y `msiexec` está sin probar en real.
Lo que sigue distingue una cosa de la otra.

Se usó PowerShell 7.4.6 portable para parsear y ejecutar. El script está escrito
para Windows PowerShell 5.1 (sin sintaxis exclusiva de 7.x).

Qué significa esto en la práctica: la **lógica de decisión** está probada (qué se
desinstala, cómo se resuelven las rutas, qué código de salida sale en cada caso), y
el **acceso al sistema** no (leer el registro, escribirlo, llamar a `msiexec`, elevar
por UAC, reiniciar). Esas son las funciones que hay que validar primero en Windows.

## Probado y verde

### Sintaxis
`Deploy-TokenService.ps1` y `PSADT/Invoke-AppDeployToolkit.ps1` parsean sin errores.

### Unitario — 43 asserts, todos OK

| Qué | Resultado |
| --- | --- |
| `Test-MsiSuccess`: 0, 3010, 1641, 1605 → éxito; 1603, 1618 → fallo | OK |
| `Get-MsiExitDescription` para códigos conocidos y desconocidos | OK |
| `Initialize-Log` con directorio que **existe pero no es escribible** → cae a `%TEMP%` | OK |
| `Initialize-Log` con directorio nuevo → lo crea y escribe | OK |
| `Resolve-MsiPath`: junto al script / en `Files\` / `-MsiPath` explícito / errores | OK |

**`Get-MatchedField` — "cualquier MSI que diga token-service"** (22 asserts):

| Caso | Resultado |
| --- | --- |
| `token-service`, `token service`, `tokenservice`, `token_service` | matchea |
| `Token-Service`, `TOKEN-SERVICE v4`, `token-service_v4` | matchea (case-insensitive) |
| `GDE Firma Digital Service Firefox Catamarca`, `GCBA Firma Digital` | matchea |
| DisplayName inocuo pero `InstallLocation = C:\token-service\` | matchea por InstallLocation |
| DisplayName inocuo pero `DisplayIcon = ...\tokensign.exe` | matchea por DisplayIcon |
| DisplayName inocuo pero UninstallString referencia el MSI | matchea por UninstallString |
| Precedencia: DisplayName gana sobre los otros campos al reportar | OK |
| Chrome, Firefox, Edge, Acrobat, 7-Zip, Java, Office, AnyDesk | **no** matchea |

**`Resolve-InstallDirectory`** (5 asserts): usa `InstallLocation` si es válido;
lo ignora si no existe y sondea `%ProgramFiles(x86)%` antes que `%ProgramFiles%`;
devuelve `$null` si no encuentra nada; limpia la barra final.

### End-to-end con `msiexec` y el registro stubbeados — 11 escenarios

| Escenario | Esperado | Resultado |
| --- | --- | --- |
| 2 versiones previas (una detectada por nombre, otra por carpeta) → desinstala ambas, instala, registra HKLM, reinicia | 0 | OK |
| Sin versión previa → instala directo | 0 | OK |
| `-DryRun` → reporta y dice **por qué** matcheó cada entrada, no ejecuta nada | 0 | OK |
| `-NoReboot` → hace todo, no reinicia | 0 | OK |
| Falla la desinstalación (msiexec 1603) | 69002 | OK |
| Desinstala OK pero queda residuo en appwiz | 69002 | OK |
| Falla la instalación (msiexec 1603) | 69003 | OK |
| Instala OK pero no queda registrada | 69003 | OK |
| **No se puede ubicar la carpeta de instalación** | 69005 | OK |
| **No se escribe ninguna clave de mensajería nativa** | 69005 | OK |
| **Se escriben las claves pero la verificación de lectura falla** | 69005 | OK |
| Instalación devuelve 3010 | 3010 | OK |
| MSI inexistente / carpeta sin MSI | 69001 | OK |

Líneas de comando verificadas:

```
msiexec.exe /x {GUID} /qn /norestart /l*v "<log>"
msiexec.exe /i "<ruta>.msi" /qn /norestart ALLUSERS=1 REBOOT=ReallySuppress /l*v "<log>"
```

### Bugs encontrados y corregidos durante las pruebas
1. `Initialize-Log` corría antes del chequeo de elevación y explotaba al no poder crear
   `C:\Windows\Logs\Software` sin admin, en vez de pedir UAC.
2. El `catch` del log no disparaba si el directorio ya existía pero no era escribible
   → el despliegue habría corrido **sin log** en las 500 máquinas. Reemplazado por una
   prueba de escritura real.
3. `Split-Path -Parent $PSCommandPath` fallaba con mensaje inútil si el script se
   ejecutaba dot-sourced. Ruta y raíz se capturan a nivel script.
4. El código 69001 (MSI no encontrado) nunca se usaba: caía en el `catch` genérico.

## SIN PROBAR — hay que validarlo en Windows

- [ ] `Get-InstalledMatch` contra el registro real (`OpenBaseKey` con vistas
      Registry64/Registry32/HKCU). **Es la función crítica sin probar**: de ella depende
      qué se desinstala. La lógica de decisión (`Get-MatchedField`) sí está probada;
      lo que falta es la lectura del registro que la alimenta.
- [ ] `Register-NativeMessagingHost` y `Test-NativeMessagingHost` contra el registro real.
      En las pruebas se simularon con un hashtable.
- [ ] Que Chrome y Firefox **efectivamente** levanten el host desde HKLM en las versiones
      que corren en el parque.
- [ ] Que el patrón matchee lo que está instalado en el parque real.
- [ ] La autoelevación por UAC y el paso de parámetros al relanzar.
- [ ] `msiexec` real: desinstalación e instalación.
- [ ] Que los códigos de salida lleguen enteros a GPO/SCCM/Intune (en Windows son de
      32 bits; en Linux se truncan a 8 y por eso los tests muestran 137/138/139/141/194).
- [ ] `Unblock-File` sobre el MSI y el reinicio vía `shutdown /r`.
- [ ] La variante PSADT — necesita `New-ADTTemplate`, que solo corre en Windows.

> La variante PSADT **no registra HKLM**: solo hace desinstalar + instalar. Si terminan
> usando esa, hay que portarle la Fase 5.

## Cómo correr estas pruebas en Windows

La suite se escribió para PowerShell portable en Linux. En Windows se corre igual:
carga las funciones del script por AST, sin ejecutar el `main`.

```powershell
$src = ".\Deploy-TokenService.ps1"
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
$ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
    ForEach-Object { . ([scriptblock]::Create($_.Extent.Text)) }

# ahora se pueden probar las funciones sueltas, por ejemplo:
Get-MatchedField -Pattern 'Firma Digital|tokensign|token.?service' -DisplayName 'token-service'
Get-InstalledMatch -Pattern 'Firma Digital|tokensign|token.?service' | Format-Table
```

La segunda línea es la que **no** se pudo correr desde Linux. Es la primera que hay
que mirar al llegar a Windows.

## Plan de validación sugerido

1. VM Windows 10/11 limpia → `-DryRun` → no detecta nada, sale 0.
2. Instalar una versión vieja → `-DryRun` → **confirmar que la detecta y leer la línea
   "coincide por ..."**. Este paso valida la función crítica.
3. `-NoReboot` → verificar appwiz.cpl (una sola entrada, versión nueva), que existan
   las claves en `HKLM\SOFTWARE\{Google\Chrome,Mozilla}\NativeMessagingHosts\gcbatoken`
   y en su equivalente bajo `WOW6432Node`, y el log sin errores.
4. Correr de nuevo sobre lo ya instalado → debe salir 0 (idempotencia).
5. **Firmar de verdad** con un usuario común (no admin) en Chrome y en Firefox. Es el
   único paso que prueba que el arreglo de HKLM sirvió.
6. Piloto en 5–10 máquinas por la vía de despliegue elegida.

Los criterios de aceptación del `AGENTS.md` siguen sin tildar hasta el paso 5.
