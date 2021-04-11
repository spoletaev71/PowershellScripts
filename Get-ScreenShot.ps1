function Get-ScreenShot {
<#
.SYNOPSIS
Делает снимок экрана как картинку в папку.

.DESCRIPTION
Делает снимок экрана как картинку в папку.

.PARAMETER $ComputerName
Задает имя проверяемого компьютера. Не обязательный параметр.
По умолчанию: текущий компьютер

.EXAMPLE
Screenshot.ps1
Делает снимок экрана как картинку в папку.

.EXAMPLE
Get-ADComputer -Filter * -SearchBase "ou=DomainComputers,dc=domain,dc=ru" | %{./Screenshot.ps1 $_.name}
Делает снимок экрана как картинку в папку для компьютеров из контейнера AD "ou=DomainComputers,dc=domain,dc=ru".

.NOTES
ИМЯ: Screenshot.ps1
ЯЗЫК: PoSH
ДАТА СОЗДАНИЯ: 30.05.2018
#>

[CmdletBinding()]

Param (
    [Parameter (Mandatory = $false, Position = 0)]
    [String]$ComputerName = 'LOCALHOST'
)

Process {
    [string]$Path = Get-Location

    if ($ComputerName = 'LOCALHOST') { $ComputerName = $env:COMPUTERNAME }
    
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
	    [void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    	$size = [Windows.Forms.SystemInformation]::VirtualScreen
	    $bitmap = new-object Drawing.Bitmap $size.width, $size.height
    	$graphics = [Drawing.Graphics]::FromImage($bitmap)
	    $graphics.CopyFromScreen($size.location,[Drawing.Point]::Empty, $size.size)
    	$graphics.Dispose()
	    $bitmap.Save("$Path\scr-$ComputerName.png")
    	$bitmap.Dispose()
    }
}#Process
}#function