({ invoke : function(component) {

 

    var flowName = component.get("v.flowName");
  
    var workspaceAPI = component.find("closeFlow");
  
   
  
    workspaceAPI.getAllTabInfo().then(function(response) {
  
      if (Array.isArray(response)) {
  
        response.forEach(function (tab) {
  
          if (tab.pageReference && tab.pageReference.state && tab.pageReference.state.c__flowName) {
  
            if (flowName === tab.pageReference.state.c__flowName) {
  
              workspaceAPI.closeTab({ tabId: tab.tabId });
  
            }
  
          }
  
        });
  
      }
  
    })
  
  }})