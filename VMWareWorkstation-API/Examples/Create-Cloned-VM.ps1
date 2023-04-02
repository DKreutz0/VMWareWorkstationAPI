<# Create a Template
    # 
    # https://github.com/DKreutz0/VMWareWorkstationAPI/blob/main/VMWareWorkstation-API/Documentation/Create%20a%20VM%20template%20on%20VMware%20Workstation.docx
    # https://github.com/DKreutz0/VMWareWorkstationAPI/blob/main/VMWareWorkstation-API/Documentation/Create%20a%20VM%20template%20on%20VMware%20Workstation.docx
    #
#>
import-Module -Name VMWareWorkstation-API 

#load settings
[void]::(Get-VMWareWorkstationConfiguration)
[string]$VMTemplate = "41OT7BN8UH80H4LV6RT2P306HGV638R6" # Get your VM Id with Get-VMTemplate -VirtualMachineName * -ResponseDetails

#Start creation of the Virtual Machine
$NewVMCloneName = $("CLONE-" + -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 11 | % {[char]$_})).ToUpper()
$NewClonedVM = New-VMClonedMachine -NewVMCloneName $NewVMCloneName -NewVMCloneId $VMTemplate -ResponseDetails
$NewClonedVM

# Registering the Virtual Machine in the VMWare Workstation Gui
$ClonePath = (Get-VMTemplate -VirtualMachineName $NewVMCloneName).path
$RegisterVM = Register-VMClonedMachine -NewVMCloneName $NewVMCloneName -VMClonePath $ClonePath -ResponseDetails
$RegisterVM