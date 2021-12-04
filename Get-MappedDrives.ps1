function Get-MappedDrives{

[CmdletBinding()]

param (
    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [string]$ComputerName = $env:COMPUTERNAME
)

Process {
    # Проверка доступности компьютера            
    if ( Test-Connection -Delay 1 -ComputerName $ComputerName -Count 2 -Quiet -ea Stop ) {
        $Report = @() 
        try { $explorer = Get-WmiObject win32_process -ComputerName $ComputerName | ?{ $_.name -eq 'explorer.exe' } }
        catch { #exit 5
        }

        # Проверка в HKEY_USERS сетевых дисков для SID владельцев запущеных процессов
        if ( $explorer ) {
            $hive      = 2147483651
            $sid       = ($explorer.GetOwnerSid()).sid
            $owner     = $explorer.GetOwner()
            $RegProv   = Get-WmiObject -List -Namespace "root\default" -ComputerName $ComputerName | ?{ $_.Name -eq 'StdRegProv' }
            $DriveList = $RegProv.EnumKey( $hive, $sid+'\Network' )

            # Если подключенные диски есть, то добавляем их в отчет
            if ( $DriveList.sNames.count -gt 0 ) {

                $Person = $owner.Domain+'\'+$owner.user

                foreach ( $drive in $DriveList.sNames ) {
                    $hash = [ordered]@{
                        ComputerName = $ComputerName
                        User         = $Person
                        Drive        = $drive
                        Share        = ( $RegProv.GetStringValue($Hive, $sid+'\Network\'+$drive, "RemotePath") ).sValue
                    }
                    $objDriveInfo = new-object PSObject -Property $hash
                    $Report += $objDriveInfo
                }
            }
        }

        # Вывод отчета
        $Report
    }
    else { "$ComputerName ------------- отключен -----------------" }

    #exit 0
}#process
}#function
