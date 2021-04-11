<#
.SYNOPSIS
Создает список групповых политик и их бэкапы.

.DESCRIPTION
Создает список групповых политик и их бэкапы с анализом наличия изменений.

.PARAMETER Path
Задает путь для сохранения групповых политик в папку по дате. Не обязательный параметр.
Формат: "C:\Policy"
Предыдущий список политик, если есть, будут сохранен как old.
По умолчанию: Текущий каталог

.EXAMPLE
Get-BackupPolicy.ps1 -Path "C:\Policy"
Создает список политик и их бэкапы в папку C:\Policy с анализом изменений.

.NOTES
ИМЯ: Get-BackupPolicy.ps1
ПРОТЕСТИРОВАНО НА: PowerShell v5.1
ДАТА СОЗДАНИЯ: 29.03.2019
АВТОР: Полетаев Сергей
#>
[CmdletBinding()]

param (
    [Parameter (Mandatory = $false, Position=1)]
    [string]$Path = (Get-Location).Path
)

$Day     = (Get-Date).day
$Month   = (Get-Date).month
$Year    = (Get-Date).year
$PathNew = $Path+"\GPO-$day.$month.$year"

New-Item -path $PathNew -type directory -force -EA Stop

Backup-Gpo -All -Path $PathNew -EA Stop

$BackupList  = "listbackup.csv"
$FileList    = "listpolicy.csv"
$FileListold = "listpolicy`_old.csv"

#Переименовываем старый список, если он есть
if ( Test-Path $Path\$FileList ) { 
    Remove-Item -Path $Path\$FileListold -Force -EA Stop
    Rename-Item -Path $Path\$FileList -NewName $FileListold -Force -EA SilentlyContinue
}
#Делаем новый список политик
Get-GPO -All | select DisplayName,Id,GpoStatus,CreationTime,ModificationTime,Description | Export-Csv $Path\$FileList -NoTypeInformation -Delimiter ";" -Force -Encoding UTF8

#Делаем список бэкапа политик с соответствием каталога, чтобы легче было искать
$allGPO = Get-GPO -All -EA Stop

Set-Content -Path $PathNew\$BackupList -Value "Name;PathID;GuidID;Status;CreationTime;ModificationTime;WmiFilter;Description" -Encoding UTF8 -EA SilentlyContinue

foreach ($GPO in $allGPO) {
    [xml]$xml = Get-Content "$PathNew\manifest.xml"
    
    for ( $i=0; $i -le $xml.Backups.BackupInst.Count; $i+=1 ) {
        if ( [string]$xml.Backups.BackupInst[$i].GPOGuid.'#cdata-section' -match [string]$GPO.ID ) { [string]$ID = $xml.Backups.BackupInst[$i].ID.'#cdata-section' }
    }
    
    $data = $GPO.DisplayName,$ID,$GPO.Id,$GPO.GpoStatus,$GPO.CreationTime,$GPO.ModificationTime,$GPO.WmiFilter.Name,$GPO.Description -join ";"
    if ( $data ) { Add-Content -Path $PathNew\$BackupList -Value $data -Encoding UTF8 }
}

#Сравниваем списки политик
if ( (Test-Path $Path\$FileList) -and (Test-Path $Path\$FileListold) ) {
    $change = Compare-Object -referenceobject $(get-content $Path\$FileList) -differenceobject $(get-content $Path\$FileListold)

    if ( $change.Count -gt 0 ) { Write-Host "Есть изменения!`n`n$change" -f Magenta }
    else { Write-Host "Без изменений!" -f Green }
}
else { Write-Host "Нет одного из файов для сравнения!" -f DarkGray }
