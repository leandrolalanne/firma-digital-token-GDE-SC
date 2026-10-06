# Registro de cambios

Todos los cambios relevantes de este proyecto se documentan en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa
[Versionado Semántico](https://semver.org/lang/es/).

## [Sin publicar]

### Cambiado

- README: aviso de que es una herramienta en beta, de uso personal y mantenida por una sola persona.

## [4.0.0] - 2026-10-05

### Agregado

- Extensión "Firma con Token GDE" instalada y forzada por directiva en Chrome, Edge y Firefox. Chrome y Edge
  usan la de la Chrome Web Store (`maddemndndajaiilmnjoocajgkpmlael`); Firefox, la de addons.mozilla.org
  (`firma.token@gde.gob.ar`). Se agrega solo la entrada propia en las directivas; la desinstalación la quita.
- Registro del host de mensajería nativa del token también para Edge.
- Workflow de publicación automática (`build/release.yml`), listo para activar: al crear un tag `vX.Y.Z`,
  GitHub Actions genera el instalador y crea el release.
- Códigos de salida 69010 (paquete no generado con `build/build.ps1`) y 69011 (no se pudo configurar la
  extensión).

### Cambiado

- Repositorio reorganizado: un solo script con capas acumulativas por versión (`variantes/`), script de build
  único (`build/build.ps1`) e instaladores de terceros en `instaladores/`.
- El instalador se llama `firma-digital-token-GDE-SC-<versión>.exe` y se publica en Releases.

### Eliminado

- Archivos heredados de la etapa anterior a PSAppDeployToolkit (`Deploy-TokenService.ps1`, `Instalar.bat`,
  `PSADT/`, `TokenService-Deploy.zip`) y los ejecutables generados (`Salida/`) del control de versiones.

## [3.0.0] - 2026-10-01

### Agregado

- Drivers de token, cada uno se saltea si ya está instalada esa versión o una mayor:
  SafeNet Authentication Client 10.8 (eToken 5110 y 5110+, con la licencia del proveedor SITEPRO),
  Feitian ePass2003 1.1.22.831 y Longmai mToken CryptoID 2.2.26.324.
- Código de salida 69009 (un driver no quedó instalado).

## [2.0.0] - 2026-10-01

### Agregado

- Java 8 x64 (instalador de Oracle provisto por Modernización), solo si no hay un Java 8 instalado. Tiene que
  ser Java 8: el firmador de `tokensign.exe` no funciona con Java 9 o posterior.
- Certificados de las Autoridades Certificantes de Firma Digital de Argentina (instalador oficial), con
  verificación de las dos AC Raíz.
- Códigos de salida 69007 (Java) y 69008 (certificados).

## [1.0.0] - 2026-10-01

### Agregado

- Instalador en un solo `.exe`: se ejecuta con doble clic, pide permiso de administrador y muestra el
  progreso. Por dentro es un paquete PSAppDeployToolkit 4.1.8.
- Desinstalación de versiones previas del token: todo paquete MSI que diga "GDE" o "Firma Digital".
- Instalación de `token-service_v4.msi` y verificación en Programas y características.
- Registro del host de mensajería nativa en el equipo (HKLM) para Chrome y Firefox, para que la firma funcione
  para cualquier usuario y no solo para quien instaló.
- Reinicio con cuenta regresiva de 60 segundos. En instalaciones silenciosas no reinicia y devuelve 3010.
- Isotipo y nombre de la Secretaría de Estado de Modernización de Santa Cruz en las ventanas.
- Códigos de salida 69002, 69003, 69005 y 69006.

[Sin publicar]: https://github.com/leandrolalanne/firma-digital-token-GDE-SC/compare/v4.0.0...HEAD
[4.0.0]: https://github.com/leandrolalanne/firma-digital-token-GDE-SC/compare/v3.0.0...v4.0.0
[3.0.0]: https://github.com/leandrolalanne/firma-digital-token-GDE-SC/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/leandrolalanne/firma-digital-token-GDE-SC/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/leandrolalanne/firma-digital-token-GDE-SC/releases/tag/v1.0.0
