# Заполняем значения переменных
$From       = "Report@firma.ru"
$To         = "usermail@firma.ru"
$Subject    = "Ошибка копирования бэкапа с сервера"
$MailServer = "server.firma.ru"
$Encoding   = [System.Text.Encoding]::utf8

$source ="d:\backup\"
$dest ="\\192.168.2.1\backups\"
$mask ="*.txt"

# Определяем исходные файлы
$files = dir ($source+$mask).tostring()

Try {
    if ($files -ne $null) {
        # сравниваем каталоги, определяем отсутствующие файлы по маске в папке-приемнике и копируем недостающие из папки-источника 
        $cmpdir = Compare-Object (gci $source) (gci $dest)

        if ($cmpdir | Where-Object {($_.SideIndicator -eq ‘<=’) -and ($_.InputObject -like $mask)}) {
            $cmpdir | Where-Object {($_.SideIndicator -eq ‘<=’) -and ($_.InputObject -like $mask)} | ForEach-Object {
                Copy-Item ($_.InputObject).FullName -Destination $dest -ErrorAction Stop    #if(-not $?){ $err = $_.Exception.Message }
            }
        }
        else {Write-Host "Все файлы уже существуют."}

    }
    else {Write-Host "Нет файлов в исходной папке."}
}
Catch {
    # Добавляем ошибку в текст письма и отправляем администратору
    $Body = ForEach-Object{ $error }
    Send-MailMessage -SmtpServer $MailServer -To $To -From $From -Subject $Subject -Body $Body -Encoding $Encoding -EA SilentlyContinue
}
Finally {
    # удаление всех файлов кроме 3-х свежайших в папке-источнике
    get-item -path ($source+$mask).tostring() | Sort -property lastwritetime -desc | select -skip 3 | Remove-Item
}