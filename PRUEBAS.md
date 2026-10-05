# Pruebas

Qué se probó en cada versión. Criterios de aceptación en `AGENTS.md`; logs en `C:\Windows\Logs\Software\`.
Equipo de prueba: `NOTEBOOK-SEMIT`, Windows 11 Pro (build 26200), x64; ejecución con doble clic en el `.exe`
(modo interactivo) aceptando UAC.

## 4.0.0 — pre-release, falta probar en una PC

Verificado sin instalar:

| Fecha | Qué | Resultado |
| --- | --- | --- |
| 2026-10-05 | Sintaxis de `build.ps1`, `Invoke-AppDeployToolkit.ps1` y `Lanzar.ps1` (ASCII puro) | OK |
| 2026-10-05 | `build.ps1` con las cuatro capas | OK, salida 0. Cada paquete lleva solo sus instaladores y su `Variante.psd1`; manifiesto `requireAdministrator` |
| 2026-10-05 | `build.ps1` con una capa inexistente | Error en esa capa, salida **1** |
| 2026-10-05 | Paquete sin `Variante.psd1` | Corta con **69010** |
| 2026-10-05 | Paquete armado ejecutado sin administrador | Lee la variante y la versión; corta en el chequeo de administrador (60008) |
| 2026-10-05 | Extensiones: IDs en las tiendas | Chrome Web Store: `maddemndndajaiilmnjoocajgkpmlael` = "Firma con Token GDE (Sistema de Gestión Documental)" 2.0.1 (los otros 3 IDs de `cnmtoken.json` no están publicados). addons.mozilla.org: `firma.token@gde.gob.ar` = "Firma con token GDE" 3.2.0. Tienda de Edge: no está |
| 2026-10-05 | URL de Firefox `.../firma-con-token-gde/latest.xpi` | HTTP 200, `application/x-xpinstall` → `firma_con_token_gde-3.2.0.xpi` |
| 2026-10-05 | Directivas de extensiones con registro simulado | Sin directivas: crea las entradas. 2.ª corrida: saltea. Con otras extensiones forzadas: usa el primer número libre y fusiona el JSON de Firefox. Uninstall: quita solo las propias. JSON de Firefox dañado: no lo toca, sale **69011** |
| 2026-10-05 | `build/release.yml` con actionlint; paso de notas ejecutado localmente | 0 errores; notas = sección [4.0.0] del CHANGELOG + SHA-256 |

Falta (criterios de aceptación de la 4.0.0):

- [ ] Activar `build/release.yml` y verificar un release generado por GitHub Actions.
- [ ] PC con versión previa del token y PC sin nada; 2.ª corrida seguida.
- [ ] Extensiones visibles y forzadas en Chrome, Edge y Firefox (`chrome://policy`, `edge://policy`, `about:policies`).
- [ ] Edge en una PC fuera de dominio.
- [ ] Firma real en GDE desde los tres navegadores.

## 3.0.0 — probada

| Fecha y hora | Estado previo | Resultado | Salida |
| --- | --- | --- | --- |
| 2026-10-01 12:48 | Sin token, sin Java, sin drivers | Instaló Java 8u503, certificados (AC Raíz verificadas), SafeNet 10.8, ePass2003, LMCryptoIDE y el token, en 72 s | 3010 |

- Log sin entradas de severidad 2 ni 3. Sin ventanas que pidieran clics.
- Nombres en Programas y características: `SafeNet Authentication Client 10.8` (10.8.259.0), `ePass2003`
  (1.1.22.831), `LMCryptoIDE versión 2.2.26.324` (clave `{F72BDB06-...}_is1`).
- Antes, sin instalar: detección de drivers con casos simulados (igual/mayor saltea, menor actualiza, versión
  ilegible = instalado). SafeNet 10.8 reconoce IDPrime 930 (eToken 5110+), la 10.5 no.

## 2.0.0 — probada

| Fecha y hora | Estado previo | Resultado | Salida |
| --- | --- | --- | --- |
| 2026-10-01 11:52 | Token y Java 8u503 instalados | Desinstaló el token, salteó Java, certificados y AC Raíz verificadas, instaló el token | 3010 |
| 2026-10-01 12:11 | Sin token, sin Java | Instaló Java 8u503, certificados y el token | 3010 |

- Log sin entradas de severidad 2 ni 3. AC Raíz verificadas: `D774180508C65136B80130B6AF0F002B131FD76B`
  (2007) y `887A1FE63A485392EA5F1526670ABC81E20009AD` (2016).
- El instalador de Oracle deja también `Java Auto Updater`.

## 1.0.0 — probada

| Fecha y hora | Estado previo | Resultado | Salida |
| --- | --- | --- | --- |
| 2026-10-01 10:39 | `GDE Firma Digital Service Firefox Catamarca 2.0.0` | Desinstaló, instaló, registró el host en HKLM | 3010 |
| 2026-10-01 11:09 | `GDE Firma Digital Service Firefox 2.0.0` (otro nombre, mismo ProductCode) | Igual | 3010 |
| 2026-10-01 11:20 | `GDE Firma Digital Service Firefox 2.0.0` | Igual | 3010 |

- Log sin entradas de severidad 2 ni 3; queda una sola entrada en Programas y características.
- El `.exe` publicado es el build final aprobado como versión 1 (11:32): respecto de las corridas de prueba
  agrega el isotipo y el texto de la Secretaría en las ventanas.

## Problemas encontrados y corregidos

| Versión | Problema | Corrección |
| --- | --- | --- |
| 1.0.0 | "El sistema no puede encontrar el archivo especificado" al abrir el `.exe`: el SFX antepone `.\` a `RunProgram` | `Directory=""` en la configuración del SFX |
| 1.0.0 | PSADT no se autoeleva: corta con "requires administrative permissions" | Manifiesto `requireAdministrator` en el módulo SFX |
| 1.0.0 | La ventana de reinicio corre desde la carpeta temporal del SFX | `Lanzar.ps1` espera a los procesos `PSADT.ClientServer.*` |
| 1.0.0 | `$PSScriptRoot` vacío en los valores por defecto de `param()` (PowerShell 5.1) | Se calcula en el cuerpo del script |
| 4.0.0 | Con `powershell -File`, `-Variantes basico,java` llega como un solo texto | `build.ps1` separa por comas |
| 4.0.0 | Sin `Variante.psd1`, `Import-PowerShellDataFile` no cortaba (error no terminante) | `-ErrorAction Stop` → sale 69010 |

## Nunca probado

- `-DeploymentType Uninstall`.
- Actualización SafeNet 10.5 → 10.8.
- PC del dominio con GPO de ejecución de scripts, y modo silencioso por GPO/Intune/SCCM.
- PC con JDK 9+ instalado.
