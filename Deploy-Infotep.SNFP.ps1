<#
.SYNOPSIS
  Despliega Infotep.SNFP en IIS con inclusión de bin/, CLR v4.0 y ApplicationPoolIdentity.

.DESCRIPTION
  - Importa WebAdministration
  - Crea/actualiza AppPool con -Force, CLR v4.0 y identity
  - Crea carpeta IIS, asigna permisos NTFS
  - Crea/actualiza sitio IIS
  - Copia TODO el contenido (incluye bin/) desde el share SMB
  - Verifica que bin\ contenga ensamblados críticos
  - Reinicia AppPool y sitio
  - Desbloquea y configura anonymousAuthentication sin intervención
  - Valida HTTP local
  - Logging cronológico en C:\DeployLogs

.NOTES
  Autor: Wellin Santana  
  Fecha: 2025-08-02 (versión ajustada)
#>

#-----------------------
# Parámetros & Módulos
#-----------------------
Import-Module WebAdministration -ErrorAction Stop

$AppName     = "Infotep.SNFP"
$PoolName    = $AppName
$IISRoot     = "E:\inetpub\$AppName"
$ShareSource = "\\srvfiles01.infotep.gov.do\Tecnologia\Desarrollo\rpascal\Pre Produccion\$AppName"
$Port        = 8081

#-----------------------
# Preparar Log
#-----------------------
$LogPath   = "C:\DeployLogs"
If (-Not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory | Out-Null
}
$TimeStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile   = "$LogPath\Deploy-$AppName-$TimeStamp.log"

function Write-Log {
    param (
        [string] $Message,
        [ValidateSet("INFO","WARN","ERROR")] [string] $Level = "INFO"
    )
    $ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $emoji = switch ($Level) {
        "INFO"  { "✅" }
        "WARN"  { "⚠️" }
        "ERROR" { "❌" }
    }
    $line  = "[$ts] [$Level] $emoji $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

Write-Log "Despliegue de '$AppName' iniciado" "INFO"

Try {
    #-----------------------
    # 1. AppPool
    #-----------------------
    if (-Not (Test-Path "IIS:\AppPools\$PoolName")) {
        New-WebAppPool -Name $PoolName -Force
        Write-Log "AppPool '$PoolName' creado (-Force)" "INFO"
    }
    else {
        Write-Log "AppPool '$PoolName' ya existe. Actualizando CLR/identity" "WARN"
    }
    Set-ItemProperty IIS:\AppPools\$PoolName -Name managedRuntimeVersion -Value "v4.0"
    Set-ItemProperty IIS:\AppPools\$PoolName -Name processModel.identityType -Value "ApplicationPoolIdentity"
    Write-Log "CLR=v4.0 y identity=ApplicationPoolIdentity aplicados al AppPool" "INFO"

    #-----------------------
    # 2. Carpeta física
    #-----------------------
    if (-Not (Test-Path $IISRoot)) {
        New-Item -Path $IISRoot -ItemType Directory | Out-Null
        Write-Log "Carpeta '$IISRoot' creada" "INFO"
    }
    else {
        Write-Log "Carpeta '$IISRoot' ya existe" "WARN"
    }

    #-----------------------
    # 3. Permisos NTFS
    #-----------------------
    $acl      = Get-Acl $IISRoot
    $identity = "IIS AppPool\$PoolName"
    $rule     = New-Object System.Security.AccessControl.FileSystemAccessRule(
                   $identity,
                   "Read,ReadAndExecute,ListDirectory",
                   "ContainerInherit,ObjectInherit",
                   "None",
                   "Allow"
               )
    $acl.SetAccessRule($rule)
    Set-Acl -Path $IISRoot -AclObject $acl
    Write-Log "Permisos NTFS asignados a '$identity'" "INFO"

    #-----------------------
    # 4. Sitio IIS
    #-----------------------
    if (-Not (Get-Website -Name $AppName -ErrorAction SilentlyContinue)) {
        New-Website -Name $AppName `
                    -Port $Port `
                    -PhysicalPath $IISRoot `
                    -ApplicationPool $PoolName
        Write-Log "Sitio IIS '$AppName' creado en puerto $Port" "INFO"
    }
    else {
        Write-Log "Sitio IIS '$AppName' ya existe" "WARN"
    }

    #-----------------------
    # 5. Copia Robocopy
    #-----------------------
    Write-Log "Iniciando robocopy (incluye bin/) desde $ShareSource" "INFO"
    $rc = robocopy $ShareSource $IISRoot /MIR /Z /R:2 /W:5 /XD obj .vs /LOG+:"$LogFile"
    if ($LASTEXITCODE -le 3) {
        Write-Log "Robocopy completado (código $LASTEXITCODE)" "INFO"
    }
    else {
        Throw "Robocopy falló con código $LASTEXITCODE"
    }

    # Verificar carpeta bin
    if (-Not (Test-Path "$IISRoot\bin")) {
        Write-Log "¡ bin\\ NO existe tras copiado! Verifica share o filtros." "ERROR"
        Throw "bin/ no copiado"
    }
    else {
        $cnt = (Get-ChildItem "$IISRoot\bin" -Recurse -File).Count
        Write-Log "Encontrados $cnt archivos en bin\" "INFO"
    }

    #-----------------------
    # 6. Reiniciar
    #-----------------------
    Restart-WebAppPool $PoolName
    Start-Website     $AppName
    Write-Log "AppPool y sitio reiniciados" "INFO"

    #-----------------------
    # 7. anonymousAuthentication
    #-----------------------
    $filter = "/system.webServer/security/authentication/anonymousAuthentication"
    # Desbloquear siempre antes de configurar
    Clear-WebConfigurationLock -Filter $filter -PSPath "MACHINE/WEBROOT/APPHOST" -ErrorAction SilentlyContinue
    Set-WebConfigurationProperty -Filter $filter -PSPath "IIS:\Sites\$AppName" -Name userName -Value ""
    Write-Log "anonymousAuthentication identity=ApplicationPoolIdentity configurado" "INFO"

    #-----------------------
    # 8. Validación HTTP
    #-----------------------
    $resp = Invoke-WebRequest "http://localhost:$Port/" -UseBasicParsing -ErrorAction Stop
    if ($resp.StatusCode -eq 200) {
        Write-Log "HTTP 200 OK verificado" "INFO"
    }
    else {
        Write-Log "HTTP inesperado: $($resp.StatusCode)" "WARN"
    }
}
Catch {
    Write-Log "Error: $_" "ERROR"
    exit 1
}

Write-Log "Despliegue finalizado" "INFO"

