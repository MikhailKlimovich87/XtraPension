@isTest
private class RE_AddressWrapperUtilTest {
    
    // ==========================================================
    // TESTS FOR wrapAddress()
    // ==========================================================
    
    @isTest
    static void testWrapAddress_nullInput() {
        List<String> result = RE_AddressWrapperUtil.wrapAddress(null, 35);
        System.assertEquals(1, result.size(), 'Null input should return one empty line');
        System.assertEquals('', result[0], 'Line should be empty string');
    }
    
    @isTest
    static void testWrapAddress_blankInput() {
        List<String> result = RE_AddressWrapperUtil.wrapAddress('   ', 35);
        System.assertEquals(1, result.size(), 'Blank input should return one empty line');
        System.assertEquals('', result[0], 'Line should be empty string');
    }
    
    @isTest
    static void testWrapAddress_emptyString() {
        List<String> result = RE_AddressWrapperUtil.wrapAddress('', 35);
        System.assertEquals(1, result.size(), 'Empty string should return one empty line');
    }
    
    @isTest
    static void testWrapAddress_shortInput_fitsOnOneLine() {
        String input = '140 TRINITY ROAD';
        List<String> result = RE_AddressWrapperUtil.wrapAddress(input, 35);
        System.assertEquals(1, result.size(), 'Short input should fit on one line');
        System.assertEquals('140 TRINITY ROAD', result[0]);
    }
    
    @isTest
    static void testWrapAddress_exactFit() {
        // 10 chars exactly
        String input = '1234567890';
        List<String> result = RE_AddressWrapperUtil.wrapAddress(input, 10);
        System.assertEquals(1, result.size(), 'Exactly fitting text should stay on one line');
        System.assertEquals('1234567890', result[0]);
    }
    
    @isTest
    static void testWrapAddress_breaksAtWordBoundary() {
        String input = 'FLAT 4, ST. MARTINS COURT, 140 TRINITY ROAD';
        List<String> result = RE_AddressWrapperUtil.wrapAddress(input, 35);
        
        // Verify every line is <= 35 chars
        for (String line : result) {
            System.assert(line.length() <= 35, 
                'Line should not exceed 35 chars: "' + line + '" (' + line.length() + ')');
        }
        
        // Verify no word was split
        String rejoined = String.join(result, ' ');
        System.assertEquals(input, rejoined, 'Rejoined lines should equal original (no word split)');
    }
    
    @isTest
    static void testWrapAddress_singleLongWord() {
        String input = 'SUPERCALIFRAGILISTICEXPIALIDOCIOUS';
        List<String> result = RE_AddressWrapperUtil.wrapAddress(input, 10);
        System.assertEquals(1, result.size(), 'Single word longer than limit stays on one line');
        System.assertEquals('SUPERCALIFRAGILISTICEXPIALIDOCIOUS', result[0]);
    }
    
    @isTest
    static void testWrapAddress_multipleSpacesBetweenWords() {
        String input = 'FLAT   4,   ST.    MARTINS';
        List<String> result = RE_AddressWrapperUtil.wrapAddress(input, 35);
        System.assertEquals(1, result.size());
        System.assertEquals('FLAT 4, ST. MARTINS', result[0], 
            'Multiple spaces should be normalized to single space');
    }
    
    @isTest
    static void testWrapAddress_multipleLines() {
        String input = 'FLAT 4, ST. MARTINS COURT, 140 TRINITY ROAD LONDON SW17 7HS';
        List<String> result = RE_AddressWrapperUtil.wrapAddress(input, 20);
        
        System.assert(result.size() > 1, 'Long input should wrap into multiple lines');
        
        for (String line : result) {
            System.assert(line.length() <= 20, 
                'Line should not exceed 20 chars: "' + line + '"');
        }
        
        String rejoined = String.join(result, ' ');
        System.assertEquals(input, rejoined, 'No words should be lost or split');
    }
    
    @isTest
    static void testWrapAddress_leadingTrailingSpaces() {
        String input = '   FLAT 4, LONDON   ';
        List<String> result = RE_AddressWrapperUtil.wrapAddress(input, 35);
        System.assertEquals(1, result.size());
        System.assertEquals('FLAT 4, LONDON', result[0], 'Leading/trailing spaces should be trimmed');
    }
    
    // ==========================================================
    // TESTS FOR buildWrappedAddress()
    // ==========================================================
    
    @isTest
    static void testBuildWrappedAddress_emptyList() {
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>(), 35
        );
        System.assertEquals(1, result.size(), 'Empty list should return one empty line');
        System.assertEquals('', result[0]);
    }
    
    @isTest
    static void testBuildWrappedAddress_allBlankComponents() {
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>{null, '', '   '}, 35
        );
        System.assertEquals(1, result.size());
        System.assertEquals('', result[0]);
    }
    
    @isTest
    static void testBuildWrappedAddress_singleComponent() {
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>{'140 TRINITY ROAD'}, 35
        );
        System.assertEquals(1, result.size());
        System.assertEquals('140 TRINITY ROAD', result[0]);
    }
    
    @isTest
    static void testBuildWrappedAddress_multipleComponents_oneLine() {
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>{'LONDON', 'SW17 7HS'}, 35
        );
        System.assertEquals(1, result.size());
        System.assertEquals('LONDON, SW17 7HS', result[0], 
            'Components on same line should be comma-separated');
    }
    
    @isTest
    static void testBuildWrappedAddress_commaSeparator() {
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>{'FLAT 4', 'LONDON'}, 35
        );
        System.assertEquals(1, result.size());
        System.assert(result[0].contains(', '), 'Components should be separated by comma+space');
        System.assertEquals('FLAT 4, LONDON', result[0]);
    }
    
    @isTest
    static void testBuildWrappedAddress_noLeadingCommaOnNewLine() {
        // Two components that don't fit on same line
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>{'1234567890', 'ABCDEFGHIJ'}, 10
        );
        System.assertEquals(2, result.size());
        System.assert(!result[1].startsWith(','), 
            'Second line should NOT start with comma: "' + result[1] + '"');
    }
    
    @isTest
    static void testBuildWrappedAddress_skipsBlankComponents() {
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>{'FLAT 4', null, '', 'LONDON', '   '}, 35
        );
        System.assertEquals(1, result.size());
        System.assertEquals('FLAT 4, LONDON', result[0], 
            'Blank components should be skipped');
    }
    
    @isTest
    static void testBuildWrappedAddress_ukAddressExample() {
        // Realistic UK address test
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>{
                'FLAT 4, ST. MARTINS COURT',
                '140 TRINITY ROAD',
                'LONDON',
                'SW17 7HS'
            }, 35
        );
        
        // Every line must be <= 35 chars
        for (String line : result) {
            System.assert(line.length() <= 35, 
                'Line exceeds limit: "' + line + '" (' + line.length() + ')');
        }
        
        // No line should start with a comma
        for (String line : result) {
            System.assert(!line.startsWith(','), 
                'Line should not start with comma: "' + line + '"');
        }
        
        // Postcode should appear somewhere
        String joined = String.join(result, ' ');
        System.assert(joined.contains('SW17 7HS'), 'Postcode should be present');
    }
    
    @isTest
    static void testBuildWrappedAddress_abroadAddressWithLongStreet() {
        // Street alone exceeds line length, must wrap
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>{
                'THE CAMPUS, 57 SLOANE STREET',
                'BRYANSTON',
                'JOHANNESBURG',
                '2191',
                'SOUTH AFRICA'
            }, 30
        );
        
        for (String line : result) {
            System.assert(line.length() <= 30, 
                'Line exceeds 30 chars: "' + line + '"');
        }
        
        // All original words should be present
        String joined = String.join(result, ' ');
        System.assert(joined.contains('CAMPUS'));
        System.assert(joined.contains('SLOANE'));
        System.assert(joined.contains('JOHANNESBURG'));
        System.assert(joined.contains('SOUTH AFRICA'));
    }
    
    @isTest
    static void testBuildWrappedAddress_componentOneCharOver() {
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>{'1234567890', 'ABCDEF'}, 16
        );
        // "1234567890, ABCDEF" = 17 chars - should split
        System.assertEquals(2, result.size());
    }
    
    @isTest
    static void testBuildWrappedAddress_multipleSmallComponents() {
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>{'A', 'B', 'C', 'D', 'E'}, 10
        );
        // "A, B, C, D, E" = 13 chars - splits
        // Expected: "A, B, C, D" (10) then "E"
        System.assert(result.size() >= 1);
        for (String line : result) {
            System.assert(line.length() <= 10);
        }
    }
    
    // ==========================================================
    // INTEGRATION-STYLE TESTS
    // ==========================================================
    
    @isTest
    static void testIntegration_realUKAddress() {
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>{
                'FLAT 4, ST. MARTINS COURT, 140 TRINITY ROAD',
                'LONDON',
                '',
                'SW17 7HS'
            }, 35
        );
        
        System.assert(result.size() >= 2, 'Long address should wrap');
        System.assert(result.size() <= 4, 'Should fit in typical 4-line field');
    }
    
    @isTest
    static void testIntegration_realSouthAfricaAddress() {
        List<String> result = RE_AddressWrapperUtil.buildWrappedAddress(
            new List<String>{
                'THE CAMPUS, 57 SLOANE STREET',
                'BRYANSTON',
                'JOHANNESBURG',
                '2191',
                'SOUTH AFRICA'
            }, 35
        );
        
        for (String line : result) {
            System.assert(line.length() <= 35);
            System.assert(!line.startsWith(','));
        }
        
        String joined = String.join(result, ' ');
        System.assert(joined.contains('DIMENSION') || joined.contains('CAMPUS'));
    }
    
}