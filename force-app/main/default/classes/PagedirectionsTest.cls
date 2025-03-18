@isTest
public with sharing class PagedirectionsTest {
    @IsTest
    static void doRedirectActionTest(){
        PageReference pageRef = Page.EmailMessages;
        Test.setCurrentPage(pageRef);
        Pagedirections controller = new Pagedirections();
        String nextPage = controller.doRedirectAction().getUrl();
        System.assertNotEquals(null, nextPage);
    }
}