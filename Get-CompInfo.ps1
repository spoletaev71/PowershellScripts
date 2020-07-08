
function Decode {
    If ($args[0] -is [System.Array]) { [System.Text.Encoding]::ASCII.GetString($args[0]) }
    Else {"не найдено"}
} #function


function Get-CompInfo {
<#
.SYNOPSIS
Выводит данные по АРМ.

.DESCRIPTION
Предназначен для инвентаризации моделей, конфигурации и серийных номеров оборудования АРМ.

.PARAMETER $Name
Задает имя проверяемого компьютера. Не обязательный параметр.
По умолчанию: текущий компьютер

.EXAMPLE
Get-CompInfo
Выводит данные по локальному АРМ.

.EXAMPLE
Get-ADComputer -Filter * -SearchBase 'ou=Computers,dc=Domain,dc=com' | Get-CompInfo
Выводит данные по АРМ из контейнера AD "Computers" в домене domain.com

.EXAMPLE
Get-ADComputer -Filter * | Get-CompInfo > inventory.txt
Получает данные по АРМ из всего домена и выгружает их в файл inventory.txt.

.NOTES
ИМЯ: Get-CompInfo.ps1
ЯЗЫК: PoSH
ДАТА СОЗДАНИЯ: 28.05.2018
АВТОР: Полетаев Сергей
#>
[CmdletBinding()]

param (
    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [string]$Name = $env:COMPUTERNAME
)

Process {
    #Проверка доступности компьютера            
    if ( Test-Connection -Delay 1 -ComputerName $Name -Count 2 -Quiet -ea SilentlyContinue ) {
        try {
            #Запросы к компьютеру
            $csys = gwmi Win32_ComputerSystem              -ComputerName $Name -ea SilentlyContinue
            $osys = gwmi Win32_OperatingSystem             -ComputerName $Name -ea SilentlyContinue
            $bios = gwmi Win32_bios                        -ComputerName $Name -ea SilentlyContinue
            $proc = gwmi Win32_Processor                   -ComputerName $Name -ea SilentlyContinue
            $mem  = gwmi Win32_PhysicalMemory              -ComputerName $Name -ea SilentlyContinue
            $net  = gwmi Win32_NetworkAdapterConfiguration -ComputerName $Name -ea SilentlyContinue -Filter "IPEnabled='TRUE'"
            $disk = gwmi Win32_DiskDrive                   -ComputerName $Name -ea SilentlyContinue | ?{$_.InterfaceType -ne "USB"}
            $mon  = gwmi WmiMonitorID                      -ComputerName $Name -ea SilentlyContinue -Namespace root\wmi
            $ups  = gwmi Win32_Battery                     -ComputerName $Name -ea SilentlyContinue
            $prn  = gwmi Win32_Printer                     -ComputerName $Name -ea SilentlyContinue -Filter "Default='TRUE'"
        }
        catch{ 
        #exit 5
        }
        #Подготовка переменных к выводу
        [string]$memLocate = ''
        [string]$memModel  = ''
        [string]$memSize   = ''
        foreach ($planka in $mem) {
            [string]$memLocate += [string]$planka.DeviceLocator + ',  '
            [string]$memModel  += [string]$planka.PartNumber + ', '
            [string]$memSize   += [string]([math]::Truncate($planka.Capacity/1Gb)) + 'Gb,   '
        }
        [string]$diskModel = ''
        [string]$diskSize  = ''
        foreach ($hdd in $disk) {
            [string]$diskModel += [string]$hdd.Model + ',  '
            [string]$diskSize  += [string]([math]::Round(($hdd.Size/1Gb), 2)) + 'Gb,  '
        }

        #Формируем объект типа хэш-массив
        $myobj = [pscustomobject]@{
            Manufacturer         = $csys.Manufacturer
            Model                = $csys.Model
            DNSHostName          = $csys.DNSHostName
            Name                 = $csys.__SERVER
            OS                   = $osys.Name+" "+$osys.OSArchitecture
            LogonUser            = $csys.UserName
            ComputerSerialNumber = $bios.SerialNumber
            CPUModel             = $proc.Name
            CPUNumber            = [string]$csys.NumberOfProcessors+' x'+[string]$proc.AddressWidth
            CPUNumberCORE        = $proc.NumberOfCores
            CPUNumberLogical     = $csys.NumberOfLogicalProcessors
            RAMVolume            = [string]([math]::Ceiling($csys.TotalPhysicalMemory/1Gb)) + 'Gb'
            MemoryLocation       = $memLocate 
            MemoryPartNumber     = $memModel
            MemoryVolume         = $memSize
            NetAdapter           = $net.Description
            IPAddress            = $net.IPAddress
            MACAddress           = $net.MACAddress
            HDDModel             = $diskModel
            HDDSize              = $diskSize
            MonitorModel         = (Decode $mon.UserFriendlyName)
            MonitorSerialNumber  = (Decode $mon.SerialNumberID)
        }
        #Добавляем данные в массив, если обнаружено что-то
        if ($ups.DeviceID -ne $null) { $myobj | Add-Member -MemberType NoteProperty -Name UPSSerialNumberModel -Value $ups.DeviceID }
        if ($prn.Name     -ne $null) { $myobj | Add-Member -MemberType NoteProperty -Name DefaultPrinterModel  -Value $prn.Name }
        if ($prn.PortName -ne $null) { $myobj | Add-Member -MemberType NoteProperty -Name DefaultPrinterPort   -Value $prn.PortName }

        #Создаем свой тип объекта
        #$myType = "my.ComputerInfo"
        #$myobj.psobject.TypeNames.Insert(0, $myType)

        #Вывод массива
        $myobj
    }
    else { "$Name ------------- отключен -----------------" }
    #exit 0
} #Process
} #Function
