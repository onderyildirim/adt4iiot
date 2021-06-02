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
fi


simVMCustomData='#cloud-config\n\napt:\n  preserve_sources_list: true\n  sources:\n    msft.list:\n      source: \"deb https://packages.microsoft.com/ubuntu/18.04/multiarch/prod bionic main\"\n      key: |\n        -----BEGIN PGP PUBLIC KEY BLOCK-----\n        Version: GnuPG v1.4.7 (GNU/Linux)\n\n        mQENBFYxWIwBCADAKoZhZlJxGNGWzqV+1OG1xiQeoowKhssGAKvd+buXCGISZJwT\n        LXZqIcIiLP7pqdcZWtE9bSc7yBY2MalDp9Liu0KekywQ6VVX1T72NPf5Ev6x6DLV\n        7aVWsCzUAF+eb7DC9fPuFLEdxmOEYoPjzrQ7cCnSV4JQxAqhU4T6OjbvRazGl3ag\n        OeizPXmRljMtUUttHQZnRhtlzkmwIrUivbfFPD+fEoHJ1+uIdfOzZX8/oKHKLe2j\n        H632kvsNzJFlROVvGLYAk2WRcLu+RjjggixhwiB+Mu/A8Tf4V6b+YppS44q8EvVr\n        M+QvY7LNSOffSO6Slsy9oisGTdfE39nC7pVRABEBAAG0N01pY3Jvc29mdCAoUmVs\n        ZWFzZSBzaWduaW5nKSA8Z3Bnc2VjdXJpdHlAbWljcm9zb2Z0LmNvbT6JATUEEwEC\n        AB8FAlYxWIwCGwMGCwkIBwMCBBUCCAMDFgIBAh4BAheAAAoJEOs+lK2+EinPGpsH\n        /32vKy29Hg51H9dfFJMx0/a/F+5vKeCeVqimvyTM04C+XENNuSbYZ3eRPHGHFLqe\n        MNGxsfb7C7ZxEeW7J/vSzRgHxm7ZvESisUYRFq2sgkJ+HFERNrqfci45bdhmrUsy\n        7SWw9ybxdFOkuQoyKD3tBmiGfONQMlBaOMWdAsic965rvJsd5zYaZZFI1UwTkFXV\n        KJt3bp3Ngn1vEYXwijGTa+FXz6GLHueJwF0I7ug34DgUkAFvAs8Hacr2DRYxL5RJ\n        XdNgj4Jd2/g6T9InmWT0hASljur+dJnzNiNCkbn9KbX7J/qK1IbR8y560yRmFsU+\n        NdCFTW7wY0Fb1fWJ+/KTsC4=\n        =J6gs\n        -----END PGP PUBLIC KEY BLOCK----- \npackages:\n  - moby-engine\n  - moby-cli\nruncmd:\n  - |\n      set -x\n      (\n        docker run -p 54845:54845 -p 54855:54855 -p 1880:1880 --name opcsimulator onderyildirim/opcsimulator:0.1.50.0-amd64\n      ) &\n'
edgeVMCustomData='#cloud-config\n\napt:\n  preserve_sources_list: true\n  sources:\n    msft.list:\n      source: \"deb https://packages.microsoft.com/ubuntu/18.04/multiarch/prod bionic main\"\n      key: |\n        -----BEGIN PGP PUBLIC KEY BLOCK-----\n        Version: GnuPG v1.4.7 (GNU/Linux)\n\n        mQENBFYxWIwBCADAKoZhZlJxGNGWzqV+1OG1xiQeoowKhssGAKvd+buXCGISZJwT\n        LXZqIcIiLP7pqdcZWtE9bSc7yBY2MalDp9Liu0KekywQ6VVX1T72NPf5Ev6x6DLV\n        7aVWsCzUAF+eb7DC9fPuFLEdxmOEYoPjzrQ7cCnSV4JQxAqhU4T6OjbvRazGl3ag\n        OeizPXmRljMtUUttHQZnRhtlzkmwIrUivbfFPD+fEoHJ1+uIdfOzZX8/oKHKLe2j\n        H632kvsNzJFlROVvGLYAk2WRcLu+RjjggixhwiB+Mu/A8Tf4V6b+YppS44q8EvVr\n        M+QvY7LNSOffSO6Slsy9oisGTdfE39nC7pVRABEBAAG0N01pY3Jvc29mdCAoUmVs\n        ZWFzZSBzaWduaW5nKSA8Z3Bnc2VjdXJpdHlAbWljcm9zb2Z0LmNvbT6JATUEEwEC\n        AB8FAlYxWIwCGwMGCwkIBwMCBBUCCAMDFgIBAh4BAheAAAoJEOs+lK2+EinPGpsH\n        /32vKy29Hg51H9dfFJMx0/a/F+5vKeCeVqimvyTM04C+XENNuSbYZ3eRPHGHFLqe\n        MNGxsfb7C7ZxEeW7J/vSzRgHxm7ZvESisUYRFq2sgkJ+HFERNrqfci45bdhmrUsy\n        7SWw9ybxdFOkuQoyKD3tBmiGfONQMlBaOMWdAsic965rvJsd5zYaZZFI1UwTkFXV\n        KJt3bp3Ngn1vEYXwijGTa+FXz6GLHueJwF0I7ug34DgUkAFvAs8Hacr2DRYxL5RJ\n        XdNgj4Jd2/g6T9InmWT0hASljur+dJnzNiNCkbn9KbX7J/qK1IbR8y560yRmFsU+\n        NdCFTW7wY0Fb1fWJ+/KTsC4=\n        =J6gs\n        -----END PGP PUBLIC KEY BLOCK----- \npackages:\n  - moby-engine\n  - moby-cli\nruncmd:\n  - |\n      set -x\n      (\n        # Wait for docker daemon to start, otherwise installation of IoT Edge fails\n        while [ $(ps -ef | grep -v grep | grep docker | wc -l) -le 0 ]; do \n          sleep 3\n        done\n\n        # Install IoT Edge\n        sudo apt-get install -y aziot-edge\n        sudo cp /etc/aziot/config.toml.edge.template /etc/aziot/config.toml\n      ) &\n'

simVMMachineName="$prefix-simvm"
echo "simVMMachineName=$simVMMachineName"
simVMDeploymentOutput=$(az deployment group create --name SimVMDeployment --resource-group "$rg" --template-file "$vmDeploymentFilePath" --parameters \
vmMachineName="$simVMMachineName" networkName="$networkName" adminUserName="$adminUserName" adminUserSshPublicKey="$adminUserSshPublicKey" vmSize="$vmSize" customData="$simVMCustomData" \
 --query "properties.outputs.[vmMachineName.value, vmMachineIP.value, vmAdminUserName.value]" -o tsv) 

vmMachineName=${simVMDeploymentOutput[0]}
vmMachineIP=${simVMDeploymentOutput[1]}
vmAdminUserName=${simVMDeploymentOutput[2]}

echo "VM Name: $vmMachineName"
echo "VM IP: $vmMachineIP"
echo "VM Admin: $vmAdminUserName"




edgeVMDeploymentOutput=$(az deployment group create --name EdgeVMDeployment --resource-group "$rg" --template-file "$edgeVMDeploymentFilePath" --parameters \
networkRG="$networkRG" networkName="$networkName" prefix="$prefix" adminUserName="$adminUserName" adminUserSshPublicKey="$adminUserSshPublicKey" vmSize="$vmSize" \
 --query "properties.outputs.[vmMachineName.value, vmMachineIP.value, vmAdminUserName.value]" -o tsv) 

vmMachineName=${edgeVMDeploymentOutput[0]}
vmMachineIP=${edgeVMDeploymentOutput[1]}
vmAdminUserName=${edgeVMDeploymentOutput[1]}

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
