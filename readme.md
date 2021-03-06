# Azure Digital Twins for Industrial IoT
###### 15 mins to review documentation, 30 mins for script to run

This sample shows how to use Azure Digital Twins in an industrial environment.

![Azure Digital Twins for Industrial IoT Solution Architecture](images/arch.png)

<br>
<br>

## Pre-requisites

- An **Azure account with a valid subscription**. 

- **[Azure CLI](https://docs.microsoft.com/en-us/cli/azure/?view=azure-cli-latest) with CLI extensions below** installed. We'll use a bash terminal from the [Azure Cloud Shell](https://docs.microsoft.com/en-us/azure/cloud-shell/overview) during install for which only a browser is needed.

  1. Open the [Azure Cloud Shell](https://shell.azure.com/) from your browser

  2. If you're using [Azure Cloud Shell](https://shell.azure.com/) for the first time, you'll be prompted to select a subscription to create a storage account and a Microsoft Azure Files share. Select Create storage to create a storage account for your Cloud Shell session information. This storage account is separate from resources used in this tutorial.

  3. Azure CLI extensions
     - Verify if required extensions is already installed with at least versions below:
     
        | Extension   | Version |
        | ----------- | ------- |
        | azure-iot   | 0.10.13 |
        | datafactory | 0.3.0   |
        | kusto       | 0.3.0   |
        <br>
     - Run following to get versions

       ```bash
       az --version
       ```
        <br>
     - If not yet installed or lower version, run following commands to install/upgrade:
       ```bash
       az extension add --upgrade --name azure-iot
       az extension add --upgrade --name datafactory
       az extension add --upgrade --name kusto
       ```

  4. Verify that your are using the right subscription. You can also give subscription as a parameter to `./install.sh`

     ```bash
     az account show
     ```
<br>


## Deployment

### Download sources

First we need to prepare the environment.

From the [Azure Cloud Shell](https://shell.azure.com/):

- Download the scripts:

  ```bash
  git clone https://github.com/onderyildirim/adt4iiot.git
  ```

- Give execution permissions to these script:

  ```bash
  cd ./adt4iiot
  find  -name '*.sh' -print0 | xargs -0 chmod +x
  ```

- Unless you already have a SSH key pair, create one to connect to simulator and edge machines (To learn more about SSH key pairs, read [this documentation](https://docs.microsoft.com/azure/virtual-machines/linux/mac-create-ssh-keys)):

  ```bash
  ssh-keygen -m PEM -t rsa -b 4096
  ```
### Run installation script
- Run following to deploy Azure Digital Twins for Industrial IoT sample (~30 minutes):

  ```bash
  ./install.sh
  ```
  By default it will use first 5 letters of your user name as "prefix" and create all resources in to a resource group named "\<prefix\>-rg". You may also give any prefix you want from the command line parameters 
  ```bash
  ./install.sh --prefix adt4iiot
  ```
  The full syntax for install.sh is below
  ```bash
  Syntax: ./install.sh [-flag=value]
  
  List of optional flags:
  -h,--help              Print this help.
  -s,--subscription      Azure subscription ID to use to deploy resources. 
                              Default: use current subscription of Azure CLI.
  -l,--location          Azure region to deploy resources to. Default: eastus2.
  -p,--prefix            Prefix used for all new Azure Resource Groups created by this script. 
                              Default: first 5 characters of your user id.
  -v,--vmSize            Size of the Azure VMs to deploy. Default: Standard_B1ms.
  -k,--ssh-keypath       Path to the SSH public key that should be used to connect to simulator and edge VMs. 
                              Default: ~/.ssh/id_rsa.pub
  -u,--adminuser         Name of the admin user to be created in simulator and edge VMs. Default: azureuser
  ```
- At this point, ADX database structure has to be created before initiating data ingestion. Before you move on make sure you copied two commands given below to a safe place.

  ```bash
  az kusto data-connection iot-hub create --cluster-name <prefix>adx --data-connection-name <prefix>hub --database-name "iiotdb" --resource-group <prefix>-rg --consumer-group adxconsumer --data-format JSON --iot-hub-resource-id <iotHubResourceId> --location <azureDatacenterLocation> --event-system-properties "iothub-connection-device-id" --mapping-rule-name "iiot_raw_mapping" --shared-access-policy-name "iothubowner" --table-name "iiot_raw"
  ```

  ```bash
  az datafactory pipeline create-run --factory-name "<prefix>-syncassets" --name "SyncAssetModel" --resource-group <prefix>-rg --output none
  ```

### Post install configuration
#### Create Data Explorer schema
- After the script finishes, goto Azure Data Explorer resource created in Azure portal, the ADX instance is named as "\<prefix\>adx" 
- Select "Query" in the left blade
- Make sure "*iiotdb*" database is selected on the left
- Run following Data Explorer script in query window to create database schema
  ```KQL
  .execute database script <|
  .create-merge table iiot_raw  (rawdata:dynamic)
  .alter-merge table iiot_raw policy retention softdelete = 0d
  .create-or-alter table iiot_raw ingestion json mapping 'iiot_raw_mapping' '[{"column":"rawdata","path":"$","datatype":"dynamic"}]'
  .create-merge table iiot (Timestamp: datetime, TagId: string, AssetId: string, Tag:string, Value: double)
  .create-or-alter function parseRawData()
  {
  iiot_raw
  | extend Timestamp =  todatetime(rawdata.Timestamp)
  | extend TagId = tostring(rawdata.TagId)
  | extend AssetId = substring(rawdata.TagId, 0, indexof(rawdata.TagId, "."))
  | extend Tag = substring(rawdata.TagId, indexof(rawdata.TagId, ".")+1)
  | extend Value = todouble(rawdata.Value)
  | project Timestamp, TagId, AssetId, Tag, Value
  }
  .alter table iiot policy update @'[{"IsEnabled": true, "Source": "iiot_raw", "Query": "parseRawData()", "IsTransactional": true, "PropagateIngestionProperties": true}]'
  ```
- Run following in the same query windows to enable Azure Digital Twins plugin
  ```KQL
  .enable plugin azure_digital_twins_query_request
  ```
#### Upload Azure Digital Twins graph
- Download `twingraph.xlsx` file from github repo to your local drive. Direct link to file is below
      https://github.com/onderyildirim/adt4iiot/blob/main/assetmodel/twingraph.xlsx
- Goto Azure Digital Twins instance in Azure portal and click on "Open Azure Digital Twins Explorer" in "Overview" blade.
- Click on "Twin Graph" and then "Import Graph"<br>
  ![Upload Azure Digital Twins graph - Step 1](images/adtimport1.png)
- Select `twingraph.xlsx` file you downloaded above and select upload
- Click *Save* button upper right<br>
  ![Upload Azure Digital Twins graph - Step 2](images/adtimport2.png)
- You should see below if upload is succesfull<br>
  ![Upload Azure Digital Twins graph - Step 3](images/adtimport3.png)

#### Complete install script commands
- Go back to Azure shell window where you ran "install.sh" and run commands given at the end of install script. They should be similar to below
  ```bash
  az kusto data-connection iot-hub create --cluster-name <dataExplorerClusterName> --data-connection-name <iotHubName> --database-name <dataExplorerDBName> --resource-group <resourceGroupName> --consumer-group adxconsumer --data-format JSON --iot-hub-resource-id <iotHubResourceId> --location <azureDatacenterLocation> --mapping-rule-name "iiot_raw_mapping" --shared-access-policy-name "iothubowner" --table-name "iiot_raw"
  ```

  ```bash
  az datafactory pipeline create-run --factory-name <dataFactoryName> --name <dataFactoryPipelineName> --resource-group <resourceGroupName> --output none
  ```

If your connection expires in Azure Shell, you can just open a new connection and run commands there.


### Optional configuration items
#### Activate Azure Data Factory trigger
Install script creates a trigger for data factory pipeline to transfer data from ADT into ADX. The trigger however is left disabled. If you would like it to run periodically, follow steps below 
- Go to Azure Data Factory instance (named \<prefix\>-syncassets) in Azure Portal
- Click on "Author & Monitor"
- Click on "Manage" on the toolbat at the left
- Click on "Triggers" under "Author"
- Click "DailyTrigger"
- Select "Yes" under "Activated"
- Optionally set "Recurence" to something other than default (24 hours)

#### Set root twin id in Azure Data Factory
When we query data from Azure Digital Twins graph we need to set the root twin. If you imported the default `twingraph.xlsx` file, the root entity is the twin id `contoso`. If you would like to import your own twin structure, also remember to modify root object in query within the ADF pipeline: 
- Go to Azure Data Factory instance (named \<prefix\>-syncassets) in Azure Portal
- Click on "Author & Monitor"
- Click on "Author" on the toolbat at the left
- Click on "SyncAssetModel" under "Pipeline"
- Click "SyncAssetModelCommand" in the editor pane
- Select "Command" tab at the bottom pane
- Change **root twin id** to match the root twin of your hierarchy

    `.set-or-replace AssetModel <|` <br>
    `evaluate azure_digital_twins_query_request(` <br>
        `"https://<ADT instance>.digitaltwins.azure.net",`  <br>
        `"SELECT asset, unit, cell, area, site, enterprise`  <br>
        `FROM DIGITALTWINS enterprise JOIN site  RELATED enterprise.rel_has_sites`  <br>
                                     `JOIN area  RELATED site.rel_has_areas`  <br>
                                     `JOIN cell  RELATED area.rel_has_cells`  <br>
                                     `JOIN unit  RELATED cell.rel_has_units`  <br>
                                     `JOIN asset RELATED unit.rel_has_assets`  <br>
        `WHERE enterprise.$dtId = '`**contoso**`'")` <br>
      `| project AssetId=tostring(asset.TagId),` <br>
      `          DtId=tostring(asset.$dtId),` <br>
      `          Asset=tostring(asset.Name),` <br>
      `          AssetName=tostring(asset.AssetName),` <br>
      `          YearDeployed=tostring(asset.YearDeployed),` <br>
      `          AssetModel=tostring(asset.AssetModel),` <br>
      `          Capacity=tostring(asset.Capacity),` <br>
      `          Unit=tostring(unit.Name),` <br>
      `          Cell=tostring(cell.Name),` <br>
      `          Area=tostring(area.Name),` <br>
      `          Site=tostring(site.Name),` <br>
      `          Enterprise=tostring(enterprise.Name),` <br>
      `          asset_data=asset,` <br>
      `          unit_data=unit,` <br>
      `          cell_data=cell,` <br>
      `          area_data=area,` <br>
      `          site_data=site,` <br>
      `          enterprise_data=enterprise`


### Deployment complete

At this point your deployment is complete. Wait for 5-10 minutes for data to accumulate and continue to verify your deployment by reviewing data.

## Verify Deployment

Azure Digital Twins for Industrial IoT solution simulates industrial IoT data points and uses them to

- Update properties in the respective digital twin instance
- Save IoT data into Azure Data Explorer

Therefore to verify proper deployment you need to see Digital Twins properties updated and you need to be able to contextualize IoT data with Asset Model data.

### Monitor Digital Twin Updates

You an use below commands from Azure Shell window to monitor how property values change. Note that you should see a change approximately every minute.

- Query twin in the sample ($dtid="fr-line2-a3")

  ```bash
  az dt twin show -n <prefix>assets --twin-id fr-line2-a3 --query "[{TwinId: \"\$dtId\", PropertyName: 'ITEM_COUNT_GOOD', LastUpdated: \"\$metadata\".ITEM_COUNT_GOOD.lastUpdateTime, Value: ITEM_COUNT_GOOD}, {TwinId: \"\$dtId\", PropertyName: 'ITEM_COUNT_BAD', LastUpdated: \"\$metadata\".ITEM_COUNT_BAD.lastUpdateTime, Value: ITEM_COUNT_BAD}, {TwinId: \"\$dtId\", PropertyName: 'STATUS', LastUpdated: \"\$metadata\".STATUS.lastUpdateTime, Value: STATUS}]" --output table
  ```

- Query twin in the sample ($dtid="ca-line1-a1")

  ```bash
  az dt twin show -n <prefix>assets --twin-id ca-line1-a1 --query "[{TwinId: \"\$dtId\", PropertyName: 'ITEM_COUNT_GOOD', LastUpdated: \"\$metadata\".ITEM_COUNT_GOOD.lastUpdateTime, Value: ITEM_COUNT_GOOD}, {TwinId: \"\$dtId\", PropertyName: 'ITEM_COUNT_BAD', LastUpdated: \"\$metadata\".ITEM_COUNT_BAD.lastUpdateTime, Value: ITEM_COUNT_BAD}, {TwinId: \"\$dtId\", PropertyName: 'STATUS', LastUpdated: \"\$metadata\".STATUS.lastUpdateTime, Value: STATUS}]" --output table
  ```

### Contexualize Industrial IoT Data with Asset Model data from Azure Digital Twins 
- Go to Azure Data Explorer resource created in Azure portal, the ADX instance is named as "\<prefix\>adx" 
- Select "Query" in the left blade
- Make sure "iiotdb" database is selected on the left
- Run following Data Explorer script in query window to filter IoT data by very attributes contained in Azure Digital Twins

  ```bash
  iiot
  | where Timestamp between (ago(1d) .. ago(0h))
  | join kind=leftouter AssetModel on $left.AssetId == $right.AssetId
  | where Site == "Canada"
  | where AssetDescription == "45-Preprocess LINE 2B "
  | where AssetModel == "MKR132 "
  ```


## Azure Costs

The base solution consumes **$4.12** Azure credits per day when running. If you stop compute resources by using commands below the cost drops to **$0.13** per day. For details on Azure costs of this solution, see the [Azure Pricing Estimate](https://azure.com/e/b5e46763e0c9463eab584280419bd26e).

Also note that you can minimize costs but shutting down compute resources when you are not using the solution. Commands to shutdown and start compute resources on demand are given at the end of install script and they are similar to below

- Commands to start compute resources.

  ```bash
  az kusto cluster start --resource-group "<prefix>-rg" --name "<prefix>adx" --no-wait
  az vm start --resource-group "<prefix>-rg"  -n "<prefix>-simvm"
  az vm start --resource-group "<prefix>-rg"  -n "<prefix>-edgevm"
  az stream-analytics job start --resource-group "<prefix>-rg" --name "<prefix>-hub2adt"
  az functionapp start --resource-group "<prefix>-rg" --name "<prefix>asa2adt"
  ```
- Commands to stop compute resources.

  ```bash
  az kusto cluster stop --resource-group "<prefix>-rg" --name "<prefix>adx" --no-wait
  az vm deallocate --resource-group "<prefix>-rg"  -n "<prefix>-simvm"
  az vm deallocate --resource-group "<prefix>-rg"  -n "<prefix>-edgevm"
  az stream-analytics job stop --resource-group "<prefix>-rg" --name "<prefix>-hub2adt"
  az functionapp stop --resource-group "<prefix>-rg" --name "<prefix>asa2adt"
  ```


## Cleanup

If you want to remove the solution you may just delete the resource group created, from Azure Portal or running the command below

  ```bash
  az group delete --name <prefix>-rg
  ```



## Contributing

The project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
