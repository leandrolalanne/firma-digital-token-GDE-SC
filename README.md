# Firma Digital con Token GDE — Santa Cruz

Instalador que deja una PC con Windows 10 u 11 (64 bits) lista para **firmar con token en GDE**.
Lo mantiene la Secretaría de Estado de Modernización de Santa Cruz.

## Descarga

Los instaladores se publican en **[Releases](https://github.com/leandrolalanne/firma-digital-token-GDE-SC/releases)**:
un archivo por versión, `firma-digital-token-GDE-SC-<versión>.exe`. El repositorio es privado: para descargar
hace falta una cuenta de GitHub con acceso.

## Cómo se usa

1. Doble clic en el `.exe`.
2. Si Windows muestra "Windows protegió su PC": **Más información → Ejecutar de todas formas** (el instalador
   todavía no tiene firma digital).
3. Aceptar el permiso de administrador.
4. Esperar: el asistente muestra el progreso y no hace preguntas.
5. Al terminar aparece una cuenta regresiva de 60 segundos y la PC se reinicia sola (o con "Reiniciar ahora").

Si algo falla aparece un cartel de error. El detalle queda en `C:\Windows\Logs\Software\`.

## Qué instala

Cada componente se saltea si ya está instalado, así que se puede volver a ejecutar sin problema.

| Componente | Desde la versión |
| --- | --- |
| Token GDE (`token-service`): desinstala versiones anteriores, instala la nueva y la registra para Chrome y Firefox (Edge desde la 4.0.0) | 1.0.0 |
| Java 8 (solo si falta) | 2.0.0 |
| Certificados de las Autoridades Certificantes de Firma Digital de Argentina | 2.0.0 |
| Drivers de token: SafeNet (eToken 5110 y 5110+), Feitian ePass2003, Longmai mToken | 3.0.0 |
| Extensión "Firma con Token GDE" en Chrome, Edge y Firefox | 4.0.0 |

## Versiones

| Versión | Fecha | Qué agrega | Estado |
| --- | --- | --- | --- |
| [4.0.0](https://github.com/leandrolalanne/firma-digital-token-GDE-SC/releases/tag/v4.0.0) | 2026-10-05 | Extensiones de Chrome, Edge y Firefox | En prueba (pre-release) |
| [3.0.0](https://github.com/leandrolalanne/firma-digital-token-GDE-SC/releases/tag/v3.0.0) | 2026-10-01 | Drivers de token | Probada — **versión recomendada** |
| [2.0.0](https://github.com/leandrolalanne/firma-digital-token-GDE-SC/releases/tag/v2.0.0) | 2026-10-01 | Java 8 y certificados | Probada |
| [1.0.0](https://github.com/leandrolalanne/firma-digital-token-GDE-SC/releases/tag/v1.0.0) | 2026-10-01 | Token GDE | Probada |

Usar la versión recomendada. Las anteriores quedan disponibles para casos puntuales: por ejemplo, la 1.0.0
si en la PC solo hay que reinstalar el token. El detalle de cada versión está en [`CHANGELOG.md`](CHANGELOG.md)
y las pruebas en [`PRUEBAS.md`](PRUEBAS.md).

Los números siguen [Versionado Semántico](https://semver.org/lang/es/): `MAYOR.MENOR.PARCHE`.

## Para quien mantiene el proyecto

| Archivo | Para qué |
| --- | --- |
| [`AGENTS.md`](AGENTS.md) | Reglas del proyecto, estructura, códigos de salida y criterios de aceptación |
| [`CHANGELOG.md`](CHANGELOG.md) | Registro de cambios por versión |
| [`PRUEBAS.md`](PRUEBAS.md) | Qué se probó en cada versión y qué falta |
| [`docs/NOTAS-TECNICAS.md`](docs/NOTAS-TECNICAS.md) | Detalle de cada componente, despliegue por GPO/Intune/SCCM y firma del `.exe` |

**Generar el instalador** (Windows PowerShell 5.1 y [7-Zip](https://www.7-zip.org/) instalado):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\build.ps1 -Version 4.0.0
```

Deja `dist\firma-digital-token-GDE-SC-4.0.0.exe` y el paquete sin empaquetar en `dist\paquetes\` para
despliegue masivo.

**Publicar una versión nueva:**

1. Hacer los cambios, generar el instalador con `build.ps1 -Version X.Y.Z` y probarlo.
2. Anotar los cambios en `CHANGELOG.md` bajo un título `## [X.Y.Z] - AAAA-MM-DD`.
3. Commitear, crear el tag, subirlo y crear el release con el `.exe` (las notas son la sección del
   `CHANGELOG.md`, guardada en `notas.md`):

   ```powershell
   git tag -a vX.Y.Z -m "X.Y.Z"
   git push origin main vX.Y.Z
   gh release create vX.Y.Z dist\firma-digital-token-GDE-SC-X.Y.Z.exe --title vX.Y.Z --notes-file notas.md
   ```

**Publicación automática (opcional):** `build/release.yml` es un workflow de GitHub Actions que hace el paso 3
solo al subir el tag. Para activarlo, una única vez: `gh auth refresh -h github.com -s workflow`, copiar el
archivo a `.github/workflows/release.yml` y subirlo. Desde ahí alcanza con `git push origin main vX.Y.Z`.
