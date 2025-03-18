({
    handleSelect : function (component, event) {
        var statusName = event.getParam("detail").value;
        var recordId = component.get("v.recordId");

        var action = component.get("c.saveAppStatus"); // referring to apex controller method.
        action.setParams({
            "statusName":statusName,
            "recordId":recordId
        });

        action.setCallback(this, function (response) { 
            var state = response.getState();
            if (state === 'SUCCESS') {
                var result = response.getReturnValue();
                window.location.reload();
                if(result=='Success'){
                    console.log("Updated is Success");
                    
                }
            } else if (state === 'ERROR') {
                var errors = response.getError();
                if (errors) {
                    if (errors[0] && errors[0].message) {
                        console.log("Error message: " + errors[0].message);
                    }
                } else {
                        console.log("Unknown error");
                }
            }
        });
        $A.enqueueAction(action);
    }
})