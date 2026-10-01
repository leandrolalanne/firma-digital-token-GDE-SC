# Mudanza del proyecto a Windows

Hasta acá el proyecto se desarrolló en Linux. Lo que queda **solo se puede hacer en
Windows**: empaquetar todo en un único archivo y validar lo que no se pudo probar.

## Por qué se muda

Dos cosas pendientes necesitan Windows sí o sí:

1. **El paquete único.** Se pidió un solo archivo (`.exe` u otra extensión) con todo
   adentro. Las herramientas que lo hacen bien (IExpress, WiX Burn, PS2EXE, el SFX de
   7-Zip) son de Windows. Se puede forzar la construcción desde Linux concatenando
   módulos SFX, pero sale un `.exe` sin firmar, armado a mano, que es exactamente lo
   que un antivirus marca — mala idea para 500 máquinas de gobierno.
2. **La validación.** Todo lo que toca el registro de Windows y `msiexec` está sin
   probar en real. Ver `PRUEBAS.md`.

## Qué llevar

Copiar la carpeta completa del proyecto. Lo imprescindible:

```
Deploy-TokenService.ps1     el script, ya probado en lo que se pudo
Instalar.bat                lanzador con elevación
token-service_v4.msi        el paquete
README.md                   uso y despliegue
PRUEBAS.md                  qué está validado y qué no
MIGRAR-A-WINDOWS.md         este archivo
PSADT/                      variante PSAppDeployToolkit (opcional)
```

Los `.ps1` y el `.bat` ya están en **ASCII puro con finales de línea CRLF**, así que se
abren bien en cualquier editor de Windows y no dependen de la codificación del equipo.

## Preparar la máquina Windows

```powershell
# Ver versión de PowerShell (el script apunta a 5.1, que viene de fábrica)
$PSVersionTable.PSVersion

# Permitir ejecución solo en esta sesión, sin tocar la política de la máquina
Set-ExecutionPolicy -Scope Process -Bypass

# Si los archivos vinieron por red o descarga, quitarles la marca de bloqueo
Get-ChildItem -Recurse | Unblock-File
```

Verificar que el script parsea antes de nada:

```powershell
$e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    "$PWD\Deploy-TokenService.ps1", [ref]$null, [ref]$e)
if ($e) { $e } else { 'SINTAXIS OK' }
```

---

## Paso 1 — Validar antes de empaquetar

**No empaquetar nada hasta que el script funcione.** Empaquetar primero solo hace más
lento cada ciclo de prueba.

Seguir el plan de `PRUEBAS.md`. El resumen:

1. VM limpia → `.\Deploy-TokenService.ps1 -DryRun` → no detecta nada, sale 0.
2. Instalar una versión vieja → `-DryRun` → **confirmar que la detecta** y leer la
   línea `coincide por ...`.
3. `.\Deploy-TokenService.ps1 -NoReboot` → revisar appwiz.cpl, las claves HKLM y el log.
4. Correr de nuevo → debe salir 0 (idempotencia).
5. **Firmar de verdad** con un usuario común, no admin, en Chrome y en Firefox.

Las claves que tienen que existir después del paso 3:

```powershell
'SOFTWARE\Google\Chrome\NativeMessagingHosts\gcbatoken',
'SOFTWARE\Mozilla\NativeMessagingHosts\gcbatoken' | ForEach-Object {
    foreach ($view in 'Registry64','Registry32') {
        $b = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', $view)
        $k = $b.OpenSubKey($_)
        '{0,-10} {1} = {2}' -f $view, $_, $(if ($k) { $k.GetValue('') } else { 'FALTA' })
    }
}
```

---

## Paso 2 — Empaquetar en un solo archivo

Cuatro caminos. Elegir uno según cómo se vaya a distribuir.

### Opción A — Intune: `.intunewin` (si despliegan por Intune)

Es la respuesta correcta si el parque está en Intune. Un solo archivo, formato nativo,
sin problemas de firma ni de antivirus.

```powershell
# Descargar Microsoft-Win32-Content-Prep-Tool desde GitHub (Microsoft oficial)
.\IntuneWinAppUtil.exe -c C:\Paquetes\TokenService -s Deploy-TokenService.ps1 -o C:\Salida
```

En Intune, como Win32 app:

- **Install command:** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File Deploy-TokenService.ps1`
- **Uninstall command:** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File Deploy-TokenService.ps1 -DryRun`
  (ver nota abajo: falta un modo desinstalar)
- **Install behavior:** System
- **Return codes:** 0 y 3010 = éxito. Agregar 69001–69005 como *failed*.

### Opción B — IExpress: `.exe` sin instalar nada

`iexpress.exe` viene en todo Windows. Es lo más rápido para tener un `.exe` hoy.

```
iexpress.exe
```

En el asistente:

1. *Create new Self Extraction Directive file*
2. *Extract files and run an installation command*
3. **Install Program:** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File Deploy-TokenService.ps1`
4. Agregar `Deploy-TokenService.ps1` y `token-service_v4.msi`
5. *Hidden* (sin ventana), *No message*, *No restart* — el reinicio lo maneja el script
6. Guardar el `.SED` junto al proyecto para poder regenerar el `.exe` sin rehacer el asistente

Limitación: IExpress es de 32 bits y extrae a una carpeta temporal. El script ya resuelve
rutas relativas a sí mismo, así que funciona, pero conviene confirmarlo en la prueba.

### Opción C — SFX de 7-Zip: `.exe` con más control

Con 7-Zip instalado:

```powershell
# 1. Armar el archivo con los dos archivos necesarios
& 'C:\Program Files\7-Zip\7z.exe' a -t7z payload.7z Deploy-TokenService.ps1 token-service_v4.msi

# 2. config.txt (guardar en UTF-8)
@'
;!@Install@!UTF-8!
Title="Firma Digital - Token Service"
RunProgram="powershell.exe -NoProfile -ExecutionPolicy Bypass -File Deploy-TokenService.ps1"
GUIMode="2"
;!@InstallEnd@!
'@ | Set-Content -Encoding UTF8 config.txt

# 3. Concatenar modulo SFX + config + archivo
cmd /c copy /b "C:\Program Files\7-Zip\7zSD.sfx" + config.txt + payload.7z TokenService-Deploy.exe
```

`7zSD.sfx` viene con la instalación de 7-Zip. Si no está, bajar el paquete *7-Zip Extra*
de la versión que corresponda.

### Opción D — WiX Burn: `.exe` bootstrapper (la solución de fondo)

Es lo correcto a nivel empresa: maneja elevación, encadena MSI de forma nativa, genera
un log propio y se puede firmar. Requiere instalar el WiX Toolset y escribir un
`Bundle.wxs`. Más trabajo, pero es lo que un paquete de gobierno debería ser.

Vale especialmente la pena si terminan **recompilando el MSI** (ver punto 1 de
`README.md`), porque en ese caso el bootstrapper puede reemplazar al script entero.

---

## Paso 3 — Firmar el ejecutable

**Esto no es opcional para 500 máquinas de gobierno.** Un `.exe` sin firmar que extrae
archivos y los ejecuta es el patrón exacto que marcan SmartScreen y los antivirus.

```powershell
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
    /f certificado.pfx /p <clave> TokenService-Deploy.exe
```

Si Modernización ya tiene un certificado de firma de código, usarlo. Si no, las
alternativas son:

- Desplegar por GPO/SCCM/Intune desde un share de confianza y **excluir la ruta en el
  antivirus** por política.
- Saltear el `.exe` y desplegar los archivos sueltos desde el share, que es lo que ya
  funciona hoy sin empaquetar nada.

> Vale la pena preguntarse si el paquete único hace falta. Si el despliegue va por
> GPO/SCCM/Intune, esas tres herramientas copian la carpeta entera solas y el `.exe`
> no agrega nada — solo suma el problema de la firma. El archivo único gana cuando
> alguien tiene que instalar **a mano**, máquina por máquina.

---

## Pendientes de código

Cosas que quedaron sin hacer y conviene resolver ya en Windows:

- [ ] **Modo desinstalar.** El script hoy solo reemplaza. Para Intune/SCCM hace falta
      un `-Uninstall` que desinstale y borre las claves HKLM. Es media hora de trabajo.
- [ ] **Portar la Fase 5 a la variante PSADT.** `PSADT/Invoke-AppDeployToolkit.ps1` hace
      desinstalar + instalar pero **no registra HKLM**. Si usan esa vía, le falta eso.
- [ ] **Edge.** El MSI registra Chrome y Firefox nada más. Si en el parque se firma con
      Edge, agregar `SOFTWARE\Microsoft\Edge\NativeMessagingHosts\gcbatoken` a
      `$NmhEntradas` en el script.
- [ ] **Limpiar claves HKCU viejas.** Las que dejó el MSI anterior en perfiles de usuario
      no se borran. Son inofensivas mientras apunten a la carpeta que existe.

## Pendientes con el MSI

No son del script, son del paquete. Ver `README.md`:

- [ ] Recompilar sin licencia *trial* de Advanced Installer (hoy dice
      `(Evaluation Installer)` en appwiz.cpl).
- [ ] Decidir si se corrige el branding (`Catamarca` / `GCBA` en un despliegue de Santa Cruz).
- [ ] Idealmente, cambiar el registro del native messaging host de `HKCU` a `HKLM`
      dentro del MSI. Eso dejaría el MSI autosuficiente y la Fase 5 del script sobraría.
