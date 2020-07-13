trigger WorkOrderClaimsTrigger on WorkOrder (after update) {
    WorkOrderClaimsTriggerHandler.afterUpdate(Trigger.newMap,Trigger.oldMap);
}