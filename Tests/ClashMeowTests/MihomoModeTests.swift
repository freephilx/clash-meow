import Testing
@testable import ClashMeow

struct MihomoModeTests {
    @Test func displayValueMatchesForwardingSelection() {
        #expect(MihomoMode.rule.displayValue == "RULE")
        #expect(MihomoMode.global.displayValue == "GLOBAL")
        #expect(MihomoMode.direct.displayValue == "DIRECT")
    }

    @Test func configValueParsingIsCaseInsensitive() {
        #expect(MihomoMode(configValue: "Rule") == .rule)
        #expect(MihomoMode(configValue: "GLOBAL") == .global)
        #expect(MihomoMode(configValue: nil) == .rule)
    }

    @Test func yamlGlobalModeDoesNotOverrideSavedRulePreference() {
        let yamlMode = MihomoMode(configValue: "global")
        let savedMode = MihomoMode.rule
        #expect(yamlMode != savedMode)
        #expect(savedMode.displayValue == "RULE")
    }
}
