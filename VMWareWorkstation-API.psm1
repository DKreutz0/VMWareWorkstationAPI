#Requires -RunAsAdministrator
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
        Preconfig { 
            Write-Host "TEST"
        }
        ConfigCredentialsCheck {
            if (($VMwareWorkstationConfigParameters.HostAddress) -and ($VMwareWorkstationConfigParameters.port) -and ($VMwareWorkstationConfigParameters.Password)) {
                 $URL = "http://$($VMwareWorkstationConfigParameters.HostAddress):$($VMwareWorkstationConfigParameters.port)/api/vms"  
                 [void]::(Invoke-VMWareRestRequest -Method GET -Uri $URL)
            }
            else {

                Write-Message -Message "Hostadress and password are not define, cant proceed" -MessageType ERROR
                break
            }
        }
    }
}
# Sets the API username and password
Function VMWare_SetPassword {

    Write-Message -Message "Invalid Credentials please set your credentials." -MessageType WARNING
    if ([void]::(Get-Process -Name vmrest -ErrorAction SilentlyContinue)) {
            [void]::(Stop-Process -Name vmrest -Force)
    }
    else {
        write-host ""
        [void]::(Start-Process -FilePath $(Join-Path -Path $VMwareWorkstationConfigParameters.InstallLocation -ChildPath "vmrest.exe") -ArgumentList "-C" -Wait -PassThru -NoNewWindow)
        $Global:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "Password" -Value $(Get-Credential -UserName $VMwareWorkstationConfigParameters.username -message "Provide the vmrest credentials You typed in the other screen").password -Force -ErrorAction Stop
    }
        VMWare_ExportSettings
        VMWare_ImportSettings
}
# Import xml to $VMwareWorkstationConfigParameters
Function VMWare_ImportSettings {
    $VMWareImportSettings = "$PSScriptRoot\Settings-$($([System.Security.Principal.WindowsIdentity]::GetCurrent().Name).replace("\","-")).xml"

    try {
        Remove-Variable -Name VMwareWorkstationConfigParameters -ErrorAction SilentlyContinue
        if (Test-Path -Path $VMWareImportSettings -ErrorAction Stop) {
            $GLOBAL:VMwareWorkstationConfigParameters = Import-Clixml -Path $VMWareImportSettings -ErrorAction Stop
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
    $VMwareWorkstationConfigParameters | Export-Clixml -Path "$PSScriptRoot\Settings-$($([System.Security.Principal.WindowsIdentity]::GetCurrent().Name).replace("\","-")).xml" -Force
}
# Gather Configuration needed to run script module
Function VMWare_RetrieveSettings {
    if (Get-Member -InputObject $VMwareWorkstationConfigParameters -Name installlocation -ErrorAction SilentlyContinue) {
        Remove-Variable VMwareWorkstationConfigParameters -ErrorAction SilentlyContinue
    }

    if (Test-Path -Path "$PSScriptRoot\Settings-$($([System.Security.Principal.WindowsIdentity]::GetCurrent().Name).replace("\","-")).xml") {
        Remove-Item -Path "$PSScriptRoot\Settings-$($([System.Security.Principal.WindowsIdentity]::GetCurrent().Name).replace("\","-")).xml" -Force -ErrorAction SilentlyContinue
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
                                2 { $RetryRetrieveFolderError = $true | Write-Error -Exception "Path Not found" -ErrorAction Stop }
                            }
                        }
                    }
                    FileInfo {
                        $RetryRetrieveFolderError = $true
                        $Global:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "InstallLocation" -Value $(Join-Path $FolderBrowserDialogPath.Directory -ChildPath "\") -Force -ErrorAction Stop
                        $Global:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "Name" -Value "VMware Workstation" -Force -ErrorAction Stop
                        $Global:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "Version" -Value "$([System.Diagnostics.FileVersionInfo]::GetVersionInfo($FolderBrowserDialogPath.FullName) | Select-Object -ExpandProperty FileVersion)" -Force
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
                           $Global:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "Name" -Value "VMware Workstation" -Force -ErrorAction Stop
                           $Global:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "Version" -Value "$([System.Diagnostics.FileVersionInfo]::GetVersionInfo($Collected.fullname) | Select-Object -ExpandProperty FileVersion)" -Force
                           $Global:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "InstallLocation" -Value $Collected.DirectoryName -Force -ErrorAction Stop
                    }

                    if ($Collected.count -gt 1) {
                        do {
                            $SelectedPath = $Collected | Select-Object Name,fullname,DirectoryName | Out-GridView -Title "Multiple VMWare Workstation installation folders found, please select the folder where VMWare Workstation is installed" -OutputMode Single
                            if ($null -ne $SelectedPath) {
                                if (Test-Path $SelectedPath.FullName -ErrorAction Stop) {
                                    $Global:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty -Name "InstallLocation" -Value $SelectedPath.DirectoryName -Force -ErrorAction Stop
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
        }
    }

   #Gather VMRest Config Settings vmrest.cfg
    if ($RetryRetrieveFolderError)  {
        Write-Message -Message "Gathering VMREST config" -MessageType INFORMATION
        Try {
            $GetVMRESTConfig = Get-ChildItem -Path $([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) -Recurse | Where-Object { $_.Name -eq "vmrest.cfg" } | Select-Object -ExpandProperty fullname -ErrorAction SilentlyContinue

            if (Test-Path $GetVMRESTConfig) {
                $GetVMRESTConfigLoader = $(Get-Content -Path $GetVMRESTConfig -ErrorAction Stop | Select-String -Pattern 'PORT','USERNAME' -AllMatches ).line.Trim()

                if (!([String]::IsNullOrEmpty(($GetVMRESTConfigLoader)))) {
                    $GetVMRESTConfigLoader | ForEach-Object { 
                        $Global:VMwareWorkstationConfigParameters | Add-Member -MemberType Noteproperty $($_.split("=")[0]) $($_.split("=")[1]) -Force
                }
            
                $Global:VMwareWorkstationConfigParameters | Add-Member -MemberType NoteProperty "HostAddress" -Value "127.0.0.1" -Force
                $Global:VMwareWorkstationConfigParameters | Add-Member -MemberType Noteproperty -Name BASEURL -Value "http://$($VMwareWorkstationConfigParameters.HostAddress):$($VMwareWorkstationConfigParameters.port)/api/" -Force
                Remove-Variable -name GetVMRESTConfigLoader,GetVMRESTConfig -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            Write-Message -Message "Cannot load the vmrest.cfg file" -MessageType INFORMATION 
            Start-Process -FilePath $(Join-Path -Path $VMwareWorkstationConfigParameters.InstallLocation -ChildPath "\vmrest.exe") -ArgumentList "-C" -Wait
            VMWare_RetrieveSettings
         }
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
        $Body=$Null
    )
    if (!($(Get-Process -name vmrest -ErrorAction SilentlyContinue))) {
        Stop-Process -name vmrest -ErrorAction SilentlyContinue -Force
        Start-Process -FilePath $(Join-Path -Path $VMwareWorkstationConfigParameters.InstallLocation -ChildPath "vmrest.exe") -PassThru -NoNewWindow -Verbose #-ArgumentList "" -WindowStyle Minimized
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
            throw $_.ErrorDetails.Message
        }
        else {
            if ($StatusCode) {
                switch ($StatusCode) {
                    105 { write-host  "The resource doenst exists- $($RequestResponse.Message)" }
                    204 { write-host "The resource has been deleted - $($RequestResponse.Message)" }
                    400 { write-host "Invalid parameters - $($RequestResponse.Message)" }
                    401 { VMWare_SetPassword } 
                    403 { write-host  "Permission denied - $($RequestResponse.Message)" }
                    404 { write-host "No such resource - $($RequestResponse.Message)" }
                    406 { write-host "Content type was not supported - $($RequestResponse.Message)" }
                    409 { write-host "Resource state conflicts $($RequestResponse.Message)" }
                    500 { write-host "Server error - $($RequestResponse.Message)" }
                    201 { return $RequestResponse }
                    200 { return $RequestResponse }  
                    default { Write-Message -Message "Unexpected error" $RequestResponse -MessageType ERROR } 
                }   
            }  
        }
    }
catch {
    write-host $error[0]
}

}
# Check if VNWare.exe process is active
Function CheckVMWareProcess   {
    
    try {
        if ($(Get-Process -name vmware -ErrorAction SilentlyContinue)) {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $MessageBoxReturn=[System.Windows.Forms.MessageBox]::Show("The VMware Gui is running, this can interfere with the vmware api module, press ok for quiting the gui","Warning action required",[System.Windows.Forms.MessageBoxButtons]::OKCancel) 
            switch ($MessageBoxReturn){
                "OK" {
                    Stop-Process -name vmrest -ErrorAction SilentlyContinue -Force -Verbose -PassThru
                } 
                "Cancel" {
                    Write-Message -Message "The script will continue, but some functions wont work correctly." -MessageType WARNING
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
    $DefaultBrowserName = (Get-Item $DefaultSettingPath | Get-ItemProperty).ProgId
    $null = New-PSDrive -PSProvider registry -Root 'HKEY_CLASSES_ROOT' -Name 'HKCR'
    $DefaultBrowserOpenCommand = (Get-Item "HKCR:\$DefaultBrowserName\shell\open\command" | Get-ItemProperty).'(default)'
    $DefaultBrowserPath = [regex]::Match($DefaultBrowserOpenCommand,'\".+?\"')
    Start-Process -FilePath $DefaultBrowserPath -ArgumentList  "https://developer.vmware.com/apis/412/vmware-workstation-pro-api,https://www.dtonias.com/create-vm-template-vmware-workstation/"
}
<#
--------------------------------------------------------------------------------------------------------------------------------------
    Host Networks Management
--------------------------------------------------------------------------------------------------------------------------------------
#>
#GET /vmnet Returns all virtual networks
Function Get-VMVirtualNetworks {
<#
    .SYNOPSIS
    
        Returns all virtual networks

    .DESCRIPTION
        Returns all virtual networks

    .EXAMPLE
    
        $VirtualNetworks = Get-VMVirtualNetworks
        num vmnets
        --- ------
        4 {@{name=vmnet0; type=bridged; dhcp=false; subnet=; mask=}, @{name=vmnet1; type=hostOnly; dhcp=true; subnet=192.168.80.0; mask=255.255.255.0}, @{name=vmnet8; type=nat; dhcp=true; subnet=192.168.174.0; mask=255.255.255.0}, @{name=vm…

        .EXAMPLE

        $VirtualNetworks = $(Get-VMVirtualNetworks).vmnets
        
            $virtualNetworks contains for example

            name   : vmnet0
            type   : bridged
            dhcp   : false
            subnet :
            mask   :

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
    
    .INPUTS
        System.String

    .OUTPUTS
        System.Array
#>  
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet")
            return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
#GET /vmnet/{vmnet}/mactoip
Function Get-VMNetMacToip {
    param (
        $VMNetMacToip
    )    
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
         $VMNetMacToip | ForEach-Object {
            $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vmnet/$($VMNetMacToip))/mactoip")
            return $RequestResponse
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}

<#
--------------------------------------------------------------------------------------------------------------------------------------
    VM Management
--------------------------------------------------------------------------------------------------------------------------------------
#>
#0 - Load Configuration
function Get-VMWareWorkstationConfiguration {
<#
    .SYNOPSIS
    
        creates a psobject to store the data needed for the proper functioning of the module, all the necessary data is stored in a variable

    .DESCRIPTION
        creates a psobject to store the data needed for the proper functioning of the module, all the necessary data is stored in a variable

    .EXAMPLE
    
        Get-VMWareWorkstationConfiguration
        will create a global variable $VMwareWorkstationConfigParameters based on the existing xml file that has been saved. or on the gathered information.


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

    .EXAMPLE

        Adding own data to the variable. 

        load the variable with Get-VMWareWorkstationConfiguration

        $VMwareWorkstationConfigParameters | Add-Member -MemberType Noteproperty -Name DATA -Value "Your data here" -Force
    
        use the -force to override settings.
    
        use [ Get-VMWareWorkstationConfiguration -SaveConfig ] to save the data into the XML file that will be created in the module folder.
    .EXAMPLE

        Removing data from the object 

        load the variable with Get-VMWareWorkstationConfiguration

        remove data from the object 
        $VMwareWorkstationConfigParameters.PSObject.properties.remove('data')
    
        use [ Get-VMWareWorkstationConfiguration -SaveConfig ] to save the data into the XML file that will be created in the module folder.
    
        .EXAMPLE

        using data

        load the variable with Get-VMWareWorkstationConfiguration
                
                Name            Definition                                                             
                ----            ----------                                                             
                BASEURL         string BASEURL=http://127.0.0.1:8697/api/    
        
        
        VMwareWorkstationConfigParameters.PSOBJECT can be called
        
        for example
        
        $VMwareWorkstationConfigParameters.BASEURL
        
        will result in a string with output http://127.0.0.1:8697/api/
    
    .INPUTS
        System.String

    .OUTPUTS
        System.String

#>  
    [cmdletbinding()]
    param (
        [switch]$SaveConfig
    )
    
    if ($(Get-Process -name vmrest -ErrorAction SilentlyContinue)) {
        Stop-Process -name vmrest -ErrorAction SilentlyContinue -Force
    }

    if ($SaveConfig) {
        if ($(Get-Variable VMwareWorkstationConfigParameters)) {
            VMWare_ExportSettings
        }
    }
    else {
        try {
            [void]::(Get-Variable -Name $VMwareWorkstationConfigParameters -ErrorAction Stop)
            }
        catch {
            $Global:VMwareWorkstationConfigParameters = New-Object PSObject
        }

        VMWare_ImportSettings    
    
        if ([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.Password)) {
            VMWare_SetPassword
        }
            RunVMRestConfig -Config ConfigCredentialsCheck
            $Global:VMwareWorkstationConfigParameters | Add-Member -MemberType Noteproperty -Name BASEURL -Value "http://$($VMwareWorkstationConfigParameters.HostAddress):$($VMwareWorkstationConfigParameters.port)/api/" -Force
            Clear-Host -ErrorAction SilentlyContinue
            (Get-Variable VMwareWorkstationConfigParameters -ErrorAction SilentlyContinue -Verbose) | Select-Object -ExpandProperty Name 
            (Get-Member -InputObject $VMwareWorkstationConfigParameters -MemberType NoteProperty -ErrorAction SilentlyContinue | Select-Object Name, Definition)
    }
}
# 1 GET /vms Returns a list of VM IDs and paths for all VMs
Function Get-VMTemplate {
<#
    .SYNOPSIS        
        List the virtual machines stored in the virtual machine folder

    .DESCRIPTION        
        List the virtual machines stored in the virtual machine folder

    .PARAMETER VirtualMachinename
       Can be a asterix * to retrieve all virtual machines
       Mandatory - [string]

        PS C:\WINDOWS\system32> Get-VMTemplate -VirtualMachinename *

        id                               path                                                                                           
        --                               ----                                                                                           
        PK7CPPB5UV50M3B73QD5ELDQN2OD9UFJ D:\Virtual machines\VMFOLDER1\VMNAME1.vmx 
        649TJ74BEAHCM93M56DM79VD21562M8D D:\Virtual machines\VMFOLDER2\VMNAME2.vmx 

    .PARAMETER Description
       Can be a VMID retrieved bij knowing the VMID 

        PS C:\WINDOWS\system32> Get-VMTemplate -VirtualMachinename VMNAME3

        id                               path                                                                                           
        --                               ----                                                                                           
        E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5 D:\Virtual machines\VMFOLDER3\VMNAME3.vmx

       Mandatory - [string]


     .EXAMPLE
       Can be a asterix * to retrieve all virtual machines a machine name or a vmid
       
       Mandatory - [string]

        Get-VMTemplate -VirtualMachinename *

        id                               path                                                                                           
        --                               ----                                                                                           
        PK7CPPB5UV50M3B73QD5ELDQN2OD9UFJ D:\Virtual machines\VMFOLDER1\VMNAME1.vmx 
        649TJ74BEAHCM93M56DM79VD21562M8D D:\Virtual machines\VMFOLDER2\VMNAME2.vmx 
    .PARAMETER Description
       Can be a VMID retrieved by knowing the VMID 

        Get-VMTemplate -VirtualMachinename VMNAME2

        id                               path                                                                                           
        --                               ----                                                                                           
        E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5 D:\Virtual machines\VMFOLDER2\VMNAME2.vmx
        Mandatory - [string]                                 
    .EXAMPLE        
        retrieve the path of the virtual machine
        $(Get-VMTemplate -VirtualMachinename PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ).Path

        results in D:\Virtual machines\VMFOLDER1\VMNAME1.vmx

    .EXAMPLE        
        Get-VMTemplate -VirtualMachinename E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5

        id                               path
        --                               ----
        E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5 D:\Virtuele machines\Windows Server 2016 DC-GUI Template\Windows Server 2016 DC-GUI Template.vmx
    
    .EXAMPLE        
        Get-VMTemplate -VirtualMachinename "Windows Server 2016 DC-GUI Template.vmx"

        id                               path
        --                               ----
        E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5 D:\Virtuele machines\Windows Server 2016 DC-GUI Template\Windows Server 2016 DC-GUI Template.vmx

    .EXAMPLE
        retrieve the id of the virtual machine
        $(Get-VMTemplate -VirtualMachinename PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ).id

        results E6QBUTVNKFRL0TTG8JA8BCN5LKCKFTJ5
    .EXAMPLE     
     $GatherVMS = $(Get-VMTemplate -VirtualMachinename *)

    .INPUTS
       System.String

    .OUTPUTS
       System.String
#>
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        $VirtualMachinename
    )

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        $RequestResponse=Invoke-VMWareRestRequest -method  GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms")
        
        
        if ($VirtualMachinename -eq "*") {
            return $RequestResponse
        }
        
        if ($VirtualMachinename -match $RequestResponse.id) {
            return $RequestResponse.id
        }

        foreach ($VM in $RequestResponse)
        {
            $PathSplit = ($vm.path).split("\")
            $vmxfile = $PathSplit[($PathSplit.Length)-1]
            $thisVM = ($vmxfile).split(".")[0]
            if ($thisVM -eq $VirtualMachinename) { return $VM ;break}
        } 
        return $VM
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
# 2 GET /vms/{id} Returns the VM setting information of a VM
function Get-VM {
<#
    .SYNOPSIS        
        Returns the VM setting information of a VM

    .DESCRIPTION        
        Returns the VM setting information of a VM
    .PARAMETER vmid
        
        Can be a VMID retrieved by knowing the VMID or by a asterix for al the vm's in a foreach loop
        Must be 32 characters long and the id can be rerieved with :  Get-VMTemplate -VirtualMachinename *

        id                               path                                                                                           
        --                               ----                                                                                           
        PK7CPPB5UV50M3B73QD5ELDQN2OD9UFJ D:\Virtual machines\VMFOLDER1\VMNAME1.vmx 
        649TJ74BEAHCM93M56DM79VD21562M8D D:\Virtual machines\VMFOLDER2\VMNAME2.vmx 
    .EXAMPLE

        retrieve the id of the virtual machine
        
        get-VM -VMId M3HAD21LB73N4GSHGJIC2MDM115A5GJT
        
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
        [ValidatePattern('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        [string]$VMId
    )

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        $RequestResponse = Invoke-VMWareRestRequest -method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($vmid)") 
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
#3 GET /vms/{id}/params/{name} Get the VM config params
Function Get-VMConfigParam {
}
# 4 GET /vms/{id}/restrictions Returns the restrictions information of the VM
Function Get-VMRestrictions {
<#
    .SYNOPSIS        
        Returns the restrictions information of the VM

    .DESCRIPTION        
        Returns the restrictions information of the VM

    .PARAMETER VMId
        Can be a VMID retrieved by knowing the VMID or by a asterix for al the vm's in a foreach loop
        Must be 32 characters long and the id can be rerieved with :  Get-VMTemplate -VirtualMachinename *

    .EXAMPLE

        Get-VMRestrictions -VMId PK7CPPB5UV50M3B73QD5ELDQN2OD9UFJ

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
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMId
    )
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        $RequestResponse = Invoke-VMWareRestRequest -method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($vmid)/restrictions") 
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
# 5 GET /vms/{id}/params/{name} update the VM config params
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

    [cmdletbinding()]
    param 
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMId,
		[Parameter(Mandatory)]
        [ValidatePattern ('^[0-9]', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $processors,
        [Parameter(Mandatory)]
        [ValidatePattern ('^[0-9]', errormessage = "{0}, The processors field can contain [0-9] ")]
        $memory
    )    
    CheckVMWareProcess
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if (!($(Get-Process -name vmware -ErrorAction SilentlyContinue))) {
            $Body = @{
                'id'= $("$VMId");
                'processors' = $processors;
                'memory' = $memory
            } | ConvertTo-Json
            
            $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($vmid)") -Method PUT -Body $Body
            return $RequestResponse
        }
        else {
            Write-Message -Message "Can't close vmware.exe. The settings setted for $($VMId) can't be proccessed. please close the program " -MessageType ERROR
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
#6 PUT /vms/{id}/configparams update the vm config params
Function Set-VMConfigParam {
}
# 7 POST /vms Creates a copy of the VM
Function New-VMClonedMachine {
<#
    .SYNOPSIS        
        Creates a copy of a VM

    .DESCRIPTION        
        Creates a copy of a VM

    .PARAMETER NewVMCloneName
        Can be anyting 

    .PARAMETER NewVMCloneId
        Must be a $vmid retrieved bij Get-VMTemplate -VirtualMachine * 

    .EXAMPLE
        Creates a new cloned machine based on a template 
        $machineToDelete = (Get-VMTemplate -VirtualMachinename $NewClonedMachine).id
        $NewVMCloneName = $("CLONE-" + -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 11 | % {[char]$_})).ToUpper()
        $NewClonedMachine

        id                               cpu             memory
        --                               ---             ------
        JMPFQNFBDPGGCRTGSVQOTUES038F4VEC @{processors=2}   4096

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
        $NewVMCloneName,
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $NewVMCloneId
    )

    CheckVMWareProcess

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if (!($(Get-Process -name vmware -ErrorAction SilentlyContinue))) {
            $Body = @{
                'name' = $NewVMCloneName;
                'parentId' = $NewVMCloneId
            }   | ConvertTo-Json
            $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms") -Method POST -Body $body
            return $RequestResponse
        }
        else {
            Write-Message -Message "Can't close vmware.exe the creation of vm with id $($NewVMCloneName) can't be proccessed. please close the program " -MessageType ERROR
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
# 8 POST /vms/registration Register VM to VM Library
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

    .EXAMPLE

        after creating a new cloned machine the vm can be registered in the gui
        Create a generic name
        
        $NewVMCloneName = $("CLONE-" + -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 11 | % {[char]$_})).ToUpper()
        
        $NewVMCloneName
        
        CLONE-WDMEPYTYLTC

        $NewClonedMachine = New-VMClonedMachine -NewVMCloneName $NewVMCloneName -NewVMCloneId 649TJ74BEAHCM93M56DM79CD21562M8D
        $NewClonedMachine

        id                               cpu             memory
        --                               ---             ------
        JMPFQNFBDPGGCRTGSVQOTUES038F4VEC @{processors=2}   4096

        Register-VMClonedMachine -NewVMCloneName $NewVMCloneName -VMClonePath (Get-VMTemplate -VirtualMachinename $NewVMCloneName).path

        id                               path
        --                               ----
        JMPFQNFBDPGGCRTGSVQOTUES038F4VEC D:\Virtuele machines\CLONE-WDMEPYTYLTC\CLONE-WDMEPYTYLTC.vmx

    .EXAMPLE
        Register-VMClonedMachine -NewVMCloneName $NewVMCloneName -VMClonePath (Get-VMTemplate -VirtualMachinename $NewVMCloneName).path

        id                               path
        --                               ----
        JMPFQNFBDPGGCRTGSVQOTUES038F4VEC D:\Virtuele machines\CLONE-WDMEPYTYLTC\CLONE-WDMEPYTYLTC.vmx

    .INPUTS
       System.String
       system.integer

    .OUTPUTS
       System.array
#>   
    [cmdletbinding()]
    [OutputType([Bool])]
    param 
    (
        [Parameter(Mandatory)]
		#[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $NewVMCloneName,
        [Parameter(Mandatory)]
        $VMClonePath
    )
    CheckVMWareProcess
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
         if (!($(Get-Process -name vmware -ErrorAction SilentlyContinue))) {
            $Body = @{
                'name' = $NewVMCloneName;
                'path' = $VMClonePath
            } | ConvertTo-Json

            $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/registration") -Method POST -Body $Body
            return $RequestResponse
        }
        else {
            Write-Message -Message "Can't close vmware.exe the deletion of vm with id $($id) can't be proccessed. please close the program " -MessageType ERROR
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
# 9 DELETE /vms/{id} Deletes a VM
Function Remove-VMClonedMachine {
<#
    .SYNOPSIS        
        Deletes a VM

    .DESCRIPTION        
        Deletes a VM

    .PARAMETER NewVMCloneName
        Can be anyting 

    .PARAMETER NewVMCloneId
        Must be a $vmid retrieved bij Get-VMTemplate -VirtualMachine * 

    .EXAMPLE
       Get-VMTemplate -VirtualMachinename *

        id                               path
        --                               ----
        MRJVR0R64RS7GLC7EMG9QRCOB015RNSV D:\Virtuele machines\CLONE-1SBAZX9JQCE\CLONE-1SBAZX9JQCE.vmx
        GBILCONH2U9FG18K09KVIKB8FV10I02V D:\Virtuele machines\CLONE-BVGMLE27N1H\CLONE-BVGMLE27N1H.vmx


        Remove-VMClonedMachine -VMId MRJVR0R64RS7GLC7EMG9QRCOB015RNSV
        
        Result:
        The resource has been deleted -

        Get-VMTemplate -VirtualMachinename *

        id                               path
        --                               ----
        GBILCONH2U9FG18K09KVIKB8FV10I02V D:\Virtuele machines\CLONE-BVGMLE27N1H\CLONE-BVGMLE27N1H.vmx


    .INPUTS
       System.String
    .OUTPUTS
       Message
#>   
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMId
    )
    CheckVMWareProcess  
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if (!($(Get-Process -name vmware -ErrorAction SilentlyContinue))) {

            $RequestResponse=Invoke-VMWareRestRequest -Method DELETE -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMid)")
            return $RequestResponse
        }
        else {
            Write-Message -Message "Can't close vmware.exe the deletion of vm with id $($id) can't be proccessed. please close the program " -MessageType ERROR
         }                
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}

<#
--------------------------------------------------------------------------------------------------------------------------------------
    VM Network Adapters Management
--------------------------------------------------------------------------------------------------------------------------------------
#>
#GET /vms/{id}/ip Returns the IP address of a VM
function Get-VMIpAddress {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        [string]$VMId
    )

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        $RequestResponse = Invoke-VMWareRestRequest -method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($vmid)/ip") 
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
#GET /vms/{id}/nic Returns all network adapters in the VM
function Get-VMNic {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        [string]$VMId
    )

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {

        $RequestResponse = Invoke-VMWareRestRequest -method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($vmid)/nic") 
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
#GET /vms/{id}/nicips Returns the IP stack configuration of all NICs of a VM
function Get-VMnicIps {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        [string]$VMId
    )

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        $RequestResponse = Invoke-VMWareRestRequest -method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($vmid)/nicips") 
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
#PUT /vms/{id}/nic/{index} Updates a network adapter in the VM
Function Update-VMNetAdapter {
 
    # enum via Get-VMVirtualNetworks

    [cmdletbinding()]
    param 
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMId,
		[Parameter(Mandatory)]
        [ValidatePattern ('^[0-9]', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMNicIndex,
        $VMNet,
        [Parameter(Mandatory)]
        [ValidateSet('bridged','nat','hostonly','custom', errormessage = "{0}, Value must be: bridged, nat, hostonly, custom")]
        $VMNettype
    )    
    CheckVMWareProcess

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if (!($(Get-Process -name vmware -ErrorAction SilentlyContinue))) {
            $Body = @{
                'type'= $VMNettype;
                'vmnet' = $vmnet;
            } | ConvertTo-Json
            
            $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($vmid)/nic/$($VMNicIndex)") -Method PUT -Body $Body
            return $RequestResponse
        }
        else {
            Write-Message -Message "Can't close vmware.exe. The settings setted for $($VMId) can't be proccessed. please close the program " -MessageType ERROR
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}

#POST /vms/{id}/nic Creates a network adapter in the VM
Function Add-VMNetAdapter {
    [cmdletbinding()]
    param 
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMId,
        $VMNet,
        [Parameter(Mandatory)]
        [ValidateSet('bridged','nat','hostonly','custom', errormessage = "{0}, Value must be: bridged, nat, hostonly, custom")]
        $VMNettype,
        $VMMacAddress
    )    
    CheckVMWareProcess

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if (!($(Get-Process -name vmware -ErrorAction SilentlyContinue))) {
            $Body = @{
                'type'= $VMNettype;
                'vmnet' =  $VMNet;
            } | ConvertTo-Json
            
            $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($vmid)/nic") -Method POST -Body $Body
            return $RequestResponse
        }
        else {
            Write-Message -Message "Can't close vmware.exe. The settings setted for $($VMId) can't be proccessed. please close the program " -MessageType ERROR
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
#DELETE /vms/{id}/nic/{index} Deletes a VM network adapter
Function Remove-VMNetAdapter {
    [cmdletbinding()]
    param 
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMId,
        [ValidatePattern ('^[0-9]', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMNicIndex
    )    
    CheckVMWareProcess

    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if (!($(Get-Process -name vmware -ErrorAction SilentlyContinue))) {

            $RequestResponse=Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($vmid)/nic/$VMNicIndex") -Method DELETE
            return $RequestResponse
        }
        else {
            Write-Message -Message "Can't close vmware.exe. The settings setted for $($VMId) can't be proccessed. please close the program " -MessageType ERROR
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
<#
--------------------------------------------------------------------------------------------------------------------------------------
    VM Power Management
--------------------------------------------------------------------------------------------------------------------------------------
#>

# /vms/{id}/power Returns the power state of the VM
Function Get-VMPowerSettings {
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMId
    )
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
            $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMid)/power")
            return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
#/vms/{id}/power Changes the VM power state
Function Set-VMPowerSettings {
    param (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{32,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMId,
        [ValidateSet('on', 'off', 'shutdown', 'suspend','pause','unpause', errormessage = "{0}, Value must be: on, off, shutdown, suspend,pause, unpause")]
        $PowerMode
    )    
    CheckVMWareProcess  
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if ($(Get-Process -Name  vmware -ErrorAction SilentlyContinue)) {
            $VMWareReopen = $true
            Stop-Process -Name vmware -ErrorAction SilentlyContinue -Force 
        }        

        if (!($(Get-Process -name vmware -ErrorAction SilentlyContinue))) {

            $RequestResponse=Invoke-VMWareRestRequest -Method PUT -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMid)/power") -Body $PowerMode
            return $RequestResponse
        }
        else {
            Write-Message -Message "Can't close vmware.exe the deletion of vm with id $($VMId) can't be proccessed. please close the program first" -MessageType ERROR
        }
                
        if ($VMWareReopen) {
            Start-Sleep 5
            Start-Process -FilePath $(Join-Path -Path $VMwareWorkstationConfigParameters.InstallLocation -ChildPath "vmware.exe")
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}

<#
--------------------------------------------------------------------------------------------------------------------------------------
    VM Shared Folders Management
--------------------------------------------------------------------------------------------------------------------------------------
#>

#1 GET /vms/{id}/sharedfolders Returns all shared folders mounted in the VM
Function Get-VMSSharedFolders {
<#
    .SYNOPSIS
    
        Returns all shared folders mounted in the VM

    .DESCRIPTION
        Returns all shared folders mounted in the VM

    .EXAMPLE
    
        Get-VMSSharedFolders -VMId PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ

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
		[ValidatePattern ('^[A-Za-z0-9*]{1,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMId
    )
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        $RequestResponse=Invoke-VMWareRestRequest -Method GET -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($VMid)/sharedfolders")
        return $RequestResponse
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}

#2 PUT /vms/{id}/sharedfolders/{folder id} Updates a shared folder mounted in the VM
# Nog niet werkend. vanaf hier verder
Function Update-VMSSharedFolders {
<#
    .SYNOPSIS
    
        Updates a shared folder mounnted in the VM

    .DESCRIPTION
        Updates a shared folder mounnted in the VM

    .EXAMPLE
    
        Update-VMSSharedFolders -VMId PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ -host_path 'D:\Virtual machines\' -SharedFolderName "VMShare" -flags 4
        for read/write with flag 4
    .EXAMPLE
    
        Update-VMSSharedFolders -VMId PK7CPPB5UV50M3B73QD5OLDQN2OD9UFJ -host_path 'D:\Virtual machines\' -SharedFolderName "VMShare" -flags 0
        for readonly with flag 0

    .INPUTS
        System.String

    .OUTPUTS
        System.String
#> 
    [cmdletbinding()]
    param 
    (
        [Parameter(Mandatory)]
        #[ValidatePattern ('^[*][A-Za-z0-9]{1,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMId,
        [Parameter(Mandatory)]
        [ValidateScript({
            if( -Not ($_ | Test-Path) ){
                return $false
            }
            return $true
        }, errormessage = "{0}, is a non-existing path")]
        [System.IO.FileInfo]$host_path,
        $SharedFolderName,
        [ValidateSet('4','0', errormessage = "{0}, The flag can contain 0 or 4 and must be 1 characters long, 4 = read/write 0 = read only ")]
        $flags
    )    
    CheckVMWareProcess
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if (!($(Get-Process -name vmware -ErrorAction SilentlyContinue))) {

            $Body = @{
                'folder_id' = $SharedFolderName;
                'host_path' = $host_path.FullName;
                'flags' = $flags
            }
            
            $Body = $Body | ConvertTo-Json

            $RequestResponse = Invoke-VMWareRestRequest -uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($vmid)/sharedfolders/$($SharedFolderName)")  -Method PUT -Body $Body
            if ($RequestResponse) {
                Write-Message -Message "Share with name: $($SharedFolderName) changed to: $($host_path.FullName) with flag: $($flags)" -MessageType INFORMATION
                return $RequestResponse
            }
        }
        else {
            Write-Message -Message "Can't close vmware.exe. The settings setted for $($VMId) can't be proccessed. please close the program " -MessageType ERROR
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}

#3 POST /vms/{id}/sharedfolders Mounts a new shared folder in the VM
Function Add-VMSSharedFolders {
    [cmdletbinding()]
    param 
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{1,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMId,
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
        $SharedFolderName,
        [ValidateSet('4','0', errormessage = "{0}, The flag can contain 0 or 4 and must be 1 characters long, 4 = read/write 0 = read only ")]
        $flags     
    )    
    CheckVMWareProcess
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if (!($(Get-Process -name vmware -ErrorAction SilentlyContinue))) {
            $Body = @{
                'folder_id' = $SharedFolderName;
                'host_path' = $host_path.FullName;
                'flags' = $flags
            } 
            $Body = ($Body | ConvertTo-Json)
            $RequestResponse = invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($vmid)/sharedfolders") -Method POST -Body $Body
            
            if ($RequestResponse) {
                Write-Message -Message "Share with $($SharedFolderName) and path $($host_path) added" -MessageType INFORMATION
                return $RequestResponse
            }
        }
        else {
            Write-Message -Message "Can't close vmware.exe. The settings setted for $($VMId) can't be proccessed. please close the program " -MessageType ERROR
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}
#4 DELETE /vms/{id}/sharedfolders/{folder id} Deletes a shared folder
Function Remove-VMSSharedFolders {
    [cmdletbinding()]
    param 
    (
        [Parameter(Mandatory)]
		[ValidatePattern ('^[A-Za-z0-9]{1,32}$', errormessage = "{0}, The VMId can contain [a-z][0-9] and must be 32 characters long ")]
        $VMId,
        $SharedFolderName
    )
    CheckVMWareProcess
    if (!([string]::IsNullOrEmpty($VMwareWorkstationConfigParameters.BASEURL))) {
        if (!($(Get-Process -name vmware -ErrorAction SilentlyContinue))) {
            $RequestResponse = Invoke-VMWareRestRequest -Uri ($VMwareWorkstationConfigParameters.BASEURL + "vms/$($vmid)/sharedfolders/$($SharedFolderName)") -Method DELETE -Body $Body
            return $RequestResponse
        }
        else {
            Write-Message -Message "Can't close vmware.exe. The settings setted for $($VMId) can't be proccessed. please close the program " -MessageType ERROR
        }
    }
    else {
        Write-Message -Message "Configuration is not loaded, use Get-VMWareWorkstationConfiguration to load the configuration" -MessageType ERROR 
    }
}