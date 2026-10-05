# Mudanza a Windows — completada

Este documento guiaba el paso del desarrollo de Linux a Windows. **Ya se hizo** (2026-10-01):

- El paquete se armó con **PSAppDeployToolkit 4.1.8** en `Certificados/` (no con `Deploy-TokenService.ps1`).
- El "paquete en un solo archivo" es `Salida\FirmaDigital-Instalador.exe` (7-Zip SFX con manifiesto de
  administrador), generado por `Empaquetado/Build-Instalador.ps1`.
- La validación en Windows está en `PRUEBAS.md`.
- La firma del ejecutable sigue pendiente: opciones en `README.md`.

Contenido original: `git show v1.0.0:MIGRAR-A-WINDOWS.md`.
