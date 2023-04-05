<# Create a Template
    # 
    # https://github.com/DKreutz0/VMWareWorkstationAPI/blob/main/VMWareWorkstation-API/Documentation/Create%20a%20VM%20template%20on%20VMware%20Workstation.docx
    # https://github.com/DKreutz0/VMWareWorkstationAPI/blob/main/VMWareWorkstation-API/Documentation/Create%20a%20VM%20template%20on%20VMware%20Workstation.docx
    #
#>

try {
    Import-Module -Name VMWareWorkstation-API -ErrorAction Stop
    [string]$VMTemplate = "649TJ74BEAHCM93M56DM79CD21562M8D" # Get your VM Id with the Get-VMTemplates function
    #Start creation of the Virtual Machine    

        $NewVMCloneName = $("CLONEDVM-" + -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 11 | ForEach-Object  {[char]$_})).ToUpper()
        $NewClonedVM = New-VMClonedMachine -NewVMCloneName $NewVMCloneName -NewVMCloneId $VMTemplate -ResponseDetails -ErrorAction Stop

   $NewClonedVM

    # Registering the Virtual Machine in the VMWare Workstation console

        $ClonePath = Get-VirtualMachines -VirtualMachineName $NewVMCloneName
        $RegisterVM = Register-VMClonedMachine -NewVMCloneName $NewVMCloneName -VMClonePath $ClonePath.path -ResponseDetails -ErrorAction Stop
    
    $RegisterVM

}
catch {
    Write-Host "Error occured $($error[0].exeption)"
}