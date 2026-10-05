@{
    # Capa agregada en 1.0.0. Basico: el token de Firma Digital (desinstala versiones previas e instala el MSI).
    Nombre      = 'Basico'
    Base        = ''
    Componentes = @('Token')

    # Origen: relativo a instaladores\. Destino: relativo a Files\ del paquete PSADT.
    Archivos    = @(
        @{ Origen = 'token\token-service_v4.msi'; Destino = 'token-service_v4.msi' }
    )
}
