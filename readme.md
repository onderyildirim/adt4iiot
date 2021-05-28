 

$env:AZURE_CORE_NO_COLOR=$true

$rg="ccadt"

$hubname="ccadthub"

$hubpolicy="iothubowner"

$hubpolicykey=""

$dtconsumergroup="asaconsumer"

$adxconsumergroup="adxconsumer"

$asaname="asahub2adt"

$asainput=$hubname

$asaoutput ="adt"

$functionapp="AsaToAdt"

$telemetryfunctionname ="UpdateADT"

$storage=$rg +"storage"

$location="eastus2"

$dtname=$rg

$adtUpdateFreqInSeconds=60

$adxname=$rg+"adx"

$adxdb=$rg+"db"

$adxhubdataconnection="iothub"

$adminuser="ondery@microsoft.com"

$adf=$rg+"SyncAssetModel"

$adxconnection="adxiiot"

$adtmapfilecontainer="adt4iiot-config"

$adtmapfilepath="assetid2dtid.csv"

 

az group create --name $rg --location $location

 

\#create ADT instance

az provider register --namespace 'Microsoft.DigitalTwins'

az extension add --upgrade --name azure-iot

 

az dt create --dt-name $dtname --resource-group $rg --location $location

az dt role-assignment create --dt-name $dtname --assignee $adminuser --role "Azure Digital Twins Data Owner"

 

az dt show --dt-name $dtname

 

\#import model

az dt model create --dt-name $dtname --models assetmodel.json

 

\#import twins

\#use ADT explorer to import twingraph.xlsx

 

az iot hub create --name $hubname --resource-group $rg --sku S1

az iot hub consumer-group create --name $hubname --resource-group $rg --name $dtconsumergroup

az iot hub consumer-group create --name $hubname --resource-group $rg --name $adxconsumergroup

$hubpolicykey=az iot hub policy show --hub-name $hubname --name $hubpolicy --query primaryKey --output tsv

 

$inputSerializationJson=' {

   "type": "Json",

   "properties": {

​     "encoding": "UTF8"

   }

 }'

 

$inputDatasourceJson='{{

   "type": "Microsoft.Devices/IotHubs",

   "properties": {{

​     "iotHubNamespace": "{0}",

​     "sharedAccessPolicyName": "{1}",

​     "sharedAccessPolicyKey": "{2}",

​     "consumerGroupName": "{3}",

​     "endpoint": "messages/events"

   }}

}}' -f $hubname, $hubpolicy, $hubpolicykey, $dtconsumergroup

 

 

 

$outputSerializationJson='{

   "type": "Json",

   "properties": {

​     "encoding": "UTF8",

​     "format": "Array"

   }

 }'

 

$outputDatasourceJson='{{

   "type": "Microsoft.AzureFunction",

   "properties": {{

​     "functionAppName": "{0}",

​     "functionName": "{1}",

​     "apiKey": null

   }}

}}' -f $functionapp, $telemetryfunctionname 

 

$inputSerializationJsonFile=$env:TEMP + "\inputSerialization.json"

$inputSerializationJson | Out-File -FilePath $inputSerializationJsonFile

 

$inputDatasourceJsonFile=$env:TEMP + "\inputDatasource.json"

$inputDatasourceJson | Out-File -FilePath $inputDatasourceJsonFile

 

$outputSerializationJsonFile=$env:TEMP + "\outputSerialization.json"

$outputSerializationJson | Out-File -FilePath $outputSerializationJsonFile

 

$outputDatasourceJsonFile=$env:TEMP + "\outputDatasource.json"

$outputDatasourceJson | Out-File -FilePath $outputDatasourceJsonFile

 

az stream-analytics job create --resource-group $rg --name $asaname --location $location 

 

\#goto azure portal and set compatibility-level 1.2 for ASA job you created. CLI does not support compatibility level setting

 

\#after running below command go and set iot hub shared access key for ASA input from portal. It does not seem go get shared access key from datasource.json file

az stream-analytics input create --resource-group $rg --job-name $asaname --name $asainput --type Stream --datasource $inputDatasourceJsonFile --serialization $inputSerializationJsonFile

 

\#create storage if needed

az storage account create --name $storage --location $location --resource-group $rg --sku Standard_LRS

 

 

\#create azure function "asa2adt", use windows version

\#$functionappplan=$functionapp+"plan"

\#az functionapp plan create --name $functionappplan --resource-group $rg --location $location--sku B1

 

\#az functionapp create --resource-group $rg --runtime dotnet --functions-version 3 --os-type linux --consumption-plan-location $location --name $functionapp --storage-account $storage

\#az functionapp create --resource-group $rg --runtime dotnet --functions-version 3 --os-type windows --consumption-plan-location $location --name $functionapp --storage-account $storage --plan $functionappplan

az functionapp create --resource-group $rg --runtime dotnet --functions-version 3 --os-type windows --consumption-plan-location $location --name $functionapp --storage-account $storage 

 

 

az functionapp start --resource-group $rg --name $functionapp

 

$adthostname = "https://" + $(az dt show -n $dtname --query 'hostName' -o tsv)

az functionapp config appsettings set -g $rg -n $functionapp --settings "ADT_SERVICE_URL=$adthostname"

 

$storagekey=az storage account keys list --account-name $storage --query [0].value --output tsv

az storage container create --name $adtmapfilecontainer --account-key "$storagekey" --account-name $storage --auth-mode key

 

az storage blob upload --file "assetmodel\twinidmap.csv" --name $adtmapfilepath --container-name $adtmapfilecontainer --account-key "$storagekey" --account-name $storage --auth-mode key

 

$storageconnectionstring=az storage account show-connection-string --name $storage --resource-group $rg --query connectionString --output tsv

 

az functionapp config appsettings set -g $rg -n $functionapp --settings "MAPFILE_BLOB_CONNECTION_STRING=$storageconnectionstring"

az functionapp config appsettings set -g $rg -n $functionapp --settings "MAPFILE_BLOB_CONTAINERNAME=$adtmapfilecontainer"

az functionapp config appsettings set -g $rg -n $functionapp --settings "MAPFILE_PATH=$adtmapfilepath"

az functionapp config appsettings set -g $rg -n $functionapp --settings "MAPFILE_SEPARATOR=,"

 

 

 

\#deploy azure function from "C:\Projects\asa2adt"

\#right click on project > Publish

\#Click "+New" to create a new publish profile for the function app above

 

\#assign the function app's identity to the Azure Digital Twins Data Owner role for Azure Digital Twins instance

$principalID = $(az functionapp identity assign -g $rg -n $functionapp --query principalId)

az dt role-assignment create --dt-name $dtname --assignee $principalID --role "Azure Digital Twins Data Owner"

 

 

\#if defining function output for ASA raises error , do it from portal

\#[az stream-analytics output create not working for 'Microsoft.AzureFunction' · Issue #2790 · Azure/azure-cli-extensions (github.com)](https://github.com/Azure/azure-cli-extensions/issues/2790)

az stream-analytics output create --resource-group $rg --job-name $asaname --name $asaoutput --datasource $outputDatasourceJsonFile --serialization $outputSerializationJsonFile

 

 

 

$query ='WITH LastInWindow AS

(

  SELECT 

​    TagId, MAX([Timestamp]) AS LastEventTime

  FROM 

​    {2} TIMESTAMP BY [Timestamp]

  GROUP BY 

​    TagId, TumblingWindow(second, {0})

)

SELECT 

  hub.TagId,

  hub.[Timestamp],

  hub.Value

INTO {1}

FROM

  {2} as hub TIMESTAMP BY [Timestamp] 

  INNER JOIN LastInWindow

  ON DATEDIFF(second, hub, LastInWindow) BETWEEN 0 AND 60

  AND hub.[Timestamp] = LastInWindow.LastEventTime

  AND hub.TagId = LastInWindow.TagId' -f $adtUpdateFreqInSeconds, $asaoutput, $asainput

 

az stream-analytics transformation create --resource-group $rg --job-name $asaname --name Transformation --streaming-units "1" --transformation-query $query.replace("`n"," ")

 

\#start the ASA job

az stream-analytics job start --resource-group $rg --name $asaname --output-start-mode JobStartTime

 

 

\#create ADT model from assetmodel\AssetModel.json

\#upload twin graph by uploading assetmodel\twingraph.xlsx

 

\#run to monitor twin updates

az dt twin show -n $dtname --twin-id fr-line2-a3 --query "[\""`$metadata\"".ITEM_COUNT_GOOD.lastUpdateTime, ITEM_COUNT_GOOD]"

 

 

\#ADX cluster

az extension add -n kusto

az kusto cluster create --cluster-name $adxname --sku name="Dev(No SLA)_Standard_E2a_v4" tier="Basic" capacity=1 --resource-group $rg --location $location

 

az kusto cluster-principal-assignment create --cluster-name $adxname --principal-id $adminuser --principal-type "User" --role "AllDatabasesAdmin" --principal-assignment-name $adminuser --resource-group $rg

 

az kusto database create --cluster-name $adxname --resource-group $rg --database-name $adxdb --read-write-database soft-delete-period=P365D hot-cache-period=P1D location=$location

 

\#run following from azure portal kusto query interface

.execute database script <|

.create-merge table iiot_raw (rawdata:dynamic)

.alter-merge table iiot_raw policy retention softdelete = 0d

.create-or-alter table iiot_raw ingestion json mapping 'iiot_raw_mapping' '[{"column":"rawdata","path":"$","datatype":"dynamic"}]'

.create-merge table iiot (Timestamp: datetime, TagId: string, AssetId: string, Tag:string, Value: double, DeviceId:string)

.create-or-alter function parseRawData()

{

iiot_raw

| extend Timestamp = todatetime(rawdata.Timestamp)

| extend TagId = tostring(rawdata.TagId)

| extend AssetId = tostring(rawdata.TagId)

| extend Tag = tostring(rawdata.TagId)

| extend Value = todouble(rawdata.Value)

| extend DeviceId = tostring(rawdata.['iothub-connection-device-id'])

| project Timestamp, TagId, AssetId, Tag, Value, DeviceId

}

.alter table iiot policy update @'[{"IsEnabled": true, "Source": "iiot_raw", "Query": "parseRawData()", "IsTransactional": true, "PropagateIngestionProperties": true}]'

 

\#run following from azure portal kusto query interface

.enable plugin azure_digital_twins_query_request

 

\#create kusto data source

$hubresourceid=(az iot hub show --name $hubname --resource-group $rg --query "id" --output tsv)

az kusto data-connection iot-hub create --cluster-name $adxname --data-connection-name $adxhubdataconnection --database-name $adxdb --resource-group $rg --consumer-group $adxconsumergroup --data-format JSON --iot-hub-resource-id $hubresourceid --location $location --event-system-properties "iothub-connection-device-id" --mapping-rule-name "iiot_raw_mapping" --shared-access-policy-name "iothubowner" --table-name "iiot_raw"

 

 

 

az datafactory factory create --resource-group $rg --factory-name $adf

 

\#get managed identity of adf- cli

$adfprincipalid=az datafactory factory show --resource-group $rg --factory-name $adf --query identity.principalId -o tsv

$adftenantid=az datafactory factory show --resource-group $rg --factory-name $adf --query identity.tenantId -o tsv

$adfappid=az ad sp show --id $adfprincipalid --query appId -o tsv

 

\#give ADF access to ADX

az kusto database add-principal --cluster-name $adxname --resource-group $rg --database-name $adxdb --value name=$adf app-id=$adfappid type="App" role="Admin"

 

az kusto database add-principal --cluster-name $adxname --resource-group $rg --database-name $adxdb --value name=$adf+"app" app-id="ae31e1e3-1561-43fb-91c0-2c68cf2d2dca" type="App" role="Admin"

 

 

 

\#below code does not work so create linked service manually

$adxendpoint=az kusto cluster show --cluster-name $adxname --resource-group $rg --query "uri" -o tsv

$props = @{

"type" = "AzureDataExplorer"

"typeProperties" = @{

"endpoint" = "$adxendpoint"

"database" = "$adxdb"

}

}

$propsJson = $props | ConvertTo-Json -Compress 

$propsJson = $propsJson -Replace '"', '\"'

 

az datafactory linked-service create --factory-name $adf --linked-service-name $adxconnection --resource-group $rg --properties "$propsJson"

  

\#goto ADF create a new pipeline and add below as ADX command (Pipelines -> SyncAssetModel -> SyncADTCommand -> Command -> Command)

 

.execute database script <|
 .enable plugin azure_digital_twins_query_request

.set-or-replace AssetModel <|
 evaluate azure_digital_twins_query_request("https://adtAssets.api.eus2.digitaltwins.azure.net", "SELECT asset, unit, cell, area, site, enterprise FROM DIGITALTWINS enterprise JOIN site RELATED enterprise.rel_has_sites JOIN area RELATED site.rel_has_areas JOIN cell RELATED area.rel_has_cells JOIN unit RELATED cell.rel_has_units JOIN asset RELATED unit.rel_has_assets WHERE enterprise.$dtId = 'contoso'")
  | project AssetId=tostring(asset.TagId), 
       DtId=tostring(asset.$dtId), 
       Asset=tostring(asset.Name), 
       AssetName=tostring(asset.AssetName), 
       YearDeployed=tostring(asset.YearDeployed), 
       AssetModel=tostring(asset.AssetModel), 
       Capacity=tostring(asset.Capacity), 
       Unit=tostring(unit.Name), 
       Cell=tostring(cell.Name), 
       Area=tostring(area.Name), 
       Site=tostring(site.Name), 
       Enterprise=tostring(enterprise.Name), 
       asset_data=asset, 
       unit_data=unit, 
       cell_data=cell, 
       area_data=area, 
       site_data=site, 
       enterprise_data=enterprise

 

 

 

az dt role-assignment create --dt-name $dtname --assignee $adfprincipalid --role "Azure Digital Twins Data Owner"

 

 