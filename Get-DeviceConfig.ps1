<#
.SYNOPSIS
Сохраняет рабочие конфигурации(running-config) с коммутаторов.

.DESCRIPTION
Сохраняет рабочие конфигурации(running-config) с коммутаторов.

.PARAMETER FileDevice
Задает полный путь к файлу со списком IP-адресов устройств. Обязательный параметр.
Формат: "C:\Device.txt"
Формат файла:

ip,type,enpwd
192.168.1.1,CiscoASA,PasswordEnable
192.168.1.2,CiscoSW,PasswordEnable

.PARAMETER Path
Задает путь для сохранения конфигурационных файлов. Не обязательный параметр.
Формат: "C:\Config"
Предыдущий конфиг, если есть, будет переименован в <IP>_old.txt.
Если каталог не существует, то он будет создан(если есть на это права!!!).
По умолчанию: Текущий каталог

.PARAMETER UserName
Задает пользователя для авторизации на устройствах. Не обязательный параметр.
По умолчанию: administrator

.EXAMPLE
Get-DeviceConfig.ps1 -FileDevice "C:\Device.txt"
Сохраняет рабочие конфигурации(running-config) с коммутаторов, IP-адреса которых перечисленны в файле "C:\Device.txt".

.EXAMPLE
Get-DeviceConfig.ps1 -FileDevice "C:\Device.txt" -Path "C:\Config"
Сохраняет рабочие конфигурации(running-config) с коммутаторов в папку C:\Config, IP-адреса которых перечисленны в файле "C:\Device.txt".

.EXAMPLE
Get-DeviceConfig.ps1 -FileDevice "C:\Device.txt" -Path "D:\Config" -UserName "administrator"
Сохраняет рабочие конфигурации(running-config) с коммутаторов в папку D:\Config под учеткой administrator, IP-адреса которых перечисленны в файле "C:\Device.txt".

.NOTES
ИМЯ: Get-DeviceConfig.ps1
ПРОТЕСТИРОВАНО НА: PowerShell v5.1 + модуль Posh-SSH v2.1(https://www.powershellgallery.com/packages/Posh-SSH/2.1)
ДАТА СОЗДАНИЯ: 24.03.2019
АВТОР: Полетаев Сергей
#>

[CmdletBinding()]

param (
    [Parameter (Mandatory = $true, Position=0)]
    [string]$FileDevice,

    [Parameter (Mandatory = $false, Position=1)]
    [string]$Path = (Get-Location).Path,

    [Parameter (Mandatory = $false, Position=2)]
    [string]$UserName = 'administrator'
)

function getcfg {
    param (
        [string]$itemip,
        [string]$itemtype,
        [string]$itemenpwd
    )
Process {
    try {
        #Создаем сессию SSH
        $session = New-SSHSession -ComputerName $itemip -Credential $cred -acceptkey:$true
        #Создаем поток
        $stream = $session.Session.CreateShellStream("dumb", 0, 0, 0, 0, 1000)
        #определяем тип оборудования и загоняем поток вывода(конфиг) в переменную cfg
        switch ( $itemtype ) {
            "CiscoSW" {
                $stream.Write("term len 0`n")
                sleep 2
                $stream.Write("show run`n")
                sleep 10

                $cfg = $stream.Read()

                $stream.Write("exit`n")
                sleep 1
            }
            "CiscoASA" {
                $stream.Write("`n")
                sleep 1

                #Проверка режима enable
                $prmpt = $stream.Read().Trim()
                if ( $prmpt -like "*>*" ) {
                    $stream.Write("en`n")
                    sleep 1
                    $stream.Write("$itemenpwd`n")
                    sleep 1
                }

                $stream.Write("term page 0`n")
                sleep 2
                $stream.Write("show run`n")
                sleep 10

                $cfg = $stream.Read()

                $stream.Write("exit`n")
                sleep 1
            }
            "CiscoAP" {
                $stream.Write("config paging disable`n")
                sleep 2
                $stream.Write("show run`n")
                sleep 10
                
                $cfg = $stream.Read()

                $stream.Write("exit`n")
                sleep 2
            }
            "HuaweiSW" {
                $stream.Write("screen-length 0 temporary`n")
                sleep 2
                $stream.Write("disp cur`n")
                sleep 10

                $cfg = $stream.Read()

                $stream.Write("quit`n")
                sleep 1
            }
            default { Write-Host "Для устройства $itemip указан недопустимый тип - $itemtype"; break }
        }
 
        #Переименовываем старый конфиг, если он есть
        $Filecfg    = "`\$itemip`.txt"
        $Filecfgold = "`\$itemip`_old.txt"
 
        if ( Test-Path $Path$Filecfg ) { 
            Remove-Item -Path $Path$Filecfgold -Force -EA SilentlyContinue
            Rename-Item -Path $Path$Filecfg -NewName "$itemip`_old.txt" -Force -EA SilentlyContinue
        }
        #Сохраняем конфиг в файл
        $cfg | Out-File $Path$Filecfg
 
        #Сравниваем конфиги
        if ( (Test-Path $Path$Filecfg) -and (Test-Path $Path$Filecfgold) ) {
            $change = Compare-Object -referenceobject $(get-content $Path$Filecfg) -differenceobject $(get-content $Path$Filecfgold)
            $change = $change | ?{ ($_.InputObject -notlike "ntp clock-period*") -and ($_.InputObject -notlike "*The current login time is*") }

            if ( $change.Count -gt 0 ) { Write-Host "Есть изменения на $itemip!" -f Magenta }
            else { Write-Host "Без изменений на $itemip!" -f Green }
        }
        else { Write-Host "Нет одного из конфигов для сравнения по $itemip!" -f DarkGray }
    }
    catch { Write-Host "Проблема с подключением к $itemip!" -f Red }
    finally { Remove-SshSession -SSHSession $session }
}#process
}#function


#######################
##                   ##
##  Основной модуль  ##
##                   ##
#######################

#Проверяем наличие модуля Posh-SSH
if ( !(Get-module Posh-SSH) ) {
    try   { Import-Module Posh-SSH -EA Stop }
    catch { Write-Host "Модуль Posh-SSH не загружен!`nСсылка для скачивания https://www.powershellgallery.com/packages/Posh-SSH/2.1`nДальнейшее выполнение скрипта невозможно..." -f Red; break }
}

#Создаем папку куда сохранять, если нету таковой
if ( !(Test-Path $Path -PathType Container) ) { New-Item -ItemType Directory -Path $Path -Force }

if ( Test-Path $FileDevice ) {
    $devices = Import-Csv $FileDevice

    if ( $devices.Length -ne 0 ) {
        #Данные для авторизации
        $cred = Get-Credential -Credential $UserName
        #если пароль на enable совпадает с паролем на авторизацию можно так       $enpwd = $cred.GetNetworkCredential().password

        foreach ( $item in $devices ) {
            if ( Test-Connection -ComputerName $item.ip -Count 2 -Quiet -ea SilentlyContinue ) { getcfg $item.ip $item.type $item.enpwd }
            else { Write-Host "Устройство "$item.ip" недоступно." -f Magenta }
        }
    }
    else { Write-Host "Файл со списком устройств пуст!" -f Red }
}
else { Write-Host "Файл со списком устройств не найден!" -f Red }
