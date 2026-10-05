@{
    # Capa agregada en 2.0.0. Java: lo de Basico + Java 8 x64 (solo si falta) + certificados de las AC.
    Nombre      = 'Java'
    Base        = 'basico'
    Componentes = @('Java8', 'CertificadosAC')

    # Origen: relativo a instaladores\. Destino: relativo a Files\ del paquete PSADT.
    Archivos    = @(
        @{ Origen = 'java\jre-8u503-windows-x64.exe'; Destino = 'jre-8u503-windows-x64.exe' }
        @{ Origen = 'certificados\Certificados AC Firma Digital Argentina.exe'; Destino = 'Certificados AC Firma Digital Argentina.exe' }
    )
}
