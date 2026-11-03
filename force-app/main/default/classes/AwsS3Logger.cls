/**
 * Utility class for logging
 */
public with sharing class AwsS3Logger {
    
    public static Boolean enableDebug = true;
    public static Boolean enableInfo = true;
    public static Boolean enableWarn = true;
    public static Boolean enableError = true;
    
    public static void debug(String message) {
        if (enableDebug) {
            System.debug('🔍 [DEBUG] ' + message);
        }
    }
    
    public static void info(String message) {
        if (enableInfo) {
            System.debug('ℹ️ [INFO] ' + message);
        }
    }
    
    public static void warn(String message) {
        if (enableWarn) {
            System.debug('⚠️ [WARN] ' + message);
        }
    }
    
    public static void error(String message) {
        if (enableError) {
            System.debug('❌ [ERROR] ' + message);
        }
    }
}