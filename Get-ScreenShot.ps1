function Get-ScreenShot {
<#
.SYNOPSIS
Делает снимок экрана как картинку в текущую папку.

.DESCRIPTION
Делает снимок экрана как картинку в текущую папку.


.EXAMPLE
Get-Screenshot
Делает снимок экрана как картинку в папку.

.NOTES
ИМЯ: Get-Screenshot.ps1
ЯЗЫК: PoSH
ДАТА СОЗДАНИЯ: 30.05.2018
#>

[CmdletBinding()]

Param ()

Process {
    [string]$Path = Get-Location

    [void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    $size = [Windows.Forms.SystemInformation]::VirtualScreen

    $bitmap = new-object Drawing.Bitmap $size.width, $size.height

    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($size.location, [Drawing.Point]::Empty, $size.size)
    $graphics.Dispose()

    $bitmap.Save("$Path\scr-$ComputerName.png")
    $bitmap.Dispose()

}#Process

}#function