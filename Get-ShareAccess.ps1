function Get-ShareAccess {
<#
.SYNOPSIS
Выводит данные по действиям с файлом.

.DESCRIPTION
Предназначен для контроля над действиями пользователей с файлом на файловом сервере.
Использует журнал безопасности с включенным аудитом на windows server 2008r2.

.PARAMETER $FileName
Задает имя проверяемого файла. Обязательный параметр.
По умолчанию: текущий компьютер

.PARAMETER $LastHours
Задает глубину времени в часас от текущего времени. Не обязательный параметр.
По умолчанию: 1 час

.PARAMETER $ShareServer
Задает имя файлового сервера на котором ведется аудит доступа. Не обязательный параметр.
По умолчанию: server1

.PARAMETER $EventId
Задает идентификатор события по которому искать. Может принимать 2 значения: 4659 и 4663. Не обязательный параметр.
По умолчанию: 4663

.EXAMPLE
Get-ShareAccess "file.xlsx"
Выводит данные контроля по событию 4663 над действиями пользователей с файлом "file.xlsx" на сервере "server1" за последний час.

.EXAMPLE
Get-ShareAccess -FileName "file.xlsx" -LastHours 2 -ShareServer server1 -EventId 4659
Выводит данные контроля по событию 4659 над действиями пользователей с файлом "file.xlsx" на сервере "server1" за последние 2 часа.

.NOTES
ИМЯ: Get-ShareAccess.ps1
ЯЗЫК: PoSH
ДАТА СОЗДАНИЯ: 03.07.2020
АВТОР: Полетаев Сергей
#>

[CmdletBinding()]

param (
    [Parameter (Mandatory = $true, Position=0)]
    [string] $FileName,

    [Parameter (Mandatory = $false, Position=1)]
    [int] $LastHours=1,

    [Parameter (Mandatory = $false, Position=2)]
    [string] $ShareServer="server1",

    [Parameter (Mandatory = $false, Position=3)]
    [ValidateSet(4659,4663)]
    [int] $EventId=4663
)

Process {
    $Date = (Get-Date).AddHours(-$LastHours)
    $arr = Get-WinEvent -ComputerName $ShareServer -FilterHashtable @{ LogName='Security'; StartTime=$Date; Id=$EventId } | ?{$_.Message -match $FileName }

    foreach ($evnt in $arr) {
        $dt = $evnt.TimeCreated

        $startindex = $evnt.Message.IndexOf("Account Name:") + 14
        $endindex = $evnt.Message.IndexOf("Account Domain:")
        $len = $endindex - $startindex

        $account = $evnt.Message.Substring($startindex, $len)

        $startindex = $evnt.Message.IndexOf("Object Name:") + 12
        $endindex = $evnt.Message.IndexOf("Handle ID:")
        $len = $endindex - $startindex

        $file = $evnt.Message.Substring($startindex, $len)

        $startindex = $evnt.Message.IndexOf("Accesses:") + 9
        $endindex = $evnt.Message.IndexOf("Access Mask:")
        $len = $endindex - $startindex

        $task = $evnt.Message.Substring($startindex, $len)

        $out += "$dt $account $file $task`n"
    }
    $out
} #Process
}#function