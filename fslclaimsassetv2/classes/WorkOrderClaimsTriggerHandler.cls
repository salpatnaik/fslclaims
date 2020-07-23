public class WorkOrderClaimsTriggerHandler {
    
    public static Boolean isRecursion = false;
    public static Map<Id,Map<String,Asset>> woAssetProductIdMap = new Map<Id,Map<String,Asset>>();
    public static Map<Id,Map<String,Asset>> woAssetSerialNumberMap = new Map<Id,Map<String,Asset>>();
    
    public static void afterUpdate(Map<Id,WorkOrder> newMap,Map<Id,WorkOrder> oldMap){
        if(!isRecursion){
            createClaims(newMap,oldMap);
            createServiceCharge(newMap,oldMap);
        }
        isRecursion=true;
    }
    
    public static void createClaims(Map<Id,WorkOrder> newMap,Map<Id,WorkOrder> oldMap){
        
        Map<Id,DE_Claim__c> claimMap = new Map<Id,DE_Claim__c>();
        List<DE_Claim_Product__c> claimProductList = new List<DE_Claim_Product__c >();
        List<ProductConsumed> productConsumedList = new List<ProductConsumed>();
        Set<Id> workOrderIdSet = new Set<Id>();
        
        //Filter Completed Work Orders
        for(Id woId:newMap.keyset()){
            if(newMap.get(woId).Status == 'Completed' && oldMap.get(woId).Status != 'Completed'){
                workOrderIdSet.add(woId);
            }
        }
        
        //Fetch workorder Related Asset and Product Consumed
        Map<Id,WorkOrder> workOrderMap = new Map<Id,WorkOrder>([SELECT Id,AssetId,Asset.AssetLevel,Asset.ParentId,Asset.Parent.ParentId,Asset.Parent.Parent.ParentId,(SELECT Product2Id,ProductItemId,UnitPrice,QuantityConsumed,Total_Price__c,DE_Total_Effective_Amount__c,DE_Asset_Number__c FROM ProductsConsumed) FROM WorkOrder WHERE Id IN:workOrderIdSet]);
        setRequiredAssets(workOrderMap);
        for(Workorder wo:workOrderMap.values()){
            if(wo.ProductsConsumed.size()>0){
                //Fetch Asset Heirarchies
                Map<String,Asset> assetSerialNumberMap = woAssetSerialNumberMap.get(wo.Id);
                Map<String,Asset> assetProductIdMap = woAssetProductIdMap.get(wo.Id);
                Boolean claimNeeded = false;
                for(ProductConsumed pc : wo.ProductsConsumed){
                    Asset relatedAsset=null;
                    system.debug(pc.Product2Id+'--'+assetProductIdMap.keyset());
                    //Check asset by serial number if not found or blank check via product
                    if(String.isNotBlank(pc.DE_Asset_Number__c) && assetSerialNumberMap.containsKey(pc.DE_Asset_Number__c)){
                        relatedAsset = assetSerialNumberMap.get(pc.DE_Asset_Number__c);
                    } else if(assetProductIdMap.containsKey(pc.Product2Id)){
                        relatedAsset = assetProductIdMap.get(pc.Product2Id);
                    }
                    //check status of asset if found
                    if(relatedAsset!=null && relatedAsset.Entitlement_Status__c!='Expired'){
                        DE_Claim_Product__c cp = new DE_Claim_Product__c(DE_Claim__c = wo.Id,DE_Amount__c = pc.UnitPrice,DE_Quantity__c = pc.QuantityConsumed,DE_Product__c=pc.Product2Id,DE_Product_Item__c=pc.ProductItemId);
                        claimProductList.add(cp);
                        pc.DE_Total_Effective_Amount__c = 0;
                        productConsumedList.add(pc);
                        claimNeeded = true;
                	}
                    else{
                        system.debug('here'+pc.Total_Price__c);
                        pc.DE_Total_Effective_Amount__c = pc.Total_Price__c;
                    	productConsumedList.add(pc);
                    }
            	}
                if(claimNeeded){
                    DE_Claim__c claim = new DE_Claim__c(DE_Work_Order__c = wo.Id);
                	claimMap.put(wo.Id,claim);
				}
        	}
        }
        //update the Product Consumed List with Effective Amount
        update productConsumedList;
        //Insert the Claim records
        insert claimMap.values();
        //Link the Claim records with Claim Product and Insert
        for(DE_Claim_Product__c cp : claimProductList){
            if(claimMap.containskey(cp.DE_Claim__c)){
            	cp.DE_Claim__c = claimMap.get(cp.DE_Claim__c).Id;
            }
        }
        insert claimProductList;
    }
	    
    public static void setRequiredAssets(Map<Id,WorkOrder> workOrderMap){ 
        List<Asset> allAssets = [SELECT Id,Name,Entitlement_Status__c,Product2Id,Product2.Name,SerialNumber,AssetLevel,ParentId FROM Asset WHERE AssetLevel=1 OR (AssetLevel>1 AND ParentId!=null)  Order By AssetLevel];
		Map<Id,Id> workOrderParentAssetMap = new Map<Id,Id>();
        Map<Id,List<Asset>> parentChildAssetMap = new Map<Id,List<Asset>>();
        for(WorkOrder wo:workOrderMap.values()){
            if(wo.Asset.AssetLevel == 1){
               workOrderParentAssetMap.put(wo.Id,wo.AssetId); 
            } else if(wo.Asset.AssetLevel == 2){
               workOrderParentAssetMap.put(wo.Id,wo.Asset.ParentId); 
            } else if(wo.Asset.AssetLevel == 3){
               workOrderParentAssetMap.put(wo.Id,wo.Asset.Parent.ParentId); 
            } else if(wo.Asset.AssetLevel == 4){
               workOrderParentAssetMap.put(wo.Id,wo.Asset.Parent.Parent.ParentId); 
            } 
        }
        for(Asset a : allAssets){
            if(a.AssetLevel==1 && workOrderParentAssetMap.values().contains(a.Id)){
                List<Asset> tempAsset = new List<Asset>();
                tempAsset.addAll(getChildAssets(allAssets,a.AssetLevel,a.Id));
                tempAsset.add(a);
                parentChildAssetMap.put(a.Id,tempAsset);
            }
        }
        
        for(Id woId : workOrderParentAssetMap.keyset()){
            Map<String,Asset> assetSerialNumberMap = new Map<String,Asset>();
            Map<String,Asset> assetProductIdMap = new Map<String,Asset>();
            for(Asset a : parentChildAssetMap.get(workOrderParentAssetMap.get(woId))){
                assetSerialNumberMap.put(a.SerialNumber,a);
                assetProductIdMap.put(a.Product2Id,a);
            }
            woAssetSerialNumberMap.put(woId,assetSerialNumberMap);
            woAssetProductIdMap.put(woId,assetProductIdMap);
        }
    }
    
    public static List<Asset> getChildAssets(List<Asset> allAssets,Integer level,Id ParentId){
        List<Asset> tempAsset = new List<Asset>();
        for(Asset a : allAssets){
            if(a.AssetLevel==level+1 && a.parentId==ParentId){  
                tempAsset.addAll(getChildAssets(allAssets,a.AssetLevel,a.Id));
                tempAsset.add(a); 
            }
        }
        return tempAsset;
    }
    
    public static void createServiceCharge(Map<Id,WorkOrder> newMap,Map<Id,WorkOrder> oldMap){
        Set<Id> workOrderIdSet = new Set<Id>();
        Set<Id> claimsIdSet = new Set<Id>();
        Map<Id,DE_Claim__c> claimsMap = new Map<Id,DE_Claim__c>();
        Map<Id,PricebookEntry> peMap = new Map<Id,PricebookEntry>();
        List<ProductConsumed> pcList = new List<ProductConsumed>();
        Product2 p = [SELECT Id,Standard_Pricebook_Price__c FROM Product2 WHERE Name = 'Service Charge' LIMIT 1];
        for(PricebookEntry pe : [SELECT Id,Pricebook2Id FROM PricebookEntry WHERE Product2Id=:p.Id]){
            peMap.put(pe.Pricebook2Id,pe);
        }
        //Filter Completed Work Orders
        for(Id woId:newMap.keyset()){
            if(newMap.get(woId).Status == 'Completed' && oldMap.get(woId).Status != 'Completed'){
                workOrderIdSet.add(woId);
            }
        }
		Map<Id,WorkOrder> workOrderMap = new Map<Id,WorkOrder>([SELECT Id,Pricebook2Id,(SELECT Id FROM ProductsConsumed),(SELECT Id FROM Claims__r ORDER BY CreatedDate DESC LIMIT 1) FROM WorkOrder WHERE Id IN :workOrderIdSet]);
        for(WorkOrder wo : workOrderMap.values()){
            if(wo.Claims__r.size()==0){
                ProductConsumed pc = new ProductConsumed();
                pc.WorkOrderId = wo.Id;
                pc.QuantityConsumed = 1;
                pc.UnitPrice = p.Standard_Pricebook_Price__c;
                pc.DE_Total_Effective_Amount__c = p.Standard_Pricebook_Price__c;
                pc.PricebookEntryId = peMap.get(wo.Pricebook2Id).Id;
                pcList.add(pc);
            } else {
                claimsIdSet.add(wo.Claims__r[0].Id);
            }
        }
        if(claimsIdSet.size()>0){
            claimsMap = new Map<Id,DE_Claim__c>([SELECT Id,(SELECT Id FROM Claim_Products__r) FROM DE_Claim__c WHERE Id IN:claimsIdSet]);
            for(WorkOrder wo : workOrderMap.values()){
                if(wo.ProductsConsumed.size()>0 && wo.ProductsConsumed.size() > claimsMap.get(wo.Claims__r[0].Id).Claim_Products__r.size() ){
                    ProductConsumed pc = new ProductConsumed();
                    pc.WorkOrderId = wo.Id;
                    pc.QuantityConsumed = 1;
                    pc.UnitPrice = p.Standard_Pricebook_Price__c;
                    pc.DE_Total_Effective_Amount__c = p.Standard_Pricebook_Price__c;
                    pc.PricebookEntryId = peMap.get(wo.Pricebook2Id).Id;
                    pcList.add(pc);
                }
        	}
        }
	Insert pcList;         
    }
}
