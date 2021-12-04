#####################################################################################
## ИМЯ: srvjournal.ps1
## ЯЗЫК: PoSH V5
## ДАТА ИЗМЕНЕНИЯ: 01.07.2020
## АВТОР: Полетаев Сергей
## ОПИСАНИЕ: Скрипт для создания журнала о конфигурации доменных серверов или компов.
## Можно добавить в планировщик заданий для наличия всегда свежей информации. 
## Запускать с любого компа из консоли PowerShell с правами администратора домена,
## либо непосредственно с консоли сервера под правами администратора.
## Вызов: ./srvjournal.ps1 "имя_сервера"
## либо  Get-Content "servers.txt" | %{./srvjournal.ps1 $_} ,
## где servers.txt - файл со списоком серверов
##
#####################################################################################
[CmdletBinding()]

Param ([String]$NameServer = "LOCALHOST")

function ConvertTo-Encoding ([string]$From, [string]$To){
    Begin {
        $encFrom = [System.Text.Encoding]::GetEncoding($From)
        $encTo = [System.Text.Encoding]::GetEncoding($To)
    }#Begin

    Process {
        $bytes = $encTo.GetBytes($_)
        $bytes = [System.Text.Encoding]::Convert($encFrom, $encTo, $bytes)
        $encTo.GetString($bytes)
    }#Process
}#function ConvertTo-Encoding


if (($NameServer -eq '') -or ($NameServer -eq 'localhost') -or ($NameServer -eq '127.0.0.1')) {
    $NameServer = $env:computername
    $params = @{}
}
elseif ( $NameServer -eq $env:computername ) { $params = @{} }
else { $params = @{"ComputerName" = $NameServer} }


$journal  = (Get-Location).Path+"\$NameServer.txt"

if (Test-Connection $NameServer -Count 3 -Quiet) {
    Write-Host "Сервер $NameServer `tдоступен. Начинаем сбор данных..."

    $date = (Get-Date).tostring("dd.MM.yyyy")
    
    "Журнал настроек сервера $NameServer" | Out-File -Force $journal
    "на $date`n`n" | Out-File -Append $journal
    
    "1. Сведения о серверной платформе:" | Out-File -Append $journal
    Get-WmiObject Win32_ComputerSystem @params | fl Model,SystemType,Domain,PartOfDomain `
        | Out-File -Append $journal
    
    "2. Сведения о производителе, серийном номер и версии БИОС:" | Out-File -Append $journal
    Get-WmiObject Win32_BIOS @params | fl Manufacturer,SerialNumber,BIOSVersion,SMBIOSBIOSVersion,ReleaseDate `
        | Out-File -Append $journal

    "3. Сведения о процессоре:" | Out-File -Append $journal
     Get-WmiObject Win32_Processor @params `
         | fl Manufacturer,Name,SocketDesignation,Status,L2CacheSize,L3CacheSize,NumberOfCores,NumberOfLogicalProcessors `
         | Out-File -Append $journal

    "4. Сведения об оперативной памяти:" | Out-File -Append $journal
    Get-WmiObject Win32_MemoryArray @params `
        | fl @{name="Size (GB)"; expression={"{0:n2}" -f ($_.EndingAddress/1048576)}} | Out-File -Append $journal
    Get-WmiObject Win32_PhysicalMemory @params `
        | ft Manufacturer,DeviceLocator,@{name="Size (MB)"; expression={"{0:n2}" -f ($_.Capacity/1048576)}} -AutoSize `
        | Out-File -Append $journal

    "5. Сведения о логических дисках:" | Out-File -Append $journal
    Get-WmiObject Win32_LogicalDisk  -Filter 'DriveType=3' @params `
        | fl DeviceID,@{name="Size (GB)"; expression={"{0:n2}" -f ($_.Size/1Gb)}},FileSystem | Out-File -Append $journal

    "6. Сведения об операционной системе:" | Out-File -Append $journal
    $os = Get-WmiObject Win32_OperatingSystem @params
    $os | fl Caption,BuildNumber,OSArchitecture,Version,OSLanguage | Out-File -Append $journal

    "7. Сведения о подключении к домену:" | Out-File -Append $journal
    Get-WmiObject Win32_NTDomain -Filter 'Status = "OK"' @params | fl DcSiteName,DnsForestName,DomainControllerName `
        | Out-File -Append $journal

    "8. Сведения о часовом поясе:" | Out-File -Append $journal
    Get-WmiObject Win32_TimeZone @params | fl Bias,Caption | Out-File -Append $journal
    if ($psISE) {
        $NTPstate = w32tm /query /status /computer:$NameServer | Out-String | ConvertTo-Encoding cp866 windows-1251
        $NTPconf = w32tm /query /configuration /computer:$NameServer | Out-String | ConvertTo-Encoding cp866 windows-1251
    }
    else {
        $NTPstate = w32tm /query /status /computer:$NameServer | Out-String
        $NTPconf = w32tm /query /configuration /computer:$NameServer | Out-String
    }
    "`nСостояние NTP клиента:`n$NTPstate" | Out-File -Append $journal
    "`nКонфигурация NTP:`n$NTPconf" | Out-File -Append $journal

    "`n9. Сведения об установленном ПО:" | Out-File -Append $journal
    if ($os.Caption -match "10") {
        Get-WmiObject Win32_InstalledWin32Program | sort name,version -Unique | `
            ft name,version,vendor -AutoSize | Out-File -Append $journal
    }
    else {
        #Get-WmiObject Win32_Product | sort Name -Unique | ft Name,Version,Vendor -AutoSize | Out-File -Append $journal
        Get-WmiObject Win32reg_AddRemovePrograms @params | select DisplayName,Version,Publisher,InstallDate `
            | sort Displayname -Unique | ft -AutoSize | Out-File -Append $journal
    }

    "10. Сведения об установленных ролях и компонентах:" | Out-File -Append $journal
    if ($os.Caption -match "server") {
        Get-WmiObject Win32_ServerFeature @params | select Name | sort Name | Out-File -Append $journal
    }
    else { "`n На клиентских ОС недоступно.`n" | Out-File -Append $journal }

    "11. Сведения о службах:" | Out-File -Append $journal
    Get-WmiObject win32_Service @params | select DisplayName,StartMode,State,StartName | sort DisplayName | ft -AutoSize `
        | Out-File -Append $journal

    "12. Сведения о локальных пользователях и группах:" | Out-File -Append $journal
    Get-WmiObject Win32_UserAccount @params -Filter "Domain = ""$NameServer""" | select Name,Status,Disabled,Description `
        | sort Name | ft -AutoSize | Out-File -Append $journal
    $out = Get-WmiObject Win32_GroupUser @params | ?{$_.GroupComponent -like "*domain=""$NameServer""*"} `
        | fl PartComponent -groupby GroupComponent | Out-String -Stream | Where { $_.Trim().Length -gt 0 }

    $out.Trim() | %{ $_ -replace("^G.+Name=", "`tAccounts in the group: ")} `
                | %{ $_ -replace("^P.+Name=", "")} `
                | Out-File -Append $journal

    "`n`n13. Сведения о файловых ресурсах в сетевом доступе и правах доступа к ним:`n" | Out-File -Append $journal
    $Shares = Get-WmiObject Win32_Share @params
    foreach ($Share in $Shares) {
        if ($Share.Path -ne '') {
            [string]$pathShare = "\\$NameServer\"+$Share.Name
            $pathShare | Out-File -Append $journal
            Get-Acl $pathShare | fl Path,Owner,Group,AccessToString | Out-File -Append $journal
        }
    }

    "14. Сведения об установленных принтерах:" | Out-File -Append $journal
    Get-WmiObject Win32_Printer @params | ft Name,DriverName,PortName,Shared,Default -AutoSize -Wrap | Out-File -Append $journal
    
    "15. Сведения о сетевых адаптерах и их конфигурации:" | Out-File -Append $journal
    Get-WmiObject Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE @params `
        | fl IPAddress,MACAddress,DHCPEnabled,DefaultIPGateway,DNSDomain,DNSServerSearchOrder,Description | Out-File -Append $journal

    "16. Таблица маршрутизации:" | Out-File -Append $journal
    Get-WmiObject Win32_IP4RouteTable @params | select Name,Mask,Destination,NextHop,Metric1 -Unique | ft | Out-File -Append $journal

}
else { Write-Host "Компьютер с именем $NameServer `tнедоступен." }
