@IsTest
public class EmailMessagePageredirectorTest {
    @IsTest
    static void doRedirectActionTest(){
        PageReference pageRef = Page.EmailMessages;
        Test.setCurrentPage(pageRef);
        EmailMessagePageredirector controller = new EmailMessagePageredirector();
        String nextPage = controller.doRedirectAction().getUrl();
        System.assertNotEquals(null, nextPage);
    }
}