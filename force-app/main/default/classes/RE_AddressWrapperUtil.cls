public class RE_AddressWrapperUtil {
    
    /**
     * Wraps a single address string into multiple lines.
     * Moves words to the next line if they don't fit.
     */
    public static List<String> wrapAddress(String input, Integer lineLength) {
        List<String> lines = new List<String>();
        if (String.isBlank(input)) {
            lines.add('');
            return lines;
        }
        
        String[] words = input.trim().split('\\s+');
        String currentLine = '';
        
        for (String word : words) {
            if (String.isBlank(currentLine)) {
                currentLine = word;
            } else if ((currentLine + ' ' + word).length() <= lineLength) {
                currentLine += ' ' + word;
            } else {
                lines.add(currentLine);
                currentLine = word;
            }
        }
        
        if (String.isNotBlank(currentLine)) {
            lines.add(currentLine);
        }
        
        return lines;
    }
    
    /**
     * Combines multiple address components into wrapped lines.
     * 
     * @param components          List of address parts (street, city, postcode, etc.)
     * @param lineLength          Max chars per line
     * @param addTrailingCommas   If true, adds a comma at the end of each line
     *                            (except the last) so the full address reads
     *                            naturally top-to-bottom.
     * @param addFieldSeparator   If true, adds ", " between components on the same line.
     *                            If false, components are concatenated with a space.
     */
    public static List<String> buildWrappedAddress(
        List<String> components,
        Integer lineLength,
        Boolean addTrailingCommas,
        Boolean addFieldSeparator
    ) {
        // Filter out blank components
        List<String> validComponents = new List<String>();
        for (String comp : components) {
            if (String.isNotBlank(comp)) {
                validComponents.add(comp.trim());
            }
        }
        
        if (validComponents.isEmpty()) {
            return new List<String>{''};
        }
        
        // When trailing commas are requested, reserve 1 char for the comma
        // so the comma doesn't push the line over the limit.
        Integer effectiveLimit = addTrailingCommas == true 
            ? lineLength - 1 
            : lineLength;
        
        // Determine the separator to use between fields on the same line
        String fieldSeparator = (addFieldSeparator == false) ? ' ' : ', ';
        
        List<String> resultLines = new List<String>();
        String currentLine = '';
        
        for (Integer i = 0; i < validComponents.size(); i++) {
            String component = validComponents.get(i);
            String separator = String.isBlank(currentLine) ? '' : fieldSeparator;
            
            if ((currentLine + separator + component).length() <= effectiveLimit) {
                currentLine += separator + component;
            } else {
                if (String.isNotBlank(currentLine)) {
                    resultLines.add(currentLine);
                    currentLine = '';
                }
                
                List<String> wrapped = wrapAddress(component, effectiveLimit);
                for (Integer j = 0; j < wrapped.size(); j++) {
                    String wrappedLine = wrapped.get(j);
                    
                    if (j == wrapped.size() - 1 && i < validComponents.size() - 1) {
                        currentLine = wrappedLine;
                    } else {
                        resultLines.add(wrappedLine);
                    }
                }
            }
        }
        
        if (String.isNotBlank(currentLine)) {
            resultLines.add(currentLine);
        }
        
        // Apply trailing commas to all lines except the last
        if (addTrailingCommas == true && resultLines.size() > 1) {
            for (Integer i = 0; i < resultLines.size() - 1; i++) {
                String line = resultLines[i];
                if (String.isNotBlank(line) && !line.endsWith(',')) {
                    resultLines[i] = line + ',';
                }
            }
        }
        
        return resultLines;
    }

    public static List<String> buildWrappedName(
        List<String> components,
        Integer lineLength
    ) {
        // Filter out blank components
        List<String> validComponents = new List<String>();
        for (String comp : components) {
            if (String.isNotBlank(comp)) {
                validComponents.add(comp.trim());
            }
        }

        if (validComponents.isEmpty()) {
            return new List<String>{''};
        }

        // Join with spaces (no commas), then wrap by word
        String joined = String.join(validComponents, ' ');
        return wrapAddress(joined, lineLength);
    }
    
    /**
     * Backwards-compatible overload — trailing commas on, field separator on.
     */
    public static List<String> buildWrappedAddress(
        List<String> components,
        Integer lineLength,
        Boolean addTrailingCommas
    ) {
        return buildWrappedAddress(components, lineLength, addTrailingCommas, true);
    }
    
    /**
     * Backwards-compatible overload — no trailing commas, field separator on.
     */
    public static List<String> buildWrappedAddress(
        List<String> components,
        Integer lineLength
    ) {
        return buildWrappedAddress(components, lineLength, false, true);
    }
}