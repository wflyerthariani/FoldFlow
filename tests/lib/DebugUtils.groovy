class DebugUtils {

    // ANSI color codes
    static final String RESET   = "\033[0m"
    static final String CYAN    = "\033[36m"
    static final String YELLOW  = "\033[33m"
    static final String GREEN   = "\033[32m"
    static final String MAGENTA = "\033[35m"

    // Static method to print a debug object tree
    static void printTree(obj, String indent = "", boolean top = true) {

        // Only print top-level object header
        if (top) {
            println ""
            println "--------------------------------"
            println "PROCESS OUTPUT"
            println "$obj"
            println "--------------------------------"
            println ""
            println "--------------------------------"
            println "DETAILED TREE VIEW OF PROCESS OUTPUT"
            println "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
            println ""
        }

        if (obj instanceof Map) {
            obj.each { k, v ->
                println "${indent}${CYAN}${k}${RESET}:"
                printTree(v, indent + "  ", false)
            }
        } else if (obj instanceof List) {
            obj.eachWithIndex { v, i ->
                println "${indent}${YELLOW}- [$i]${RESET}"
                printTree(v, indent + "  ", false)
            }
        } else if (obj instanceof File || obj instanceof java.nio.file.Path ||
                  (obj instanceof String && new File(obj).exists())) {
            println "${indent}${GREEN}${obj}${RESET}"
        } else {
            println "${indent}${MAGENTA}${obj}${RESET}"
        }
    }
}