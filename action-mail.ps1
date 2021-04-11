function Get-VmwareHostsTemp {
    param (
        $vhost,
        $cred,
        $option,
        $sensor
    )    

    Process {
        $tempHost=Get-WSManInstance -Authentication basic -ConnectionURI "https://$vhost/wsman" `
            -Credential $cred -Enumerate -port 443 -UseSSL -SessionOption $option `
            -ResourceURI http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_NumericSensor `
            -ErrorAction Stop `
            | ?{$_.caption -eq $sensor}
        $tmp=$tempHost.CurrentReading
        $tmp
    }
}

$From       = 'Report@firma.ru'
$To         = 'usermail@mail.com'
$Subject    = 'Report action'
$MailSrv    = 'mailserver.firma.ru'
$Encoding   = [System.Text.Encoding]::utf8

$vCenterSrv = 'vcenter'
$flHosts    = 'C:\Util\data\vmHosts.txt'
$flServers  = 'C:\Util\data\servers.txt'
$PathSecStr = 'C:\Util\data\security.txt'

$filetemp   = 'C:\Util\temp.txt'

#Подключам сессию почтовика
$session=New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://$MailSrv/powershell
Import-PSSession $session

[string]$Begin = Get-Date
$Body = $Begin +" begin`n"

$date = Get-Date

#Проверяем сообщения с личного ящика на рабочий и выбираем последнее
$msg = Search-MessageTrackingReport -Identity s.poletaev -BypassDelegateChecking -Sender $To -ResultSize 1 -DoNotResolve
[string]$Subject = 'Report action ' + $msg.Subject 

$pass = ConvertTo-SecureString -String (Get-Content -Path $PathSecStr)

Try {
    if($msg.SubmittedDateTime -gt $date.AddMinutes(-310)) {        #Отсекаем старые сообщения пришедшие более 5мин. назад(на всякий случай)
        switch -regex ($msg.Subject) {                             #Определяем по заголовку что будем делать
            "^r_.+" {                                              #Запрос на перезагрузку сервера(ОПАСНО!!!)
                $namesrv = ($msg.Subject).Substring(2)
                #Подгружаем модуль VMware, если еще не загружен
                if( -not (Get-PSSnapin VMware.VimAutomation.Core)) {Add-PSSnapin VMware.VimAutomation.Core}

                if(!$vc.IsConnected) {$vc = Connect-VIServer -Server $vCenterSrv}

                if($vc.IsConnected) {
                    Restart-VM -VM $namesrv -Confirm:$false -EA SilentlyContinue
                    Disconnect-VIServer -Server $vCenterSrv -Confirm:$false -EA SilentlyContinue
                }
                else{$Body += "vc is not available`n"}
                break
            }
            "^s_.+" {                                             #Запрос о состоянии служб сервера
                $namesrv = ($msg.Subject).Substring(2)
                $cred = New-Object System.Management.Automation.PSCredential -ArgumentList 'administrator',$pass

                Get-WmiObject win32_Service -ComputerName $namesrv -Credential $cred | select DisplayName,StartMode,State | sort DisplayName | ft -AutoSize | Out-File $filetemp
                break
            }
            "^e_.+" {                                             #Запрос о системных ошибках сервера за последние 3 суток
                $namesrv = ($msg.Subject).Substring(2)
                $option = New-PSSessionOption -SkipCACheck
                $cred = New-Object System.Management.Automation.PSCredential -ArgumentList 'administrator',$pass

                Invoke-Command -ComputerName $namesrv -ScriptBlock `
                    {Get-EventLog -Log System -EntryType Warning,Error -After (Get-Date).AddDays(-3)} -SessionOption $option -Credential $cred | fl TimeGenerated,Source,Message | Out-File $filetemp
                break
            }
            'temp' {                                               #Запрос температуры с хостов
                $option = New-WSManSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
                $cred = New-Object System.Management.Automation.PSCredential -ArgumentList 'root',$pass

                $sensor = 'Front Panel Board 1 Ambient Temp'       #Для серверов с версией вари 5 и выше
                foreach ($vhost in (Get-Content -Path $flHosts)) {
                    $tmp = Get-VmwareHostsTemp $vhost $cred $option $sensor
                    $shost=$vhost -split "[.]",3
                    $Body += $shost[2] + " -   $tmp`n"
                }
                break
            }
            'space' {                                              #Запрос о дисковом пространстве на серверах
                $option = New-PSSessionOption -SkipCACheck
                $cred = New-Object System.Management.Automation.PSCredential -ArgumentList 'administrator',$pass
                $vServers = Get-Content -Path $flServers
                Invoke-Command -ComputerName $vServers -ScriptBlock {Get-PSDrive -PSProvider filesystem `
                    | ?{$_.Free -ne $null}} -SessionOption $option -Credential $cred `
                    | sort pscomputername,root `
                    | ft @{name='used (GB)'; expression={"{0:n2}" -f ($_.used/1Gb)}; align="right"}, `
                      @{name='free (GB)'; expression={"{0:n2}" -f ($_.free/1Gb)}; align="right"},root,PSComputerName -Autosize | Out-File $filetemp
                break
            }
            'login' {                                              #Запрос о залогиненых пользователях на серверах
                $cred = New-Object System.Management.Automation.PSCredential -ArgumentList 'administrator',$pass
                "Залогинены:" | Out-File $filetemp
                foreach ($vServers in (Get-Content -Path $flServers))
                {
                    $proc = Get-WmiObject win32_process -Filter "name='explorer.exe'" -ComputerName $vServers -Credential $cred
                    if ($proc -ne $null)                           #Если есть залогиненые пользователи
                    {
                        $vServers | Out-File $filetemp -Append
                        $proc.getowner() | ft user | Out-File $filetemp -Append
                    }
                }
                break
            }
            'vm' {                                                 #Запрос по состоянию и распределению виртуальных серверов по хостам
                #Подгружаем модуль VMware, если еще не загружен
                if( -not (Get-PSSnapin VMware.VimAutomation.Core)) {Add-PSSnapin VMware.VimAutomation.Core}

                if(!$vc.IsConnected) {$vc = Connect-VIServer -Server $vCenterSrv}

                if($vc.IsConnected) {
                    Get-VM | sort vmhost,name | ft name,vmhost,numcpu,memoryGB,powerstate -AutoSize | Out-File $filetemp
                    Get-View -ViewType VirtualMachine | sort Name | select Name,@{N='IP';E={[string]::Join(',',$_.Guest.net.IPAddress)}} | ft -AutoSize | Out-File -Append $filetemp

                    (Get-Content -Path $filetemp) -replace '192.168.','     ' | set-content $filetemp

                    Disconnect-VIServer -Server $vCenterSrv -Confirm:$false -EA SilentlyContinue
                }
                else{$Body += "vc is down`n"}
                break
            }
<#            'move' {
                & .\C:\Util\vMware\vmMoveGeneralHost.ps1
                $Body += "the script is executed...`n"
                break
            }#>
            'ping' {
                foreach ($vhost in (Get-Content -Path $flHosts)) {
                    if (!(test-Connection -ComputerName $vhost -Count 3 -Quiet)) {
                        $shost=$vhost -split "[.]",4
                        $Body += "Хост "+$shost[2]+'.'+$shost[3]+" недоступен!`n"
                    
                        switch ($shost[2]) {
                            '56' {
                                if     (test-Connection -ComputerName '192.168.1.1'   -Count 2 -Quiet)  {$Body += " Канал до маршр. 1 работает.`n"}
                                elseif (test-Connection -ComputerName '192.168.2.1'   -Count 2 -Quiet)  {$Body += " Канал до Наб52 работает, но шлюз 1 недоступен.`n"}
                                elseif ((test-Connection -ComputerName '192.168.3.1' -Count 2 -Quiet) `
                                   -or (test-Connection -ComputerName '192.168.3.2'  -Count 2 -Quiet)) {$Body += " Канал до связи работает, но шлюз 2 недоступен.`n"}
                                else {$Body += " Проверяй модемы!`n"}
                                break
                            }
                            '57' {
                                if     (test-Connection -ComputerName '192.168.1.1'   -Count 2 -Quiet)  {$Body += " Канал до Наб52 работает.`n"}
                                elseif ((test-Connection -ComputerName '192.168.3.1' -Count 2 -Quiet) `
                                   -or (test-Connection -ComputerName '192.168.3.2'  -Count 2 -Quiet)) {$Body += " Канал до связи работает, но шлюз 2 недоступен.`n"}
                                else {$Body += " Проверяй модемы!`n"}
                                break
                            }
                            default {$Body += "Неизвестная сеть $shost[2], проверьте исходные данные!`n"}
                        }
                    }
                }
                break
            }
            "help" {
                $Body += "s_... - состояние служб`n"
                $Body += "e_... - системные ошибки`n"
                $Body += "temp  - температура`n"
                $Body += "space - место на дисках`n"
                $Body += "login - залогиненые пользователи`n"
                $Body += "vm    - распределение по хостам`n"
#                $Body += "move - миграция vm на свои хосты(эксперементально)`n"
                $Body += "ping  - проверка сети`n"
                break
            }
            default { $Body += $msg.Subject + " - Не угадал ;)`n"}
        }
    }

    [string]$End = Get-Date
    $Body += $End+' end'
    
    ### Отправляем сообщение
    $filesexist = Test-Path -Path $filetemp
    if ($filesexist) {Send-MailMessage -SmtpServer $MailSrv -To $To -From $From -Subject $Subject -Body $Body -Encoding $Encoding -Attachments $filetemp -EA SilentlyContinue}
    else {Send-MailMessage -SmtpServer $MailSrv -To $To -From $From -Subject $Subject -Body $Body -Encoding $Encoding -EA SilentlyContinue}
}
Catch {
    $Body += ForEach-Object {$error}
    $Body += "`n"

    [string]$End = Get-Date
    $Body += $End+' end'
    
    ### Отправляем сообщение
    Send-MailMessage -SmtpServer $MailSrv -To $To -From $From -Subject $Subject -Body $Body -Encoding $Encoding -EA SilentlyContinue
}
Finally {
#    $filesexist = Test-Path -Path $filetemp
    if ( Test-Path -Path $filetemp ) { Remove-Item -Path $filetemp }
    Get-PSSession | Remove-PSSession
    Start-Sleep -Seconds 15
}
