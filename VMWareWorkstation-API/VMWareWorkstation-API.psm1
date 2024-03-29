<#TODO LIST : Verbose Functionality, VMRUN Functionality
<#
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

        Internal commands, to support the vmware rest api module.

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#>
# 1 Error handling Function
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
            $MessageStartsWith = "[ERROR] -"
        }
        INFORMATION {
            $ForegroundColor = 'White'
            $BackgroundColor = 'blue'
            $MessageStartsWith = "[INFORMATION] -"
        }
        WARNING {
            $ForegroundColor = 'White'
            $BackgroundColor = 'DarkYellow'
            $MessageStartsWith = "[WARNING] -"
        }
    }
   Write-Host "$MessageStartsWith $Message" -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor -NoNewline
   write-host ''
}
#2 shows a browserdialog to find files on disk
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
#3 Search Function for looking up specific files
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
                Write-Message -Message "The Path is not available anymore $($_)" -MessageType ERROR
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
#4 Test if the VMWare rest api is responding and test if the credentials provided are correct.
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
# 5 Function for checking if the vmrest.exe is running
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
#6 Sets the API username and password
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
#7 Import xml to $VMwareWorkstationConfigParameters
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
#8 Export $VMwareWorkstationConfigParameters to xml
Function VMWare_ExportSettings {
    $VMwareWorkstationConfigParameters | Export-Clixml -Path "$([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile))\Settings-$($([System.Security.Principal.WindowsIdentity]::GetCurrent().Name).replace("\","-")).xml" -Force
}
#9 Gather Configuration needed to run script module
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
                                0 { Write-Message -Message "The Path provide did not contain the vmware installation, please retry" -MessageType INFORMATION }
                                1 { Write-Message -Message "The Path provide did not contain the vmware installation, please retry, after this attempt the script will stop." -MessageType INFORMATION }
                                2 { $RetryRetrieveFolderError = $true ; Write-Error -Exception "Path Not found" -ErrorAction Stop }
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
#10 Calling the restapi
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
        Start-Process -FilePath $(Join-Path -Path $VMwareWorkstationConfigParameters.InstallLocation -ChildPath "vmrest.exe") -NoNewWindow #-ArgumentList "-d"

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
        $RequestResponse = Invoke-RestMethod -Uri $($URI) -Method $Method -Headers $Headers -Body $body -StatusCodeVariable "StatusCode" -SkipHttpErrorCheck -ErrorAction Stop

        if (!$?) {
            throw $_.ResponseDetails.Message
        }
        else {
            if ($StatusCode) {
                switch ($StatusCode) {
                    204 { if (!($ResponseDetails)) { Write-Message -Message "$($StatusCode) - The resource has been deleted" -MessageType INFORMATION } }
                    400 { Write-Message -Message "$($StatusCode) - Invalid parameters - $($RequestResponse.Message)" -MessageType ERROR }
                    401 { Write-Message -Message "$($StatusCode) - Authenication failed" -MessageType INFORMATION ; VMWare_SetPassword }
                    403 { Write-Message -Message "$($StatusCode) - Permission denied - $($RequestResponse.Message)" -MessageType ERROR }
                    404 { Write-Message -Message "$($StatusCode) - No such resource - $($RequestResponse.Message)" -MessageType ERROR }
                    406 { Write-Message -Message "$($StatusCode) - Content type was not supported - $($RequestResponse.Message)" -MessageType ERROR }
                    409 { Write-Message -Message "$($StatusCode) - Resource state conflicts - $($RequestResponse.Message)" -MessageType ERROR  }
                    500 { Write-Message -Message "$($StatusCode) - Internal Server error - $($RequestResponse.Message)" -MessageType ERROR }
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
       write-message -message "Unexpected error: $($_)"  -MessageType ERROR
    }
}
#11 Check if the VNWare process is active and kill it will running code from the commandline
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
                    Write-Message -Message "The VMWareWorkstation-API Module will continue, only the GET- Functions will work, but the rest of the Functions won't work untill you close the VMware Workstation console" -MessageType WARNING
                }
            }
        }
    }
    catch {
        Write-Message -Message "Unknown error $($_)" -MessageType ERROR
    }
}
#12 Documentation.
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
<#
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

        Host Networks Management
            # Fully Documented
            # Fully Tested

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

            # 1 GET /vmnet Returns all virtual networks
            # 2 GET /vmnet/{vmnet}/mactoip
            # 3 GET /vmnet/{vmnet}/portforward Returns all port forwardings
            # 4 PUT /vmnet/{vmnet}/mactoip/{mac} Updates the MAC-to-IP binding
            # 5 PUT /vmnet/{vmnet}/portforward/{protocol}/{port} Updates port forwarding
            # 6 POST /vmnets Creates a virtual network
            # 7 DELETE /vmnet/{vmnet}/portforward/{protocol}/{port} Deletes port forwarding

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#>
<#  1 GET /vmnet Returns all virtual networks
        Function tested and documented
#>
Function Get-VMVirtualNetworkList {
<#
    .SYNOPSIS
        Returns all virtual networks

    .DESCRIPTION
        Returns all virtual networks
    .EXAMPLE
        $VirtualNetworks = Get-VMVirtualNetworkList s
        num vmnets
        --- ------
        4 {@{name=vmnet0; type=bridged; dhcp=false; subnet=; mask=}, @{name=vmnet1; type=hostOnly; dhcp=true; subnet=192.168.80.0; mask=255.255.255.0}, @{name=vmnet8; type=nat; dhcp=true; subnet=192.168.174.0; mask=255.255.255.0}, @{name=vm…

    .EXAMPLE
            $VirtualNetworks = $(Get-VMVirtualNetworkList).vmnets

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
    .EXAMPLE
        $(Get-VMVirtualNetworkList -ResponseDetails).vmnets | Where-Object { $_.type -ne "hostonly" }

        name   : vmnet8
        type   : nat
        dhcp   : true
        subnet : 192.168.175.0
        mask   : 255.255.255.0
    .NOTES

            The Model:
            Networks {
                num (integer): Number of items integerDefault:0,
                vmnets (Array[Network]): The list of virtual networks
                }Network {
                name (string): Name of virtual network ,
                type (string) = ['bridged', 'nat', 'hostOnly']stringEnum:"bridged", "nat", "hostOnly",
                dhcp (string) = ['true', 'false']stringEnum:"true", "false",
                subnet (string),
                mask (string)
            }
            Example output:
            {
                "num": 0,
                "vmnets": [
                    {
                    "name": "string",
                    "type": "bridged",
                    "dhcp": "true",
                    "subnet": "string",
                    "mask": "string"
                    }
                ]
                }
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
<#  2 GET /vmnet/{vmnet}/mactoip
        Function tested and documented
#>
Function Get-VMNetMacToIp {
<#
    .SYNOPSIS
        Returns all MAC-to-IP settings for DHCP service
    .DESCRIPTION
        Returns all MAC-to-IP settings for DHCP service
    .PARAMETER VMNet
        A Virtual network name like vmnet8
        a Virtual Network name is a network used interally in vmware workstation. Under Edit > Virtual network editor you can find more information
    .PARAMETER ResponseDetails
         Switch for Responsehandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
     .EXAMPLE
        You can retreive the Macaddress to IPAddress settings with the following commnand

        $NetWorKWithDHCP = $(Get-VMVirtualNetworkList).vmnets | where-object { $_.dhcp -eq "true" } | Select-Object -ExpandProperty Name
        $NetWorKWithDHCP | foreach { Get-VMNetMacToip -VMNet $_  }
    .EXAMPLE
        Get-VMNetMacToip -VMNet vmnet8 -ResponseDetails

        returns

        num mactoips
        --- --------
        0 {}
    .EXAMPLE
        Get-VMNetMacToip -VMNet vmnet1 -ResponseDetails

        num mactoips
        --- --------
        1 {@{mac=00:0c:29:d2:2c:96; ip=192.168.85.128; vmnet=vmnet1}}
    .NOTES
        The Response Class model :
        MACToIPs {
            num (integer): Number of items integerDefault:0,
            mactoips (Array[MACToIP], optional): The list of MAC to IP settings
            }MACToIP {
            vmnet (string),
            mac (string),
            ip (string)
        }
        Example output:
        {
        "num": 0,
        "mactoips": [
            {
            "vmnet": "string",
            "mac": "string",
            "ip": "string"
            }
        ]
        }
    .INPUTS
       System.String
    .OUTPUTS
       System.String
#>
    [cmdletbinding()]
    param (

        [Parameter(Mandatory)]
        [ValidateScript({$_ -cmatch 'vmnet([1]?\d|20)$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits and between 1 and 20")]
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
<#  3 GET /vmnet/{vmnet}/portforward Returns all port forwardings
        Function tested and documented
#>
Function Get-VMVirtualNetworkListPortForwarding {
 <#
    .SYNOPSIS
        Returns all port forwardings
    .DESCRIPTION
        Returns all port forwardings
    .PARAMETER VMNet
        A Virtual network name like
        a Virtual Network name is a network used interally in vmware workstation. Under Edit > Virtual network editor you can find more information
    .PARAMETER ResponseDetails
         Switch for Responsehandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        Get-VMVirtualNetworkListPortForwarding -VMNet vmnet1

        num mactoips
        --- --------
        1 {@{mac=00:0c:29:d2:2c:96; ip=192.168.85.128; vmnet=vmnet1}}
    .EXAMPLE
        You can retreive the vmnets with the following commnand

        $NetWorKWithDHCP = $(Get-VMVirtualNetworkList).vmnets.name

        Get-VMVirtualNetworkListPortForwarding -VMNet vmnet8

        num mactoips
        --- --------
        0 {}

    .EXAMPLE
        $NetWorkList = $(Get-VMVirtualNetworkList).vmnets | Where-Object { $_.dhcp -eq "True"} | Select-Object -ExpandProperty Name

        $NetWorkList contains
        vmnet1
        vmnet8
        vmnet16
        vmnet17
        vmnet18

        $NetWorkList | foreach { Get-VMVirtualNetworkListPortForwarding -VMNet $_ }

        num mactoips
        --- --------
        1 {@{mac=00:0c:29:d2:2c:96; ip=192.168.85.128; vmnet=vmnet1}}
        0 {}
        0 {}
        0 {}
        0 {}
    .NOTES
        The Response Class model :
            Portforwards {
                num (integer): Number of items integerDefault:0,
                port_forwardings (Array[Portforward]): The list of port forwardings
                }Portforward {
                port (integer): port of communication integerDefault:0,
                protocol (string) = ['tcp', 'udp']stringEnum:"tcp", "udp",
                desc (string),
                guest (inline_model)
                }inline_model {
                ip (string),
                port (integer): port of communication integerDefault:0
            }
	  Example output:
        {
        "num": 0,
        "port_forwardings": [
            {
            "port": 0,
            "protocol": "tcp",
            "desc": "string",
            "guest": {
                "ip": "string",
                "port": 0
            }
            }
        ]
        }
    .INPUTS
       System.String
    .OUTPUTS
       System.String
#>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({$_ -cmatch 'vmnet([1]?\d|20)$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits and between 1 and 20")]
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
<#  4 PUT /vmnet/{vmnet}/mactoip/{mac} Updates the MAC-to-IP binding
        Function tested and documented
#>
Function Set-VMMacToIpBinding {
<#
    .SYNOPSIS
        Updates the MAC-to-IP binding
    .DESCRIPTION
        Updates the MAC-to-IP binding
    .PARAMETER VMNet
        A Virtual network name like vmnet8
        a Virtual Network name is a network used interally in vmware workstation. Under Edit > Virtual network editor you can find more information
    .PARAMETER MACAddress
        A mac-address format: 00:00:00:00:00:00 example: 00:0c:29:d2:2c:96
        A MAC address (media access control address) is a 12-digit hexadecimal number assigned to each device connected to the network.
        Primarily specified as a unique identifier during device manufacturing, the MAC address is often found on a device's network interface card (NIC)
    .PARAMETER IpAddress
        An IP address is a string of numbers separated by periods. IP addresses are expressed as a set of four numbers — an example address might be 192.158.1.38.
        Each number in the set can range from 0 to 255. So, the full IP addressing range goes from 0.0.0.0 to 255.255.255.255
    .PARAMETER ResponseDetails
         Switch for Responsehandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
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
    .NOTES
        The Response Class model :
        ErrorModel {
            code (integer),
            message (string)
        }
	  Example output:
        {
            "code": 0,
            "message": "string"
        }
    .INPUTS
       System.String
    .OUTPUTS
       System.Array
#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({$_ -cmatch 'vmnet([1]?\d|20)$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits and between 1 and 20")]
        [string]$VMNet,
        [Parameter(Mandatory)]
        [ValidateScript({[System.Net.NetworkInformation.PhysicalAddress]::Parse($_) })]
        $MACAddress,
        [Parameter(Mandatory)]
        [ValidateScript({$_ -Match [IPAddress]$_ })]
        [string]$IpAddress,
        [switch]$ResponseDetails
    )
    if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
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
    else {
        Write-Message -Message "The Function Get-VMVirtualNetworkListPortForwarding must be runned with a priviliged account (run the script as administator)  " -MessageType WARNING
    }
}
<#  5 PUT /vmnet/{vmnet}/portforward/{protocol}/{port} Updates port forwarding
        Function tested and documented
#>
Function Set-VMPortForwarding {
<#
    .SYNOPSIS
        Updates a port forwarding on a vmnet
    .DESCRIPTION
        Updates port forwarding vmnet
    .PARAMETER VMNet
        A Virtual network name like vmnet8 the network must be a nat network
        a Virtual Network name is a network used interally in vmware workstation. Under Edit > Virtual network editor you can find more information
    .PARAMETER Protocol
        TCP is a connection-oriented protocol, which means, once a connection is established, data can be sent bidirectional. UDP, on the other hand, is a simpler, connectionless Internet protocol.
        Multiple messages are sent as packets in chunks using UDP.
    .PARAMETER Port
        The Port from the DCHP network
        A port in networking is a software-defined number associated to a network protocol that receives or transmits communication for a specific service.
        A port in computer hardware is a jack or socket that peripheral hardware plugs into.
    .PARAMETER GuestIP
        The IPAddress of the Virtual Machine that you want to do portforwarding on
        An IP address is a string of numbers separated by periods. IP addresses are expressed as a set of four numbers — an example address might be 192.158.1.38.
        Each number in the set can range from 0 to 255. So, the full IP addressing range goes from 0.0.0.0 to 255.255.255.255
    .PARAMETER GuestPort
        The Port on the Guest that has to be opened
        A port in networking is a software-defined number associated to a network protocol that receives or transmits communication for a specific service.
        A port in computer hardware is a jack or socket that peripheral hardware plugs into.
    .PARAMETER Description
        A Briefnote for yourself "Proxy on port 3128 opened for 192.168.125.20" for example
    .PARAMETER ResponseDetails
         Switch for Responsehandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
    .EXAMPLE
        Set-VMPortForwarding -VMNet vmnet1 -Protocol tcp 9999 -GuestIP 192.168.85.128 -guestPort 9999 -Description "test"

        Code Message
        ---- -------
        0 The operation was successful
    .EXAMPLE

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
        [ValidateScript({$_ -cmatch 'vmnet([1]?\d|20)$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits and between 1 and 20")]
        [string]$VMNet,
        [Parameter(Mandatory)]
        [ValidateSet('TCP','tcp', 'UDP','udp', errormessage = "{0}, Value must be: TCP or UDP, or lowercase")]
        $Protocol,
        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port,
        [Parameter(Mandatory)]
        [ValidateScript({$_ -Match [IPAddress]$_ })]
        [string]$GuestIP,
        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$GuestPort,
        [Parameter(Mandatory)]
        [String]$Description,
        [switch]$ResponseDetails
    )
    if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        CheckForVMRestToRun
        CheckVMWareProcess

        if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {
                $Body = @{
                    'guestIp'= $GuestIP;
                    'guestPort' = $guestPort;
                    'desc' = $Description
                } | ConvertTo-Json

                if($PSCmdlet.ShouldProcess($Body,"Updates port forwarding on $($vmNet) with $($Protocol) on $($Port) to: ")){
                    if ($ResponseDetails) {
                        $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($VMNet)/portforward/$($Protocol)/$($Port)") -Method PUT -Body $Body -ResponseDetails
                    }
                    else {
                        $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($VMNet)/portforward/$($Protocol)/$($Port)") -Method PUT -Body $Body
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
        }
        else {
            Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
        }
    }
    else {
        Write-Message -Message "The Function Set-VMPortForwarding must be runned with a priviliged account (run the script as administator)  " -MessageType WARNING
    }
}
<#  6 POST /vmnets Creates a virtual network
        Function tested and documented
#>
Function New-VMVirtualNetwork {
<#
    .SYNOPSIS
        Creates a virtual network
    .DESCRIPTION
        Creates a virtual network
    .PARAMETER VMNetName
        A Virtual network name like VMNET8
        a Virtual Network name is a network used interally in vmware workstation. Under Edit > Virtual network editor you can find more information
    .PARAMETER VMNettype
        NAT – Network Address Translation.
        Host-Only - Vmware Network Connections (sandboxed)
    .PARAMETER ResponseDetails
            Switch for Responsehandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
    .EXAMPLE
        New-VMVirtualNetwork -VMNetName vmnet12 -VMNettype hostonly -r

        num vmnets
        --- ------
        1 {@{name=vmnet12; type=hostOnly; dhcp=true; subnet=192.168.186.0; mask=255.255.255.0}}
    .NOTES
        The responseclass model:
        Network {
            name (string): Name of virtual network ,
            type (string) = ['bridged', 'nat', 'hostOnly']stringEnum:"bridged", "nat", "hostOnly",
            dhcp (string) = ['true', 'false']stringEnum:"true", "false",
            subnet (string),
            mask (string)
        }
        Example output:
        {
            "name": "string",
            "type": "bridged",
            "dhcp": "true",
            "subnet": "string",
            "mask": "string"
        }
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
        [ValidateScript({$_ -cmatch 'vmnet([1]?\d|20)$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits and between 1 and 20")]
        [string]$VMNetName,
        [Parameter(Mandatory)]
        [ValidateSet('nat','hostonly', errormessage = "{0}, Value must be: nat or hostonly")]
        [string]$VMNettype,
        [switch]$ResponseDetails
    )
    if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

        CheckForVMRestToRun
        CheckVMWareProcess
        $Body = @{
            'name' = $VMNetName;
            'type' = $VMNettype
        } | ConvertTo-Json
    }

    if($PSCmdlet.ShouldProcess($Body,"Creating a Virtual network with the name $($Name) and type $($type) ")){
        if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

            if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
                if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {
                    if ($ResponseDetails) {
                        $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnets") -Method POST -Body $body -ResponseDetails
                    }
                    else {
                        $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnets") -Method POST -Body $body
                        return $RequestResponse
                    }
                    if ($ResponseDetails) {
                        return $RequestResponse
                    }
                }
                else {
                    Write-Message -Message "Can't close the VMWare Workstation Console. The creation of the Virtual Network with name $($Name) can't be proccessed. please close the program " -MessageType ERROR
                }
            }
            else {
                Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
            }
        }
        else {
            Write-Message -Message "The Function New-VMVirtualNetwork must be runned with a priviliged account (run the script as administator)  " -MessageType WARNING
        }
    }
}
<# 7 DELETE /vmnet/{vmnet}/portforward/{protocol}/{port} Deletes port forwarding
        Function tested and documented
#>
Function Remove-VMPortForwarding {
    <#
        .SYNOPSIS
            Deletes port forwarding
        .DESCRIPTION
            Deletes port forwarding
        .PARAMETER VMNet
            A Virtual network name like vmnet8
            a Virtual Network name is a network used interally in vmware workstation. Under Edit > Virtual network editor you can find more information
        .PARAMETER Protocol
            TCP is a connection-oriented protocol, which means, once a connection is established, data can be sent bidirectional. UDP, on the other hand, is a simpler, connectionless Internet protocol.
        .PARAMETER Port
            The Port on the Guest that has to be opened
            A port in networking is a software-defined number associated to a network protocol that receives or transmits communication for a specific service.
            A port in computer hardware is a jack or socket that peripheral hardware plugs into.
        .PARAMETER ResponseDetails
            Switch for Responsehandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
        .PARAMETER Whatif
            When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
            it's a good way to test out the impact of a command, especially before you do something destructive.
        .PARAMETER Confirm
            Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
        .EXAMPLE
            Remove-VMPortForwarding -VMNet vmnet8 -Protocol tcp -Port 9999
            [INFORMATION] - 204 - The resource has been deleted
        .EXAMPLE
            Remove-VMPortForwarding -VMNet vmnet8 -Protocol tcp -Port 9999 -ResponseDetails
            [INFORMATION] - Removed portforwarding on: vmnet8 with protocol: tcp and 9999

            Code Message
            ---- -------
            204  Removed portforwarding on: vmnet8 with protocol: tcp and 9999
        .NOTES
            The responseclass model:
                None
            Example output:
                code 204
        .INPUTS
           System.String
        .OUTPUTS
           Message
    #>
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [ValidateScript({$_ -cmatch 'vmnet([1]?\d|20)$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits and between 1 and 20")]
            [string]$VMNet,
            [Parameter(Mandatory)]
            [ValidateSet('TCP','tcp', 'UDP','udp', errormessage = "{0}, Value must be: TCP or UDP")]
            $Protocol,
            [Parameter(Mandatory)]
            [ValidateRange(1, 65535)]
            [int]$Port,
            [switch]$ResponseDetails
        )
        if($PSCmdlet.ShouldProcess($($VMNET) ,"Removes a Portforwarding on: $($vmnet) with protocol: $($protocol) and $($port) ")){

            CheckForVMRestToRun
            CheckVMWareProcess

            if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
                if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {

                        if ($ResponseDetails) {
                            $RequestResponse=Invoke-VMWareRestRequest -Method DELETE -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($VMnet)/portforward/$($Protocol)/$($Port)") -ResponseDetails
                        }
                        else {
                            $RequestResponse=Invoke-VMWareRestRequest -Method DELETE -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($VMnet)/portforward/$($Protocol)/$($Port)")
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
                                    Write-Message -Message "Unexpected error: $($RequestResponse.code) : $($_)" -MessageType ERROR
                                    break
                                }
                            }
                        }
                        else {
                            if ($ResponseDetails) {
                                $RequestResponse = $null
                                $RequestResponse = New-Object PSObject
                                $RequestResponse | Add-Member -MemberType NoteProperty -Name "Code" -Value "204"
                                $RequestResponse | Add-Member -MemberType NoteProperty -Name "Message" -Value "Removed portforwarding on: $($vmnet) with protocol: $($protocol) and $($port)"
                            }
                            Write-Message -Message "Removed portforwarding on: $($vmnet) with protocol: $($protocol) and $($port)" -MessageType INFORMATION
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
<#
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

    VM Management
        # 3 not working ( still have to finish it)
        # 6 not working ( still have to finish it)

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

        # 0 - Load Configuration
        # 1 GET /vms Returns a list of VM IDs and paths for all VMs
        # 2 GET /vms/{id} Returns the VM setting information of a VM
        # 3 GET /vms/{id}/params/{name} Get the VM config params
        # 4 GET /vms/{id}/restrictions Returns the restrictions information of the VM
        # 5 GET /vms/{id}/params/{name} update the VM config params
        # 6 PUT /vms/{id}/configparams update the vm config params
        # 7 POST /vms Creates a copy of the VM
        # 8 POST /vms/registration Register VM to VM Library
        # 9 DELETE /vms/{id} Deletes a VM
        # 10 Returns a list with virtual machines that are templates

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------#>
<#  0 - Load Configuration
        Function tested and documented
#>
Function Get-VMWareWorkstationConfiguration {
<#
    .SYNOPSIS
        creates a psobject to store the data needed for the proper Functioning of the module, all the necessary data is stored in a variable
    .DESCRIPTION
        creates a psobject to store the data needed for the proper Functioning of the module, all the necessary data is stored in a variable
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
<#  1 GET /vms Returns a list of VM IDs and paths for all VMs
        Function tested and documented
#>
Function Get-VMVirtualMachineList {
<#
    .SYNOPSIS
        List the virtual machines stored in the virtual machine folder
    .DESCRIPTION
        List the virtual machines stored in the virtual machine folder
    .PARAMETER VirtualMachinename
       Can be a asterix * to retrieve all virtual machines
       Mandatory - [string]

        PS C:\WINDOWS\system32> Get-VMVirtualMachineList -VirtualMachinename *

        id                               path
        --                               ----
        PK7CPPB5UV50M3B73QD5ELDQN2OD9UFJ D:\Virtual machines\VMFOLDER1\VMNAME1.vmx
        649TJ74BEAHCM93M56DM79VD21562M8D D:\Virtual machines\VMFOLDER2\VMNAME2.vmx
    .PARAMETER Description
       Can be a VMID retrieved bij knowing the VMID

        PS C:\WINDOWS\system32> Get-VMVirtualMachineList -VirtualMachinename VMNAME3

        id                               path
        --                               ----
        E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5 D:\Virtual machines\VMFOLDER3\VMNAME3.vmx

       Mandatory - [string]
    .PARAMETER ResponseDetails
         Switch for Responsehandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
     .EXAMPLE
       Can be a asterix * to retrieve all virtual machines a machine name or a vmid

       Mandatory - [string]

        Get-VMVirtualMachineList -VirtualMachinename *

        id                               path
        --                               ----
        PK7CPPB5UV50M3B73QD5ELDQN2OD9UFJ D:\Virtual machines\VMFOLDER1\VMNAME1.vmx
        649TJ74BEAHCM93M56DM79VD21562M8D D:\Virtual machines\VMFOLDER2\VMNAME2.vmx
    .PARAMETER Description
       Can be a VMID retrieved by knowing the VMID

        Get-VMVirtualMachineList -VirtualMachinename VMNAME2

        id                               path
        --                               ----
        E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5 D:\Virtual machines\VMFOLDER2\VMNAME2.vmx
    .EXAMPLE
        Get-VMVirtualMachineList -VirtualMachinename E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5

        id                               path
        --                               ----
        E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5 D:\Virtual machines\Windows Server 2016 DC-GUI Template\Windows Server 2016 DC-GUI Template.vmx
    .EXAMPLE
        Get-VMVirtualMachineList -VirtualMachinename "Windows Server 2016 DC-GUI Template.vmx"

        id                               path
        --                               ----
        E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5 D:\Virtual machines\Windows Server 2016 DC-GUI Template\Windows Server 2016 DC-GUI Template.vmx
    .EXAMPLE
        retrieve the id of the virtual machine
        $(Get-VMVirtualMachineList -VirtualMachinename PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ).id

        results E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5
    .EXAMPLE
        retrieve the path of the virtual machine
        $(Get-VMVirtualMachineList -VirtualMachinename PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ).Path

        results in D:\Virtual machines\VMFOLDER1\VMNAME1.vmx
    .EXAMPLE
     $GatherVMS = $(Get-VMVirtualMachineList -VirtualMachinename *)
    .NOTES
        The responseclass model:
        Inline Model [
        Inline Model 1
        ]Inline Model 1 {
            id (string): ID of the VM ,
            path (string): Path of the VM
        }
	  Example output:
        [
            {
                "id": "string",
                "path": "string"
            }
        ]
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
        Write-Verbose -Message "Creating the Errorcode to throw on Function Get-VMVirtualMachineList "
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
<#  2 GET /vms/{id} Returns the VM setting information of a VM
        Function tested and documented
#>
Function Get-VMConfig {
<#
    .SYNOPSIS
        Returns the VM setting information of a VM
    .DESCRIPTION
        Returns the VM setting information of a VM
    .PARAMETER vmid
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList  -VirtualMachinename *

        id                               path
        --                               ----
        PK7CPPB5UV50M3B73QD5ELDQN2OD9UFJ D:\Virtual machines\VMFOLDER1\VMNAME1.vmx
        649TJ74BEAHCM93M56DM79VD21562M8D D:\Virtual machines\VMFOLDER2\VMNAME2.vmx
    .PARAMETER ResponseDetails
         Switch for Responsehandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        retrieve the id of the virtual machine

        Get-VMConfig -VMId M3HAD21LB73N4GSHGJIC2MDM115A5GJT

        results in"
        id                               cpu             memory
        --                               ---             ------
        M3HAD21LB73N4GSHGJIC2MDM115A5GJT @{processors=1}    512
    .NOTES
        The responseclass model:
            ConfigVMParamsParameter {
                name (string, optional): config params name ,
                value (string, optional): config params value
            }
	  Example output:
            {
                "name": "string",
                "value": "string"
            }
    .INPUTS
       System.String
    .OUTPUTS
       System.array
#>

    [cmdletbinding()]
    param (
        [ValidatePattern('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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
<#  3 GET /vms/{id}/params/{name} Get the VM config params
        Still have to find out what can be retrieved
#>
Function Get-VMConfigParam {
}
<#  4 GET /vms/{id}/restrictions Returns the restrictions information of the VM
        Function tested and documented
#>
Function Get-VMRestriction {
<#
    .SYNOPSIS
        Returns the restrictions information of the VM
    .DESCRIPTION
        Returns the restrictions information of the VM
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
	.PARAMETER ResponseDetails
		 Switch for Responsehandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
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
    .NOTES
        The responseclass model:
            VMRestrictionsInformation {
                id (string),
                managedOrg (string, optional): The organization manages the VM ,
                integrityconstraint (string, optional) = ['true', 'false']stringEnum:"true", "false",
                cpu (VMCPU, optional),
                memory (integer, optional): Memory size in mega bytes integerDefault:512,
                applianceView (VMApplianceView, optional),
                cddvdList (VMConnectedDeviceList, optional),
                floopyList (VMConnectedDeviceList, optional),
                firewareType (integer, optional): Number of items integerDefault:0,
                guestIsolation (VMGuestIsolation, optional),
                niclist (NICDevices, optional),
                parallelPortList (VMConnectedDeviceList, optional),
                serialPortList (VMConnectedDeviceList, optional),
                usbList (VMUsbList, optional),
                remoteVNC (VMRemoteVNC, optional)
                }VMCPU {
                processors (integer, optional): Number of processor cores integerDefault:1
                }VMApplianceView {
                author (string, optional),
                version (string, optional),
                port (integer, optional): port of communication integerDefault:0,
                showAtPowerOn (string, optional) = ['true', 'false']stringEnum:"true", "false"
                }VMConnectedDeviceList {
                num (integer, optional): Number of items integerDefault:0,
                devices (Array[VMConnectedDevice], optional)
                }VMGuestIsolation {
                copyDisabled (string, optional) = ['true', 'false']stringEnum:"true", "false",
                dndDisabled (string, optional) = ['true', 'false']stringEnum:"true", "false",
                hgfsDisabled (string, optional) = ['true', 'false']stringEnum:"true", "false",
                pasteDisabled (string, optional) = ['true', 'false']stringEnum:"true", "false"
                }NICDevices {
                num (integer): Number of NIC devices integerDefault:1,
                nics (Array[NICDevice]): The network adapter added to this VM
                }VMUsbList {
                num (integer, optional): Number of items integerDefault:0,
                usbDevices (Array[VMUsbDevice], optional)
                }VMRemoteVNC {
                VNCEnabled (string, optional) = ['true', 'false']stringEnum:"true", "false",
                VNCPort (integer, optional): port of communication integerDefault:0
                }VMConnectedDevice {
                index (integer, optional): Number of items integerDefault:0,
                startConnected (string, optional) = ['true', 'false']stringEnum:"true", "false",
                connectionStatus (integer, optional): Number of items integerDefault:0,
                devicePath (string, optional)
                }NICDevice {
                index (integer): Index of Network Adapters integerDefault:1,
                type (string): The network type of network adapter = ['bridged', 'nat', 'hostonly', 'custom']stringEnum:"bridged", "nat", "hostonly", "custom",
                vmnet (string): The vmnet name ,
                macAddress (string): Mac address
                }VMUsbDevice {
                index (integer, optional): Number of items integerDefault:0,
                connected (string, optional) = ['true', 'false']stringEnum:"true", "false",
                backingInfo (string, optional),
                BackingType (integer, optional): Number of items integerDefault:0
            }
	  Example output:
            {
            "id": "string",
            "managedOrg": "string",
            "integrityconstraint": "true",
            "cpu": {
                "processors": 1
            },
            "memory": 512,
            "applianceView": {
                "author": "string",
                "version": "string",
                "port": 0,
                "showAtPowerOn": "true"
            },
            "cddvdList": {
                "num": 0,
                "devices": [
                {
                    "index": 0,
                    "startConnected": "true",
                    "connectionStatus": 0,
                    "devicePath": "string"
                }
                ]
            },
            "floopyList": {
                "num": 0,
                "devices": [
                {
                    "index": 0,
                    "startConnected": "true",
                    "connectionStatus": 0,
                    "devicePath": "string"
                }
                ]
            },
            "firewareType": 0,
            "guestIsolation": {
                "copyDisabled": "true",
                "dndDisabled": "true",
                "hgfsDisabled": "true",
                "pasteDisabled": "true"
            },
            "niclist": {
                "num": 1,
                "nics": [
                {
                    "index": 1,
                    "type": "bridged",
                    "vmnet": "string",
                    "macAddress": "string"
                }
                ]
            },
            "parallelPortList": {
                "num": 0,
                "devices": [
                {
                    "index": 0,
                    "startConnected": "true",
                    "connectionStatus": 0,
                    "devicePath": "string"
                }
                ]
            },
            "serialPortList": {
                "num": 0,
                "devices": [
                {
                    "index": 0,
                    "startConnected": "true",
                    "connectionStatus": 0,
                    "devicePath": "string"
                }
                ]
            },
            "usbList": {
                "num": 0,
                "usbDevices": [
                {
                    "index": 0,
                    "connected": "true",
                    "backingInfo": "string",
                    "BackingType": 0
                }
                ]
            },
            "remoteVNC": {
                "VNCEnabled": "true",
                "VNCPort": 0
            }
            }
    .INPUTS
       System.String
    .OUTPUTS
       System.array that can be converted to JSON
#>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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
<#  5 GET /vms/{id}/params/{name} update the VM config params
        Function tested and documented
#>
Function Set-VMConfig {
<#
    .SYNOPSIS
        update the VM config params
    .DESCRIPTION
        update the VM config params
    .PARAMETER processors
        Must be a number and is not not mandatory
        A central processing unit (CPU), also called a central processor or main processor, is the most important processor in a given computer.
    .PARAMETER memory
        Must be a number and is not mandatory, VMWare Workstation calculates the best size.
        In computing, memory is a device or system that is used to store information for immediate use in a computer or related computer hardware
    .PARAMETER ResponseDetails
         Switch for Responsehandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
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
    .EXAMPLE

        Set-VMConfig -VMId 2SC4BST99C9C6Q8UOTNQQV659NNDUTLL -ResponseDetails -Memory 512
        id                               cpu             memory
        --                               ---             ------
        2SC4BST99C9C6Q8UOTNQQV659NNDUTLL @{processors=2}    512
    .EXAMPLE
        Set-VMConfig -VMId 2SC4BST99C9C6Q8UOTNQQV659NNDUTLL -ResponseDetails -Processors 3
        id                               cpu             memory
        --                               ---             ------
        2SC4BST99C9C6Q8UOTNQQV659NNDUTLL @{processors=3}    512
    .NOTES
        The responseclass model:
        VMInformation {
            id (string),
            cpu (VMCPU, optional),
            memory (integer, optional): Memory size in mega bytes integerDefault:512
            }VMCPU {
            processors (integer, optional): Number of processor cores integerDefault:1
        }
	  Example output:
      {
        "id": "string",
        "cpu": {
            "processors": 1
        },
        "memory": 512
    }
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
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
        [string]$VMId,
        [ValidatePattern ('^[0-9]', errormessage = "{0}, The Processor parameter can contain [0-9]")]
        [int]$Processors,
        [ValidatePattern ('^[0-9]', errormessage = "{0}, The Memory parameter can contain [0-9]")]
        [int]$Memory,
        [switch]$ResponseDetails
    )

    CheckForVMRestToRun
    CheckVMWareProcess

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if (!($(Get-Process -Name vmware -ErrorAction SilentlyContinue))) {

           $CurrentConfig = Get-VMConfig -VMId $VMId

           if (!($Processors)) { $Processors = $CurrentConfig.cpu.processors }
           if (!($Memory)) { $Memory = $CurrentConfig.Memory }

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
<# 6 PUT /vms/{id}/configparams update the vm config params
        # still have to find out how this function works
#>
Function Set-VMConfigParam {
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
    )
    if($PSCmdlet.ShouldProcess($Body,"Change the Virtual machine settings on $($VMID) to: ")){
    }
}
<#  7 POST /vms Creates a copy of the VM
        Function tested and documented
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
        Must be a $VMId retrieved bij Get-VMVirtualMachineList -VirtualMachine * or with Get-VMTemplateList function
    .PARAMETER ResponseDetails
         Switch for Responsehandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
    .EXAMPLE
        $NewVMCloneName = $("CLONE-" + -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 11 | % {[char]$_})).ToUpper()
        $NewClonedVM = New-VMClonedMachine -NewVMCloneName $NewVMCloneName -NewVMCloneId 649TJ74BEAHCM93M56DM79CD21562M8D -ResponseDetails
        $NewClonedVM

        id                               cpu             memory
        --                               ---             ------
        NSL0TNFKV4TPL87NVVAUETDR8GF658AT @{processors=1}    512
    .EXAMPLE
        $NewVMCloneName = $("CLONE-" + -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 11 | % {[char]$_})).ToUpper()
        $NewClonedVM = New-VMClonedMachine -NewVMCloneName $NewVMCloneName -NewVMCloneId 649TJ74BEAHCM93M56DM79CD21562M8D -ResponseDetails
        $NewClonedVM

        id                               cpu             memory
        --                               ---             ------
        NSL0TNFKV4TPL87NVVAUETDR8GF658AT @{processors=1}    512

        # Registering the Virtual Machine in the VMWare Workstation console

            $ClonePath = Get-VirtualMachines -VirtualMachineName $NewVMCloneName
            $RegisterVM = Register-VMClonedMachine -NewVMCloneName $NewVMCloneName -VMClonePath $ClonePath.path -ResponseDetails -ErrorAction Stop

        $RegisterVM

        The Machine will be visable in the VMWare Workstation console
    .NOTES
        The responseclass model:
            VMInformation {
                id (string),
                cpu (VMCPU, optional),
                memory (integer, optional): Memory size in mega bytes integerDefault:512
                }VMCPU {
                processors (integer, optional): Number of processor cores integerDefault:1
            }
	  Example output:
        {
            "id": "string",
            "cpu": {
                "processors": 1
            },
            "memory": 512
        }
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
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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
<#  8 POST /vms/registration Register VM to VM Library
    Function tested and documented
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
		 Switch for Responsehandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        after creating a new cloned machine the vm can be registered in the vmware gui

        For example
        Create a generic name

        Use name that was used in the NEW-VM
        $NewVMCloneName = $("CLONE-" + -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 11 | % {[char]$_})).ToUpper()

        $NewVMCloneName

        CLONE-WDMEPYTYLTC ( this name was made within the New-VMClonedMachine Function)

        $NewClonedMachine = New-VMClonedMachine -NewVMCloneName $NewVMCloneName -NewVMCloneId 649TJ74BEAHCM93M56DM79CD21562M8D
        $NewClonedMachine

        id                               cpu             memory
        --                               ---             ------
        JMPFQNFBDPGGCRTGSVQOTUES038F4VEC @{processors=2}   4096

        Register-VMClonedMachine -NewVMCloneName $NewVMCloneName -VMClonePath (Get-VMVirtualMachineList -VirtualMachinename $NewVMCloneName).path

        id                               path
        --                               ----
        JMPFQNFBDPGGCRTGSVQOTUES038F4VEC D:\Virtual machines\CLONE-WDMEPYTYLTC\CLONE-WDMEPYTYLTC.vmx
    .EXAMPLE
        Register-VMClonedMachine -NewVMCloneName $NewVMCloneName -VMClonePath (Get-VMVirtualMachineList -VirtualMachinename $NewVMCloneName).path

        id                               path
        --                               ----
        JMPFQNFBDPGGCRTGSVQOTUES038F4VEC D:\Virtual machines\CLONE-WDMEPYTYLTC\CLONE-WDMEPYTYLTC.vmx
    .EXAMPLE

        Retrieve VM's with Get-VMVirtualMachineList -VirtualMachinename *

        Get-VMVirtualMachineList -VirtualMachinename *

        id                               path
        --                               ----
        LR4UDDNNON7BD3SC1MIG8A2GO03EAR2O D:\Virtual machines\CLONE-8EFNC1M6XWJ\CLONE-8EFNC1M6XWJ.vmx

        Register-VMClonedMachine -NewVMCloneName CLONE-8EFNC1M6XWJ.vmx or CLONE-8EFNC1M6XWJ -VMClonePath "D:\Virtual machines\CLONE-8EFNC1M6XWJ\CLONE-8EFNC1M6XWJ.vmx"

        id                               path
        --                               ----
        LR4UDDNNON7BD3SC1MIG8A2GO03EAR2O D:\Virtual machines\CLONE-WDMEPYTYLTC\CLONE-8EFNC1M6XWJ.vmx
    .NOTES
        The responseclass model:
            VMRrgistrationInformation {
                id (string, optional): Registered VM name id ,
                path (string, optional): Registered VM path
            }
	  Example output:
        {
            "id": "string",
            "path": "string"
        }
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
<#  9 DELETE /vms/{id} Deletes a VM
    Function tested and documented
#>
Function Remove-VMClonedMachine {
<#
    .SYNOPSIS
        Deletes a VM
    .DESCRIPTION
        Deletes a VM
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
    .PARAMETER NewVMCloneName
        Can be anyting
    .PARAMETER NewVMCloneId
        Must be a $VMId retrieved bij Get-VMVirtualMachineList -VirtualMachine *
    .PARAMETER ResponseDetails
         Switch for Responsehandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
    .EXAMPLE
       Get-VMVirtualMachineList -VirtualMachinename *

        id                               path
        --                               ----
        MRJVR0R64RS7GLC7EMG9QRCOB015RNSV D:\Virtual machines\CLONE-1SBAZX9JQCE\CLONE-1SBAZX9JQCE.vmx
        GBILCONH2U9FG18K09KVIKB8FV10I02V D:\Virtual machines\CLONE-BVGMLE27N1H\CLONE-BVGMLE27N1H.vmx


        Remove-VMClonedMachine -VMId MRJVR0R64RS7GLC7EMG9QRCOB015RNSV

        Result:
        The resource has been deleted -

        Get-VMVirtualMachineList -VirtualMachinename *

        id                               path
        --                               ----
        GBILCONH2U9FG18K09KVIKB8FV10I02V D:\Virtual machines\CLONE-BVGMLE27N1H\CLONE-BVGMLE27N1H.vmx
    .NOTES
        The responseclass model:
            none
	  Example output:
        204 when the machine is deleted
    .INPUTS
       System.String
    .OUTPUTS
       Message
#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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
                                Write-Message -Message "Unexpected error: $($RequestResponse.code) : $($_)" -MessageType ERROR
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
<#  10 Returns a list with virtual machines that are templates
    Function tested and documented
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
        $VirtualMachines = Get-VMVirtualMachineList  -VirtualMachineName * -ErrorAction Stop

        ForEach ($VirtualMachine in $VirtualMachines) {
            if (!([string]::IsNullOrEmpty($VirtualMachines.Path))) {
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
        }
        return $VirtualMachineIsTemplate
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR
    }
}
<#
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

    VM Network Adapters Management
        # Fully Tested
        # Fully Documented

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

        # 1 GET /vms/{id}/ip Returns the IP address of a VM
        # 2 GET /vms/{id}/nic Returns all network adapters in the VM
        # 3 GET /vms/{id}/nicips Returns the IP stack configuration of all NICs of a VM
        # 4 PUT /vms/{id}/nic/{index} Updates a network adapter in the VM
        # 5 POST /vms/{id}/nic Creates a network adapter in the VM
        # 6 DELETE /vms/{id}/nic/{index} Deletes a VM network adapter

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#>
<#  1 GET /vms/{id}/ip Returns the IP address of a VM
        Function tested and documented
#>
Function Get-VMIPAddress {
<#
    .SYNOPSIS
        Returns the IP address of a VM
    .DESCRIPTION
        Returns the IP address of a VM
    .PARAMETER VMId
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
        Must be a $VMId retrieved bij Get-VMVirtualMachineList -VirtualMachine *
	.PARAMETER ResponseDetails
		 Switch for Responsehandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
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
    .NOTES
        The responseclass model:
        inline_model_0 {
            ip (string): Guest OS IP address
        }
	  Example output:
        {
            "ip": "string"
        }
    .INPUTS
       System.String
    .OUTPUTS
       system.array
#>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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
<#  2 GET /vms/{id}/nic Returns all network adapters in the VM
        Function tested and documented
#>
Function Get-VMNetworkAdapter {
<#
    .SYNOPSIS
        Returns all network adapters in the VM
    .DESCRIPTION
        RReturns all network adapters in the VM
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
	.PARAMETER ResponseDetails
		 Switch for Responsehandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        $(Get-VMNetworkAdapter-VMId M3HAD21LB73N4GSHGJIC2MDM115A5GJT).nics

        index type    vmnet  macAddress
        ----- ----    -----  ----------
            1 nat     vmnet8 00:0c:29:e5:d9:b9
            2 bridged vmnet0 00:0c:29:e5:d9:e1
            3 custom  vmnet1 00:0c:29:e5:d9:eb
     .EXAMPLE
    Get-VMNetworkAdapter -VMId M3HAD21LB73N4GSHGJIC2MDM115A5GJT

    num nics
    --- ----
    9 {@{index=1; type=custom; vmnet=vmnet8; macAddress=00:0c:29:e5:d9:9b}, @{index=3; type=custom; vmnet=vmnet0; macAdd…
    .NOTES
        The responseclass model:
        NICDevices {
            num (integer): Number of NIC devices integerDefault:1,
            nics (Array[NICDevice]): The network adapter added to this VM
        }
        NICDevice {
            index (integer): Index of Network Adapters integerDefault:1,
            type (string): The network type of network adapter = ['bridged', 'nat', 'hostonly', 'custom']stringEnum:"bridged", "nat", "hostonly", "custom",
            vmnet (string): The vmnet name ,
            macAddress (string): Mac address
        }
	  Example output:
        {
            "num": 1,
            "nics": [
                {
                "index": 1,
                "type": "bridged",
                "vmnet": "string",
                "macAddress": "string"
                }
            ]
        }
    .INPUTS
       System.String
    .OUTPUTS
        system.array
#>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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
<#  3 GET /vms/{id}/nicips Returns the IP stack configuration of all NICs of a VM
        Function tested and documented
#>
Function Get-VMNetAdapterIPStack {
<#
    .SYNOPSIS
        Returns the IP stack configuration of all NICs of a VM
    .DESCRIPTION
        Returns the IP stack configuration of all NICs of a VM
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
	.PARAMETER ResponseDetails
		 Switch for Responsehandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
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
    .NOTES
        The responseclass model:
        NicIpStackAll {
            nics (NicIpStack, optional),
            routes (Array[RouteEntry], optional),
            dns (DnsConfig, optional): Global DNS configuration ,
            wins (WinsConfig, optional): Global WINS configuration ,
            dhcpv4 (DhcpConfig, optional): Global DHCPv4 configuration ,
            dhcpv6 (DhcpConfig, optional): Global DHCPv6 configuration
        }
        NicIpStack {
            mac (string): Mac address, E.g., de:ad:be:ef:12:34 ,
            ip (Array[IPNetAddress], optional): IP address(es) of the interface (CIDR) ,
            dns (DnsConfig, optional): DNS configuration of the interface ,
            wins (WinsConfig, optional): WINS configuration of the interface ,
            dhcp4 (DhcpConfig, optional): DHCPv4 configuration of the interface ,
            dhcp6 (DhcpConfig, optional): DHCPv6 configuration of the interface
        }
        RouteEntry {
            dest (string): IP address ,
            prefix (integer): Number of items integerDefault:0,
            nexthop (string, optional): IP address ,
            interface (integer): Number of items integerDefault:0,
            type (integer): Number of items integerDefault:0,
            metric (integer): Number of items integerDefault:0
        }
        DnsConfig {
            hostname (string, optional),
            domainname (string, optional),
            server (Array[string], optional),
            search (Array[string], optional)
        }
        WinsConfig {
            primary (string),
            secondary (string)
            }DhcpConfig {
            enabled (boolean),
            setting (string)
        }
        IPNetAddress {
            string: IP address in CIDR notation, E.g., 192.168.0.1/24
        }

	  Example output:
        {
        "nics": {
            "mac": "string",
            "ip": [
            "string"
            ],
            "dns": {
            "hostname": "string",
            "domainname": "string",
            "server": [
                "string"
            ],
            "search": [
                "string"
            ]
            },
            "wins": {
            "primary": "string",
            "secondary": "string"
            },
            "dhcp4": {
            "enabled": true,
            "setting": "string"
            },
            "dhcp6": {
            "enabled": true,
            "setting": "string"
            }
        },
        "routes": [
            {
            "dest": "string",
            "prefix": 0,
            "nexthop": "string",
            "interface": 0,
            "type": 0,
            "metric": 0
            }
        ],
        "dns": {
            "hostname": "string",
            "domainname": "string",
            "server": [
            "string"
            ],
            "search": [
            "string"
            ]
        },
        "wins": {
            "primary": "string",
            "secondary": "string"
        },
        "dhcpv4": {
            "enabled": true,
            "setting": "string"
        },
        "dhcpv6": {
            "enabled": true,
            "setting": "string"
        }
    }
    .INPUTS
       System.String
    .OUTPUTS
        system.array
#>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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
<# 4 PUT /vms/{id}/nic/{index} Updates a network adapter in the VM
        Function tested and documented
#>
Function Update-VMNetWorkAdapter {
<#
    .SYNOPSIS
        Updates a network adapter in the VM
    .DESCRIPTION
        Updates a network adapter in the VM
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
    .PARAMETER VMNicIndex
        The Index number of the nic that must be changed.

        $(Get-VMNetworkAdapter -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR).nics

        index type   vmnet  macAddress
        ----- ----   -----  ----------
            1 custom vmnet8 00:0c:29:18:8b:04
            2 custom vmnet8 00:0c:29:18:8b:0e
    .PARAMETER VMNet
        VMNets can be retrieved with the Get-VMVirtualNetworkList command

        $VMNets = $(Get-VMVirtualNetworkList s -ResponseDetails).vmnets
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
    .PARAMETER VMNettype
        Vmware Network Connections Types – Graphical Samples
        NAT – Network Address Translation.
        Vmware Network Connections – Bridged.
        Vmware Network Connections – Host-Only.
        Custom Network.
    .PARAMETER ResponseDetails
         Switch for Responsehandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
     .EXAMPLE
        $ChangeNetAdapter = Update-VMNetWorkAdapter -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR -VMNicIndex 1 -VMNet vmnet8 -VMNettype custom -ResponseDetails

        $ChangeNetAdapter

        index type   vmnet  macAddress
        ----- ----   -----  ----------
            1 custom vmnet8 00:0c:29:18:8b:04
    .NOTES
        The responseclass model:
        NICDevice {
            index (integer): Index of Network Adapters integerDefault:1,
            type (string): The network type of network adapter = ['bridged', 'nat', 'hostonly', 'custom']stringEnum:"bridged", "nat", "hostonly", "custom",
            vmnet (string): The vmnet name ,
            macAddress (string): Mac address
        }
	  Example output:
        {
            "index": 1,
            "type": "bridged",
            "vmnet": "string",
            "macAddress": "string"
        }
    .INPUTS
       System.String
       Sytem.int
    .OUTPUTS
        system.array
#>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
        [string]$VMId,
		[Parameter(Mandatory)]
        [ValidatePattern ('^[0-9]', errormessage = "{0}, The Virtual machines nic index can contain [0-9]")]
        [int]$VMNicIndex,
        [Parameter(Mandatory)]
        [ValidateScript({$_ -cmatch 'vmnet([1]?\d|20)$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits and between 1 and 20")]
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
<#  5 POST /vms/{id}/nic Creates a network adapter in the VM
    Function tested and documented
#>
Function Add-VMNetAdapter {
<#
    .SYNOPSIS
        Creates a network adapter in the VM
    .DESCRIPTION
        Creates a network adapter in the VM
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
    .PARAMETER VMNet
        A Virtual network name like vmnet8
        a Virtual Network name is a network used interally in vmware workstation. Under Edit > Virtual network editor you can find more information
        VMNets can be retrieved with the Get-VMVirtualNetworkList command

        $VMNets = $(Get-VMVirtualNetworkList s -ResponseDetails).vmnets
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

    .PARAMETER VMNettype
        Vmware Network Connections Types – Graphical Samples
        NAT – Network Address Translation.
        Vmware Network Connections – Bridged.
        Vmware Network Connections – Host-Only.
        Custom Network.
    .PARAMETER ResponseDetails
         Switch for Responsehandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
     .EXAMPLE
        $AddNetAdapter = Add-VMNetAdapter -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR -VMNet vmnet8 -VMNettype custom -ResponseDetails
        $AddNetAdapter

        index type   vmnet  macAddress
        ----- ----   -----  ----------
            2 custom vmnet8
    .NOTES
        The responseclass model:
        NICDevice {
            index (integer): Index of Network Adapters integerDefault:1,
            type (string): The network type of network adapter = ['bridged', 'nat', 'hostonly', 'custom']stringEnum:"bridged", "nat", "hostonly", "custom",
            vmnet (string): The vmnet name ,
            macAddress (string): Mac address
        }
	  Example output:
        {
            "index": 1,
            "type": "bridged",
            "vmnet": "string",
            "macAddress": "string"
        }
#>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
        [string]$VMId,
        [Parameter(Mandatory)]
        [ValidateScript({$_ -cmatch 'vmnet([1]?\d|20)$'},ErrorMessage = "{0} must be lowercase like: vmnet with max 2 digits and between 1 and 20")]
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
<#  6 DELETE /vms/{id}/nic/{index} Deletes a VM network adapter
    Function tested and documented
#>
Function Remove-VMNetAdapter {
<#
    .SYNOPSIS
        Deletes a VM network adapter
    .DESCRIPTION
        Deletes a VM network adapter
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
    .PARAMETER VMNicIndex
        The Index number of the nic that must be deleted

        $(Get-VMNetworkAdapter -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR).nics

        index type   vmnet  macAddress
        ----- ----   -----  ----------
            1 custom vmnet8 00:0c:29:18:8b:04
            2 custom vmnet8 00:0c:29:18:8b:0e
    .PARAMETER ResponseDetails
         Switch for Responsehandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.

    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
     .EXAMPLE
        $DeleteNetAdapter = Remove-VMNetAdapter -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR -VMNicIndex 2 -ResponseDetails
        $DeleteNetAdapter

        Code Message
        ---- -------
        204  Networkadapter with nicindex 2 has been deleted
    .NOTES
        The responseclass model:
            none
	  Example output:
            204
    .INPUTS
       System.String
       Sytem.int
    .OUTPUTS
        system.array
#>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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
                                Write-Message -Message "Unexpected error: $($RequestResponse.code) : $($_)" -MessageType ERROR
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
<#
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

    VM Power Management
        # Fully Tested
        # Fully Documented

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

        # 1 /vms/{id}/power Returns the power state of the VM
        # 2 /vms/{id}/power Changes the VM power state

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------#>
<#  1 /vms/{id}/power Returns the power state of the VM
    Function tested and documented
#>
Function Get-VMPowerStatus {
<#
    .SYNOPSIS
       Returns the power state of the VM
    .DESCRIPTION
        Returns the power state of the VM
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
     .EXAMPLE
        $GetVMPowerstatus = Get-VMPowerStatus -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR
        $GetVMPowerstatus

        power_state
        -----------
        poweredOn
    .NOTES
        The responseclass model:
            VMPowerState {
                power_state (string) = ['poweredOn', 'poweredOff', 'paused', 'suspended']stringEnum:"poweredOn", "poweredOff", "paused", "suspended"
            }
	  Example output:
        {
            "power_state": "poweredOn"
        }
#>
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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
<#  2 /vms/{id}/power Changes the VM power state
    Function tested and documented
#>
Function Set-VMPowerStatus {
<#
    .SYNOPSIS
        Changes the VM power state
    .DESCRIPTION
        Changes the VM power state
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
    .PARAMETER PowerMode
        can be 'on', 'off', 'shutdown', 'suspend','pause','unpause'
	.PARAMETER ResponseDetails
		 Switch for Responsehandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
     .EXAMPLE
        $VMSetPowerstatus = Set-VMPowerStatus -VMId RLCM43SOALUGU2DSG3RH5LJR48IM53OR -PowerMode on
        $VMSetPowerstatus

        power_state
        -----------
        poweredOn
    .NOTES
        The responseclass model:
            VMPowerState {
                power_state (string) = ['poweredOn', 'poweredOff', 'paused', 'suspended']stringEnum:"poweredOn", "poweredOff", "paused", "suspended"
            }
	  Example output:
        {
            "power_state": "poweredOn"
        }
#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
        [string]$VMId,
        [ValidateSet('on', 'off', 'shutdown', 'suspend','pause','unpause', errormessage = "{0}, Value must be: on, off, shutdown, suspend,pause, unpause")]
        [string]$PowerMode
    )
    if($PSCmdlet.ShouldProcess($VMNicIndex,"Changing the Virtuals machine powerstatus on $($VMId) to $($PowerMode) ")){
        CheckForVMRestToRun
        CheckVMWareProcess

        if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            if ($(Get-Process -Name  vmware -ErrorAction SilentlyContinue)) {
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
<#
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

    VM Shared Folders Management
        # Fully Documented
        # Fully Tested
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

        # 1 GET /vms/{id}/sharedfolders Returns all shared folders mounted in the VM
        # 2 PUT /vms/{id}/sharedfolders/{folder id} Updates a shared folder mounted in the VM
        # 3 POST /vms/{id}/sharedfolders Mounts a new shared folder in the VM
        # 4 DELETE /vms/{id}/sharedfolders/{folder id} Deletes a shared folder

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#>
<#  1 GET /vms/{id}/sharedfolders Returns all shared folders mounted in the VM
    Function tested and documented
#>
Function Get-VMSharedFolder {
<#
    .SYNOPSIS
        Returns all shared folders mounted in the VM
    .DESCRIPTION
        Returns all shared folders mounted in the VM
	.PARAMETER ResponseDetails
		 Switch for Responsehandling. that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .EXAMPLE
        Get-VMSharedFolder -VMId PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ

        folder_id  host_path             flags
        ---------  ---------             -----
        VMShare    D:\Virtual machines\     4
        VMShares   D:\Virtual machines\     0
        VMShares12 D:\Virtual machines\     0
        VMShares13 D:\Virtual machines\     0
    .NOTES
        The responseclass model:
            SharedFolders [
                SharedFolder
            ]
            SharedFolder {
                folder_id (string): ID of folder which be mounted to the host ,
                host_path (string): Path of the host shared folder ,
                flags (integer): The flags property specifies how the folder will be accessed by the VM. There is only one flag supported which is "4" and means read/write access.
            }
	  Example output:
        [
            {
                "folder_id": "string",
                "host_path": "string",
                "flags": 0
            }
        ]
    .INPUTS
        System.String
    .OUTPUTS
        System.String
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9*]{1,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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
<#  2 PUT /vms/{id}/sharedfolders/{folder id} Updates a shared folder mounted in the VM
    Function tested and documented
#>
Function Update-VMSharedFolder {
<#
    .SYNOPSIS
        Updates a shared folder mounnted in the VM
    .DESCRIPTION
        Updates a shared folder mounnted in the VM
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
    .PARAMETER SharedFolderName
        the name of the share, must be a valid sharename that is already provided to the Virtual Machine
    .PARAMETER host_path
        a valid directory PATH
    .PARAMETER flags
        4 = read/write
        0 = ReadOnly
    .PARAMETER ResponseDetails
         Switch for Responsehandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
    .EXAMPLE
        Update-VMSharedFolder -VMId PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ -host_path 'D:\Virtual machines\' -SharedFolderName "VMShare" -flags 4
        for read/write with flag 4
    .EXAMPLE
        Update-VMSharedFolder -VMId PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ -host_path 'D:\Virtual machines\' -SharedFolderName "VMShare" -flags 0
        for readonly with flag 0
    .NOTES
        The responseclass model:
            SharedFolders [
                SharedFolder
            ]
            SharedFolder {
                folder_id (string): ID of folder which be mounted to the host ,
                host_path (string): Path of the host shared folder ,
                flags (integer): The flags property specifies how the folder will be accessed by the VM. There is only one flag supported which is "4" and means read/write access.
            }
	  Example output:
            [
                {
                    "folder_id": "string",
                    "host_path": "string",
                    "flags": 0
                }
            ]
    .INPUTS
        System.String
        System.int
    .OUTPUTS
        System.String
        System.array
#>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
        [ValidatePattern ('^[*][A-Za-z0-9]{1,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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
<#   3 POST /vms/{id}/sharedfolders Mounts a new shared folder in the VM
        Function tested and documented
#>
Function Add-VMSharedFolder {
 <#
    .SYNOPSIS
       Mounts a new shared folder in the VM
    .DESCRIPTION
        Mounts a new shared folder in the VM
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
    .PARAMETER SharedFolderName
        the name of the share, and can be anything
    .PARAMETER host_path
        a valid directory PATH
    .PARAMETER flags
        4 = read/write
        0 = ReadOnly
    .PARAMETER ResponseDetails
         Switch for Responsehandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.

    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
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
    .NOTES
        The responseclass model:
            SharedFolders [
                SharedFolder
            ]
            SharedFolder {
                folder_id (string): ID of folder which be mounted to the host ,
                host_path (string): Path of the host shared folder ,
                flags (integer): The flags property specifies how the folder will be accessed by the VM. There is only one flag supported which is "4" and means read/write access.
            }
	  Example output:
            [
                {
                    "folder_id": "string",
                    "host_path": "string",
                    "flags": 0
                }
            ]
    .INPUTS
        System.String
        sYSTEM.int
    .OUTPUTS
        System.String
        System.array
#>
    [CmdletBinding(SupportsShouldProcess)]
    param
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{1,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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

<#  4 DELETE /vms/{id}/sharedfolders/{folder id} Deletes a shared folder
        Function tested and documented
#>
Function Remove-VMSharedFolder {
 <#
    .SYNOPSIS
       Deletes a shared folder mounted in a vm
    .DESCRIPTION
        Deletes a shared folder mounted in a vm
    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID
        Must be 32 characters long and the id can be rerieved with :  Get-VMVirtualMachineList -VirtualMachinename *
    .PARAMETER SharedFolderName
        the name of the share, and can be anything
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
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
     .NOTES
        The responseclass model:
            none
	  Example output:
            204
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
		[ValidatePattern ('^[A-Za-z0-9]{1,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long. Use Get-VMVirtualMachineList  to retrieve the VMId's ")]
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
                                Write-Message -Message "Unexpected error: $($RequestResponse.code) : $($_))" -MessageType ERROR
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
<#
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

    VMRUN Virtual Machine Management
        # Fully Tested
        # Fully Documented

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

        # 1 Get-VMSnapshot      - Get a list of snapshots for a specified virtual machine ( with tree mode )
        # 2 New-VMSnapshot      - Creates a snapshot on the specified virtual machine
        # 3 Remove-VMSnapshot   - Remove a snapshot from a VM ( with andDeleteChildren option )
        # 4 Undo-VMSnapshot     - Reverts the virtual machine to the current snapshot

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
#>

<#vmrun listSnapshots "D:\Virtual machines\Template_Windows2016DataCenter\Template_Windows2016DataCenter.vmx"#>
Function Get-VMSnapshot {
 <#
    .SYNOPSIS
       returns snapshots on a virtual machine
    .DESCRIPTION
        returns snapshots on a virtual machine
    .PARAMETER host_path
        Must be a valid path to a VMX file
    .PARAMETER ShowTree
        Shows the Snapshots in tree format
        For example there are 3 snapshots on machine
            1:  CreateVM
                2:  NewSnapShot
                    3: SnapForTest
    .EXAMPLE
        $VMXPath = $(Get-VMVirtualMachineList -VirtualMachineName 649TJ74BEAHCM93M56DM79CD21562M8D).path
        $VMXPath
            D:\Virtual machines\Template_PackageMachine\Template_PackageMachine.vmx

        Get-VMSnapshot -host_path $VMXPath

        Name                    Id                               Path                                                                     Snapshot
        ----                    --                               ----                                                                     --------
        Template_PackageMachine 649TJ74BEAHCM93M56DM79CD21562M8D D:\Virtual machines\Template_PackageMachine\Template_PackageMachine.vmx  CleanVM
        Template_PackageMachine 649TJ74BEAHCM93M56DM79CD21562M8D D:\Virtual machines\Template_PackageMachine\Template_PackageMachine.vmx  test1
        Template_PackageMachine 649TJ74BEAHCM93M56DM79CD21562M8D D:\Virtual machines\Template_PackageMachine\Template_PackageMachine.vmx  test2
    .EXAMPLE
        $VMXPath = $(Get-VMVirtualMachineList -VirtualMachineName 649TJ74BEAHCM93M56DM79CD21562M8D).path

        $VMXPath
        D:\Virtual machines\Template_PackageMachine\Template_PackageMachine.vmx

        Get-VMSnapshot -host_path $VMXPath

        Code Message
        ---- -------
        105  The Virtual machine has no snapshots

     .NOTES
        The responseclass model:
            none
	  Example output:
            204
    .INPUTS
        System.String
    .OUTPUTS
        System.String
        System.array
#>
    [CmdletBinding()]
    param
    (
        [ValidateScript({
            if(-Not ($_ | Test-Path) ){
                return $false
            }
            else {
                return $true
            }
        }, errormessage = "{0}, is a non-existing path ")]
        [System.IO.FileInfo]$host_path,
        [switch]$ShowTree
    )

    try {
        $TempFile = $(New-TemporaryFile).FullName

        Start-Process -FilePath $(Join-Path -Path $VMwareWorkstationConfigParameters.InstallLocation -ChildPath "vmrun.exe") -ArgumentList "listSnapshots `"$($host_path.FullName)`"" -Wait -RedirectStandardOutput $TempFile -NoNewWindow -ErrorAction Stop

        if (((Get-Item $host_path) -is [System.IO.FileInfo]) -and ($host_path.Extension -eq ".vmx")) {
            $GetTempFileContent = Get-Content $TempFile -ErrorAction SilentlyContinue | Select-Object -Skip 1
            if ($null -ne $GetTempFileContent) {
                $VMwareWorkstationRecievedSnapshots = @()
                $GetHostPathToVMXFile = Get-Content $host_path.FullName -ErrorAction Stop | ConvertFrom-StringData
                if ($null -ne $GetHostPathToVMXFile) {
                    $GetVirtualMachineName = Get-VMVirtualMachineList -VirtualMachineName $($GetHostPathToVMXFile.displayname -replace "`"",[string]::Empty)
                    if ($null -ne $GetVirtualMachineName ) {
                        if (!($showtree)) {
                            foreach ($Line in $GetTempFileContent) {
                                $obj = New-Object -TypeName PSObject
                                $obj | Add-Member -MemberType NoteProperty -Name Name -Value $($GetHostPathToVMXFile.displayname -replace "`"",[string]::Empty)
                                $obj | Add-Member -MemberType NoteProperty -Name Id -Value $GetVirtualMachineName.id
                                $obj | Add-Member -MemberType NoteProperty -Name Path -Value $GetVirtualMachineName.path
                                $obj | Add-Member -MemberType NoteProperty -Name Snapshot -Value $line
                                $VMwareWorkstationRecievedSnapshots += $obj
                            }
                        }
                        else {
                            $obj = New-Object -TypeName PSObject
                            $obj | Add-Member -MemberType NoteProperty -Name Name -Value $($GetHostPathToVMXFile.displayname -replace "`"",[string]::Empty)
                            $obj | Add-Member -MemberType NoteProperty -Name Id -Value $GetVirtualMachineName.id
                            $obj | Add-Member -MemberType NoteProperty -Name Path -Value $GetVirtualMachineName.path
                            $obj | Add-Member -MemberType NoteProperty -Name Snapshot -Value $GetTempFileContent
                            $VMwareWorkstationRecievedSnapshots += $obj
                        }
                    }
                    else {
                        $ErrorMessage = "Couln't retreive the virtual machines name"
                    }
                }
                else {
                    $ErrorMessage = "Couldn't open the Content of $($host_path)"
                }
            }
            else {
                $ErrorMessage = "The Virtual machine has no snapshots"
            }
        }
        else {
            $ErrorMessage = "The provided file $($host_path) isn't containing a VMX file"
        }
        Stop-Process -Name VMRUN -ErrorAction SilentlyContinue
        Remove-Item -Path $TempFile -Force -ErrorAction SilentlyContinue
        if ($null -ne $ErrorMessage) {
            $obj = New-Object -TypeName PSObject
            $obj | Add-Member -MemberType NoteProperty -Name Code -Value "105"
            $obj | Add-Member -MemberType NoteProperty -Name Message -Value $ErrorMessage
            $VMwareWorkstationRecievedSnapshots += $obj
        }
        return $VMwareWorkstationRecievedSnapshots
    }
    catch {
        Write-Message -Message "[ Get-VMSnapshot ] - $($_)" -MessageType ERROR
    }
}
#vmrun createsnapshot "D:\virtual machines\Template_Windows2016DataCenter\Template_Windows2016DataCenter.vmx" "NAME"
Function New-VMSnapshot {
 <#
    .SYNOPSIS
       Create a snapshot on a virtual machine
    .DESCRIPTION
        rCreate a snapshot on a virtual machine
    .PARAMETER host_path
        Must be a valid path to a VMX file
    .PARAMETER SnapShotName
        the name of the snapshot, and can be anything
    .PARAMETER ResponseDetails
         Switch for Responsehandling that shows extra information when a error occcured or extra information is send back from the VMware Workstation Rest API
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
    .EXAMPLE
        $VMXPath = $(Get-VMVirtualMachineList -VirtualMachineName 649TJ74BEAHCM93M56DM79CD21562M8D).path
        $VMXPath
            D:\Virtual machines\Template_PackageMachine\Template_PackageMachine.vmx

        New-VMSnapshot -host_path $VMXPath -SnapShotName "9 april 2023"

        Get-VMSnapshot -host_path $VMXPath

        Name                        Id                               Path                                                                       Snapshot
        ----                        --                               ----                                                                       --------
        Template_PackageMachine     7J6LMKNTS5152016VBEQ0PFTIQHDULUP D:\virtual machines\Template_PackageMachine\Template_PackageMachine.vmx    testsnapshot
        Template_PackageMachine     7J6LMKNTS5152016VBEQ0PFTIQHDULUP D:\virtual machines\Template_PackageMachine\Template_PackageMachine.vmx    9 april 2023
     .NOTES
        The responseclass model:
            none
	  Example output:
            204
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
        [ValidateScript({
            if(-Not ($_ | Test-Path) ){
                return $false
            }
            else {
                return $true
            }
        }, errormessage = "{0}, is a non-existing path ")]
        [System.IO.FileInfo]$host_path,
        [string]$SnapShotName
    )

    try {
        if($PSCmdlet.ShouldProcess("","Creates a new Snapshot for Virtual machine $($host_path) with snapshot name: $($SnapShotName) ")){

            if (((Get-Item $host_path) -is [System.IO.FileInfo]) -and ($host_path.Extension -eq ".vmx")) {
                $GetHostPathToVMXFile = Get-Content $host_path.FullName -ErrorAction SilentlyContinue | ConvertFrom-StringData
                if ($null -ne $GetHostPathToVMXFile) {
                    $GetVirtualMachineName = Get-VMVirtualMachineList -VirtualMachineName $($GetHostPathToVMXFile.displayname -replace "`"",[string]::Empty)
                    if ($null -ne $GetVirtualMachineName ) {

                        $VMwareWorkstationCreateSnapshot = @()
                        $Tempfile = $(New-TemporaryFile).FullName

                        Start-Process -FilePath $(Join-Path -Path $VMwareWorkstationConfigParameters.InstallLocation -ChildPath "vmrun.exe") -ArgumentList "snapshot `"$($host_path.FullName)`" `"$($SnapShotName)`"" -Wait -NoNewWindow -RedirectStandardOutput $TempFile -ErrorAction Stop
                        $resultCreateSnapshot = Get-Content -Path $Tempfile -ErrorAction SilentlyContinue

                        if ($null -eq $resultCreateSnapshot) {

                            $CheckForCreation = $(Get-VMSnapshot -host_path $host_path -ShowTree).snapshot

                            if ($null -ne $CheckForCreation) {
                                foreach ($Snapshot in $CheckForCreation) {
                                    if ($Snapshot -eq $SnapShotName) {
                                        $obj = New-Object -TypeName PSObject
                                        $obj | Add-Member -MemberType NoteProperty -Name Code -Value "204"
                                        $obj | Add-Member -MemberType NoteProperty -Name Message -Value "Snapshot with name $($SnapShotName) created on $($GetVirtualMachineName.path)"
                                        $VMwareWorkstationCreatesnapshot += $obj
                                    }
                                }
                            }
                            else {
                                $ErrorMessage = "Could not find the Snapshot with name $($SnapShotName) on $($GetVirtualMachineName.path)"
                            }
                        }
                        else {
                                $ErrorMessage = "$($resultCreateSnapshot). Snapshot $($SnapShotName) already exists on $($GetVirtualMachineName.path)"
                        }
                    }
                    else {
                        $ErrorMessage = "Couln't retreive the virtual machines name"
                    }
                }
                else{
                    $ErrorMessage = "Couldn't open the content of $($host_path)"
                }
            }
            else {
                $ErrorMessage = "The provided file $($host_path) isn't containing a VMX file"
            }
        }
        Remove-Item -Path $Tempfile -Force -ErrorAction SilentlyContinue
        if ($null -ne $ErrorMessage) {
            $obj = New-Object -TypeName PSObject
            $obj | Add-Member -MemberType NoteProperty -Name Code -Value "105"
            $obj | Add-Member -MemberType NoteProperty -Name Message -Value $ErrorMessage
            $VMwareWorkstationCreatesnapshot += $obj
        }
        return $VMwareWorkstationCreatesnapshot
    }
    catch {
        Write-Message -Message "[ New-VMSnapshot ] - $($_)" -MessageType ERROR
    }
}
<# vmrun deleteSnapshot "D:\virtual machines\Template_Windows2016DataCenter\Template_Windows2016DataCenter.vmx" "NAME"#>
Function Remove-VMSnapshot {
<#
    .SYNOPSIS
       Remove a snapshot from a VM and/or its children
    .DESCRIPTION
        Remove a snapshot from a VM and/or its children
    .PARAMETER host_path
        Must be a valid path to a VMX file
    .PARAMETER SnapShotName
        the name of the snapshot, and can be anything
    .PARAMETER AndDeleteChildren
        Removes the underlaying snapshots in the row
        Get-VMSnapshot -host_path "D:\Virtual machines\test\test.vmx"

        Name    Id                               Path                                     Snapshot
        ----    --                               ----                                     --------
        test    7J6LMKNTS5152016VBEQ0PFTIQHDULUP D:\Virtual machines\test\test.vmx       1
        test    7J6LMKNTS5152016VBEQ0PFTIQHDULUP D:\Virtual machines\test\test.vmx       2
        test    7J6LMKNTS5152016VBEQ0PFTIQHDULUP D:\Virtual machines\test\test.vmx       3

        Remove-VMSnapshot -host_path "D:\Virtual machines\test\test.vmx" -SnapShotName "2" -AndDeleteChildren

        Get-VMSnapshot -host_path "D:\Virtual machines\test\test.vmx"

        Name    Id                               Path                                     Snapshot
        ----    --                               ----                                     --------
        test    7J6LMKNTS5152016VBEQ0PFTIQHDULUP D:\Virtual machines\test\test.vmx       1
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
     .NOTES
        The responseclass model:
            none
	  Example output:
            204
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
        [ValidateScript({
            if(-Not ($_ | Test-Path) ){
                return $false
            }
            else {
                return $true
            }
        }, errormessage = "{0}, is a non-existing path ")]
        [System.IO.FileInfo]$host_path,
        [string]$SnapShotName,
        [switch]$AndDeleteChildren
    )
    try {
        if($PSCmdlet.ShouldProcess("","Remove a snapshot from a VM. Virtual machine path: $($host_path), snapshotname: $($SnapShotName) ( with additional andDeleteChildren option ) ")){
            if (((Get-Item $host_path) -is [System.IO.FileInfo]) -and ($host_path.Extension -eq ".vmx")) {
                $GetHostPathToVMXFile = Get-Content $host_path.FullName -ErrorAction SilentlyContinue | ConvertFrom-StringData
                if ($null -ne $GetHostPathToVMXFile) {
                    $GetVirtualMachineName = Get-VMVirtualMachineList -VirtualMachineName $($GetHostPathToVMXFile.displayname -replace "`"",[string]::Empty)
                    if ($null -ne $GetVirtualMachineName ) {

                        $VMwareWorkstationRemoveSnapshot = @()
                        $Tempfile = $(New-TemporaryFile).FullName

                        if ($AndDeleteChildren) {
                            Start-Process -FilePath $(Join-Path -Path $VMwareWorkstationConfigParameters.InstallLocation -ChildPath "vmrun.exe") -ArgumentList "deleteSnapshot `"$($host_path.FullName)`" `"$($SnapShotName)`" andDeleteChildren" -Wait -NoNewWindow -RedirectStandardOutput $TempFile -ErrorAction Stop
                            $resultRemoveSnapshot = Get-Content -Path $Tempfile -ErrorAction SilentlyContinue
                        }
                        else {
                            Start-Process -FilePath $(Join-Path -Path $VMwareWorkstationConfigParameters.InstallLocation -ChildPath "vmrun.exe") -ArgumentList "deleteSnapshot `"$($host_path.FullName)`" `"$($SnapShotName)`"" -Wait -NoNewWindow -RedirectStandardOutput $TempFile -ErrorAction Stop
                            $resultRemoveSnapshot = Get-Content -Path $Tempfile -ErrorAction SilentlyContinue
                        }

                        if ($null -ne $resultRemoveSnapshot) {
                            $ErrorMessage = "$($resultRemoveSnapshot)"
                        }
                        else {
                            if ($AndDeleteChildren) {
                                $ErrorMessage = "Snapshot with name $($SnapShotName) and its children has been deleted $($resultRemoveSnapshot)"
                            }
                            else {
                                $ErrorMessage = "Snapshot with name $($SnapShotName) has been deleted"
                            }
                        }
                    }
                    else {
                        $ErrorMessage = "Couln't retreive the virtual machines name"
                    }
                }
                else{
                    $ErrorMessage = "Couldn't open the content of $($host_path)"
                }

            }
            else {
                $ErrorMessage = "The provided file $($host_path) isn't containing a VMX file"
            }
        }
        Remove-Item -Path $Tempfile -Force -ErrorAction SilentlyContinue
        if ($null -ne $ErrorMessage) {
            $obj = New-Object -TypeName PSObject
            $obj | Add-Member -MemberType NoteProperty -Name Code -Value "105"
            $obj | Add-Member -MemberType NoteProperty -Name Message -Value $ErrorMessage
            $VMwareWorkstationRemoveSnapshot += $obj
        }
        return $VMwareWorkstationRemoveSnapshot
    }
    catch {
        Write-Message -Message "[ Remove-VMSnapshot ] - $($_)" -MessageType ERROR
    }
}

Function Undo-VMRevertSnapshot {
<#
    .SYNOPSIS
       Reverts the virtual machine to the current snapshot
    .DESCRIPTION
        Reverts the virtual machine to the current snapshot
    .PARAMETER host_path
        Must be a valid path to a VMX file
    .PARAMETER SnapShotName
        the name of the snapshot, and can be anything
    .PARAMETER Whatif
        When a command supports the -WhatIf parameter, it allows you to see what the command would have done instead of making changes.
        it's a good way to test out the impact of a command, especially before you do something destructive.
    .PARAMETER Confirm
        Commands that support -WhatIf also support -Confirm. This gives you a chance confirm an action before performing it.
    .EXAMPLE
        Get-VMSnapshot -host_path "D:\Virtual machines\test\test.vmx"

        Name    Id                               Path                                     Snapshot
        ----    --                               ----                                     --------
        test    7J6LMKNTS5152016VBEQ0PFTIQHDULUP D:\Virtual machines\test\test.vmx       1
        test    7J6LMKNTS5152016VBEQ0PFTIQHDULUP D:\Virtual machines\test\test.vmx       2
        test    7J6LMKNTS5152016VBEQ0PFTIQHDULUP D:\Virtual machines\test\test.vmx       3

        Undo-VMRevertSnapshot -host_path "D:\Virtual machines\test\test.vmx" -SnapShotName "2"
       Code Message
        ---- -------
        105  Virtual Machine with name "D:\Virtual machines\test\test.vmx" has been reverted to 2 state
     .NOTES
        The responseclass model:
            none
	  Example output:
            204
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
        [ValidateScript({
            if(-Not ($_ | Test-Path) ){
                return $false
            }
            else {
                return $true
            }
        }, errormessage = "{0}, is a non-existing path ")]
        [System.IO.FileInfo]$host_path,
        [string]$SnapShotName
    )
    try {
        if($PSCmdlet.ShouldProcess("","Reverts Virtual machine $($host_path) and to state: $($SnapShotName)")){
            if (((Get-Item $host_path) -is [System.IO.FileInfo]) -and ($host_path.Extension -eq ".vmx")) {

                $GetHostPathToVMXFile = Get-Content $host_path.FullName -ErrorAction SilentlyContinue | ConvertFrom-StringData

                if ($null -ne $GetHostPathToVMXFile) {
                    $GetVirtualMachineName = Get-VMVirtualMachineList -VirtualMachineName $($GetHostPathToVMXFile.displayname -replace "`"",[string]::Empty)
                    if ($null -ne $GetVirtualMachineName ) {

                        $VMwareWorkstationRemoveSnapshot = @()
                        $Tempfile = $(New-TemporaryFile).FullName

                            Start-Process -FilePath $(Join-Path -Path $VMwareWorkstationConfigParameters.InstallLocation -ChildPath "vmrun.exe") -ArgumentList "revertToSnapshot `"$($host_path.FullName)`" `"$($SnapShotName)`"" -Wait -NoNewWindow -RedirectStandardOutput $TempFile -ErrorAction Stop

                        if ($null -ne $resultReversnapshot) {
                            $ErrorMessage = "$($resultReversnapshot)"
                        }
                        else {
                            $ErrorMessage = "Virtual Machine with name $($GetVirtualMachineName.path) has been reverted to $($SnapShotName) state"
                        }
                    }
                    else {
                        $ErrorMessage = "Couln't retreive the virtual machines name"
                    }
                }
                else{
                    $ErrorMessage = "Couldn't open the content of $($host_path)"
                }

            }
            else {
                $ErrorMessage = "The provided file $($host_path) isn't containing a VMX file"
            }
        }
        Remove-Item -Path $Tempfile -Force -ErrorAction SilentlyContinue
        if ($null -ne $ErrorMessage) {
            $obj = New-Object -TypeName PSObject
            $obj | Add-Member -MemberType NoteProperty -Name Code -Value "105"
            $obj | Add-Member -MemberType NoteProperty -Name Message -Value $ErrorMessage
            $VMwareWorkstationRemoveSnapshot += $obj
        }
        return $VMwareWorkstationRemoveSnapshot
        }
    catch {
        Write-Message -Message "[ Undo-VMRevertSnapshot ] - $($_)" -MessageType ERROR
    }
}

#Loader: For when the module is addressed during loading
if ((!(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
    Write-Message -Message "Some Functions can only be used with a priviliged account. These functions are: Set-VMPortForwarding, Set-VMMacToIpBinding, New-VMVirtualNetwork and Remove-VMPortForwarding" -MessageType INFORMATION
}

$Path = "$([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile))\Settings-$($([System.Security.Principal.WindowsIdentity]::GetCurrent().Name).replace("\","-")).xml"
if (!(Test-Path -Path $Path)) {
    Write-Message -Message "VMWare Workstation API - Configuration not found, to load the configuration, use the: Get-VMWareWorkstationConfiguration command" -MessageType INFORMATION
}
else {
    CheckVMWareProcess
    Get-VMWareWorkstationConfiguration
}