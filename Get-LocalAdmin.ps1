#Скрипт формирует файл с пользователями в группе админов по компам домена

# Функция проверки
Function Check {
param (
    $List,
    $CheckALL,
    $CheckYES,
    $CheckNO,
    $CheckERR,
    $Container
)

Process {
    #Выбираем все ПК из нужного OU, которые логинились за последние 90 дней
    $CompObj = Get-ADComputer -SearchBase "$Container" -Filter * -Properties LastLogonDate | ?{((get-date) - ($_.LastLogonDate)).Days -le 90} | select DNSHostName | sort DNSHostName

    #Проверка не устарел ли полный список компов (действителен в текущие сутки),
    #если не протух еще, то готовим список на добивание недоступных и с ошибками (вдруг включили и исправились ошибки;)
    if ( Test-Path $CheckALL ) {
        $flAll = Get-ChildItem -Path $CheckALL

        if ( ($flAll.LastWriteTime).Date -eq (Get-Date).Date ) { $CheckALLOld = $false }
        else { $CheckALLOld = $true }
    }
    else { $CheckALLOld = $true }
    #Если проверка была не сегодня, то создаем логи, иначе работаем по необработанным
    if ( $CheckALLOld ) {
        $CompObj.DNSHostName | Set-Content -Path $CheckALL -Encoding UTF8
        $comps = Get-Content -Path $CheckALL
        Set-Content -Path $List     -Value "PC;Domain;LocalAdmin" -Encoding UTF8
        Set-Content -Path $CheckYES -Value $null
        Set-Content -Path $CheckNO  -Value $null
        Set-Content -Path $CheckERR -Value $null
    }
    else {
        if ( (Test-Path $CheckNO) -or (Test-Path $CheckERR) ) {
            if ( Test-Path $CheckNO ) { 
                if ((Get-Content -Path $CheckNO).count -ge 1 ) 
                    { $comps = Get-Content -Path $CheckNO; Set-Content -Path $CheckNO  -Value $null }
            }
            if ( Test-Path $CheckERR ) {
                if ((Get-Content -Path $CheckERR).count -ge 1 ) 
                    { $comps += Get-Content -Path $CheckERR; Set-Content -Path $CheckERR -Value $null }
            }
        }
    }

    #Сама проверка, если есть чего проверять, то заполнение отчета и логов
    if ( $comps ) {
        $spVoice = new-object -com "SAPI.spvoice"
        foreach ($comp in $comps) {
            if (Test-Connection -ComputerName $comp -Count 1 -Quiet -EA SilentlyContinue) {

                try {
                    $admins = gwmi win32_groupuser -ComputerName $comp -EA SilentlyContinue `
                        | ? {($_.groupcomponent –like '*"Administrators"') -or ($_.groupcomponent –like '*"Администраторы"') }

                    if ($admins) {
                        foreach ($admin in $admins) {
                            $LocalAdmin = $admin.PartComponent.Split('="')[2,5] -join ";"
                            $data = $comp,$LocalAdmin -join ';'
                            Add-Content -Value $data -Path $List -Encoding UTF8
                        }
                        Write-Host $comp "`t`t- готово" -f DarkGray
                        Add-Content -Path $CheckYES -Value $comp -Encoding UTF8
                    }
                    else {
                        $spVoice.Speak("oshibka vmeai")
                        Write-Host $comp "`t`t- ошибка WMI!" -f Red
                        Add-Content -Path $CheckERR -Value $comp -Encoding UTF8
                    }
                }
                catch {
                    if ( $_.Exception.Message -like "*0x800706BA*" ) { 
                        $spVoice.Speak("oshibka dostupa rpc")
                        Write-Host $comp "`t`t- RPC недоступен!" -f Red
                    else {
                        $spVoice.Speak("neizvestnaya oshibka")
                        Write-Host "`n$comp `t`t- неизвестная ошибка!`t`t$_.Exception.Message`n" -f Red
                    }
                    Add-Content -Path $CheckERR -Value $comp -Encoding UTF8 }
                }
            }
            else {
                Write-Host $comp "`t`t- недоступен!" -f Magenta
                Add-Content -Path $CheckNO -Value $comp -Encoding UTF8
            }
        }
    }
    else { Write-Host " На СЕГОДНЯ непроверенных компов нет!" -f Green }

    Write-Host "`nВсего компов: " (Get-Content -Path $CheckALL).Count ', Проверено:' (Get-Content -Path $CheckYES).Count `
                ', Недоступно:' (Get-Content -Path $CheckNO).Count ', С ошибками: ' (Get-Content -Path $CheckERR).Count
}#Process
}#Function

#######################
##                   ##
##  Основной модуль  ##
##                   ##
#######################

#Где искать и куда складывать лог файлы
$Path        = 'D:\Check_LocalAdmin\'

$place = Read-Host "Введите площадку для опроса:`n 0 - Все площадки (All) `n 1 - ГП-1 (GP1)`n 2 - Москва (MSK)`n 3 - НУр (NUX)`n"

Write-Host "begin " (Get-Date)

#Подготовка переменных для площадок
switch ( $place ) {
    0 {
        $filial = 'All'
        $Container = 'OU=Domain Computers,DC=domain,DC=com'
        break
    }
    1 {
        $filial = 'GP1'
        $Container = 'OU=GP,OU=Domain Computers,DC=domain,DC=com'
        break
    }
    2 {
        $filial = 'MSK'
        $Container = 'OU=MSK,OU=Domain Computers,DC=domain,DC=com'
        break
    }
    3 {
        $filial = 'NUX'
        $Container = 'OU=NUX,OU=Domain Computers,DC=domain,DC=com'
        break
    }
    default { Write-Host "`n Не угадал с площадкой ;)`n Попробуй еще раз." -f Red; break }
}

if ( $place -in 0,1,2,3 ) {
    $List      = $Path+"AdmCheck-$filial-List.csv"
    $CheckALL  = $Path+"ALL-$filial.txt"
    $CheckYES  = $Path+"AdmCheck-$filial-YES.txt"
    $CheckNO   = $Path+"AdmCheck-$filial-NO.txt"
    $CheckERR  = $Path+"AdmCheck-$filial-ERR.txt"
    
    #Вызов функции проверки
    Check $List $CheckALL $CheckYES $CheckNO $CheckERR $Container
    
    Write-Host "`nДля проверки СЕГОДНЯ всех компов площадки, надо убрать логи (AdmCheck-* файлы по проверяемой площадке в каталоге $Path)." -f Green
}

Write-Host "end " (Get-Date)
