public class AssignClaimsPermission {
	public static void assignPermission(){
        
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Claims_Asset_Permission_Set' LIMIT 1];
            Set<Id> userIdSet = new Set<Id>();
            List<PermissionSetAssignment> permissionSetList = new List<PermissionSetAssignment>();
        	for (ServiceResource sr : [SELECT Id,Name,RelatedRecordId FROM ServiceResource WHERE RelatedRecordId!=null]){ 
            	userIdSet.add(sr.RelatedRecordId);
            }
            for (Id userId : userIdSet){ 
            	PermissionSetAssignment psa = new PermissionSetAssignment (PermissionSetId = ps.Id, AssigneeId = userId);
            	permissionSetList.add(psa);
            }
            upsert permissionSetList;
        	
        	Product2 p = new Product2();
            p.Name = 'Service Charge';
            p.ProductCode = 'SC-0809';
            p.IsActive = true;
            p.Standard_Pricebook_Price__c = 150;
            insert p;
    }
}
