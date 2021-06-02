#!/usr/bin/env bash

location="eastus2"
prefix="adt4iiot"
adminUserName="azureuser"
vmSize="Standard_B1ms"
adminUserSshPublicKeyPath="$(readlink -f ~/.ssh/id_rsa.pub)"


while (( "$#" )); do
  case "$1" in
    -h|-\?|--help)
      show_help
      exit;;
    -l|--location)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        location=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -p|--prefix)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        prefix=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -v|--vmsize)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        vmSize=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -k|--ssh-keypath)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        adminUserSshPublicKeyPath=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -u|--adminuser)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        adminUserName=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -s|--subscription)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        subscription=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -*|--*=) 
      echo "Error: Unsupported argument $1" >&2
      exit 1
      ;;

  esac
done



echo "location=$location"
echo "prefix=$prefix"
echo "adminUserName=$adminUserName"
echo "adminUserSshPublicKeyPath=$adminUserSshPublicKeyPath"
echo "vmSize=$vmSize"
echo "subscription=$subscription"

rg="$prefix-rg"
networkName="$prefix-network"
adminUserSshPublicKey=$(cat $adminUserSshPublicKeyPath)


echo "rg=$rg"

if [ ! -z $subscription ]; then
  az account set --subscription $subscription
fi

subscriptionDetails=($(az account show --query '[id, name]' -o tsv))
subscription=${subscriptionDetails[0]}
subscriptionName=${subscriptionDetails[1]}
echo "Deploying to Azure Subscription: ${subscriptionName} (${subscription})" 

if ( $(az group exists -n "$rg") )
then
  echo "Resource group $rg already exists."
else
  az group create --name "$rg" --location "$location" --tags "$prefix" "CreationDate"=$(date --utc +%Y%m%d_%H%M%SZ)  1> /dev/null
  echo "Create resource group $rg"
fi

networkDeploymentFilePath="templates/networkdeploy.json"
edgeVMDeploymentFilePath="templates/iotedgedeploy.json"
simVMDeploymentFilePath="templates/opcsimdeploy.json"
vmDeploymentFilePath="templates/vmdeploy.json"


if [ ! -z  $(az network vnet list --resource-group "$rg" --query "[?name=='$networkName'].id" --output tsv) ] 
then
  echo "Network $networkName already exists."
else
  networkDeploymentOutput=$(az deployment group create --name NetworkDeployment --resource-group "$rg" --template-file "$networkDeploymentFilePath" --parameters \
  networkName="$networkName" \
  --query "properties.outputs.[resourceGroup.value, virtualNetwork.value]" -o tsv) 

  outnetworkRG=${networkDeploymentOutput[0]}
  outnetworkName=${networkDeploymentOutput[1]}

  echo "Created network $networkName."
  echo "Network RG  : $outnetworkRG"
  echo "Network Name: $outnetworkName"
  echo "======================================"
fi


simVMMachineName="$prefix-simvm"
echo "simVMMachineName=$simVMMachineName"

if [ ! -z  $(az vm list --resource-group "$rg" --query "[?name=='$simVMMachineName'].id" --output tsv) ] 
then
  echo "VM $simVMMachineName already exists."
else
  simVMDeploymentOutput=$(az deployment group create --name SimVMDeployment --resource-group "$rg" --template-file "$vmDeploymentFilePath" --parameters \
  vmType="simulator" vmMachineName="$simVMMachineName" networkName="$networkName" adminUserName="$adminUserName" adminUserSshPublicKey="$adminUserSshPublicKey" vmSize="$vmSize" \
  --query "properties.outputs.[vmMachineName.value, vmMachinePrivateIP.value, vmMachineFqdn.value, vmAdminUserName.value]" -o tsv) 

  vmMachineName     =${simVMDeploymentOutput[0]}
  vmMachinePrivateIP=${simVMDeploymentOutput[1]}
  vmMachineFqdn     =${simVMDeploymentOutput[2]}
  vmAdminUserName   =${simVMDeploymentOutput[3]}

  echo "VM Name:       $vmMachineName"
  echo "VM Private IP: $vmMachinePrivateIP"
  echo "VM Fqdn:       $vmMachineFqdn"
  echo "VM Admin:      $vmAdminUserName"
  echo "======================================"
fi


edgeVMMachineName="$prefix-edgevm"
echo "edgeVMMachineName=$edgeVMMachineName"

if [ ! -z  $(az vm list --resource-group "$rg" --query "[?name=='$edgeVMMachineName'].id" --output tsv) ] 
then
  echo "VM $edgeVMMachineName already exists."
else
  edgeVMDeploymentOutput=$(az deployment group create --name EdgeVMDeployment --resource-group "$rg" --template-file "$vmDeploymentFilePath" --parameters \
  vmType="edge" vmMachineName="$edgeVMMachineName" networkName="$networkName" adminUserName="$adminUserName" adminUserSshPublicKey="$adminUserSshPublicKey" vmSize="$vmSize" \
  --query "properties.outputs.[vmMachineName.value, vmMachinePrivateIP.value, vmMachineFqdn.value, vmAdminUserName.value]" -o tsv) 

  vmMachineName     =${edgeVMDeploymentOutput[0]}
  vmMachinePrivateIP=${edgeVMDeploymentOutput[1]}
  vmMachineFqdn     =${edgeVMDeploymentOutput[2]}
  vmAdminUserName   =${edgeVMDeploymentOutput[3]}

  echo "VM Name:       $vmMachineName"
  echo "VM Private IP: $vmMachinePrivateIP"
  echo "VM Fqdn:       $vmMachineFqdn"
  echo "VM Admin:      $vmAdminUserName"
  echo "======================================"
fi


function script_usage() {
   echo "Run this script to simulate in Azure: a Purdue Network, PLCs, IoT Edge devices sending data to IoT Hub."
   echo
   echo "Syntax: ./install.sh [-flag=value]"
   echo ""
   echo "List of mandatory flags:"
   echo "-hubrg                 Azure Resource Group with the Azure IoT Hub."
   echo "-hubname               Name of the Azure IoT Hub controlling the IoT Edge devices."
   echo ""
   echo "List of optional flags:"
   echo "-h                     Print this help."
   echo "-c                     Path to configuration file with IIOT assets and IoT Edge VMs information. Default: ./config.txt."
   echo "-s                     Azure subscription ID to use to deploy resources. Default: use current subscription of Azure CLI."
   echo "-l                     Azure region to deploy resources to. Default: eastus."
   echo "-rg                    Prefix used for all new Azure Resource Groups created by this script. Default: iotedge4iiot."
   echo "-vmSize                Size of the Azure VMs to deploy. Default: Standard_B1ms."
   echo "-sshPublicKeyPath      Path to the SSH public key that should be used to connect to the jump box, which is the entry point to the Purdue network. Default: ~/.ssh/id_rsa.pub"
   echo
}
