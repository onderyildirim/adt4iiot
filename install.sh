#!/usr/bin/env bash

location="eastus2"
prefix="adt4iiot"
adminUserName="azureuser"
vmSize="Standard_B1ms"


while :; do
    case $1 in
        -h|-\?|--help)
            show_help
            exit;;
        -l=?*)
            location=${1#*=}
            ;;
        -l=)
            echo "Location missing"
            exit;;
        -s=?*)
            subscription=${1#*=}
            ;;
        -prefix=?*)
            prefix=${1#*=}
            ;;
        -prefix=)
            echo "Prefix missing"
            exit;;
        -vmSize=?*)
            vmSize=${1#*=}
            ;;
        -vmSize=)
            echo "vmSize missing"
            exit;;
        -adminUserSshPublicKeyPath=)
            echo "SSH public key missing."
            exit;;
        -adminUserSshPublicKeyPath=?*)
            adminUserSshPublicKeyPath=${1#*=}
            ;;
        --)
            shift
            break;;
        *)
            break
    esac
    shift
done





rg="$prefix-rg"
networkName="$prefix-network"
adminUserSshPublicKey=$(cat $adminUserSshPublicKeyPath)

if [ ! -z $subscription ]; then
  az account set --subscription $subscription
fi
subscriptionDetails=($(az account show --query '[id, name]' -o tsv))
subscription=${subscriptionDetails[0]}
subscriptionName=${subscriptionDetails[1]}
echo "Deploying to Azure Subscription: ${subscriptionName} (${subscription})" 

if ( $(az group exists -n "$rg") )
then
  echo "Resource group $rg already exists. Exiting."
  exit
else
  az group create --name "$rg" --location "$location" --tags "$prefix" "CreationDate"=$(date --utc +%Y%m%d_%H%M%SZ)  1> /dev/null
  echo "Create resource group $rg"
fi

networkDeploymentFilePath="templates/networkdeploy.json"
edgeVMDeploymentFilePath="templates/iotedgedeploy.json"
simVMDeploymentFilePath="templates/opcsimdeploy.json"

networkDeploymentOutput=$(az deployment group create --name NetworkDeployment --resource-group "$rg" --template-file "$networkDeploymentFilePath" --parameters \
 networkName="$networkName" \
 --query "properties.outputs.[resourceGroup.value, virtualNetwork.value]" -o tsv) 

networkRG=${networkDeploymentOutput[0]}
networkName=${networkDeploymentOutput[1]}

echo "Network RG  : $networkRG"
echo "Network Name: $networkName"

edgeVMDeploymentOutput=$(az deployment group create --name EdgeVMDeployment --resource-group "$rg" --template-file "$edgeVMDeploymentFilePath" --parameters \
networkRG="$networkRG" networkName="$networkName" prefix="$prefix" adminUserName="$adminUserName" adminUserSshPublicKey="$adminUserSshPublicKey" vmSize="$vmSize" \
 --query "properties.outputs.[vmMachineName.value, vmMachineIP.value, vmAdminUserName.value]" -o tsv) 

vmMachineName=${edgeVMDeploymentOutput[0]}
vmMachineIP=${edgeVMDeploymentOutput[1]}
vmAdminUserName=${edgeVMDeploymentOutput[1]}

echo "VM Name: $vmMachineName"
echo "VM IP: $vmMachineIP"
echo "VM Admin: $vmAdminUserName"

simVMDeploymentOutput=$(az deployment group create --name SimVMDeployment --resource-group "$rg" --template-file "$simVMDeploymentFilePath" --parameters \
networkRG="$networkRG" networkName="$networkName" prefix="$prefix" adminUserName="$adminUserName" adminUserSshPublicKey="$adminUserSshPublicKey" vmSize="$vmSize" \
 --query "properties.outputs.[vmMachineName.value, vmMachineIP.value, vmAdminUserName.value]" -o tsv) 

vmMachineName=${simVMDeploymentOutput[0]}
vmMachineIP=${simVMDeploymentOutput[1]}
vmAdminUserName=${simVMDeploymentOutput[1]}

echo "VM Name: $vmMachineName"
echo "VM IP: $vmMachineIP"
echo "VM Admin: $vmAdminUserName"



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
