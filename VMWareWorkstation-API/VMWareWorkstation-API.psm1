<#
TODO LIST
    Some functions still have to be created
    verbose functionality
    VMRUN Functionality
#>
<#
    --------------------------------------------------------------------------------------------------------------------------------------
        Internal commands, to support the vmware rest api module.
    --------------------------------------------------------------------------------------------------------------------------------------
#>
# Error handling function
Function Write-Message {
    [cmdletbinding()]
    Param
    (
        [Parameter(Mandatory)]
        [String]$Message,

        [Parameter(Mandatory)]
        [ValidateSet('ERROR', 'INFORMATION', 'WARNING')]
        $MessageType
    )
    switch ($MessageType) {
        ERROR {
            $ForegroundColor = 'White'
            $BackgroundColor = 'Red'
            $MessageStartsWith = "[ERROR] - "
        }
        INFORMATION {
            $ForegroundColor = 'White'
            $BackgroundColor = 'blue'
            $MessageStartsWith = "[INFORMATION] - "
        }
        WARNING {
            $ForegroundColor = 'White'
            $BackgroundColor = 'DarkYellow'
            $MessageStartsWith = "[WARNING] - "
        }
    }
   Write-Host "$MessageStartsWith $Message" -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor -NoNewline
   write-host ''
}
# shows a browserdialog
 Function ShowFolder {
    [cmdletbinding()]
    param(
        [ValidateScript({
            if( -Not ($_ | Test-Path) ){
                $Selectedpath = $([System.Environment]::GetFolderPath('MyComputer'))
                [void]::($Selectedpath)
            }
            return $true
        })]
        [System.IO.FileInfo]$Selectedpath
    )

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $FolderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog -ErrorAction Stop
    $FolderBrowserDialog.Description = "Select the Folder where VMWARE Workstation $($VMWareWorkStationSettings.Version) is installed"
    $FolderBrowserDialog.ShowNewFolderButton = $false
    $FolderBrowserDialog.SelectedPath = $Selectedpath
    $FolderBrowserDialog.ShowDialog((New-Object System.Windows.Forms.Form -Property @{TopMost = $true; TopLevel = $true }))

    $FolderBrowserDialog.SelectedPath
}
# Search function for specific files
Function FindFiles {
    [cmdletbinding()]
    Param
    (
        [Parameter(Mandatory)]
        [ValidateSet('GetVMWareWorkstationInstallationPath')]
        $Parameter
    )
    switch ($Parameter) {

        GetVMWareWorkstationInstallationPath { $FolderBrowserFile = "vmware.exe" }
    }
    $FolderBrowserDialogPath = ShowFolder -Selectedpath $([System.Environment]::GetFolderPath('ProgramFilesX86') + "\vmware\")
    try {
        if ($FolderBrowserDialogPath[0] -eq "OK") {

            if (Test-Path -Path $FolderBrowserDialogPath[1] -ErrorAction Stop) {
                $GetExecPath = Get-ChildItem -Path $FolderBrowserDialogPath[1] -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $FolderBrowserFile } -ErrorAction Stop

                if ($null -eq $GetExecPath) {
                     return $GetExecPath = "EMPTY"
                }

                if (Test-Path -Path $GetExecPath.fullname -ErrorAction Stop) {
                    return $GetExecPath
                }

                return $GetExecPath
            }
            else {
                Write-Message -Message "The Path is not available anymore $($error[0])" -MessageType ERROR
            }
        }
        if ($FolderBrowserDialogPath[0] -eq "CANCEL") {
            return $GetExecPath = "CANCEL"
        }
        return $GetExecPath
    }
    catch {
        break
    }
}
# Test if the VMWare rest api is responding and test if the credentials provided are correct
Function RunVMRestConfig {
    [cmdletbinding()]
    Param
    (
        [Parameter(Mandatory)]
        [ValidateSet('Preconfig','ConfigCredentialsCheck')]
        $Config
    )
    switch ($Config) {
        ConfigCredentialsCheck {
            if (($VMwareWorkstationConfigParameters.HostAddress) -and ($VMwareWorkstationConfigParameters.port) -and ($VMwareWorkstationConfigParameters.Password)) {
                 $URL = "http://$($VMwareWorkstationConfigParameters.HostAddress):$($VMwareWorkstationConfigParameters.port)/api/vms"
                 [void]::(Invoke-VMWareRestRequest -Method GET -Uri $URL)
            }
            else {
                Write-Message -Message "Hostadress and password are not defined, can't proceed" -MessageType ERROR
                break
            }
        }
    }
}
Function CheckForVMRestToRun {
    if (!(Get-Process -Name vmrest -ErrorAction SilentlyContinue)) {
        RunVMRestConfig -Config ConfigCredentialsCheck
        Do {
            $Process = Get-Process -Name vmrest -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName

            If (!($Process)) {
                Start-Sleep -Seconds 1
            }
            Else {
                $Process = $true
            }
        }
        Until ($Process)
    }
}
# Sets the API username and password
Function VMWare_SetPassword {

    if (([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.username)) -or (([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.password)))) {
        Write-Message -Message "Username and Password not set, please set your username and password for the VMWare Rest API" -MessageType WARNING
    }
    elseif (([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.username))) {
        Write-Message -Message "Username not set, please set your username and password for the VMWare Rest API" -MessageType WARNING
    }
    elseif (([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.Password)))  {
        Write-Message -Message "Password not set, please set your username and password for the VMWare Rest API" -MessageType WARNING
    }

    if ([void]::(Get-Process -Name vmrest -ErrorAction SilentlyContinue)) {
        [void]::(Stop-Process -Name vmrest -Force)
    }

    [void]::(Start-Process -FilePath $(Join-Path -Path $VMwareWorkstationConfigParameters.InstallLocation -ChildPath "vmrest.exe") -ArgumentList "-C" -Wait -PassThru -NoNewWindow)

    VMWare_RetrieveSettings

    Import-Module CredentialManager
    $password = (Get-Credential -UserName $VMwareWorkstationConfigParameters.username -Message "Provide the vmrest credentials You typed in the other screen" ).Password
    $script:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "Password" -Value $Password -Force -ErrorAction Stop
    Remove-Variable Password -ErrorAction SilentlyContinue

    VMWare_ExportSettings
    VMWare_ImportSettings
}
# Import xml to $VMwareWorkstationConfigParameters
Function VMWare_ImportSettings {
    $VMWareImportSettings = "$([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile))\Settings-$($([System.Security.Principal.WindowsIdentity]::GetCurrent().Name).replace("\","-")).xml"

    try {
        Remove-Variable -Name VMwareWorkstationConfigParameters -ErrorAction SilentlyContinue
        if (Test-Path -Path $VMWareImportSettings -ErrorAction Stop) {
            $script:VMwareWorkstationConfigParameters = Import-Clixml -Path $VMWareImportSettings -ErrorAction Stop
            [void]::($VMwareWorkstationConfigParameters)
        }
        else {
            VMWare_RetrieveSettings
        }
    }
    catch {
        VMWare_RetrieveSettings
    }
}
# Export $VMwareWorkstationConfigParameters to xml
Function VMWare_ExportSettings {
    $VMwareWorkstationConfigParameters | Export-Clixml -Path "$([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile))\Settings-$($([System.Security.Principal.WindowsIdentity]::GetCurrent().Name).replace("\","-")).xml" -Force
}
# Gather Configuration needed to run script module
Function VMWare_RetrieveSettings {
    if (Get-Member -InputObject $VMwareWorkstationConfigParameters -Name installlocation -ErrorAction SilentlyContinue) {
        Remove-Variable VMwareWorkstationConfigParameters -ErrorAction SilentlyContinue
    }
    try {

        if ([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.InstallLocation)) {

            Write-Message -Message "Select the path where the VMWare Workstation Application is installed." -MessageType INFORMATION

            [void]::([int]$RetryRetrieveFolder = 0)
            [bool]$RetryRetrieveFolderError = $false

            do {
                $FolderBrowserDialogPath = FindFiles -Parameter GetVMWareWorkstationInstallationPath
                switch ($FolderBrowserDialogPath.GetType().Name) {
                    String {

                       if ($FolderBrowserDialogPath -eq "CANCEL") {
                            $RetryRetrieveFolderError = $false
                            Write-Error -Exception "Path Not found" -ErrorAction Stop
                       }
                       if ($FolderBrowserDialogPath -eq "EMPTY") {

                            $RetryRetrieveFolderError = $false

                            switch ($RetryRetrieveFolder) {
                                0 {
                                    Write-Message -Message "The Path provide did not contain the vmware installation, please retry" -MessageType INFORMATION
                                }
                                1 {
                                    Write-Message -Message "The Path provide did not contain the vmware installation, please retry, after this attempt the script will stop." -MessageType INFORMATION
                                }
                                2 {
                                    $RetryRetrieveFolderError = $true
                                    Write-Error -Exception "Path Not found" -ErrorAction Stop
                                }
                            }
                        }
                    }
                    FileInfo {
                        $RetryRetrieveFolderError = $true
                        $script:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "InstallLocation" -Value $(Join-Path $FolderBrowserDialogPath.Directory -ChildPath "\") -Force -ErrorAction Stop
                        $script:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "Name" -Value "VMware Workstation" -Force -ErrorAction Stop
                        $script:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "Version" -Value "$([System.Diagnostics.FileVersionInfo]::GetVersionInfo($FolderBrowserDialogPath.FullName) | Select-Object -ExpandProperty FileVersion)" -Force
                        Write-Message -Message "Vmware Workstation $($VMwareWorkstationConfigParameters.Version) Installlocation defined as: $($VMwareWorkstationConfigParameters.InstallLocation)" -MessageType INFORMATION
                        break
                    }
                }
                [void]::($RetryRetrieveFolder++)
            } until (($RetryRetrieveFolder -gt 3) -or (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.InstallLocation))))

        }
    }
    catch {
         try {
             if ($RetryRetrieveFolderError) {
                Write-Message -Message "Doing a alternative scan - Scanning all filesystem disks that are found on your system" -MessageType INFORMATION
                $CollectDriveLetters = $(Get-PSDrive -PSProvider FileSystem ) | Select-Object -ExpandProperty Root
                $Collected = [System.Collections.ArrayList]@()
                $CollectDriveLetters | ForEach-Object { $Collected += Get-ChildItem -Path $($_) -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "vmware.exe" } }
                [void]::($RetryRetrieveFolder = 0)
                if (!([string]::IsNullOrEmpty($Collected))) {
                    if ($Collected.count -le 1) {
                           $script:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "Name" -Value "VMware Workstation" -Force -ErrorAction Stop
                           $script:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "Version" -Value "$([System.Diagnostics.FileVersionInfo]::GetVersionInfo($Collected.fullname) | Select-Object -ExpandProperty FileVersion)" -Force
                           $script:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "InstallLocation" -Value $Collected.DirectoryName -Force -ErrorAction Stop
                    }

                    if ($Collected.count -gt 1) {
                        do {
                            $SelectedPath = $Collected | Select-Object Name,fullname,DirectoryName | Out-GridView -Title "Multiple VMWare Workstation installation folders found, please select the folder where VMWare Workstation is installed" -OutputMode Single
                            if ($null -ne $SelectedPath) {
                                if (Test-Path $SelectedPath.FullName -ErrorAction Stop) {
                                    $script:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "InstallLocation" -Value $SelectedPath.DirectoryName -Force -ErrorAction Stop
                                    $RetryRetrieveFolderError = $false
                                    break
                                }
                            }
                            else {
                                if ($RetryRetrieveFolder -lt 1) {
                                    Write-Message -Message "No input gathered, retrying" -MessageType INFORMATION
                                }
                                if ($RetryRetrieveFolder -gt 1) {
                                    Write-Message -Message "No input gathered, last retry" -MessageType INFORMATION
                                    Write-Error -Exception "Path Not found" -ErrorAction Stop
                                    break
                                }
                                [void]::($RetryRetrieveFolder++)
                            }

                        } until ($RetryRetrieveFolder -ge 2)
                    }
                }
             }
        }
        catch {
                 Write-Message -Message "Unknown error occured the script is quitting" -MessageType ERROR
        }

        if ([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.InstallLocation)) {
            Write-Message -Message "Cannot determine if VMWare Workstation is installed on this machine, the script is quitting" -MessageType ERROR
            $RetryRetrieveFolder = $false
            break
        }
    }

   #Gather VMRest Config Settings vmrest.cfg
    if ($RetryRetrieveFolderError)  {
        Write-Message -Message "Gathering VMREST config" -MessageType INFORMATION
        Try {
            $GetVMRESTConfig = Get-ChildItem -Path $([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) -Recurse | Where-Object { $_.Name -eq "vmrest.cfg" } | Select-Object -ExpandProperty fullname -ErrorAction SilentlyContinue

            if (Test-Path -Path $GetVMRESTConfig -ErrorAction Stop) {
                $GetVMRESTConfigLoader = $(Get-Content -Path $GetVMRESTConfig -ErrorAction Stop | Select-String -Pattern 'PORT','USERNAME' -AllMatches ).line.Trim()

                if (!([String]::IsNullOrEmpty(($GetVMRESTConfigLoader)))) {
                    $GetVMRESTConfigLoader | ForEach-Object {
                        $script:VMwareWorkstationConfigParameters | Add-Member -MemberType Noteproperty $($_.split("=")[0]) $($_.split("=")[1]) -Force
                }

                $script:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty "HostAddress" -Value "127.0.0.1" -Force
                $script:VMwareWorkstationConfigParameters | Add-Member -MemberType Noteproperty -Name BASEURL -Value "http://$($VMwareWorkstationConfigParameters.HostAddress):$($VMwareWorkstationConfigParameters.port)/api/" -Force
                Remove-Variable -Name GetVMRESTConfigLoader,GetVMRESTConfig -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            Write-Message -Message "Cannot load the vmrest.cfg file" -MessageType INFORMATION
            VMWare_SetPassword
         }
         VMWare_ExportSettings
         VMWare_ImportSettings
    }
}
# Calling the restapi
Function Invoke-VMWareRestRequest {
    [cmdletbinding()]
    Param
    (
        $Uri=$URL,
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'PUT', 'POST', 'DELETE', errormessage = "{0}, Value must be: GET, PUT, POST, DELETE")]
        $Method,
        $Body=$null,
        [switch]$ResponseDetails
    )

    if (!($(Get-Process -Name vmrest -ErrorAction SilentlyContinue))) {
        Start-Process -FilePath $(Join-Path -Path $VMwareWorkstationConfigParameters.InstallLocation -ChildPath "vmrest.exe") -NoNewWindow

        Do {
            $Process = Get-Process -Name vmrest -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName

            If (!($Process)) {
                Start-Sleep -Seconds 1
            }
            Else {
                $Process = $true
            }
        }
        Until ($Process)

        RunVMRestConfig -Config ConfigCredentialsCheck
    }

    $Authentication = ("{0}:{1}" -f $VMwareWorkstationConfigParameters.username,($VMwareWorkstationConfigParameters.password | ConvertFrom-SecureString -AsPlainText))
    $Authentication = [System.Text.Encoding]::UTF8.GetBytes($Authentication)
    $Authentication = [System.Convert]::ToBase64String($Authentication)
    $Authentication = "Basic {0}" -f $Authentication

    $Headers = @{
        'authorization' =  $Authentication;
        'content-type' =  'application/vnd.vmware.vmw.rest-v1+json';
        'accept' = 'application/vnd.vmware.vmw.rest-v1+json';
        'cache-control' = 'no-cache'
    }
    try {
        $Error.clear()
        $StatusCode = $null
        $RequestResponse = Invoke-RestMethod -Uri $URI -Method $Method -Headers $Headers -Body $body -StatusCodeVariable "StatusCode" -SkipHttpErrorCheck -ErrorAction Stop

        if (!$?) {
            throw $_.ResponseDetails.Message
        }
        else {
            if ($StatusCode) {
                switch ($StatusCode) {
                    105 { Write-Message -Message "The resource doens't exists " -MessageType ERROR }
                    204 { Write-Message -Message "The resource has been deleted" -MessageType INFORMATION ; return $RequestResponse }
                    400 { Write-Message -Message "Invalid parameters - $($RequestResponse.Message)" -MessageType ERROR }
                    401 { VMWare_SetPassword }
                    403 { Write-Message -Message  "Permission denied - $($RequestResponse.Message)" -MessageType ERROR }
                    404 { Write-Message -Message "No such resource - $($RequestResponse.Message)" -MessageType ERROR }
                    406 { Write-Message -Message "Content type was not supported - $($RequestResponse.Message)" -MessageType ERROR }
                    409 { Write-Message -Message "Resource state conflicts - $($RequestResponse.Message)" -MessageType ERROR  }#; break
                    500 { Write-Message -Message "Server error - $($RequestResponse.Message)" -MessageType ERROR }
                    201 { return $RequestResponse }
                    200 { return $RequestResponse }
                    default { Write-Message -Message "Unexpected error" $RequestResponse -MessageType ERROR }
                }
            }
            if ($ResponseDetails) {
                return $RequestResponse
            }
        }

    }
    catch {
        Write-Message -Message "Unexpected error $($error[0].Exception)" -MessageType ERROR
    }
}
# Check if the VNWare process is active and kill it will running code from the commandline
Function CheckVMWareProcess {
    try {
        if ($(Get-Process -Name vmware -ErrorAction SilentlyContinue)) {
            Write-Message -Message "Detected that the VMWare Workstation Console is active. Please close VMWare Workstation and then retry" -MessageType WARNING
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $MessageBoxReturn=[System.Windows.Forms.MessageBox]::Show("Detected that the VMware Workstation console is started. This can interfere with the VMWareWorkstation-API Module. Press OK for quiting the VMware Workstation console","VMWareWorkstation-API - Warning action required",[System.Windows.Forms.MessageBoxButtons]::OKCancel,48)
            switch ($MessageBoxReturn){
                "OK" {
                    [void]::(Stop-Process -Name vmware -ErrorAction SilentlyContinue -Force)
                    Do {
                        $Process = Get-Process -Name vmware -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName

                        If (!($Process)) {
                            Start-Sleep -Seconds 1
                        }
                        Else {
                            Write-Message "The VMware Workstation Console has been closed. Please proceed" -MessageType INFORMATION
                            Start-Sleep 5
                            $Process = Get-Process -Name vmware -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName
                            if ($null -eq $Process) {
                                $Process = $true
                            }
                        }
                    }
                    Until ($Process)
                }
                "Cancel" {
                    Write-Message -Message "The VMWareWorkstation-API Module will continue, only the GET- functions will work, but the rest of the functions won't work untill you close the VMware Workstation console" -MessageType WARNING
                }
            }
        }
    }
    catch {
        Write-Message -Message "Unknown error $error[0]" -MessageType ERROR
    }
}
#Documentation.
Function Get-VMWareWorkstationDocumentation {
    try {
        $DefaultSettingPath = 'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice'
        $DefaultBrowserName = (Get-Item $DefaultSettingPath -ErrorAction Stop | Get-ItemProperty).ProgId
        $null = New-PSDrive -PSProvider registry -Root 'HKEY_CLASSES_ROOT' -Name 'HKCR'
        $DefaultBrowserOpenCommand = (Get-Item "HKCR:\$DefaultBrowserName\shell\open\command" -ErrorAction Stop | Get-ItemProperty).'(default)'
        $DefaultBrowserPath = [regex]::Match($DefaultBrowserOpenCommand,'\".+?\"')

        if ($DefaultSettingPath -like "*Chrome*") {
            $Argument ="--new-window https://developer.vmware.com/apis/412/vmware-workstation-pro-api https://www.dtonias.com/create-vm-template-vmware-workstation/"
            Start-Process -FilePath $DefaultBrowserPath -ArgumentList $Argument
        }

        $urls = @("https://developer.vmware.com/apis/412/vmware-workstation-pro-api","https://www.dtonias.com/create-vm-template-vmware-workstation/")
        foreach($url in $urls){
            Start-Process -FilePath $DefaultBrowserPath -ArgumentList @($url)
            Start-Sleep -Seconds 1
        }
    }
    catch {
        $Message = "Unexpected error can not open the websites in your browser. Maybe there isnt a default browser setted"
        Write-Message -Message $Message -MessageType ERROR
    }
}


#
#
#
# HIER VERDER AFMAKEN
#
#
#


<#
    --------------------------------------------------------------------------------------------------------------------------------------
        Host Networks Management
    --------------------------------------------------------------------------------------------------------------------------------------
#>
#--------------------------------------------------------------------------------------------------------------------------------------
#1 GET /vmnet Returns all virtual networks
<#
    Function tested, and ok!
    Documented
#>
Function Get-VirtualNetworks {
<#
    .SYNOPSIS

        Returns all virtual networks

    .DESCRIPTION
        Returns all virtual networks

    .EXAMPLE

        $VirtualNetworks = Get-VirtualNetwork s
        num vmnets
        --- ------
        4 {@{name=vmnet0; type=bridged; dhcp=false; subnet=; mask=}, @{name=vmnet1; type=hostOnly; dhcp=true; subnet=192.168.80.0; mask=255.255.255.0}, @{name=vmnet8; type=nat; dhcp=true; subnet=192.168.174.0; mask=255.255.255.0}, @{name=vm…

        .EXAMPLE

        $VirtualNetworks = $(Get-VirtualNetwork s).vmnets

            $virtualNetworks contains for example

            name   : vmnet0
            type   : bridged
            dhcp   : false
            subnet :
            mask   :

            name   : vmnet1
            type   : hostOnly
            dhcp   : true
            subnet : 192.168.99.0
            mask   : 255.255.255.0

            name   : vmnet8
            type   : nat
            dhcp   : true
            subnet : 192.168.175.0
            mask   : 255.255.255.0

            name   : vmnet10
            type   : hostOnly
            dhcp   : true
            subnet : 192.168.125.0
            mask   : 255.255.255.0

    .INPUTS
        System.String

    .OUTPUTS
        System.Array
#>
    CheckForVMRestToRun

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet")
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
#2 GET /vmnet/{vmnet}/mactoip
<#
    Function tested, and ok!
    Documented
#>
Function Get-VMNetMacToIp {
<#
    .SYNOPSIS
        Returns all MAC-to-IP settings for DHCP service
    .DESCRIPTION
        Returns all MAC-to-IP settings for DHCP service
    .PARAMETER VMNetMacToip
    Virtual networks that has DHCP enabled
    .PARAMETER ResponseDetails
         Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
     .EXAMPLE
        You can retreive them with the following commnand

        $NetWorKWithDHCP = $(Get-VirtualNetwork s).vmnets | where-object { $_.dhcp -eq "true" } | Select-Object -ExpandProperty Name
        $NetWorKWithDHCP | foreach { Get-VMNetMacToip -VMNetMacToip $_  }

    .EXAMPLE
        Get-VMNetMacToip -VMNetMacToip vmnet8 -ResponseDetails

        num mactoips
        --- --------
        0 {}
    .INPUTS
       System.String
    .OUTPUTS
       System.String
#>
    [cmdletbinding()]
    param (

        [Parameter(Mandatory)]
        [ValidateScript({$_ -cmatch '[a-z]{5}\d{1,2}$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits")]
        [string]$VMNet,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if ($ResponseDetails) {
            $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($VMNet)/mactoip") -ResponseDetails
        }
        else {
            $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($VMNet)/mactoip")
        }
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}
#--------------------------------------------------------------------------------------------------------------------------------------

#3 GET /vmnet/{vmnet}/portforward Returns all port forwardings
<#
    Function tested, and ok!
    Documented
#>
Function Get-VirtualNetworkPortForwarding {
 <#
    .SYNOPSIS
        Returns all port forwardings
    .DESCRIPTION
        Returns all port forwardings
    .PARAMETER VMNet
        a Virtual network name like VMNET8
    .PARAMETER ResponseDetails
         Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
     .EXAMPLE
        You can retreive the vmnets with the following commnand

        $NetWorKWithDHCP = $(Get-VirtualNetwork).vmnets

        Get-VirtualNetworkPortForwarding -VMNet vmnet8

        num mactoips
        --- --------
        0 {}
    .INPUTS
       System.String
    .OUTPUTS
       System.String
#>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({$_ -cmatch '[a-z]{5}\d{1,2}$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits")]
        [string]$VMNet,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if ($ResponseDetails) {
            $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($vmnet)/portforward") -ResponseDetails
        }
        else {
            $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($VMNet)/mactoip")
        }
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

# 4 PUT /vmnet/{vmnet}/mactoip/{mac} Updates the MAC-to-IP binding
<#
    Function tested, and ok!
    Documented
#>
Function Set-VMMacToIpBinding {
<#
    .SYNOPSIS
        Updates the MAC-to-IP binding
    .DESCRIPTION
        Updates the MAC-to-IP binding
    .PARAMETER VMNet
        A Virtual network name like VMNET8
    .PARAMETER MACAddress
        A mac-address
    .PARAMETER IpAddress
        A ip-addess
    .PARAMETER ResponseDetails
         Switch for errorhandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
     .EXAMPLE
        Set-VMMacToIpBinding -VMNet vmnet1 -MACAddress 00:0c:29:34:7c:97 -IpAddress 192.168.42.133

        Code Message
        ---- -------
        0 The operation was successful
     .EXAMPLE
        Set-VMMacToIpBinding -VMNet vmnet1 -MACAddress 00:0c:29:34:7c:97 -IpAddress 192.168.42.133

        Code Message
        ---- -------
        0 The operation was successful

        Get-VMNetMacToIp -VMNetMacToip vmnet1 -ResponseDetails

        num mactoips
        --- --------
        1 {@{mac=00:0c:29:34:7c:97; ip=192.168.42.133; vmnet=vmnet1}}
    .EXAMPLE
        Set-VMMacToIpBinding -VMNet vmnet1 -MACAddress 00:0c:29:34:7c:8d -IpAddress 192.168.42.132
        Set-VMMacToIpBinding -VMNet vmnet1 -MACAddress 00:0c:29:34:7c:8d -IpAddress 192.168.42.131

        $(Get-VMNetMacToIp -VMNetMacToip vmnet1 -ResponseDetails).mactoips

            mac               ip             vmnet
            ---               --             -----
            00:0c:29:34:7c:8f 192.168.42.132 vmnet1
            00:0c:29:34:7c:8d 192.168.42.131 vmnet1
    .INPUTS
       System.String
    .OUTPUTS
       System.Array
#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({$_ -cmatch '[a-z]{5}\d{1,2}$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits")]
        [string]$VMNet,
        [Parameter(Mandatory)]
        [ValidateScript({ [System.Net.NetworkInformation.PhysicalAddress]::Parse($_) })]
        [System.Net.NetworkInformation.PhysicalAddress]$MACAddress,
        [Parameter(Mandatory)]
        [ValidateScript({$_ -Match [IPAddress]$_ })]
        [string]$IpAddress,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun
    $Body = @{
        'IP'= $IpAddress;
    } | ConvertTo-Json
    if($PSCmdlet.ShouldProcess($Body,"Updates the MAC-to-IP binding on $($vmNet) for $($MACAddress) to $($IpAddress) to: ")){
        if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {
                if ($ResponseDetails) {
                    $RequestResponse=Invoke-VMWareRestRequest -Method PUT -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($vmnet)/mactoip/$($MACAddress)") -Body $Body -ResponseDetails
                }
                else {
                    $RequestResponse=Invoke-VMWareRestRequest -Method PUT -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($VMNet)/mactoip/$($MACAddress)") -Body $Body
                }
                return $RequestResponse
            }
            else {
                Write-Message -Message "Can not close vmware.exe. The settings setted for $($VMId) can't be proccessed. please close the program " -MessageType ERROR
            }
        }
        else {
            Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
        }
    }
}

#5 PUT /vmnet/{vmnet}/portforward/{protocol}/{port} Updates port forwarding
<#

#>
Function Set-PortForwarding {
<#
    .SYNOPSIS
        Updates port forwarding

    .DESCRIPTION
        Updates port forwarding
    .INPUTS
        System.String
        system.integer
    .OUTPUTS
        System.array
#>

        [CmdletBinding(SupportsShouldProcess)]
        param
        (
            [Parameter(Mandatory)]
            [ValidateScript({$_ -cmatch '[a-z]{5}\d{1,2}$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits")]
            [string]$VMNet,
            [Parameter(Mandatory)]
            [ValidateSet('TCP','tcp', 'UDP','udp', errormessage = "{0}, Value must be: TCP or UDP")]
            $Protocol,
            [Parameter(Mandatory)]
            [ValidateRange(1, 65535)]
            [int]$Port,
            [Parameter(Mandatory)]
            [ValidateScript({$_ -Match [IPAddress]$_ })]
            [string]$GuestIP,
            [Parameter(Mandatory)]
            [ValidateRange(1, 65535)]
            [int]$guestPort,
            [Parameter(Mandatory)]
            [String]$Description,
            [switch]$ResponseDetails
        )

        CheckForVMRestToRun
        CheckVMWareProcess

        if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {
                $Body = @{
                    'guestIp'= $GuestIP;
                    'guestPort' = $guestPort;
                    'desc' = $Description
                } | ConvertTo-Json

                if($PSCmdlet.ShouldProcess($Body,"Updates port forwarding on $($vmNet) with $($protocol) on $($Port) to: ")){
                    if ($ResponseDetails) {
                        $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($VMNet)/portforward/$($Protocol)/$($Port)") -Method PUT -Body $Body -ResponseDetails
                    }
                    else {
                        $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($VMNet)/portforward/$($Protocol)/$($Port)") -Method PUT -Body $Body
                    }
                }
            }
            else {
                if ($ResponseDetails) {
                    $RequestResponse = $null
                    $RequestResponse = New-Object PSObject
                    $RequestResponse | Add-Member -MemberType NoteProperty -Name "Code" -Value "105"
                    $RequestResponse | Add-Member -MemberType NoteProperty -Name "Message" -Value "VMWare workstation is running, please close the GUI, because it interferes with the Set-VmConfig Command"
                }
                Write-Message -Message "The Set-VMConfig settings setted for $($VMId) can't be proccessed. please close the program " -MessageType ERROR
            }
            return $RequestResponse
        }
        else {
            Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
        }
    }


#6 POST /vmnets Creates a virtual network

#7 DELETE /vmnet/{vmnet}/portforward/{protocol}/{port}Deletes port forwarding





#
#
#
#
#
#
#

<#
--------------------------------------------------------------------------------------------------------------------------------------

    VM Management

--------------------------------------------------------------------------------------------------------------------------------------
#>
#--------------------------------------------------------------------------------------------------------------------------------------
#0 - Load Configuration

function Get-VMWareWorkstationConfiguration {
<#
    .SYNOPSIS
        creates a psobject to store the data needed for the proper functioning of the module, all the necessary data is stored in a variable
    .DESCRIPTION
        creates a psobject to store the data needed for the proper functioning of the module, all the necessary data is stored in a variable
    .EXAMPLE
        Get-VMWareWorkstationConfiguration
        will create a script variable $VMwareWorkstationConfigParameters based on the existing xml file that has been saved. or on the gathered information.
    .EXAMPLE
        Get-VMWareWorkstationConfiguration

                VMwareWorkstationConfigParameters

                Name            Definition
                ----            ----------
                BASEURL         string BASEURL=http://127.0.0.1:8697/api/
                HostAddress     string HostAddress=127.0.0.1
                InstallLocation string InstallLocation=C:\Program Files (x86)\VMware\VMware Workstation
                Name            string Name=VMware Workstation
                Password        securestring Password=System.Security.SecureString
                port            string port=8697
                username        string username=<your username>
                Version         string Version=17.0.1 build-21139696

    .INPUTS
        System.String
    .OUTPUTS
        System.String

#>
    [cmdletbinding()]
    param (
        [switch]$SaveConfig
    )

    #if ($(Get-Process -Name vmrest -ErrorAction SilentlyContinue)) {
    #    Stop-Process -Name vmrest -ErrorAction SilentlyContinue -Force
    #}

    if ($SaveConfig) {
        if ($(Get-Variable VMwareWorkstationConfigParameters)) {
            VMWare_ExportSettings
            VMWare_ImportSettings
            break
        }
    }
    else {
        try {
            [void]::(Get-Variable -Name $VMwareWorkstationConfigParameters -ErrorAction Stop)
            }
        catch {
            $script:VMwareWorkstationConfigParameters = New-Object PSObject
        }

        VMWare_ImportSettings

        if ([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.Password)) {
            VMWare_RetrieveSettings
        }
        (Get-Variable VMwareWorkstationConfigParameters -Verbose) | Select-Object -ExpandProperty Name
        (Get-Member -InputObject $VMwareWorkstationConfigParameters -MemberType NoteProperty | Select-Object Name, Definition)

    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
# 1 GET /vms Returns a list of VM IDs and paths for all VMs
<#
    Function tested, and ok!
    Documented
#>

Function Get-VirtualMachineList {
<#
    .SYNOPSIS
        List the virtual machines stored in the virtual machine folder
    .DESCRIPTION
        List the virtual machines stored in the virtual machine folder
    .PARAMETER VirtualMachinename
       Can be a asterix * to retrieve all virtual machines
       Mandatory - [string]

        PS C:\WINDOWS\system32> Get-VirtualMachineList-VirtualMachinename *

        id                               path
        --                               ----
        PK7CPPB5UV50M3B73QD5ELDQN2OD9UFJ D:\Virtual machines\VMFOLDER1\VMNAME1.vmx
        649TJ74BEAHCM93M56DM79VD21562M8D D:\Virtual machines\VMFOLDER2\VMNAME2.vmx
    .PARAMETER Description
       Can be a VMID retrieved bij knowing the VMID

        PS C:\WINDOWS\system32> Get-VirtualMachineList-VirtualMachinename VMNAME3

        id                               path
        --                               ----
        E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5 D:\Virtual machines\VMFOLDER3\VMNAME3.vmx

       Mandatory - [string]
    .PARAMETER ResponseDetails
         Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
     .EXAMPLE
       Can be a asterix * to retrieve all virtual machines a machine name or a vmid

       Mandatory - [string]

        Get-VirtualMachineList-VirtualMachinename *

        id                               path
        --                               ----
        PK7CPPB5UV50M3B73QD5ELDQN2OD9UFJ D:\Virtual machines\VMFOLDER1\VMNAME1.vmx
        649TJ74BEAHCM93M56DM79VD21562M8D D:\Virtual machines\VMFOLDER2\VMNAME2.vmx
    .PARAMETER Description
       Can be a VMID retrieved by knowing the VMID

        Get-VirtualMachineList-VirtualMachinename VMNAME2

        id                               path
        --                               ----
        E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5 D:\Virtual machines\VMFOLDER2\VMNAME2.vmx
    .EXAMPLE
        Get-VirtualMachineList-VirtualMachinename E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5

        id                               path
        --                               ----
        E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5 D:\Virtual machines\Windows Server 2016 DC-GUI Template\Windows Server 2016 DC-GUI Template.vmx
    .EXAMPLE
        Get-VirtualMachineList-VirtualMachinename "Windows Server 2016 DC-GUI Template.vmx"

        id                               path
        --                               ----
        E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5 D:\Virtual machines\Windows Server 2016 DC-GUI Template\Windows Server 2016 DC-GUI Template.vmx
    .EXAMPLE
        retrieve the id of the virtual machine
        $(Get-VirtualMachineList-VirtualMachinename PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ).id

        results E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5
    .EXAMPLE
        retrieve the path of the virtual machine
        $(Get-VirtualMachineList-VirtualMachinename PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ).Path

        results in D:\Virtual machines\VMFOLDER1\VMNAME1.vmx
    .EXAMPLE
     $GatherVMS = $(Get-VirtualMachineList-VirtualMachinename *)
    .INPUTS
       System.String
    .OUTPUTS
       System.String
       system.array
#>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [string]$VirtualMachineName,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    Write-Verbose -Message "Check if the variable VMwareWorkstationConfigParameters is not empty"
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if ($ResponseDetails) {
            $RequestResponse=Invoke-VMWareRestRequest -Method  GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms") -ResponseDetails
        }
        else {
            $RequestResponse=Invoke-VMWareRestRequest -Method  GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms")
        }

        if ($VirtualMachineName -eq "*") {
            Write-Verbose -Message "Asterix found as search context , all virtual machines found are listed and shown."
            return $RequestResponse
            break
        }

        $VirtualMachineNames = @()
        foreach ($VM in $RequestResponse)
        {
            if ($VM.id -eq $VirtualMachineName) {
                Write-Verbose -Message "Check if the $($vm) equals $($virtualmachinename)"
                Write-Verbose -Message "virtual Machine with $($VM.id), found that matches $VirtualMachineName"
                return $VM
                break
            }

            $VirtualMachineName = ($VirtualMachineName).split(".")[0]

            $PathSplit = ($VM.Path).Split("\")
            $VmxFile = $PathSplit[($PathSplit.Length)-1]
            $CurrentVM = ($VmxFile).Split(".")[0]

            if ($CurrentVM -eq $VirtualMachineName) {
                Write-Verbose -Message "Check if the $($CurrentVM) equals $($virtualmachinename)"
                $obj = New-Object -TypeName PSObject
                $obj | Add-Member -MemberType NoteProperty -Name Id -Value $VM.id
                $obj | Add-Member -MemberType NoteProperty -Name Path -Value $VM.path
                $VirtualMachineNames += $obj
            }
        }

        if ($VirtualMachineNames.count -eq 0) {
            Write-Verbose -Message "No Virtual machines found that matched $($VirtualMachineName)"
            $RequestResponse = $null
        }
        else {
            Write-Verbose -Message "Found Virtual Machines that matches $($VirtualMachineName)"
            return $VirtualMachineNames
            break
        }
        Write-Verbose -Message "Creating the Errorcode to throw on function Get-VirtualMachineList"
        if ($null -eq $RequestResponse) {
            if (!($RequestResponse.code)) {
                if ($ResponseDetails) {

                    $RequestResponse = New-Object PSObject
                    $RequestResponse | Add-Member -MemberType NoteProperty -Name "Code" -Value "105"
                    $RequestResponse | Add-Member -MemberType NoteProperty -Name "Message" -Value "No virtual machines were found that matched the specified name."
                }
                Write-Message -Message "No virtual machines were found that match the specified name." -MessageType ERROR
            }
        }
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
# 2 GET /vms/{id} Returns the VM setting information of a VM
<#
    Function tested, and ok!
    Documented
#>
#--------------------------------------------------------------------------------------------------------------------------------------
function Get-VMConfig {
<#
    .SYNOPSIS
        Returns the VM setting information of a VM
    .DESCRIPTION
        Returns the VM setting information of a VM
    .PARAMETER vmid
        Can be a VMID retrieved by knowing the VMID or by a asterix for al the vm's in a foreach loop
        Must be 32 characters long and the id can be rerieved with :  Get-VirtualMachineList -VirtualMachinename *

        id                               path
        --                               ----
        PK7CPPB5UV50M3B73QD5ELDQN2OD9UFJ D:\Virtual machines\VMFOLDER1\VMNAME1.vmx
        649TJ74BEAHCM93M56DM79VD21562M8D D:\Virtual machines\VMFOLDER2\VMNAME2.vmx

    .PARAMETER ResponseDetails
         Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        retrieve the id of the virtual machine

        Get-VMConfig -VMId M3HAD21LB73N4GSHGJIC2MDM115A5GJT

        results in"
        id                               cpu             memory
        --                               ---             ------
        M3HAD21LB73N4GSHGJIC2MDM115A5GJT @{processors=1}    512
    .INPUTS
       System.String
    .OUTPUTS
       System.array
#>

    [cmdletbinding()]
    param (
        [ValidatePattern('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if ($ResponseDetails) {
            $RequestResponse = Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)") -ResponseDetails
        }
        else{
            $RequestResponse = Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)")
        }
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
#3 GET /vms/{id}/params/{name} Get the VM config params
<#
#
#
#
# nog uitzoeken hoe deze functie nu werkt, nog geen flauw idee welke params meegegeven kunnen worden
#
#
#
#
#>
Function Get-VMConfigParam {
}

#--------------------------------------------------------------------------------------------------------------------------------------
# 4 GET /vms/{id}/restrictions Returns the restrictions information of the VM
<#
    Function tested, and ok!
    Documented
#>
Function Get-VMRestriction {
<#
    .SYNOPSIS
        Returns the restrictions information of the VM
    .DESCRIPTION
        Returns the restrictions information of the VM
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID or by a asterix for al the vm's in a foreach loop
        Must be 32 characters long and the id can be rerieved with :  Get-VirtualMachineList-VirtualMachinename *
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        Get-VMRestriction -VMId PK7CPPB5UV50M3B73QD5ELDQN2OD9UFJ

            id                  : PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ
            groupID             :
            orgDisplayName      :
            integrityConstraint :
            cpu                 : @{processors=1}
            memory              : 1024
            applianceView       : @{author=; version=; port=; showAtPowerOn=}
            cddvdList           : @{num=1; devices=System.Object[]}
            floppyList          : @{num=0; devices=System.Object[]}
            firewareType        : 1
            guestIsolation      : @{copyDisabled=False; dndDisabled=False; hgfsDisabled=False; pasteDisabled=False}
            nicList             : @{num=2; nics=System.Object[]}
            parallelPortList    : @{num=0; devices=System.Object[]}
            serialPortList      : @{num=0; devices=System.Object[]}
            usbList             : @{num=1; usbDevices=System.Object[]}
            remoteVNC           : @{VNCEnabled=False; VNCPort=5900}

    .INPUTS
       System.String
    .OUTPUTS
       System.array that can be converted to JSON
#>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if ($ResponseDetails) {
            $RequestResponse = Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/restrictions") -ResponseDetails
        }
        else{
            $RequestResponse = Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/restrictions")
        }
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
# 5 GET /vms/{id}/params/{name} update the VM config params
<#
    Function tested, and ok!
    Documented
#>
Function Set-VMConfig {
<#
    .SYNOPSIS
        update the VM config params
    .DESCRIPTION
        update the VM config params
    .PARAMETER processors
        Must be a number.
    .PARAMETER memory
        Must be a number, VMWare Workstation calculates the best size.
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        Set-VMConfig -vmid PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ -processors 2 -memory 1024

            id                               cpu             memory
            --                               ---             ------
            PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ @{processors=2}   1024
    .EXAMPLE
        Set-VMConfig -vmid PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ -processors 3 -memory 2049

        id                               cpu             memory
        --                               ---             ------
        PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ @{processors=3}   2048
    .INPUTS
       System.String
       system.integer
    .OUTPUTS
       System.array
#>

    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
		[Parameter(Mandatory)]
        [ValidatePattern ('^[0-9]', errormessage = "{0}, The Processor parameter can contain [0-9]")]
        [int]$Processors,
        [Parameter(Mandatory)]
        [ValidatePattern ('^[0-9]', errormessage = "{0}, The Memory parameter can contain [0-9]")]
        [int]$Memory,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun
    CheckVMWareProcess

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {
            $Body = @{
                'id'= $("$VMId");
                'processors' = $Processors;
                'memory' = $Memory
            } | ConvertTo-Json

            if($PSCmdlet.ShouldProcess($Body,"Change the Virtual machine settings on $($VMID) to: ")){
                if ($ResponseDetails) {
                    $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)") -Method PUT -Body $Body -ResponseDetails
                }
                else {
                    $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)") -Method PUT -Body $Body
                }
            }
        }
        else {
            if ($ResponseDetails) {
                $RequestResponse = $null
                $RequestResponse = New-Object PSObject
                $RequestResponse | Add-Member -MemberType NoteProperty -Name "Code" -Value "105"
                $RequestResponse | Add-Member -MemberType NoteProperty -Name "Message" -Value "VMWare workstation is running, please close the GUI, because it interferes with the Set-VmConfig Command"
            }
            Write-Message -Message "The Set-VMConfig settings setted for $($VMId) can't be proccessed. please close the program " -MessageType ERROR
        }
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
#6 PUT /vms/{id}/configparams update the vm config params
<#
# nog uitzoeken hoe deze functie nu werkt, nog geen flauw idee welke params meegegeven kunnen worden
#>
#--------------------------------------------------------------------------------------------------------------------------------------
Function Set-VMConfigParam {
}

#--------------------------------------------------------------------------------------------------------------------------------------

# 7 POST /vms Creates a copy of the VM
<#
    Function tested, and ok!
    Documented
#>
Function New-VMClonedMachine {
<#
    .SYNOPSIS
        Creates a copy of a VM
    .DESCRIPTION
        Creates a copy of a VM
    .PARAMETER NewVMCloneName
        Can be anyting
    .PARAMETER NewVMCloneId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
    .PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        $NewVMCloneName = $("CLONE-" + -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 11 | % {[char]$_})).ToUpper()
        $NewClonedVM = New-VMClonedMachine -NewVMCloneName $NewVMCloneName -NewVMCloneId 649TJ74BEAHCM93M56DM79CD21562M8D -ResponseDetails
        $NewClonedVM

        id                               cpu             memory
        --                               ---             ------
        NSL0TNFKV4TPL87NVVAUETDR8GF658AT @{processors=1}    512
    .INPUTS
       System.String
       system.integer
    .OUTPUTS
       System.array
#>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
        [string]$NewVMCloneName,
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$NewVMCloneId,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    $Body = @{
        'name' = $NewVMCloneName;
        'parentId' = $NewVMCloneId
    }   | ConvertTo-Json


    if($PSCmdlet.ShouldProcess($Body,"Creating a Virtual machine with the name $($NewVMCloneName) based on template $($NewVMCloneId) ")){

        CheckVMWareProcess

        if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {


                    if ($ResponseDetails) {
                        $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms") -Method POST -Body $body -ResponseDetails
                    }
                    else {
                        $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms") -Method POST -Body $body
                    }
                    return $RequestResponse
            }
            else {
                Write-Message -Message "Can't close the VMWare Workstation Console. The creation of the Virtual Machine with id $($NewVMCloneName) can't be proccessed. please close the program " -MessageType ERROR
            }
        }
        else {
            Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
        }
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
# 8 POST /vms/registration Register VM to VM Library
<#
    Function tested, and ok!
    Documented
#>

Function Register-VMClonedMachine {
<#
    .SYNOPSIS
        Register VM to VM Library ( visible in de gui )
    .DESCRIPTION
        Register VM to VM Library
    .PARAMETER NewVMCloneName
        Can be any name you want (best pratice Keep the name from the VMX file, for administration purposes)
    .PARAMETER VMClonePath
        Path to the VMX file on disk
    .PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        after creating a new cloned machine the vm can be registered in the vmware gui

        For example
        Create a generic name

        Use name that was used in the NEW-VM
        $NewVMCloneName = $("CLONE-" + -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 11 | % {[char]$_})).ToUpper()

        $NewVMCloneName

        CLONE-WDMEPYTYLTC ( this name was made within the New-VMClonedMachine function)

        $NewClonedMachine = New-VMClonedMachine -NewVMCloneName $NewVMCloneName -NewVMCloneId 649TJ74BEAHCM93M56DM79CD21562M8D
        $NewClonedMachine

        id                               cpu             memory
        --                               ---             ------
        JMPFQNFBDPGGCRTGSVQOTUES038F4VEC @{processors=2}   4096

        Register-VMClonedMachine -NewVMCloneName $NewVMCloneName -VMClonePath (Get-VirtualMachineList-VirtualMachinename $NewVMCloneName).path

        id                               path
        --                               ----
        JMPFQNFBDPGGCRTGSVQOTUES038F4VEC D:\Virtual machines\CLONE-WDMEPYTYLTC\CLONE-WDMEPYTYLTC.vmx
    .EXAMPLE
        Register-VMClonedMachine -NewVMCloneName $NewVMCloneName -VMClonePath (Get-VirtualMachineList-VirtualMachinename $NewVMCloneName).path

        id                               path
        --                               ----
        JMPFQNFBDPGGCRTGSVQOTUES038F4VEC D:\Virtual machines\CLONE-WDMEPYTYLTC\CLONE-WDMEPYTYLTC.vmx
    .EXAMPLE

        Retrieve VM's with Get-VirtualMachineList-VirtualMachinename *

        Get-VirtualMachineList-VirtualMachinename *

        id                               path
        --                               ----
        LR4UDDNNON7BD3SC1MIG8A2GO03EAR2O D:\Virtual machines\CLONE-8EFNC1M6XWJ\CLONE-8EFNC1M6XWJ.vmx

        Register-VMClonedMachine -NewVMCloneName CLONE-8EFNC1M6XWJ.vmx or CLONE-8EFNC1M6XWJ -VMClonePath "D:\Virtual machines\CLONE-8EFNC1M6XWJ\CLONE-8EFNC1M6XWJ.vmx"

        id                               path
        --                               ----
        LR4UDDNNON7BD3SC1MIG8A2GO03EAR2O D:\Virtual machines\CLONE-WDMEPYTYLTC\CLONE-8EFNC1M6XWJ.vmx
    .INPUTS
       System.String
       system.integer
    .OUTPUTS
       System.array
#>
    [cmdletbinding()]
        param
        (
            [Parameter(Mandatory)]
            [string]$NewVMCloneName,
            [Parameter(Mandatory)]
            [string]$VMClonePath,
            [switch]$ResponseDetails
        )

    CheckForVMRestToRun
    CheckVMWareProcess

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
         if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {
            $Body = @{
                'name' = $NewVMCloneName;
                'path' = $VMClonePath
            } | ConvertTo-Json

            if ($ResponseDetails) {
                $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/registration") -Method POST -Body $Body -ResponseDetails
            }
            else {
                $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/registration") -Method POST -Body $Body
            }
            return $RequestResponse
        }
        else {
            Write-Message -Message "Can't close the VMWare Workstation Console.. The registration of the virtual machine with id $($VMId) can't be proccessed. Please close the program " -MessageType ERROR
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
# 9 DELETE /vms/{id} Deletes a VM
<#
    Function tested, and ok!
    Documented
#>
Function Remove-VMClonedMachine {
<#
    .SYNOPSIS
        Deletes a VM
    .DESCRIPTION
        Deletes a VM
    .PARAMETER NewVMCloneName
        Can be anyting
    .PARAMETER NewVMCloneId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
    .EXAMPLE
       Get-VirtualMachineList-VirtualMachinename *

        id                               path
        --                               ----
        MRJVR0R64RS7GLC7EMG9QRCOB015RNSV D:\Virtual machines\CLONE-1SBAZX9JQCE\CLONE-1SBAZX9JQCE.vmx
        GBILCONH2U9FG18K09KVIKB8FV10I02V D:\Virtual machines\CLONE-BVGMLE27N1H\CLONE-BVGMLE27N1H.vmx


        Remove-VMClonedMachine -VMId MRJVR0R64RS7GLC7EMG9QRCOB015RNSV

        Result:
        The resource has been deleted -

        Get-VirtualMachineList-VirtualMachinename *

        id                               path
        --                               ----
        GBILCONH2U9FG18K09KVIKB8FV10I02V D:\Virtual machines\CLONE-BVGMLE27N1H\CLONE-BVGMLE27N1H.vmx
    .INPUTS
       System.String
    .OUTPUTS
       Message
#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [switch]$ResponseDetails
    )
    if($PSCmdlet.ShouldProcess($VMId,"Remove a Virtual machine with the virtual machine id $($vmid) ")){

        CheckForVMRestToRun
        CheckVMWareProcess

        if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {

                    if ($ResponseDetails) {
                        $RequestResponse=Invoke-VMWareRestRequest -Method DELETE -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)") -ResponseDetails
                    }
                    else {
                        $RequestResponse=Invoke-VMWareRestRequest -Method DELETE -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)")
                    }

                if ($ResponseDetails) {
                    if ($RequestResponse) {
                        switch ($RequestResponse.code) {
                            100 { return $RequestResponse }
                            105 { return $RequestResponse }
                            2   {
                                $RequestResponse = $null
                                $RequestResponse = New-Object PSObject
                                $RequestResponse | Add-Member -MemberType NoteProperty -Name "Code" -Value "2"
                                $RequestResponse | Add-Member -MemberType NoteProperty -Name "Message" -Value "The Virtual machine can't be deleted because its a template"
                            }
                            default {
                                Write-Message -Message "Unexpected error $($RequestResponse.code) $($error[0].Exception)" -MessageType ERROR
                                break
                            }
                        }
                    }
                    else {
                        if ($ResponseDetails) {
                            $RequestResponse = $null
                            $RequestResponse = New-Object PSObject
                            $RequestResponse | Add-Member -MemberType NoteProperty -Name "Code" -Value "204"
                            $RequestResponse | Add-Member -MemberType NoteProperty -Name "Message" -Value "Virtual Machine with VMId $($VMId) has been deleted"
                        }
                        Write-Message -Message "Virtual Machine with VMId $($VMId) has been deleted" -MessageType INFORMATION
                    }
                return $RequestResponse
                }
            }
            else {
                Write-Message -Message "Can't close the VMWare Workstation Console. the deletion of VM with id $($VMId) can't be proccessed. please close the program " -MessageType ERROR
                break
            }
        }
        else {
            Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
            break
        }
    }
}

#10 Returns a list with virtual machines that are templates
<#
    Function tested, and ok!
    Documented
#>
Function Get-VMTemplateList {
<#
    .SYNOPSIS
        Returns a list with virtual machines that are templates
    .DESCRIPTION
        Returns a list with virtual machines that are templates
    .OUTPUTS
       system.array
#>
    CheckForVMRestToRun

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {

        if (!(Get-Process -Name vmrest -ErrorAction SilentlyContinue)) {
            RunVMRestConfig -Config ConfigCredentialsCheck
            Do {
                $Process = Get-Process -Name vmrest -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName

                If (!($Process)) {
                    Start-Sleep -Seconds 1
                }
                Else {
                    $Process = $true
                }
            }
            Until ($Process)
        }

        $VirtualMachineIsTemplate = @()
        $VirtualMachines = Get-VirtualMachineList -VirtualMachineName * -ErrorAction Stop

        ForEach ($VirtualMachine in $VirtualMachines) {
            $CheckForParam = Get-Content -Path $VirtualMachine.path -ErrorAction Stop | Select-String "TemplateVM"
            $CheckForParam = $CheckForParam -replace ' = "TRUE"',[string]::Empty
            if ($CheckForParam -eq "templateVM") {
                $PathSplit = ($VirtualMachine.Path).Split("\")
                $VmxFile = $PathSplit[($PathSplit.Length)-1]
                $CurrentVM = ($VmxFile).Split(".")[0]

                $obj = New-Object -TypeName PSObject
                $obj | Add-Member -MemberType NoteProperty -Name Id -Value $VirtualMachine.id
                $obj | Add-Member -MemberType NoteProperty -Name Path -Value $VirtualMachine.path
                $obj | Add-Member -MemberType NoteProperty -Name Template -value $CurrentVM

                $VirtualMachineIsTemplate += $obj
            }
        }
        return $VirtualMachineIsTemplate
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#-------------------------------------------------------------------------------------------------------------------------------------

<#
--------------------------------------------------------------------------------------------------------------------------------------

    VM Network Adapters Management

--------------------------------------------------------------------------------------------------------------------------------------
#>
#GET /vms/{id}/ip Returns the IP address of a VM
<#
    Function tested, and ok!
    Documented
#>
function Get-VMIPAddress {
<#
    .SYNOPSIS
        Returns the IP address of a VM
    .DESCRIPTION
        Returns the IP address of a VM
    .PARAMETER VMId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
    $GetIPAddress = Get-VMIPAddress -VMId M3HAD21LB73N4GSHGJIC2MDM115A5GJT
    $GetIPAddress

    ip
    --
    192.168.174.133
     .EXAMPLE
        When the machine is starting or not poweredon

        $GetIPAddress = Get-VMIPAddress -VMId M3HAD21LB73N4GSHGJIC2MDM115A5GJT

        Powered off
        [ERROR] -  Resource state conflicts - The virtual machine is not powered

        without IPAddress or system state is not reachable ( reboot )
        [ERROR] -  Server error - Unable to get the IP address
    .INPUTS
       System.String
    .OUTPUTS
       system.array
#>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if ($ResponseDetails) {
            $RequestResponse = invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/ip") -ResponseDetails
        }
        else {
            $RequestResponse = invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/ip")
        }
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
#GET /vms/{id}/nic Returns all network adapters in the VM
<#
    Function tested, and ok!
    Documented
#>
function Get-VMNetworkAdapter {
<#
    .SYNOPSIS
        Returns all network adapters in the VM
    .DESCRIPTION
        RReturns all network adapters in the VM
    .PARAMETER VMId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        $(Get-VMNetworkAdapter-VMId M3HAD21LB73N4GSHGJIC2MDM115A5GJT).nics

        index type    vmnet  macAddress
        ----- ----    -----  ----------
            1 custom  vmnet8 00:0c:29:e5:d9:9b
            3 custom  vmnet0 00:0c:29:e5:d9:af
            4 nat     vmnet8 00:0c:29:e5:d9:b9
            5 nat     vmnet8 00:0c:29:e5:d9:c3
            6 nat     vmnet8 00:0c:29:e5:d9:cd
            7 nat     vmnet8 00:0c:29:e5:d9:d7
            8 bridged vmnet0 00:0c:29:e5:d9:e1
            9 custom  vmnet1 00:0c:29:e5:d9:eb
        10 custom  vmnet8 00:0c:29:e5:d9:f5

     .EXAMPLE
    Get-VMNetworkAdapter -VMId M3HAD21LB73N4GSHGJIC2MDM115A5GJT

    num nics
    --- ----
    9 {@{index=1; type=custom; vmnet=vmnet8; macAddress=00:0c:29:e5:d9:9b}, @{index=3; type=custom; vmnet=vmnet0; macAdd…

    .INPUTS
       System.String
    .OUTPUTS
        system.array
#>

    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if ($ResponseDetails) {
            $RequestResponse = Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/nic") -ResponseDetails
        }
        else {
            $RequestResponse = Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/nic") -ResponseDetails
        }
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
#GET /vms/{id}/nicips Returns the IP stack configuration of all NICs of a VM
<#
    Function tested, and ok!
    Documented
#>
function Get-VMNetAdapterIPStack {
<#
    .SYNOPSIS
        Returns the IP stack configuration of all NICs of a VM
    .DESCRIPTION
        Returns the IP stack configuration of all NICs of a VM
    .PARAMETER VMId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        $(Get-VMNetAdapterIPStack -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR).NICS
        mac   : 00:0c:29:18:8b:04
        ip    : {fe80::fddc:db47:e7d8:cfb7/64, 169.254.207.183/16}
        dns   : @{hostname=; domainname=; server=System.Object[]; search=System.Object[]}
        dhcp4 : @{enabled=True; setting=}
        dhcp6 : @{enabled=False; setting=}
     .EXAMPLE
        $(Get-VMNetAdapterIPStack -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR).ROUTES

        dest      : 169.254.0.0
        prefix    : 16
        interface : 0
        type      : 0
        metric    : 256

        dest      : 169.254.207.183
        prefix    : 32
        interface : 0
        type      : 0
        metric    : 256

        dest      : 169.254.255.255
        prefix    : 32
        interface : 0
        type      : 0
        metric    : 256

    .INPUTS
       System.String
    .OUTPUTS
        system.array
#>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if ($ResponseDetails) {
            $RequestResponse = Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/nicips") -ResponseDetails
        }
        else{
            $RequestResponse = Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/nicips")
        }
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
#PUT /vms/{id}/nic/{index} Updates a network adapter in the VM
<#
    Function tested, and ok!
    Documented
#>
Function Update-VMNetWorkAdapter {
<#
    .SYNOPSIS
        Updates a network adapter in the VM
    .DESCRIPTION
        Updates a network adapter in the VM
    .PARAMETER VMId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
    .PARAMETER VMNicIndex
        The Index number of the nic that must be changed.

        $(Get-VMNetworkAdapter -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR).nics

        index type   vmnet  macAddress
        ----- ----   -----  ----------
            1 custom vmnet8 00:0c:29:18:8b:04
            2 custom vmnet8 00:0c:29:18:8b:0e
    .PARAMETER VMNet
        VMNets can be retrieved with the Get-VirtualNetwork s command

        $VMNets = $(Get-VirtualNetwork s -ResponseDetails).vmnets
        $VMNets

        name   : vmnet1
        type   : hostOnly
        dhcp   : true
        subnet : 192.168.80.0
        mask   : 255.255.255.0

        name   : vmnet8
        type   : nat
        dhcp   : true
        subnet : 192.168.174.0
        mask   : 255.255.255.0

        name   : vmnet10
        type   : hostOnly
        dhcp   : true
        subnet : 192.168.20.0
        mask   : 255.255.255.0

    .PARAMETER VMNettype
        can be 'bridged','nat','hostonly','custom'
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
     .EXAMPLE
        $ChangeNetAdapter = Update-VMNetWorkAdapter -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR -VMNicIndex 1 -VMNet vmnet8 -VMNettype custom -ResponseDetails

        $ChangeNetAdapter

        index type   vmnet  macAddress
        ----- ----   -----  ----------
            1 custom vmnet8 00:0c:29:18:8b:04
#>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
		[Parameter(Mandatory)]
        [ValidatePattern ('^[0-9]', errormessage = "{0}, The Virtual machines nic index can contain [0-9]")]
        [int]$VMNicIndex,
        [Parameter(Mandatory)]
        [ValidateScript({$_ -cmatch '[a-z]{5}\d{1,2}$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits")]
        [string]$VMNet,
        [Parameter(Mandatory)]
        [ValidateSet('bridged','nat','hostonly','custom', errormessage = "{0}, Value must be: bridged, nat, hostonly, custom")]
        [string]$VMNettype,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    $Body = @{
        'type'= $VMNettype;
        'vmnet' = $VMNet;
    } | ConvertTo-Json

    if($PSCmdlet.ShouldProcess($body,"Updates a network adapter in the VM to $($VMNet) with type $($VMNettype) on adapter $($VMNicIndex) ")){
        CheckVMWareProcess

        if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {


                    if ($ResponseDetails) {
                        $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/nic/$($VMNicIndex)") -Method PUT -Body $Body -ResponseDetails
                    }
                    else {
                        $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/nic/$($VMNicIndex)") -Method PUT -Body $Body
                    }
                    return $RequestResponse
            }
            else {
                Write-Message -Message "The settings setted for $($VMId) can't be proccessed. Please close VMWware Workstation, and then retry." -MessageType ERROR
            }
        }
        else {
            Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
        }
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
#POST /vms/{id}/nic Creates a network adapter in the VM
<#
    Function tested, and ok!
    Documented
#>
Function Add-VMNetAdapter {
<#
    .SYNOPSIS
        Creates a network adapter in the VM
    .DESCRIPTION
        Creates a network adapter in the VM
    .PARAMETER VMId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
    .PARAMETER VMNet
        VMNets can be retrieved with the Get-VirtualNetwork s command

        $VMNets = $(Get-VirtualNetwork s -ResponseDetails).vmnets
        $VMNets

        name   : vmnet1
        type   : hostOnly
        dhcp   : true
        subnet : 192.168.80.0
        mask   : 255.255.255.0

        name   : vmnet8
        type   : nat
        dhcp   : true
        subnet : 192.168.174.0
        mask   : 255.255.255.0

        name   : vmnet10
        type   : hostOnly
        dhcp   : true
        subnet : 192.168.20.0
        mask   : 255.255.255.0
    .PARAMETER VMNettype
        can be 'bridged','nat','hostonly','custom'
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
     .EXAMPLE
        $AddNetAdapter = Add-VMNetAdapter -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR -VMNet vmnet8 -VMNettype custom -ResponseDetails
        $AddNetAdapter

        index type   vmnet  macAddress
        ----- ----   -----  ----------
            2 custom vmnet8
#>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [Parameter(Mandatory)]
        [ValidateScript({$_ -cmatch '[a-z]{5}\d{1,2}$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits")]
        [string]$VMNet,
        [Parameter(Mandatory)]
        [ValidateSet('bridged','nat','hostonly','custom', errormessage = "{0}, Value must be: bridged, nat, hostonly, custom")]
        [string]$VMNettype,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun
    CheckVMWareProcess

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {
            $Body = @{
                'type'= $VMNettype;
                'vmnet' =  $VMNet;
            } | ConvertTo-Json
            if ($ResponseDetails) {
                $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/nic") -Method POST -Body $Body -ResponseDetails
            }
            else {
                $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/nic") -Method POST -Body $Body
            }
            return $RequestResponse
        }
        else {
            Write-Message -Message "The settings setted for $($VMId) can't be proccessed. Please close VMWware Workstation, and then retry." -MessageType ERROR
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
#DELETE /vms/{id}/nic/{index} Deletes a VM network adapter
<#
    Function tested, and ok!
    Documented
#>
Function Remove-VMNetAdapter {
<#
    .SYNOPSIS
        Deletes a VM network adapter
    .DESCRIPTION
        Deletes a VM network adapter
    .PARAMETER VMId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
    .PARAMETER VMNicIndex
        The Index number of the nic that must be deleted

        $(Get-VMNetworkAdapter -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR).nics

        index type   vmnet  macAddress
        ----- ----   -----  ----------
            1 custom vmnet8 00:0c:29:18:8b:04
            2 custom vmnet8 00:0c:29:18:8b:0e
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
     .EXAMPLE
        $DeleteNetAdapter = Remove-VMNetAdapter -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR -VMNicIndex 2 -ResponseDetails
        $DeleteNetAdapter

        Code Message
        ---- -------
        204  Networkadapter with nicindex 2 has been deleted
#>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [int][ValidatePattern ('^[0-9]',errormessage = "{0}, The Virtual machines nic index can contain [0-9]")]
        $VMNicIndex,
        [switch]$ResponseDetails
    )
    if($PSCmdlet.ShouldProcess($VMNicIndex,"Deletes a VM network adapter with index $($VMNicIndex) on $($VMId) ")){

        CheckForVMRestToRun
        CheckVMWareProcess

        if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {

                    if ($ResponseDetails) {
                        $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/nic/$VMNicIndex") -Method DELETE -ResponseDetails
                    }
                    else {
                        $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/nic/$VMNicIndex") -Method DELETE
                    }
                    if ($ResponseDetails) {
                        if ($RequestResponse) {
                            switch ($RequestResponse.code) {
                                120 { return $RequestResponse }
                                default {
                                    Write-Message -Message "Unexpected error $($RequestResponse.code) $($error[0].Exception)" -MessageType ERROR
                                    break
                                }
                            }
                        }
                        else {
                            if ($ResponseDetails) {
                                $RequestResponse = New-Object PSObject
                                $RequestResponse | Add-Member -MemberType NoteProperty -Name "Code" -Value "204"
                                $RequestResponse | Add-Member -MemberType NoteProperty -Name "Message" -Value "Networkadapter with nicindex $($VMNicIndex) has been deleted"
                            }
                            Write-Message -Message "Networkadapter with nicindex $($VMNicIndex) has been deleted" -MessageType INFORMATION
                        }
                    return $RequestResponse
                    }
            }
            else {
                Write-Message -Message "The settings setted for $($VMId) can't be proccessed. Please close VMWware Workstation, and then retry." -MessageType ERROR
            }
        }
        else {
            Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
        }
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
<#
--------------------------------------------------------------------------------------------------------------------------------------

    VM Power Management

--------------------------------------------------------------------------------------------------------------------------------------
#>

# /vms/{id}/power Returns the power state of the VM
<#
    Function tested, and ok!
    Documented
#>
Function Get-VMPowerStatus {
<#
    .SYNOPSIS
       Returns the power state of the VM
    .DESCRIPTION
        Returns the power state of the VM
    .PARAMETER VMId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
     .EXAMPLE
        $GetVMPowerstatus = Get-VMPowerStatus -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR
        $GetVMPowerstatus

        power_state
        -----------
        poweredOn
#>
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        $VMId,
        [switch]$RequestResponse
    )

    CheckForVMRestToRun

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if ($RequestResponse) {
            $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/power") -ResponseDetails
        }
        else {
            $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/power")
        }
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
#/vms/{id}/power Changes the VM power state
<#
    Function tested, and ok!
    Documented
#>
Function Set-VMPowerStatus {
<#
    .SYNOPSIS
        Changes the VM power state
    .DESCRIPTION
        Changes the VM power state
    .PARAMETER VMId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
    .PARAMETER PowerMode
        can be 'on', 'off', 'shutdown', 'suspend','pause','unpause'
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
     .EXAMPLE
        $VMSetPowerstatus = Set-VMPowerStatus -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR -PowerMode on
        $VMSetPowerstatus

        power_state
        -----------
        poweredOn
#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [ValidateSet('on', 'off', 'shutdown', 'suspend','pause','unpause', errormessage = "{0}, Value must be: on, off, shutdown, suspend,pause, unpause")]
        [string]$PowerMode
    )
    if($PSCmdlet.ShouldProcess($VMNicIndex,"Changing the Virtuals machine powerstatus on $($VMId) to $($PowerMode) ")){
        CheckForVMRestToRun
        CheckVMWareProcess

        if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            if ($(Get-Process -Name  vmware -ErrorAction SilentlyContinue)) {
            #    $VMWareReopen = $true
                Stop-Process -Name vmware -ErrorAction SilentlyContinue -Force
            }

                if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {
                    $RequestResponse=Invoke-VMWareRestRequest -Method PUT -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/power") -Body $PowerMode
                    return $RequestResponse
                }
                else {
                    Write-Message -Message "Can't close the VMWare Workstation Console., cannot process with powering $($PowerMode) Virtual Machine with $($VMId). Please close the program first" -MessageType ERROR
                }
        }
        else {
            Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
        }
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
<#
--------------------------------------------------------------------------------------------------------------------------------------

    VM Shared Folders Management

--------------------------------------------------------------------------------------------------------------------------------------
#>
#--------------------------------------------------------------------------------------------------------------------------------------
#1 GET /vms/{id}/sharedfolders Returns all shared folders mounted in the VM
<#
    Function tested, and ok!
    Documented
#>
Function Get-VMSharedFolder {
<#
    .SYNOPSIS
        Returns all shared folders mounted in the VM
    .DESCRIPTION
        Returns all shared folders mounted in the VM
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        Get-VMSharedFolder -VMId PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ

        folder_id  host_path             flags
        ---------  ---------             -----
        VMShare    D:\Virtual machines\     4
        VMShares   D:\Virtual machines\     0
        VMShares12 D:\Virtual machines\     0
        VMShares13 D:\Virtual machines\     0
    .INPUTS
        System.String
    .OUTPUTS
        System.String
#>
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9*]{1,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if ($ResponseDetails) {
            $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/sharedfolders") -ResponseDetails
        }
        else {
            $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/sharedfolders")
        }
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
#2 PUT /vms/{id}/sharedfolders/{folder id} Updates a shared folder mounted in the VM
<#
    Function tested, and ok!
    Documented
#>
Function Update-VMSharedFolder {
<#
    .SYNOPSIS
        Updates a shared folder mounnted in the VM
    .DESCRIPTION
        Updates a shared folder mounnted in the VM
    .PARAMETER VMId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
    .PARAMETER SharedFolderName
        the name of the share, must be a valid sharename that is already provided to the Virtual Machine
    .PARAMETER host_path
        a valid directory PATH
    .PARAMETER flags
        4 = read/write
        0 = ReadOnly
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        Update-VMSharedFolder -VMId PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ -host_path 'D:\Virtual machines\' -SharedFolderName "VMShare" -flags 4
        for read/write with flag 4
    .EXAMPLE
        Update-VMSharedFolder -VMId PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ -host_path 'D:\Virtual machines\' -SharedFolderName "VMShare" -flags 0
        for readonly with flag 0
    .INPUTS
        System.String
    .OUTPUTS
        System.String
        System.array
#>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
        [ValidatePattern ('^[*][A-Za-z0-9]{1,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [Parameter(Mandatory)]
        [ValidateScript({
            if( -Not ($_ | Test-Path) ){
                return $false
            }
            return $true
        }, errormessage = "{0}, is a non-existing path")]
        [System.IO.FileInfo]$host_path,
        [string]$SharedFolderName,
        [ValidateSet('4','0', errormessage = "{0}, The flag can contain 0 or 4 and must be 1 characters long, 4 = read/write 0 = read only ")]
        [int]$flags,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    $Body = @{
        'folder_id' = $SharedFolderName;
        'host_path' = $host_path.FullName;
        'flags' = $flags
    }

    if($PSCmdlet.ShouldProcess($Body,"Updates a shared folder mounnted in the VM $($VMId) with the name $($SharedFolderName) and $($host_path)")) {
        CheckVMWareProcess

        if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {



                $Body = $Body | ConvertTo-Json
                if ($ResponseDetails) {
                    $RequestResponse = Invoke-VMWareRestRequest -uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/sharedfolders/$($SharedFolderName)")  -Method PUT -Body $Body -ResponseDetails
                }
                else {
                    $RequestResponse = Invoke-VMWareRestRequest -uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/sharedfolders/$($SharedFolderName)")  -Method PUT -Body $Body

                }
                if ($RequestResponse) {
                    Write-Message -Message "Share with name: $($SharedFolderName) changed to: $($host_path.FullName) with flag: $($flags)" -MessageType INFORMATION
                    return $RequestResponse
                }
            }
            else {
                Write-Message -Message "The Update-VMSharedFolder settings setted for $($VMId) can't be proccessed. Please close VMWware Workstation, and then retry." -MessageType ERROR
            }
        }
        else {
            Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
        }
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
<#
    Function tested
#>
#3 POST /vms/{id}/sharedfolders Mounts a new shared folder in the VM
<#
    Function tested, and ok!
    Documented
#>
Function Add-VMSharedFolder {
 <#
    .SYNOPSIS
       Mounts a new shared folder in the VM
    .DESCRIPTION
        Mounts a new shared folder in the VM
    .PARAMETER VMId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
    .PARAMETER SharedFolderName
        the name of the share, and can be anything
    .PARAMETER host_path
        a valid directory PATH
    .PARAMETER flags
        4 = read/write
        0 = ReadOnly
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        Add-VMSharedFolder -VMId PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ -host_path 'D:\Virtual machines\' -SharedFolderName "VMShare" -flags 4
        for read/write with flag 4

        $addShareFolder = Add-VMSharedFolder -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR -host_path 'G:\' -SharedFolderName "VMShareDemo" -flags 4 -ResponseDetails
        [INFORMATION] -  Share with name: VMShareDemo and path G:\ added with flags (4)
        $addShareFolder

        Code Message
        ---- -------
        200  Share with name: VMShareDemo and path G:\ added with flags (4)
    .EXAMPLE
        $addShareFolder = Add-VMSharedFolder -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR -host_path 'G:\' -SharedFolderName "VMShareDemo0" -flags 0
        $addShareFolder

        folder_id                           host_path                                                flags
        ---------                           ---------                                                -----
        VMShareDemo                         G:\                                                          4
        VMShareDemo0                        G:\                                                          0
    .INPUTS
        System.String
    .OUTPUTS
        System.String
        System.array
#>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{1,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [Parameter(Mandatory)]
        [ValidateScript({
            if(-Not ($_ | Test-Path) ){
                return $false
            }
            else {
                return $true
            }
        }, errormessage = "{0}, is a non-existing path ")]
        [System.IO.FileInfo]$host_path,
        [string]$SharedFolderName,
        [ValidateSet('4','0', errormessage = "{0}, The flag can contain 0 or 4 and must be 1 characters long, 4 = read/write 0 = read only ")]
        [int]$flags,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    if($PSCmdlet.ShouldProcess($Body,"Mounts a new shared folder in the Virtual Machine $($VMId) with the name $($SharedFolderName) with path $($host_path) and $($flags) ")){

        CheckVMWareProcess

        if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {
                $Body = @{
                    'folder_id' = $SharedFolderName;
                    'host_path' = $host_path.FullName;
                    'flags' = $flags
                }
                $Body = ($Body | ConvertTo-Json)
                if ($ResponseDetails) {
                    $RequestResponse = invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/sharedfolders") -Method POST -Body $Body -ResponseDetails
                }
                else {
                    $RequestResponse = invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/sharedfolders") -Method POST -Body $Body
                    return $RequestResponse
                }

                if ($ResponseDetails) {
                    if ($RequestResponse) {
                        switch ($RequestResponse.code) {
                            100 { return $RequestResponse }
                            116 { return $RequestResponse }
                            default {
                                $RequestResponse = $null
                                if ($null -eq $RequestResponse) {
                                    if ($ResponseDetails) {
                                        $RequestResponse = New-Object PSObject
                                        $RequestResponse | Add-Member -MemberType NoteProperty -Name "Code" -Value "200"
                                        $RequestResponse | Add-Member -MemberType NoteProperty -Name "Message" -Value "Share with name: $($SharedFolderName) and path $($host_path) added with flags ($flags)"
                                    }
                                    Write-Message -Message "Share with name: $($SharedFolderName) and path $($host_path) added with flags ($flags)" -MessageType INFORMATION
                                    return $RequestResponse
                                }
                            }
                        }
                    }
                }
            }
            else {
                Write-Message -Message "The settings setted for $($VMId) can't be proccessed. Please close VMWware Workstation, and then retry." -MessageType ERROR
            }
        }
        else {
            Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
        }
    }
}

#--------------------------------------------------------------------------------------------------------------------------------------
#4 DELETE /vms/{id}/sharedfolders/{folder id} Deletes a shared folder
<#
    Function tested, and ok!
    Documented
#>
Function Remove-VMSharedFolder {
 <#
    .SYNOPSIS
       Deletes a shared folder mounted in a vm
    .DESCRIPTION
        Deletes a shared folder mounted in a vm
    .PARAMETER VMId
        Must be a $VMId retrieved bij Get-VirtualMachineList-VirtualMachine *
    .PARAMETER SharedFolderName
        the name of the share, and can be anything
	.PARAMETER ResponseDetails
		 Switch for errorhandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        $RemoveSharedFolder = Remove-VMSharedFolder -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR -SharedFolderName VMShareDemo0 -ResponseDetails
        [INFORMATION] - The resource has been deleted
        [INFORMATION] -  Virtual Machine with VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR has been deleted
        $RemoveSharedFolder

        Code Message
        ---- -------
        204  Virtual Machine with VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR has been deleted
    .EXAMPLE
        $RemoveSharedFolder = Remove-VMSharedFolder -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR -SharedFolderName VMShareDemo
        [INFORMATION] -  The resource has been deleted
    .INPUTS
        System.String
    .OUTPUTS
        System.String
        System.array
#>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{1,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VirtualMachineList to retrieve the VMId's ")]
        [string]$VMId,
        [string]$SharedFolderName,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun

    if($PSCmdlet.ShouldProcess("Removes a shared folder mounted in a vm $($VMId) with the name $($SharedFolderName) ")){

        CheckVMWareProcess

        if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {
                if ($ResponseDetails) {
                    $RequestResponse = Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/sharedfolders/$($SharedFolderName)") -Method DELETE -Body $Body -ResponseDetails
                }
                else {
                    $RequestResponse = Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMId)/sharedfolders/$($SharedFolderName)") -Method DELETE -Body $Body
                }
                if ($ResponseDetails) {
                    if ($RequestResponse) {
                        switch ($RequestResponse.code) {
                            115 { return $RequestResponse }
                            105 { return $RequestResponse }
                            default {
                                Write-Message -Message "Unexpected error $($RequestResponse.code) $($error[0].Exception)" -MessageType ERROR
                                break
                            }
                        }
                    }
                    else {
                        if ($ResponseDetails) {
                            $RequestResponse = New-Object PSObject
                            $RequestResponse | Add-Member -MemberType NoteProperty -Name "Code" -Value "204"
                            $RequestResponse | Add-Member -MemberType NoteProperty -Name "Message" -Value "The Share folder with name: $($SharedFolderName) has been deleted"
                        }
                        Write-Message -Message "The Shared folder with name: $($SharedFolderName) has been deleted" -MessageType INFORMATION
                    }
                }
                return $RequestResponse
            }
            else {
                Write-Message -Message "The settings setted for $($VMId) can't be proccessed. Please close VMWware Workstation, and then retry." -MessageType ERROR
            }
        }
        else {
            Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
        }
    }
}
#--------------------------------------------------------------------------------------------------------------------------------------

#Loader for when the module is addressed during loading
$Path = "$([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile))\Settings-$($([System.Security.Principal.WindowsIdentity]::GetCurrent().Name).replace("\","-")).xml"
if (!(Test-Path -Path $Path)) {
    Write-Message -Message "VMWare Workstation API - Configuration not found, to load the configuration, use the: Get-VMWareWorkstationConfiguration command" -MessageType INFORMATION
}
else {
    CheckVMWareProcess
    Get-VMWareWorkstationConfiguration
    (Get-Variable VMwareWorkstationConfigParameters -Verbose) | Select-Object -ExpandProperty Name
    (Get-Member -InputObject $VMwareWorkstationConfigParameters -MemberType NoteProperty | Select-Object Name, Definition)
}