<#

Скрипт собирает с компа информацию для анализа по информационной безопасности.
Сделано для PowerSell v2 и выше.

Запускать из консоли Powershell(если политики позволяют), либо из cmd(от админа) в обход политик.
Файлы отчета создаются в текущей директории под именами "computername-sec.txt(-gpo.html)".

Параметр $UserName задает пользователя (domain\user) для проверки применяемых групповых политик.
По умолчанию, пользователь вошедший в систему.


Автор: Полетаев Сергей

Пример запуска:
Powershell: ./Get-SecurityInfo.ps1 domain\user
cmd: D:\> powershell.exe -executionpolicy bypass -file .\get-securityinfo.ps1 domain\user

#>

[CmdletBinding()]

Param (
    [String]$UserName = ""
)



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



function GetMappedDrives{
    $Report = @() 
    try { $explorer = Get-WmiObject win32_process  -EA SilentlyContinue | ?{ $_.name -eq 'explorer.exe' } }
    catch { #exit 5
    }
    # Проверка в HKEY_USERS сетевых дисков для SID владельцев запущеных процессов
    if ( $explorer ) {
        $hive      = 2147483651
        $sid       = ($explorer.GetOwnerSid()).sid
        $owner     = $explorer.GetOwner()
        $RegProv   = Get-WmiObject -List -Namespace "root\default" | ?{ $_.Name -eq 'StdRegProv' }
        $DriveList = $RegProv.EnumKey( $hive, $sid+'\Network' )

        # Если подключенные диски есть, то добавляем их в отчет
        if ( $DriveList.sNames.count -gt 0 ) {

            $Person = $owner.Domain+'\'+$owner.user

            foreach ( $drive in $DriveList.sNames ) {
                $hash = @{
                    User         = $Person
                    Drive        = $drive
                    Share        = ( $RegProv.GetStringValue($Hive, $sid+'\Network\'+$drive, "RemotePath") ).sValue
                }
                $objDriveInfo = new-object PSObject -Property $hash
                $Report += $objDriveInfo
            }
        }
    }
    $Report
}#function



Write-Host "Начался сбор данных... Ждите!"
$sys = Get-WmiObject Win32_ComputerSystem  -EA SilentlyContinue
$os  = Get-WmiObject Win32_OperatingSystem -EA SilentlyContinue

$NameServer = $env:computername
if ($UserName -eq "") { $UserName = $sys.UserName }

$journal = (Get-Location).Path + "\$NameServer-sec.txt"
$gpofile = (Get-Location).Path + "\$NameServer-gpo.html"

"`t Компьютер: $NameServer`t`t  Дата проверки: " + [string](Get-date) | Out-File -Force $journal
"`n `t Пользователь:" + $UserName | Out-File -Append $journal
"`n `t Операционная система: " + $os.Name + " " + $os.OSArchitecture | Out-File -Append $journal


'-'*50 | Out-File -Append $journal
"`n `t 1. Сведения о платформе:" | Out-File -Append $journal
$sys | fl Model,SystemType,Domain,PartOfDomain | Out-File -Append $journal
    

'-'*50 | Out-File -Append $journal
"`n `t 2. Сведения о производителе и версии БИОС:" | Out-File -Append $journal
Get-WmiObject Win32_BIOS -EA SilentlyContinue | fl Manufacturer,BIOSVersion,SMBIOSBIOSVersion,ReleaseDate `
    | Out-File -Append $journal


'-'*50 | Out-File -Append $journal
"`n `t 3. Локальные пользователи:" | Out-File -Append $journal

$local_users = Get-WmiObject Win32_Account -EA SilentlyContinue | ?{ $_.LocalAccount -eq 'True' -and $_.SIDType -eq 1 }
$local_users | ft Name,Status,Disabled,PasswordExpires,PasswordChangeable,PasswordRequired -AutoSize -Wrap `
    | Out-File -Append $journal

foreach ($user in $local_users) {
    '-'*20 | Out-File -Append $journal

    if ($psISE -and $PSVersionTable.PSVersion.Major -gt 2)
        { net user $user.Name | Out-String | ConvertTo-Encoding cp866 windows-1251 | Out-File -Append $journal }
    else { net user $user.Name | Out-String | Out-File -Append $journal }
}
#Get-LocalUser | sort Name | select -Property Name,PrincipalSource,Enabled,PasswordChangeableDate,PasswordExpires,UserMayChangePassword,PasswordRequired,PasswordLastSet,LastLogon | ft -AutoSize -Wrap | Out-File -Append $journal


'-'*50 | Out-File -Append $journal
"`n `t 4. Состав локальных групп:" | Out-File -Append $journal

$out = Get-WmiObject Win32_GroupUser -EA SilentlyContinue | ?{ $_.GroupComponent -like "*domain=""$NameServer""*" } `
    | fl PartComponent -groupby GroupComponent | Out-String -Stream | Where { $_.Length -gt 0 }

$out -replace("^   G.+Name=", "Состав группы: ")  -replace("^P.+Name=", "`t`t") | Out-File -Width 150 -Append $journal
#Get-LocalGroup | %{ Get-LocalGroupMember $_.name | ft $_.name, Name } | Out-File -Append $journal


'-'*50 | Out-File -Append $journal
"`n `t 5. Настройки сервера времени:" | Out-File -Append $journal

Get-WmiObject Win32_TimeZone | fl Bias,Caption | Out-File -Append $journal

if ($psISE -and $PSVersionTable.PSVersion.Major -gt 2) {
    $ntp_state = w32tm /query /status | Out-String | ConvertTo-Encoding cp866 windows-1251
    $ntp_conf = w32tm /query /configuration | Out-String | ConvertTo-Encoding cp866 windows-1251
}
else {
    $ntp_state = w32tm /query /status | Out-String
    $ntp_conf = w32tm /query /configuration | Out-String
}
"`nСостояние NTP клиента:`n$ntp_state" | Out-File -Append $journal
"`nКонфигурация NTP:`n$ntp_conf" | Out-File -Append $journal


'-'*50 | Out-File -Append $journal
"`n `t 6. Политики:" | Out-File -Append $journal

"`nПолитики выполнения скриптов PowerShell:" | Out-File -Append $journal 
Get-ExecutionPolicy -list | ft -autosize | Out-File -Append $journal

GPRESULT /USER:$UserName /H $gpofile /f
#Get-GPResultantSetOfPolicy -ReportType Html -Path $gpofile -User $UserName
if ( $error -like "*gpresult.exe*") { "Ошибка в запросе групповых политик для $UserName" | Out-File -Append $journal  }
else { "В Файл $gpofile выгружены примененные групповые политики для $UserName" | Out-File -Append $journal }


'-'*50 | Out-File -Append $journal
"`n `t 7. Настройки фаервола windows:" | Out-File -Append $journal

if ($psISE -and $PSVersionTable.PSVersion.Major -gt 2)
    { netsh advfirewall show allprofile | Out-String | ConvertTo-Encoding cp866 windows-1251 | Out-File -Append $journal }
else { netsh advfirewall show allprofile | Out-String | Out-File -Append $journal }
#(#posh v5)
#Get-NetFirewallProfile -policystore activestore | Out-File -Append $journal
# разрешающие правила
#Get-NetFirewallRule -Enabled True -Action Allow | sort DisplayName,Profile | ft `
#    @{Name='Protocol';Expression={($PSItem | Get-NetFirewallPortFilter).Protocol}}, `
#    @{Name='LocalPort';Expression={($PSItem | Get-NetFirewallPortFilter).LocalPort}}, `
#    @{Name='RemotePort';Expression={($PSItem | Get-NetFirewallPortFilter).RemotePort}}, `
#    @{Name='RemoteAddress';Expression={($PSItem | Get-NetFirewallAddressFilter).RemoteAddress}}, `
#    Profile,Direction,DisplayName -Wrap -AutoSize | Out-File -Append $journal


'-'*50 | Out-File -Append $journal
"`n `t 8. Содержимое файла hosts:" | Out-File -Append $journal
Get-Content "$env:SYSTEMROOT\system32\drivers\etc\hosts" | ?{$_ -notlike "#*"} | Out-File -Append $journal


'-'*50 | Out-File -Append $journal
"`n `t 9. Сведения о дисках, шарах и правах доступа к ним:" | Out-File -Append $journal

GetMappedDrives | ft -AutoSize | Out-File -Append $journal

Get-WmiObject Win32_DiskDrive -EA SilentlyContinue | ft Name,Caption,InterfaceType,Size,MediaType -AutoSize `
    | Out-File -Width 150 -Append $journal

$shares = Get-WmiObject Win32_Share -EA SilentlyContinue

foreach ($share in $shares) {
    if ($share.Path -ne '') {
        [string]$path_share = "\\$NameServer\" + $share.Name
        $path_share | Out-File -Append $journal
        Get-Acl $path_share -EA SilentlyContinue | fl Path,Owner,Group,AccessToString | Out-File -Append $journal
    }
}


'-'*50 | Out-File -Append $journal
"`n `t 10. KES статистика:" | Out-File -Append $journal

$kes_path = "C:\Program Files (x86)\Kaspersky Lab\Kaspersky Endpoint Security for Windows\avp.exe"
$kes_is_install = Test-Path -Path $kes_path

if ( $kes_is_install ) {
    if ($psISE -and $PSVersionTable.PSVersion.Major -gt 2)
        { $kes_status = &$kes_path status | Out-String | ConvertTo-Encoding cp866 windows-1251 }
    else
        { $kes_status = &$kes_path status | Out-String }

    $kes_status | Out-File -Append $journal

    foreach ($svc in ($kes_status -split ' ')) {
        if (($svc -like "Updater$*") -or ($svc -like "Scan_Objects$*")) {
            $svc | Out-File -Append $journal
            &$kes_path statistics $svc | Out-File -Append $journal
        }
    }
}
else { "$kes_path отсутствует..." | Out-File -Append $journal }


'-'*50 | Out-File -Append $journal
"`n `t 11. Установленные приложения:" | Out-File -Append $journal

$app32 = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* 

if ( $os.OSArchitecture -match '64' ) {
    $app64 = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* 

    $app32 + $app64 | sort DisplayName -Unique | ft DisplayName,DisplayVersion,InstallDate,Publisher -AutoSize `
        | Out-File -Width 150 -Append $journal
}
else {
    $app32 | sort DisplayName -Unique | ft DisplayName,DisplayVersion,InstallDate,Publisher -AutoSize `
        | Out-File -Width 150 -Append $journal
}

if ( $PSVersionTable.BuildVersion.Major -gt 6 ) {
    "`t Установленные из магазина:" | Out-File -Append $journal
    Get-AppxPackage | sort Name | ft Name, PackageFullName -AutoSize | Out-File -Width 150 -Append $journal
}


'-'*50 | Out-File -Append $journal
"`n `t 12. Cлужбы::" | Out-File -Append $journal
Get-Service | sort Status, DisplayName | ft Status, StartType, DisplayName -AutoSize | Out-File -Append $journal


'-'*50 | Out-File -Append $journal
"`n `t 13. Рабочие процессы:" | Out-File -Append $journal
$process = Get-Process
$process | sort ProcessName, Id | ft -AutoSize | Out-File -Append $journal


'-'*50 | Out-File -Append $journal
"`n `t 14. Таблица маршрутизации и открытые порты:" | Out-File -Append $journal

if ($psISE -and $PSVersionTable.PSVersion.Major -gt 2) {
    $ports = (netstat -ano | Out-String | ConvertTo-Encoding cp866 windows-1251).split("`n")
    netstat -r | Out-String | ConvertTo-Encoding cp866 windows-1251 | Out-File -Append $journal
}
else {
    $ports = (netstat -ano | Out-String).split("`n")
    netstat -r | Out-String | Out-File -Append $journal
}
"`n  Имя    Локальный адрес        Внешний адрес          Состояние       PID (ProcessName)`
  --------------------------------------------------------------------------------------" | Out-File -Append $journal
foreach ($port in $ports) {
    $p = $port.split(" ")
    foreach ($proc in $process) {
        try {
            if ([int]$p[-1] -eq $proc.Id)
                { ([string]$port).Remove([string]$port.Length-1) + "`t ("+ [string]$proc.ProcessName + ")" | Out-File -Append $journal }
        }
        catch {}
    }
}
#Get-NetTCPConnection -State Listen | Select LocalAddress, LocalPort, RemoteAddress, RemotePort, State | Sort LocalPort | ft | Out-File -Append $journal


'-'*50 | Out-File -Append $journal
"`n `t 15. Сведения о сетевых адаптерах и их конфигурации:" | Out-File -Append $journal
Get-WmiObject Win32_NetworkAdapterConfiguration -Filter IPEnabled=TRUE `
    | fl IPAddress,MACAddress,DHCPEnabled,DefaultIPGateway,DNSDomain,DNSServerSearchOrder,Description | Out-File -Append $journal


'-'*50 | Out-File -Append $journal
"`n `t 16. Установленные обновления:" | Out-File -Append $journal
Get-WmiObject win32_quickfixengineering -EA SilentlyContinue | ft -AutoSize | Out-File -Append $journal


'-'*50 | Out-File -Append $journal
"`n `t 17. Критические события в журналах за неделю:" | Out-File -Append $journal

$start_date = (Get-Date).AddDays(-7)

if ( $kes_is_install )
    { $hash = @{ LogName='Application','System','Kaspersky Endpoint Security','Kaspersky Event Log','HardwareEvents'; StartTime=$start_date; Level=2 } }
else { $hash = @{ LogName='Application','System','HardwareEvents'; StartTime=$start_date; Level=2 } }

Get-WinEvent -FilterHashtable $hash -EA SilentlyContinue | ft -AutoSize -Wrap | Out-File -Append $journal

Write-Host "Готово!"
