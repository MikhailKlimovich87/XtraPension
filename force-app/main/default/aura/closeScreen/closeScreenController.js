({    
    invoke : function(component, event, helper) {
        var navEvent = $A.get("e.force:navigateToList");
        navEvent.setParams({
            "listViewId": '00BRR0000042Z7R2AU',
            "listViewName": 'All Messages',
            "scope": "EmailMessage"
        });
        navEvent.fire();
    },
})