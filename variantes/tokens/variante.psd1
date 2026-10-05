@{
    # Capa agregada en 3.0.0. Tokens: lo de Java + drivers de token (3 instaladores, 4 modelos: ePass2003,
    # eToken 5110 y 5110+ con SafeNet 10.8, mToken CryptoID).
    Nombre      = 'Tokens'
    Base        = 'java'
    Componentes = @('DriversToken')

    # Origen: relativo a instaladores\. Destino: relativo a Files\ del paquete PSADT.
    Archivos    = @(
        @{ Origen = 'drivers\sac-10.8-x64-10.8.msi'; Destino = 'Drivers\sac-10.8-x64-10.8.msi' }
        @{ Origen = 'drivers\SITEPRO_ONE SEAT_End User License Certificate.txt'; Destino = 'Drivers\SITEPRO_ONE SEAT_End User License Certificate.txt' }
        @{ Origen = 'drivers\MSePass2003_Win_Spanish_V1.1.22.831.exe'; Destino = 'Drivers\MSePass2003_Win_Spanish_V1.1.22.831.exe' }
        @{ Origen = 'drivers\MSCryptoID-FIPS140-3_Win_Spanish_V2.2.26.324.exe'; Destino = 'Drivers\MSCryptoID-FIPS140-3_Win_Spanish_V2.2.26.324.exe' }
    )
}
