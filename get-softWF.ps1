#####################################################################################
## ИМЯ: get-softWF.ps1
## ЯЗЫК: PoSH V5
## ДАТА ИЗМЕНЕНИЯ: 02.12.2022
## АВТОР: Полетаев Сергей
## ОПИСАНИЕ: Скрипт для многопоточного сканирования доменных компов на установленное ПО
## и сканирования дисков на наличие фалов по маске(см.тело функции File_search).
## Можно добавить в планировщик заданий для наличия всегда свежей информации. 
## 
## Вызов: ./get-softWF.ps1
#####################################################################################


#создаем многопоточный процесс
workflow Check_softWF {
param (
    $computers,
    $path,
    $logfile,
    $streams
)


    #поиск софта
    function Soft_search {
    param ($srv,$os)
        try {
            $app32 = Invoke-command -ComputerName $srv -EA Stop -ScriptBlock { Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* }

            if ( $os.OSArchitecture -match '64' ) {
                $app64 = Invoke-command -ComputerName $srv -EA SilentlyContinue -ScriptBlock { Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* }

                #Данные на выход
                $soft = $app32 + $app64 | ?{ $_.DisplayName -notlike "security update*" -and $_.DisplayName -notlike "update*" } | sort DisplayName -Unique `
                    | ft DisplayName,DisplayVersion -AutoSize
            }
            else {
                #Данные на выход
                $soft = $app32 | ?{ $_.DisplayName -notlike "security update*" -and $_.DisplayName -notlike "update*" } | sort DisplayName -Unique `
                    | ft DisplayName,DisplayVersion -AutoSize
            }
            $soft
        }
        catch { "Ошибка подключения WinRM!", $_ }
    }#Soft_search


    #поиск файлов по маске(см.тело функции)
    function File_search {
    param ($srv)
        try {
            $files = Invoke-Command -ComputerName $srv -EA Stop -ScriptBlock {

                # Какие файлы будем искать !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                $include = @('*.exe','*.bat','*.cmd','*.aac','*.aif*','*.flac','*.wm*','*.avi','*.mp*','*.fb2','*.epub','*.djvu')
                # Какие папки исключаем из поиска !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                $exclude = @('Program*','Windows*')

                #инфа о логических дисках
                $disk = Get-WmiObject Win32_LogicalDisk -Filter 'DriveType=3' -EA Stop
                
                foreach ($dsk in $disk) {
                    $folders = Get-ChildItem -Path ($dsk.name + "\") -Directory -Name -Exclude $exclude

                    foreach ($folder in $folders) {
                        [string]$f_path = $dsk.name + "\$folder\"
                        $f_files = Get-ChildItem -Path $f_path -Include $include -File -Name -Recurse -EA SilentlyContinue
                        
                        #данные на выход
                        if ($f_files) { '';$f_path;$f_files }
                    }
                }
            }#end invoke-command scriptblock
            $files
        }
        catch { "Ошибка подключения WinRM!", $_ }
    }#File_search


    $data_soft  = @()
    $data_files = @()
    $log        = @()

    #запуск 30 потоков по компам
    foreach -Parallel -ThrottleLimit $streams ($comp in $computers) {
        $srv = $comp.name
        $journal = "$path$srv.txt"

        if (!(Test-Connection $comp.name -Count 2 -Quiet -EA SilentlyContinue)) { $log_tmp = "$srv `t`t`t`t-отключен!`n" }
        else {
            try {
                $os = Get-WmiObject Win32_OperatingSystem -PSComputerName $srv -EA Stop  #инфа об ОС

                $lst_soft  = Soft_search $srv $os  #поиск софта
                $lst_files = File_search $srv      #поиск файлов по маске(см.тело функции)

                $log_tmp   = "$srv `t`t- готово.`n"
            }
            catch {$log_tmp = "$srv `t`t`t`t- ошибка подключения WMI!`n" }
        }
        $workflow:data_soft  = $lst_soft
        $workflow:data_files = $lst_files
        $workflow:log       += $log_tmp

        if ($data_soft)  { Out-File -FilePath $journal -InputObject $data_soft -Encoding utf8 }
        if ($data_files) { Out-File -FilePath $journal -InputObject $data_files -Encoding utf8 -Append}
    }#foreach

    if ($log) { Out-File -FilePath "$path$logfile" -InputObject $log -Append }
}#workflow



if ( !(Get-Module ActiveDirectory) ) { try { Import-Module ActiveDirectory } catch { Write-Host 'Не загружен модуль ActiveDirectory! Выполнение скрипта невозможно.'; exit } }

#контейнер AD с компами для проверки
$domain  = (Get-ADDomain).DistinguishedName
$ou      = 'Computers'
#куда складывать отчеты
$path    = 'C:\Temp\Scan-comp\'
$logfile = '!get-soft.log'
#количество потоков для параллельного сканирования
$streams = 30

if ( $ou.Length -ne 0 ) {
    $Search = New-Object DirectoryServices.DirectorySearcher($domain)
    $Search.Filter = "(&(ou=$ou))"
    $Search.SearchScope = 2
    $result = $Search.FindAll()

    if ( $result -eq $null ) { Write-Host "Ошибочка: $ou - Такого контейнера нет в AD домена $domain"; Exit }
    else { [string]$SearchBase = $result.GetDirectoryEntry().DistinguishedName }
}
else { [string]$SearchBase = $domain }

$computers = Get-ADComputer -SearchBase $SearchBase -Filter 'Enabled -eq "true"' | select name
Write-Host "В контейнере AD: $ou, найдено компов: "$computers.Count

if ($computers) {
    if ( Test-Path "$path$logfile" ) { Get-Date -UFormat "%d.%m.%y  %R" | Out-File -Append "$path$logfile" }
    else { Get-Date -UFormat "%d.%m.%y  %R" | Out-File "$path$logfile" -Force }

    Write-Host "Начинаем их сканирование в $streams потоков... Ждите!"

    Check_softWF $computers $path $logfile $streams
    
    Write-Host "Сканирование завершено. Все отчеты в папке $path"
}
