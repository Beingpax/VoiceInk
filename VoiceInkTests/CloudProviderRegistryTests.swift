import Testing

@testable import VoiceInk

struct CloudProviderRegistryTests {

    @Test func noTwoProvidersShareAProviderKey() {
        let keys = CloudProviderRegistry.allProviders.map(\.providerKey)
        #expect(Set(keys).count == keys.count)
    }

    @Test func noTwoProvidersShareAModelProvider() {
        let providers = CloudProviderRegistry.allProviders.map(\.modelProvider)
        #expect(Set(providers).count == providers.count)
    }

    @Test func lookupByModelProviderFindsTheRegisteredProvider() {
        guard let first = CloudProviderRegistry.allProviders.first else {
            Issue.record("Expected at least one registered cloud provider")
            return
        }

        let found = CloudProviderRegistry.provider(for: first.modelProvider)
        #expect(found?.providerKey == first.providerKey)
    }

    @Test func everyProviderExposesAtLeastOneModel() {
        for provider in CloudProviderRegistry.allProviders {
            #expect(!provider.models.isEmpty, "\(provider.providerKey) has no models")
        }
    }
}
