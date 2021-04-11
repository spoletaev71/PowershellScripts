function Get-ActivationStatus {
 <#
.SYNOPSIS
Выводит данные по лицензиям АРМ.

.DESCRIPTION
Предназначен для инвентаризации по лицензиям АРМ.

.PARAMETER $Name
Задает имя проверяемого компьютера. Не обязательный параметр.
По умолчанию: текущий компьютер

.EXAMPLE
Get-ActivationStatus
Выводит данные для локальному АРМ.

.EXAMPLE
Get-ADComputer -SearchBase "ou=Domain Computers,dc=domain,dc=com" -Filter * | sort Name | Get-ActivationStatus | ft -AutoSize
Выводит данные по АРМ из контейнера AD.

.EXAMPLE
Get-ADComputer -SearchBase "ou=Domain Computers,dc=domain,dc=com" -Filter * | sort Name | Get-ActivationStatus | ft -AutoSize > inventory.txt
Выводит данные по АРМ из из контейнера AD и выгружает их в файл inventory.txt.

.NOTES
ИМЯ: Get-ActivationStatus.ps1
ЯЗЫК: PoSH
ДАТА ДОРАБОТКИ: 26.12.2018
АВТОР ДОРАБОТКИ: Полетаев Сергей
#>
[CmdletBinding()]
 
param(
    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [string]$Name = $Env:COMPUTERNAME
)
 
process {

    if (Test-Connection -Delay 1 -ComputerName $Name -Count 1 -Quiet -ea SilentlyContinue) {

        try { $wpa = Get-wmiobject SoftwareLicensingProduct -ComputerName $Name  | where PartialProductKey }
        catch {
            $status = New-Object ComponentModel.Win32Exception ($_.Exception.ErrorCode)
            $wpa = $null 
        }

        if ($wpa) {
            foreach($item in $wpa) {

                $out = New-Object psobject -Property @{
                    ComputerName = $Name;
                    Status = [string]::Empty;
                    App = $item.Name;
                    TypeKey = $item.ProductKeyChannel;
                    Key = $item.PartialProductKey;
                    KMSName = $item.DiscoveredKeyManagementServiceMachineName;
                    KMSIP = $item.DiscoveredKeyManagementServiceMachineIPAddress;
                    KMSPort = $item.DiscoveredKeyManagementServiceMachinePort;
                }
                switch ($item.LicenseStatus) {
                    0       {$out.Status = "Unlicensed"}
                    1       {$out.Status = "Licensed"}
                    2       {$out.Status = "Out-Of-Box Grace Period"}
                    3       {$out.Status = "Out-Of-Tolerance Grace Period"}
                    4       {$out.Status = "Non-Genuine Grace Period"}
                    5       {$out.Status = "Notification"}
                    6       {$out.Status = "Extended Grace"}
                    default {$out.Status = "Unknown value"}
                }

                $out | select ComputerName,App,Status,Key,TypeKey,KMSIP,KMSName,KMSPort
            }
        }
        else { $out.Status = $status.Message }
    }
    else { "$Name ------- недоступен ---------" }
} #process
} #function
