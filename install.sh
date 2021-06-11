#!/usr/bin/env bash

function show_help() {
   echo "Run this script to deploy Azure Digital Twins for Industrial IoT Solution."
   echo
   echo "Syntax: ./install.sh [-flag=value]"
   echo ""
   echo "List of optional flags:"
   echo "-h,--help              Print this help."
   echo "-p,--prefix            Prefix used for all new Azure Resource Groups created by this script. Default: first 5 characters of your user id."
   echo "-s,--subscription      Azure subscription ID to use to deploy resources. Default: use current subscription of Azure CLI."
   echo "-l,--location          Azure region to deploy resources to. Default: eastus2."
   echo "-v,--vmSize            Size of the Azure VMs to deploy. Default: Standard_B1ms."
   echo "-k,--ssh-keypath       Path to the SSH public key that should be used to connect to simulator and edge VMs. Default: ~/.ssh/id_rsa.pub"
   echo "-u,--adminuser         Name of the admin user to be created in simulator and edge VMs. Default: azureuser"
   echo "-d,--debug             Output debug information."
   echo
}

scriptStartedAt=$(date) 
location="eastus2"
adminUserName="azureuser"
vmSize="Standard_B1ms"
adminUserSshPublicKeyPath="$(readlink -f ~/.ssh/id_rsa.pub)"
debug=0

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
    -d|--debug)
      debug=1
      ;;
    -*|--*=) 
      echo "Error: Unsupported argument $1" >&2
      exit 1
      ;;

  esac
done

currentUser=$(az account show --query user.name --output tsv)

if [ -z $prefix ]; then
  prefix=${currentUser:0:5}
  prefix=${prefix//[^[:alnum:]]/}
fi

if [ ${#prefix} -gt 10 ]; then
  echo "prefix length should be less than 10 chars. prefix=$prefix"
  exit
fi

if [ -z $adminUserName ]; then
  adminUserName="azureuser"
fi


rg="$prefix-rg"
networkName="$prefix-network"
adminUserSshPublicKey=$(cat $adminUserSshPublicKeyPath)


if [ $debug == 1 ]; then
  echo "Parameters:"
  echo "   prefix=$prefix"
  echo "   rg=$rg"
  echo "   location=$location"
  echo "   adminUserName=$adminUserName"
  echo "   adminUserSshPublicKeyPath=$adminUserSshPublicKeyPath"
  echo "   vmSize=$vmSize"
  echo "   subscription=$subscription"
fi


if [ ! -z $subscription ]; then
  az account set --subscription $subscription
fi

subscriptionDetails=($(az account show --query '[id, name]' -o tsv))
subscription=${subscriptionDetails[0]}
subscriptionName=${subscriptionDetails[1]}

networkDeploymentFilePath="templates/networkdeploy.json"
vmDeploymentFilePath="templates/vmdeploy.json"
functionDeploymentFilePath="templates/functiondeploy.json"
otherServicesDeploymentFilePath="templates/otherservicesdeploy.json"

storageName="${prefix}storage" #storage name allows numbers and lower case letters only
configContainerName="${prefix}-config"
funcAppName="${prefix}asa2adt"
mapFileName="assetid2dtid.csv"

adtName="${prefix}assets"
adxName="${prefix}adx" #cluster name allows numbers and lower case letters only
adxDbName="iiotdb"
funcName="UpdateTelemetry"
adfName="${prefix}-syncassets"
adfPipelineName="SyncAssetModel"
asaName="${prefix}-hub2adt"
hubName="${prefix}hub"
asaConsumerGroup="asaconsumer"
adxConsumerGroup="adxconsumer"
edgeDeviceId="edge1"

if [ $debug == 1 ]; then
  echo ""
  echo "Variables:"
  echo "   SubscriptionId= ${subscription}" 
  echo "   SubscriptionName=${subscriptionName}"
  echo "   storageName=$storageName"
  echo "   configContainerName=$configContainerName"
  echo "   funcAppName=$funcAppName"
  echo "   mapFileName=$mapFileName"
  echo "   adtName=$adtName"
  echo "   adxName=$adxName"
  echo "   adxDbName=$adxDbName"
  echo "   funcName=$funcName"
  echo "   adfName=$adfName"
  echo "   adfPipelineName=$adfPipelineName"
  echo "   asaName=$asaName"
  echo "   hubName=$hubName"
  echo "   asaConsumerGroup=$asaConsumerGroup"
  echo "   adxConsumerGroup=$adxConsumerGroup"
  echo "   edgeDeviceId=$edgeDeviceId"
  echo "   networkDeploymentFilePath=$networkDeploymentFilePath"
  echo "   vmDeploymentFilePath=$vmDeploymentFilePath"
  echo "   functionDeploymentFilePath=$functionDeploymentFilePath"
  echo "   otherServicesDeploymentFilePath=$otherServicesDeploymentFilePath"
  echo "==============================================="
fi

echo ""

if ( $(az group exists -n "$rg") )
then
  echo "Resource group '$rg' already exists."
else
  echo "Creating resource group: $rg"
  az group create --name "$rg" --location "$location" --tags "ADT4IIOT" "prefix"="$prefix" "CreatedAt"="$(date --utc "+%Y-%m-%d %H:%M:%S")"  1> /dev/null
fi

echo "Deploying function app: $funcAppName"
functionDeploymentOutput=($(az deployment group create --name FunctionDeployment --resource-group "$rg" --template-file "$functionDeploymentFilePath" --parameters \
storageName="$storageName" configContainerName="$configContainerName" funcAppName="$funcAppName" mapFileName="$mapFileName" ))

echo "Deploying rest of platform services: ADT, ASA, ADF, ADX, IoT Hub"
otherServicesDeploymentOutput=($(az deployment group create --name OtherServicesDeployment --resource-group "$rg" --template-file "$otherServicesDeploymentFilePath" --parameters \
adtName="$adtName" adxName="$adxName" adxDbName="$adxDbName" funcAppName="$funcAppName" funcName="$funcName" adfName="$adfName" adfPipelineName="$adfPipelineName" \
asaName="$asaName" hubName="$hubName" asaConsumerGroup="$asaConsumerGroup" adxConsumerGroup="$adxConsumerGroup"))

echo "Starting ASA job: $asaName"
az stream-analytics job start --resource-group $rg --name $asaName

echo "Getting managed identity of ADF"
adfprincipalid=$(az datafactory show --resource-group $rg --factory-name $adfName --query identity.principalId -o tsv)
adftenantid=$(az datafactory show --resource-group $rg --factory-name $adfName --query identity.tenantId -o tsv)
adfappid=$(az ad sp show --id $adfprincipalid --query appId -o tsv)

echo "Getting managed identity of Azure Function"
funcprincipalid=$(az functionapp identity assign -g $rg -n $funcAppName --query principalId -o tsv)

echo "Assigning roles in ADT: $currentUser"
az dt role-assignment create --dt-name $adtName --assignee $currentUser     --role "Azure Digital Twins Data Owner" --output none
echo "Assigning roles in ADT: $adfName (ADF)"
az dt role-assignment create --dt-name $adtName --assignee $adfprincipalid  --role "Azure Digital Twins Data Owner" --output none
echo "Assigning roles in ADT: $funcAppName (Azure Function)"
az dt role-assignment create --dt-name $adtName --assignee $funcprincipalid --role "Azure Digital Twins Data Owner" --output none

echo "Get the timestamp. We will wait for 10 mins at least for these settings to propogate to ADT."
adtRoleAssignmentsGrantedAt=$(date) 

echo "Granting access to current user in ADX cluster"
az kusto cluster-principal-assignment create --cluster-name $adxName --principal-id $currentUser --principal-type "User" --role "AllDatabasesAdmin" --principal-assignment-name "kustoprincipal1" --resource-group $rg --output none

echo "Granting access to ADF in ADX database"
az kusto database add-principal --cluster-name $adxName --resource-group $rg --database-name $adxDbName --value name=$adfName app-id=$adfappid type="App" role="Admin" --output none

echo "Setting ADT_SERVICE_URL for Azure Function '$funcAppName'"
adthostname="https://"$(az dt show -n $adtName --query 'hostName' -o tsv)
az functionapp config appsettings set -g $rg -n $funcAppName --settings "ADT_SERVICE_URL=$adthostname" --output none

echo "Copying map file to storage container"
tomorrow=$(date --date "tomorrow" +%Y-%m-%d)
storageConnStr=$(az storage account show-connection-string --name $storageName --resource-group $rg  --query connectionString --output tsv)
storageSasToken=$(az storage container generate-sas --connection-string $storageConnStr --name $configContainerName --permissions acdlrw --expiry $tomorrow)
az storage blob upload --connection-string $storageConnStr --container-name $configContainerName --name $mapFileName --file "assetmodel/$mapFileName" --sas-token $storageSasToken --output none


if [ -z $(az iot hub device-identity list --hub-name $hubName --resource-group $rg --query "[?deviceId=='$edgeDeviceId'].deviceId" --output tsv) ]; then
  echo "Creating device in IoT Hub"
  az iot hub device-identity create --hub-name $hubName --resource-group $rg --device-id $edgeDeviceId  --edge-enabled --output none
fi

echo "Acquiring device connection string"
edgeDeviceConnectionString=$(az iot hub device-identity connection-string show --device-id $edgeDeviceId --hub-name $hubName  --resource-group $rg --query 'connectionString' -o tsv)


if [ ! -z  $(az network vnet list --resource-group "$rg" --query "[?name=='$networkName'].id" --output tsv) ] 
then
  echo "Network $networkName already exists."
else
  networkDeploymentOutput=$(az deployment group create --name NetworkDeployment --resource-group "$rg" --template-file "$networkDeploymentFilePath" --parameters \
  networkName="$networkName" ) 

  echo "Created network $networkName."
  echo "======================================"
fi

simVMMachineName="$prefix-simvm"

if [ ! -z  $(az vm list --resource-group "$rg" --query "[?name=='$simVMMachineName'].id" --output tsv) ] 
then
  echo "VM $simVMMachineName already exists."
else
  simVMDeploymentOutput=($(az deployment group create --name SimVMDeployment --resource-group "$rg" --template-file "$vmDeploymentFilePath" --parameters \
  vmType="simulator" vmMachineName="$simVMMachineName" networkName="$networkName" adminUserName="$adminUserName" adminUserSshPublicKey="$adminUserSshPublicKey" vmSize="$vmSize" \
  --query "properties.outputs.[vmMachineName.value, vmMachineFqdn.value, vmAdminUserName.value]" -o tsv)) 

  vmMachineName=${simVMDeploymentOutput[0]}
  vmMachineFqdn=${simVMDeploymentOutput[1]}
  vmAdminUserName=${simVMDeploymentOutput[2]}

    if [ $debug == 1 ]; then
      echo "Simulator VM Name : $vmMachineName"
      echo "Simulator VM Fqdn : $vmMachineFqdn"
      echo "Simulator VM Admin: $vmAdminUserName"
    fi  
  echo "Simulator VM SSH  : ssh ${vmAdminUserName}@${vmMachineFqdn}"
fi


edgeVMMachineName="$prefix-edgevm"

if [ ! -z  $(az vm list --resource-group "$rg" --query "[?name=='$edgeVMMachineName'].id" --output tsv) ] 
then
  echo "VM $edgeVMMachineName already exists."
else
  edgeVMDeploymentOutput=($(az deployment group create --name EdgeVMDeployment --resource-group "$rg" --template-file "$vmDeploymentFilePath" --parameters \
  vmType="edge" vmMachineName="$edgeVMMachineName" networkName="$networkName" adminUserName="$adminUserName" adminUserSshPublicKey="$adminUserSshPublicKey" vmSize="$vmSize" edgeDeviceConnectionString="$edgeDeviceConnectionString" \
  --query "properties.outputs.[vmMachineName.value, vmMachineFqdn.value, vmAdminUserName.value]" -o tsv)) 

  vmMachineName=${edgeVMDeploymentOutput[0]}
  vmMachineFqdn=${edgeVMDeploymentOutput[1]}
  vmAdminUserName=${edgeVMDeploymentOutput[2]}

  if [ $debug == 1 ]; then
    echo "Edge VM Name : $vmMachineName"
    echo "Edge VM Fqdn : $vmMachineFqdn"
    echo "Edge VM Admin: $vmAdminUserName"
  fi

  echo "Edge VM SSH  : ssh ${vmAdminUserName}@${vmMachineFqdn}"
fi

deploymentManifestTemplateFile="templates/edgeDeploymentManifest.json"
echo "Running set modules on the edge server using '$deploymentManifestTemplateFile'"
az iot edge set-modules --device-id $edgeDeviceId --hub-name $hubName --content $deploymentManifestTemplateFile --output none

hubresourceid=$(az iot hub show --name $hubName --resource-group $rg --query "id" --output tsv)

remainingSeconds=$(( 600-$(( $(date +%s)-$(date +%s -d "$adtRoleAssignmentsGrantedAt") )) ))
echo "Waiting for $remainingSeconds seconds for security settings to propogate"
sleep $remainingSeconds
echo "Continuing..."

adtModelDefinitionsFile="assetmodel/assetmodel.json"
echo "Uploading ADT model from file '$adtModelDefinitionsFile'"
az dt model create --dt-name $adtName --resource-group $rg --models $adtModelDefinitionsFile --output none

echo "======================================"
echo "Below commands help you to stop compute resources and minimize consumption"
echo "when you dont use the solution and start them again when you need to use them. "
echo ""
echo "Commands to start compute resources."
echo "az kusto cluster start --resource-group $rg --name $adxName --no-wait"
echo "az vm start --resource-group $rg  -n $edgeVMMachineName"
echo "az vm start --resource-group $rg  -n $simVMMachineName"
echo "az stream-analytics job start --resource-group $rg --name $asaName"
echo "az functionapp start --resource-group $rg --name $funcAppName"
echo ""
echo "======================================"
echo ""
echo "Commands to stop compute resources"
echo "az kusto cluster stop --resource-group $rg --name $adxName --no-wait"
echo "az vm deallocate --resource-group $rg  -n $edgeVMMachineName"
echo "az vm deallocate --resource-group $rg  -n $simVMMachineName"
echo "az stream-analytics job stop --resource-group $rg --name $asaName"
echo "az functionapp stop --resource-group $rg --name $funcAppName"
echo ""
echo "======================================"
echo ""
echo ""
scriptDurationInSecs=$(( $(date +%s)-$(date +%s -d "$scriptStartedAt") ))
echo "Script finished in $(( $scriptDurationInSecs/60 )) minute(s) $(( $scriptDurationInSecs%60 )) sec(s)."
echo ""
echo ""
echo "At this point, ADX database structure has to be created before initiating data ingestion. "
echo ""
echo "Goto ADX resource in Azure portal now and execute commands as described in readme section 'Post install configuration': https://github.com/onderyildirim/adt4iiot#post-install-configuration"
echo ""
echo "After you complete this step, return here and run following commands from this window"
echo ""
echo "=== Create data ingestion pipeline in ADX"
echo "az kusto data-connection iot-hub create --cluster-name $adxName --data-connection-name $hubName --database-name $adxDbName --resource-group $rg --consumer-group $adxConsumerGroup --data-format JSON --iot-hub-resource-id \"$hubresourceid\" --location $location --event-system-properties \"iothub-connection-device-id\" --mapping-rule-name "iiot_raw_mapping" --shared-access-policy-name \"iothubowner\" --table-name \"iiot_raw\" --data-format MULTIJSON"
echo ""
echo "=== Initialize AssetModel table in ADX by running pipeline"
echo "az datafactory pipeline create-run --factory-name $adfName --name $adfPipelineName --resource-group $rg --output none"
echo ""
echo ""
echo ""



