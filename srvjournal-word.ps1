#####################################################################################
## ИМЯ: srvjournal-word.ps1
## ЯЗЫК: PoSH V2
## ДАТА ИЗМЕНЕНИЯ: 01.07.2020
## АВТОР: Полетаев Сергей
## ОПИСАНИЕ: Скрипт для создания журнала о конфигурации серверов или компов в Word.
## Запускать с любого компа в сети из консоли PowerShell.
## Вызов: ./srvjournal-word.ps1
##
#####################################################################################


function ConvertTo-Encoding ([string]$From, [string]$To){

Begin {
    $encFrom = [System.Text.Encoding]::GetEncoding($From)
    $encTo = [System.Text.Encoding]::GetEncoding($To)
}

Process {
    $bytes = $encTo.GetBytes($_)
    $bytes = [System.Text.Encoding]::Convert($encFrom, $encTo, $bytes)
    $encTo.GetString($bytes)
}

}#function ConvertTo-Encoding



function Get-TimeSetting {

param ( [string]$NameServer )

    Try {
        if ($NameServer -eq $env:computername) {
            $ts = (w32tm /query /status) | Out-String
            $ts += (w32tm /query /configuration) | Out-String
        }
        else {
            $ts = Invoke-Command -ScriptBlock { (w32tm /query /status) | Out-String } -ComputerName $NameServer -Credential $cred
            $ts += Invoke-Command -ScriptBlock { (w32tm /query /configuration) | Out-String } -ComputerName $NameServer -Credential $cred
        }
        if ($psISE) { $ts | ConvertTo-Encoding cp866 windows-1251}
        else { $ts }
    }
    Catch {
        $ts = $_.Exception.Message
        $ts
    }
}#function Get-TimeSetting



function Get-Permissions {

param (
    [string]$Path,
    [string]$NameServer
)

    $Array = @()

    Try {
        if ($NameServer -eq $env:computername) { $ACLs = Get-Acl $Path | Select-Object -ExpandProperty Access }
        else { $ACLs = Invoke-Command -ScriptBlock {param($Path) Get-Acl $Path | Select-Object -ExpandProperty Access } -ComputerName $NameServer -Credential $cred -ArgumentList $path }
    }
    Catch {
        $_.Exception.Message
        Continue
    }

    if ($ACLs) {
        $ACLs | ForEach-Object {
            $item = $_
            Switch ($item.FileSystemRights) {
                'AppendData'                  { $Val = 'AppendData' }
                'FullControl'                 { $Val = 'FullControl' }
                'Modify, Synchronize'         { $Val = 'Modify, Synchronize' }
                'ReadAndExecute, Synchronize' { $Val = 'ReadAndExecute, Synchronize' }
                '-536805376'                  { $Val = '-536805376(RdExMdWrDel)' }
                '2032127'                     { $Val = '2032127(FullControl)' }
                '1179785'                     { $Val = '1179785(Read)' }
                '1180063'                     { $Val = '1180063(RdWr)' }
                '1179817'                     { $Val = '1179817(RdEx)' }
                '-1610612736'                 { $Val = '-1610612736(RdExExt)' }
                '1245631'                     { $Val = '1245631(RdExMdWr)' }
                '1180095'                     { $Val = '1180095(RdExWr)' }
                '268435456'                   { $Val = '268435456(FC Subfolder Only)' }
            }
            $Object = New-Object PSObject -Property @{ 
                IdentityReference      = $Item.IdentityReference           
                AccessControlType      = $Item.AccessControlType
                FileSystemRights       = $val     
                IsInherited            = $Item.IsInherited
                InheritanceFlags       = $Item.InheritanceFlags
                PropagationFlags       = $Item.PropagationFlags
            }
            $Array += $Object
        }
    }

    if ($Array) { $Array | Select-Object IdentityReference,AccessControlType,FileSystemRights,IsInherited,InheritanceFlags,PropagationFlags }

}#function Get-Permissions



function Decorate_report {

Param ( 
    [int]$progressbar_value,
    [string]$text_header

)

    $ProgressBar.Value = $progressbar_value
    if (($ProgressBar.Value -ge 45) -and ($ProgressBar.Value -lt 80)) { $Label.Text = "Выполняется $text_header, процедура долгая...ждите" }
    else { $Label.Text = "Выполняется $text_header" }
    $main_form.Update()
    Start-Sleep 2
    if (!$Selection.Font.Bold) { $Selection.Font.Bold = $true }
    $Selection.Font.Size = 11
    $Selection.TypeText("`n$text_header"+':')
    $Selection.Font.Size = 8
    $Selection.Font.Bold = $false

}#function Decorate_report



function OKButton_click {

Param ( [String]$NameServer )

begin{
    $Label.Text = "Проверка наличия MS Office Word..." 

    Try {
        #Создаем новый объект WORD
        $word = New-Object -ComObject Word.Application -ea stop
        #Создаем новый документ
        $journal = $word.Documents.Add()

#        $journal.CheckSpelling([ref]$null,[ref]$null,[ref]$null,[ref]$null)
    }
    catch {
        $Label.Text = 'Продолжение невозможно. Ошибка создания документа MS Word.'
        Write-Warning $Label.Text
        Start-Sleep 4
        $main_form.Close()
        $main_form.Dispose()
        exit
    }


    if ( ($NameServer -eq '' ) -or ( $NameServer -eq 'localhost' ) ) {
        $NameServer = $env:computername
        $params = @{}
    }
    elseif ( $NameServer -eq $env:computername ) { $params = @{} }
    else {
        $Label.Text = "Проверка доступности сервера $NameServer..." 
        if (Test-Connection -ComputerName $NameServer -Count 3 -Quiet) {
            $Label.Text = "Введите учетные данные администратора на сервере $NameServer"
            # Запрашиваем данные для авторизации на сервере
            $cred = Get-Credential -Credential sngpcom\poletaevsy
            $params = @{"ComputerName"=$NameServer;"Credential"=$cred}
            $Label.Text = "Сервер $NameServer доступен. Начинаем сбор данных..."
            Start-Sleep 2
        }
        else {
            $Label.Text = "Сервер $NameServer не найден в сети. Попробуйте другой."
            $TextBox.Enabled = $true
            $OKbutton.Enabled = $true
            $Cancelbutton.Enabled = $true
            $main_form.Update()
            Start-Sleep 2
            break
        }
    }
}#begin

Process {
    $main_form.Text = "Журналирование конфигурации сервера $NameServer"
    $main_form.Update()

    Try {
            $ProgressBar.Value = 0
            $TextBox.Enabled = $false
            $OKbutton.Enabled = $false
            $Cancelbutton.Enabled = $false
            Start-Sleep 2

            #Выбираем открывшийся документ для работы
            $Selection = $word.Selection

            #Устанавливаем отступы для документа
            $Selection.Pagesetup.Orientation  = 1
            $Selection.Pagesetup.TopMargin    = 15
            $Selection.Pagesetup.LeftMargin   = 30
            $Selection.Pagesetup.RightMargin  = 15
            $Selection.Pagesetup.BottomMargin = 15

            #Интервал отступов сверху и снизу
            $Selection.ParagraphFormat.SpaceBefore = 0
            $Selection.ParagraphFormat.SpaceAfter  = 0

            $date = (Get-Date).tostring('dd.MM.yyyy')

            #Выравнивание по центру
            $Selection.ParagraphFormat.Alignment = 1
            #Шрифт написания
            $Selection.Font.Name = 'Courier New'
            #Размер шрифта
            $Selection.Font.Size = 12
            #Пишем жирным
            $Selection.Font.Bold = $true
            $Selection.TypeText("Журнал настроек сервера $NameServer`n на $date`n")

            #Выравнивание по левому краю
            $Selection.ParagraphFormat.Alignment = 0

##1 Сведения о серверной платформе
            
            Decorate_report 5 '1. Сведения о серверной платформе'

            $out = Get-WmiObject Win32_ComputerSystem @params `
                | ForEach-Object{'Модель:         ',$_.Model,`
                                 "`nТип системы:    ",$_.SystemType,`
                                 "`nДомен:          ",$_.Domain,`
                                 "`nВведен в домен: ",$_.PartOfDomain}
            $Selection.TypeText("`n$out`n")

##2 Сведения о производителе, серийном номер и версии БИОС
            Decorate_report 10 '2. Сведения о производителе, серийном номере и версии БИОС'

            $out = Get-WmiObject Win32_BIOS @params `
                | ForEach-Object{'Производитель: ',$_.Manufacturer,`
                                 "`nСерийный №:    ",$_.SerialNumber,`
                                 "`nВерсия SMBIOS: ",$_.SMBIOSBIOSVersion,`
                                 "`nДата релиза:   ",$_.ReleaseDate}
            $out += "`nВерсия BIOS:  "
            $out += (Get-WmiObject Win32_BIOS -Property BIOSVersion @params).BIOSVersion
            $Selection.TypeText("`n$out`n")

##3 Сведения о процессоре
            Decorate_report 15 '3. Сведения о процессоре'
            $Selection.TypeText("`n")

            $out = Get-WmiObject Win32_Processor @params `
                | ForEach-Object{'Производитель: ',$_.Manufacturer,`
                                 "`nТип:           ",$_.Name,`
                                 "`nСокет:         ",$_.SocketDesignation,`
                                 "`nСостояние:     ",$_.Status,`
                                 "`nКэш L2(кБ):    ",$_.L2CacheSize,`
                                 "`nКэш L3(кБ):    ",$_.L3CacheSize,`
                                 "`nЧисло ядер:    ",$_.NumberOfCores,`
                                 "`nКол-во логических процессоров: ",$_.NumberOfLogicalProcessors}
            $Selection.TypeText("$out`n")

##4 Сведения об оперативной памяти
            Decorate_report 20 '4. Сведения об оперативной памяти'
            $Selection.TypeText("`n")

            $out = Get-WmiObject Win32_MemoryArray @params | ForEach-Object{[math]::Round($_.EndingAddress/1048576,0)}
            $Selection.TypeText("Общий объем оперативной памяти (GB): $out`n")
            $Selection.TypeText("`nПамять по физическим планкам:")
            $out = Get-WmiObject Win32_PhysicalMemory @params `
                | ForEach-Object{"`nСлот:          ",$_.DeviceLocator,`
                                 "`nПроизводитель: ",$_.Manufacturer,`
                                 "`nОбъем (MB):    ",[math]::Round($_.Capacity/1048576,0)}
            $Selection.TypeText("$out`n")

##5 Сведения о логических дисках
            Decorate_report 25 '5. Сведения о логических дисках'

            $out = Get-WmiObject Win32_LogicalDisk  -Filter 'DriveType=3' @params `
                | ForEach-Object{"`nДиск ",$_.DeviceID,[math]::Round($_.Size/1Gb),'ГБайт','   Файловая система:',$_.FileSystem}
            $Selection.TypeText("$out`n")

##6 Сведения об операционной системе
            Decorate_report 30 '6. Сведения об операционной системе'

            $os = Get-WmiObject Win32_OperatingSystem @params
            $out = $os | ForEach-Object{"`nОС:          ",$_.Caption,`
                                        "`nВерсия:      ",$_.Version,`
                                        "`nРазрядность: ",$_.OSArchitecture,`
                                        "`nЯзык:        ",$_.OSLanguage}
            $Selection.TypeText("$out`n")

##7 Сведения о подключении к доменной сети
            Decorate_report 35 '7. Сведения о подключении к доменной сети'

            $out = Get-WmiObject Win32_NTDomain -Filter 'Status = "OK"' @params `
                | ForEach-Object{"`nДомен:             ",$_.DnsForestName,`
                                 "`nСайт:              ",$_.DcSiteName,`
                                 "`nКонтроллер домена: ",$_.DomainControllerName}
            if ($out) { $Selection.TypeText("$out`n") }
            else { $Selection.TypeText("`n Нет подключения к сети`n") }

##8 Сведения о настройках времени
            Decorate_report 40 '8. Сведения о настройках времени'

            $out = Get-WmiObject Win32_TimeZone @params | ForEach-Object{"`nЧасовой пояс: ",$_.Caption}
            $Selection.TypeText("$out`n")
            $out = "`nСостояние и конфигурация NTP:`n"
            $Selection.TypeText("$out`n")
            $out = Get-TimeSetting $NameServer
            $Selection.TypeText("$out`n")

##9 Сведения об установленном ПО
            Decorate_report 45 '9. Сведения об установленном ПО'

            $app32 = Invoke-command @params { Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* }
            if ( $os.OSArchitecture -match '64' ) {
                $app64 = Invoke-command @params {
                             Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*
                         }
                $out = $app32 + $app64 | select DisplayName,DisplayVersion,Publisher,InstallDate | sort DisplayName -Unique
            }
            else {
                $out = $app32 | select DisplayName,DisplayVersion,Publisher,InstallDate | sort DisplayName -Unique
            }

            #$out = Get-WmiObject Win32reg_AddRemovePrograms @params | Select-Object DisplayName,Version,Publisher,InstallDate | Sort-Object Displayname -Unique
            #$out = Get-WmiObject win32_Product @params | select Name,Version | sort name
            #шапка таблицы
            $table = $word.ActiveDocument.Tables.Add($Word.Selection.Range, 1, 4)
            $table.Cell(1,1).Range.Text = 'Наименование ПО'
            $table.Cell(1,2).Range.Text = 'Версия'
            $table.Cell(1,3).Range.Text = 'Производитель'
            $table.Cell(1,4).Range.Text = 'Установлено'

            $j = 2
            foreach ($row in $out){
                $table.Rows.Add()
                $table.Cell($j,1).Range.Text = $row.DisplayName
                if ($row.Version) { $table.Cell($j,2).Range.Text = $row.DisplayVersion }
                else { $table.Cell($j,2).Range.Text = '' }
                if ($row.Publisher) { $table.Cell($j,3).Range.Text = $row.Publisher }
                else { $table.Cell($j,3).Range.Text = '' }
                if ($row.InstallDate) { $table.Cell($j,4).Range.Text = $row.InstallDate }
                else { $table.Cell($j,4).Range.Text = '' }
                $j += 1
            }
            $table.AutoFormat(26)
            $Selection.EndKey(6, 0)

            if ( $PSVersionTable.BuildVersion.Major -gt 6 ) {
                $Selection.TypeText("`n`t Установленные из магазина:`n")
                $out = Invoke-command @params { Get-AppxPackage | select Name | sort Name } | ForEach-Object { $_.Name }
                $Selection.TypeText("$out`n")
            }

##10 Сведения об установленных ролях и компонентах
            Decorate_report 50 '10. Сведения об установленных ролях и компонентах'

            if ($os -match "server") {
                $out = Get-WmiObject Win32_ServerFeature @params | Sort-Object Name 

                #шапка таблицы
                $table = $word.ActiveDocument.Tables.Add($Word.Selection.Range, 1, 1)
                $table.Cell(1,1).Range.Text = 'Наименование роли или компонента'

                $j = 2
                foreach ($row in $out){
                    $table.Rows.Add()
                    $table.Cell($j,1).Range.Text = $row.Name
                    $j += 1
                }
                $table.AutoFormat(26)
                $Selection.EndKey(6, 0)
            }
            else { $Selection.TypeText("`n На клиентских ОС недоступно`n") }

##11 Сведения о службах
            Decorate_report 60 '11. Сведения о службах'

            $out = Get-WmiObject win32_Service @params | Select-Object DisplayName,State,StartMode,StartName | Sort-Object DisplayName    #,Description
            #шапка таблицы
            $table = $word.ActiveDocument.Tables.Add($Word.Selection.Range, 1, 4)
            $table.Cell(1,1).Range.Text = 'Наименование службы'
            $table.Cell(1,2).Range.Text = 'Состояние'
            $table.Cell(1,3).Range.Text = 'Режим запуска'
            $table.Cell(1,4).Range.Text = 'От имени'
            #$table.Cell(1,5).Range.Text = 'Описание'

            $j = 2
            foreach ($row in $out) {
                $table.Rows.Add()
                $table.Cell($j,1).Range.Text = $row.DisplayName
                $table.Cell($j,2).Range.Text = $row.State
                $table.Cell($j,3).Range.Text = $row.StartMode
                $table.Cell($j,4).Range.Text = $row.StartName
                #$table.Cell($j,5).Range.Text = $row.Description
                $j += 1
            }
            $table.AutoFormat(36)
            $Selection.EndKey(6, 0)

##12 Сведения о локальных пользователях и группах
            Decorate_report 70 '12. Сведения о локальных пользователях и группах'

            $out = Get-WmiObject Win32_UserAccount -Filter "Domain = ""$NameServer""" @params | Select-Object Name,Status,Disabled,Description  | Sort-Object Name
            #шапка таблицы
            $table = $word.ActiveDocument.Tables.Add($Word.Selection.Range, 1, 4)
            $table.Cell(1,1).Range.Text = 'Пользователь'
            $table.Cell(1,2).Range.Text = 'Статус'
            $table.Cell(1,3).Range.Text = 'Состояние отключения'
            $table.Cell(1,4).Range.Text = 'Описание'

            $j = 2
            foreach ($row in $out) {
                $table.Rows.Add()
                $table.Cell($j,1).Range.Text = $row.Name
                $table.Cell($j,2).Range.Text = $row.Status
                $table.Cell($j,3).Range.Text = $row.Disabled.tostring()
                $table.Cell($j,4).Range.Text = $row.Description
                $j += 1
            }
            $table.AutoFormat(36)
            $Selection.EndKey(6, 0)

            $Selection.TypeText("`n")
            $out = Get-WmiObject Win32_GroupUser @params | Where-Object{$_.GroupComponent -like "*domain=""$NameServer""*"}
            #шапка таблицы
            $table = $word.ActiveDocument.Tables.Add($Word.Selection.Range, 1, 2)
            $table.Cell(1,1).Range.Text = "Группа"
            $table.Cell(1,2).Range.Text = "Состав группы"

            $j = 2
            foreach ($row in $out) {
                if (($group -ne [string]$row.GroupComponent) -and ([string]$row.GroupComponent)) {
                    $table.Rows.Add()
                    $table.Cell($j,1).Range.Text = ([string]$row.GroupComponent -Replace "^.+=")
                    foreach ($row1 in $out) {
                        if ([string]$row.GroupComponent -eq [string]$row1.GroupComponent) {
                            if ([string]::IsNullOrEmpty($incl)) {$incl = ([string]$row1.PartComponent -Replace "^.+=")}          #($incl -eq '') -or ($incl -eq $null)
                            else {$incl = $incl +"`n" + ([string]$row1.PartComponent -Replace "^.+=")}
                        }
                    }
                    $table.Cell($j,2).Range.Text = $incl
                    $j += 1
                }
                $group = [string]$row.GroupComponent
                $incl = ''
            }
            $table.AutoFormat(36)
            $Selection.EndKey(6, 0)

##13 Сведения о файловых ресурсах в сетевом доступе и правах доступа к ним
            Decorate_report 80 '13. Сведения о файловых ресурсах в сетевом доступе и правах доступа к ним'

            $Shares = Get-WmiObject Win32_Share @params
            #шапка таблицы
            $table = $word.ActiveDocument.Tables.Add($Word.Selection.Range, 1, 3)
            $table.Cell(1,1).Range.Text = 'Ресурс'
            $table.Cell(1,2).Range.Text = 'Путь'
            $table.Cell(1,3).Range.Text = "Доступ`n IdentityReference; AccessControlType; FileSystemRights; IsInherited; InheritanceFlags; PropagationFlags"

            $j = 2
            foreach ($Share in $Shares) {
                if ($Share.Path) {
                    $out = Get-Permissions $Share.path $NameServer
                    $table.Rows.Add()
                    foreach ($row in $out) {
                        $table.Cell($j,1).Range.Text = $Share.Name
                        $table.Cell($j,2).Range.Text = $Share.Path
                        $access = $out | ForEach-Object{"`n" + $_.IdentityReference,' ; ',$_.AccessControlType,' ; ',$_.FileSystemRights,' ; ',$_.IsInherited,' ; ',$_.InheritanceFlags,' ; ',$_.PropagationFlags}
                        $table.Cell($j,3).Range.Text = "$access"
                        $j += 1
                    }
                }
            }
            $table.AutoFormat(36)
            $Selection.EndKey(6, 0)

##14 Сведения об установленных принтерах
            Decorate_report 90 '14. Сведения об установленных принтерах'

            $out = Get-WmiObject Win32_Printer @params
            #шапка таблицы
            $table = $word.ActiveDocument.Tables.Add($Word.Selection.Range, 1, 5)
            $table.Cell(1,1).Range.Text = 'Наименование'
            $table.Cell(1,2).Range.Text = 'Драйвер'
            $table.Cell(1,3).Range.Text = 'Порт'
            $table.Cell(1,4).Range.Text = 'Доступ'
            $table.Cell(1,5).Range.Text = 'По умолчанию'

            $j = 2
            foreach ($row in $out) {
                $table.Rows.Add()
                $table.Cell($j,1).Range.Text = $row.Name
                $table.Cell($j,2).Range.Text = $row.DriverName
                $table.Cell($j,3).Range.Text = $row.PortName
                $table.Cell($j,4).Range.Text = $row.Shared.tostring()
                $table.Cell($j,5).Range.Text = $row.Default.tostring()
                $j += 1
            }
            $table.AutoFormat(36)
            $Selection.EndKey(6, 0)

##15 Сведения о сетевых адаптерах и их конфигурации
            Decorate_report 95 '15. Сведения о сетевых адаптерах и их конфигурации'

            $out = Get-WmiObject Win32_NetworkAdapterConfiguration @params | Where-Object{$_.MACAddress} | Sort-Object Index
            #шапка таблицы
            $table = $word.ActiveDocument.Tables.Add($Word.Selection.Range, 1, 6)
            $table.Cell(1,1).Range.Text = 'Описание'
            $table.Cell(1,2).Range.Text = 'IP адрес'
            $table.Cell(1,3).Range.Text = 'MAC адрес'
            $table.Cell(1,4).Range.Text = 'DHCP'
            $table.Cell(1,5).Range.Text = 'Шлюз'
            $table.Cell(1,6).Range.Text = 'DNS домен'

            $j = 2
            foreach ($row in $out) {
                $table.Rows.Add()
                $table.Cell($j,1).Range.Text = $row.Description
                if ($row.IPAddress) {
                    foreach ($IPAddress in $row.IPAddress) {
                        $IP = $IP +'; '+ $IPAddress.tostring()
                    }
                    $table.Cell($j,2).Range.Text = $IP.trimstart('; ')
                }
                $table.Cell($j,3).Range.Text = $row.MACAddress
                $table.Cell($j,4).Range.Text = $row.DHCPEnabled.tostring()
                if ($row.DefaultIPGateway) {
                    foreach ($IPAddress in $row.DefaultIPGateway) {
                        $IPGw = $IPGw +'; '+ $IPAddress.tostring()
                    }
                    $table.Cell($j,5).Range.Text = $IPGw.trimstart('; ')
                }
                $table.Cell($j,6).Range.Text = $row.DNSDomain
                $j += 1
            }
            $table.AutoFormat(36)
            $Selection.EndKey(6, 0)

##16 Таблица маршрутизации
            Decorate_report 100 '16. Таблица маршрутизации'

            $out = Get-WmiObject Win32_IP4RouteTable @params
            #шапка таблицы
            $table = $word.ActiveDocument.Tables.Add($Word.Selection.Range, 1, 5)
            $table.Cell(1,1).Range.Text = 'Источник'
            $table.Cell(1,2).Range.Text = 'Маска'
            $table.Cell(1,3).Range.Text = 'Назначение'
            $table.Cell(1,4).Range.Text = 'Шлюз'
            $table.Cell(1,5).Range.Text = 'Метрика'

            $j = 2
            foreach ($row in $out) {
                $table.Rows.Add()
                $table.Cell($j,1).Range.Text = $row.Name
                $table.Cell($j,2).Range.Text = $row.Mask
                $table.Cell($j,3).Range.Text = $row.Destination
                $table.Cell($j,4).Range.Text = $row.NextHop
                $table.Cell($j,5).Range.Text = $row.Metric1.tostring()
                $j += 1
            }
            $table.AutoFormat(26)
            $Selection.EndKey(6, 0)

           <#СохранитьКак указываем путь куда и имя файла
            $journal.SaveAs([ref]"D:\temp\PsWord.docx")

            #Закрываем документ
            $journal.Close()

            #Закрываем приложение
    
            $word.Quit()
            #>
    }
    Catch { 
        Write-Warning "$_.Exception.Message"
        Continue
    }
    Finally {
        #Переводим Word в видимый режим и обновляем форму
        if ($word) {
            $word.Visible = $true
            $Label.Text = 'Готово. Журнал открыт в программе MS Office Word.'
            $TextBox.Enabled = $true
            $OKbutton.Enabled = $true
            $Cancelbutton.Enabled = $true
            $main_form.Update()
        }
    }
}#process
}#function OKButton_click


Add-Type -assembly System.Windows.Forms
 
$main_form = New-Object System.Windows.Forms.Form
$main_form.Text ='Журналирование конфигурации сервера ...'
$main_form.StartPosition = 'CenterScreen'
$main_form.Width = 500
$main_form.Height = 180
#$main_form.AutoSize = $true

$Labeln = New-Object System.Windows.Forms.Label
$Labeln.Text = 'Имя сервера'
$Labeln.Location  = New-Object System.Drawing.Point(10,24)
$Labeln.AutoSize = $true
$main_form.Controls.Add($Labeln)

$TextBox = New-Object System.Windows.Forms.TextBox
$TextBox.Location  = New-Object System.Drawing.Point(100,22)
#$TextBox.Size = New-Object System.Drawing.Size (170,22)
$TextBox.Width = 170
$TextBox.TabIndex = 0         
$TextBox.Text = $env:COMPUTERNAME
$main_form.Controls.Add($TextBox)

$OKbutton = New-Object System.Windows.Forms.Button
$OKbutton.Text = 'Начать'
$OKbutton.Location = New-Object System.Drawing.Point(300,20)
$OKbutton.TabIndex = 1
$OKButton.add_click({ OKButton_click ($TextBox.Text).Trim() })
$main_form.Controls.Add($OKbutton)

$Cancelbutton = New-Object System.Windows.Forms.Button
$Cancelbutton.Text = 'Выход'
$Cancelbutton.Location = New-Object System.Drawing.Point(400,20)
$Cancelbutton.TabIndex = 2
$CancelButton.add_click({ $main_form.Close() })
$main_form.Controls.Add($Cancelbutton)

$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location  = New-Object System.Drawing.Point(10,70)
$ProgressBar.Value = 0
$ProgressBar.Width = 465
$main_form.Controls.add($ProgressBar)

$Label = New-Object System.Windows.Forms.Label
$Label.Text = 'Введите имя сервера.'
$Label.Location  = New-Object System.Drawing.Point(10,110)
$Label.AutoSize = $true
$main_form.Controls.Add($Label)
  
$main_form.BringToFront()
$main_form.Add_Shown({$TextBox.Select()})
$main_form.ShowDialog()

Remove-Variable Label,ProgressBar,CancelButton,OKButton,TextBox,Labeln,main_form
