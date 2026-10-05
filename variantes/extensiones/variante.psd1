@{
    # Capa agregada en 4.0.0 (es la que se publica). Extensiones: lo de Tokens + la extension
    # "Firma con Token GDE" forzada por directiva en Chrome, Edge y Firefox (cada navegador la baja de su
    # tienda al abrirse; no lleva archivos).
    Nombre      = 'Extensiones'
    Base        = 'tokens'
    Componentes = @('Extensiones')

    # Origen: relativo a instaladores\. Destino: relativo a Files\ del paquete PSADT.
    Archivos    = @()
}
