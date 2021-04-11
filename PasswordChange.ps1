<#
.SYNOPSIS
Отправляет по почте сообщение пользователю о смене пароля.

.DESCRIPTION
Отправляет по почте сообщение пользователю о смене пароля.
Если у учетной записи нет почты, то поиск идет по совпадению ФИО("Выводимое имя"RUS, "Display name"EN) среди контактов по всему домену.

.PARAMETER SearchBase
Путь к контейнеру AD в виде: "FirmaOU"
Контейнер должен находится в AD
Не обязательный параметр.
По умолчанию: контейнер "FirmaOU" текущего домена

.PARAMETER ChangeDаyPolicy
Задает количество дней до смены пароля прописанных в политиках домена. Не обязательный параметр.
!!!Если не указывать и значение в политиках отличается от значения по умолчанию, то дата смены пароля будет неверно расчитана!!!
Число в формате целого. 
По умолчанию: 90

.PARAMETER ChangeDаy
Задает количество дней до смены пароля, при котором отправляется письмо. Не обязательный параметр.
Число в формате целого. 
По умолчанию: 5

.PARAMETER Enabled
Отключает обработку отключенных пользователей. Не обязательный параметр.
По умолчанию: все пользователи

.EXAMPLE
PasswordChange.ps1
Отправляет по почте сообщение о смене пароля всем пользователям, в том числе и отключенным,
у которых он истекает в течении 5 дней (при действии политики обязательной смены пароля через 90 дней).

.EXAMPLE
PasswordChange.ps1 -SearchBase "FirmaOU" -Enabled
Отправляет по почте сообщение о смене пароля всем неотключенным пользователям
из контейнера AD, у которых он истекает в течении 5 дней (при действии политики обязательной смены пароля через 90 дней).

.EXAMPLE
PasswordChange.ps1 -SearchBase "FirmaOU" -ChangeDаyPolicy 60 -ChangeDаy 2 -Enabled
Отправляет по почте сообщение о смене пароля всем неотключенным пользователям
из контейнера AD, у которых он истекает в течении 2 дней (при действии политики обязательной смены пароля через 60 дней).

.NOTES
ИМЯ: PasswordChange.ps1
ЯЗЫК: PoSH + оснастка ActiveDirectory
ДАТА СОЗДАНИЯ: 7.06.2018
АВТОР: Полетаев Сергей
#>

[CmdletBinding()]

Param (
#[Parameter (Mandatory = $false, Position=0)]
[AllowEmptyString()]
[String]$SearchBase = "FirmaOU",

#[Parameter (Mandatory = $false, Position=1, HelpMessage="Количество дней до смены пароля")]
[int]$ChangeDаyPolicy = 90,

#[Parameter (Mandatory = $false, Position=2, HelpMessage="Количество дней до смены пароля")]
[int]$ChangeDаy = 5,

#[Parameter (Mandatory = $false, Position=3)]
[switch]$Enabled
)

if (-not (Get-module ActiveDirectory) ) {
    try {Import-Module ActiveDirectory -ErrorAction Stop}
    catch {Write-Host "Модуль ActiveDirectory не загружен!" -ForegroundColor "Red"}
}

$From     = "user@firma.ru"
$Subject  = "Смена пароля"
$MailSrv  = "server.firma.ru"
$Encoding = [System.Text.Encoding]::utf8

$DayDelta = $ChangeDаyPolicy-$ChangeDаy

$container = (Get-ADDomain).DistinguishedName

if ($SearchBase.Length -ne 0) {
    $Search = New-Object DirectoryServices.DirectorySearcher($container)
    $Search.Filter = "(&(ou=$SearchBase))"
    $Search.SearchScope = 2
    $result = $Search.FindOne()
    

    if ($result -eq $null) {
        Write-Host "Ошибочка: $SearchBase - Такого контейнера нет в AD домена $container"
        exit
    }
    else {$SearchBase = $result.GetDirectoryEntry().distinguishedName}
}
else {$SearchBase = $container}

$Filter = '(objectCategory=person)(objectClass=user)'
if ($Enabled) {$Filter = $Filter + '(!(userAccountControl:1.2.840.113556.1.4.803:=2))'}
$Filter = '(&' + $Filter + ')'

$Users = Get-ADUser -SearchBase $SearchBase -LDAPFilter $Filter -Properties * `
    | ? {(($_.PasswordLastSet).AddDays($DayDelta) -le (Get-Date)) -and `
    (($_.PasswordLastSet).AddDays($ChangeDаyPolicy) -gt (Get-Date)) -and `
    (!$_.PasswordNeverExpires)}

Foreach ($User in $Users) {
    if ($User -ne $null) {

        $User.Name                                              #Для контроля в консоли
        ($User.PasswordLastSet).AddDays($ChangeDаyPolicy)       #Для контроля в консоли

        if ($User.Mail -ne $null) {
            
            $User.Mail                                          #Для контроля в консоли

            $To = $User.Mail
            $Body = "Уважаемый(ая) "+$User.Name+"!"
            $Body += "`n`n Срок действия Вашего пароля в домене  ($container)  до "
            $Body += (($User.PasswordLastSet).AddDays($ChangeDаyPolicy)).toString([cultureinfo]::GetCultureInfo('ru-RU'))
            $Body += ", необходимо его сменить."
            $Body += "`nЧтобы сменить пароль надо нажать Ctrl+Alt+Del и выбрать пункт Сменить пароль..."
            $Body += "`nПароль должен быть не менее 8 символов и обязательно содержать в себе большие, маленькие буквы, цифры или спецсимволы."
            $Body += "`nПредидущие пароли система помнит и использовать не даст, так что придумываем новые."
            $Body += "`n`n                Системнный администратор."

            Send-MailMessage -SmtpServer $MailSrv -To $To -From $From -Subject $Subject -Body $Body -Encoding $Encoding -EA SilentlyContinue
        }
        else {
            $Contact = Get-ADObject -LDAPFilter '(objectClass=contact)' -Properties *| ? {$_.Name -eq $User.Name}
            if ($Contact.Mail -ne $null) {
                
                $Contact.Mail                                   #Для контроля в консоли
                
                $To = $Contact.Mail
                $Body = "Уважаемый(ая) "+$User.Name+"!"
                $Body += "`n`n Срок действия Вашего пароля в домене  ($container)  до "
                $Body += (($User.PasswordLastSet).AddDays($ChangeDаyPolicy)).toString([cultureinfo]::GetCultureInfo('ru-RU'))
                $Body += ", необходимо его сменить."
                $Body += "`nЧтобы сменить пароль надо войти на сервер, нажать Пуск->Безопасность Windows и выбрать пункт Сменить пароль..."
                $Body += "`nПароль должен быть не менее 8 символов и обязательно содержать в себе большие, маленькие буквы, цифры или спецсимволы."
                $Body += "`nПредидущие пароли система помнит и использовать не даст, так что придумываем новые."
                $Body += "`n`n                Системнный администратор."

                Send-MailMessage -SmtpServer $MailSrv -To $To -From $From -Subject $Subject -Body $Body -Encoding $Encoding -EA SilentlyContinue
            }
        }
    }
}

Remove-Variable Login,ChangeDаyPolicy,ChangeDаy,From,To,Subject,MailSrv,Body,Encoding,DayDelta,container,Filter,result,Search,Users,User,Contact -ea SilentlyContinue
