@isTest
public class BlankeSMSFlowHelperTest {

    @IsTest static void updateSmsBodyTest(){
        BlankeSMSFlowHelper.Request requestData = new BlankeSMSFlowHelper.Request();
        requestData.smsBody = 'This test data to test with data {ReceiveDate}.';
        requestData.receiveDate = Datetime.now();
        List<BlankeSMSFlowHelper.Request> requestInfo = new List<BlankeSMSFlowHelper.Request>();
        requestInfo.add(requestData);
        Test.startTest();
        List<BlankeSMSFlowHelper.Response> response = BlankeSMSFlowHelper.updateSmsBody(requestInfo);
        Test.stopTest();
        String changedDate = String.valueOf(requestData.receiveDate.format('EEE dd MMM yyyy'));
        System.assertNotEquals(null, response[0].result, 'Don\'t return result data');
        System.assert(response[0].result.contains(changedDate), 'Don\'t change receive date');
        System.assert(!response[0].result.contains('{ReceiveDate}'), 'Don\'t change receive date');
    }
}