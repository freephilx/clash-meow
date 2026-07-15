import Foundation
import Testing
@testable import ClashMeow

struct MihomoProfileParsingTests {
    @Test func subscriptionUserAgentsPreferClashMetaYAML() {
        #expect(ProfileRepository.defaultSubscriptionUserAgent.contains("clash.meta"))
        #expect(ProfileRepository.fallbackSubscriptionUserAgents.first == "ClashMetaForAndroid/2.10.1")
        #expect(ProfileRepository.fallbackSubscriptionUserAgents.contains("clash.meta"))
        #expect(ProfileRepository.fallbackSubscriptionUserAgents.last == "mihomo/1.9.27")
    }

    @Test func subscriptionNormalizerConvertsBase64ShareLinks() throws {
        let shareLinks = """
        vless://2d25d6e8-225f-4983-b5f4-e25e24c85090@example.com:443?security=tls&type=tcp&sni=example.com#Tokyo
        anytls://password@example.org:8443?sni=example.org&insecure=1#Singapore
        """
        let encoded = Data(shareLinks.utf8).base64EncodedString()

        let yaml = try SubscriptionDocumentNormalizer.normalize(encoded)
        let nodes = ProxyNodeInfo.parsed(from: yaml)
        let groups = ProxyGroupItem.parsed(from: yaml)

        #expect(nodes.map(\.name) == ["Tokyo", "Singapore"])
        #expect(groups.first?.nodes.map(\.name) == ["Tokyo", "Singapore", "DIRECT"])
    }

    @Test func proxyParserReadsInlineSubscriptionYAMLNodes() {
        let yaml = """
        proxies:
            - { name: '[vless]剩余流量：75.04 GB', type: vless, server: 199.15.77.250, port: 443, uuid: 2d25d6e8-225f-4983-b5f4-e25e24c85090, alterId: 0, cipher: auto, udp: true, flow: xtls-rprx-vision, encryption: none, tls: true, skip-cert-verify: false, servername: www.amd.com, reality-opts: { public-key: DeuGyYZvc8HbWjGRNmWCTev7y2aZSWNPwS_3sBavmQo, short-id: 3d1a }, client-fingerprint: edge, network: tcp }
            - { name: '[anytls]新加坡测试-1X', type: anytls, server: sg.dickaws.top, port: 20034, password: 2d25d6e8-225f-4983-b5f4-e25e24c85090, udp: true, sni: sgbage.koyun321.eu.cc, skip-cert-verify: true, ech-opts: { enable: true, config: AEb+DQBCiAAgACC7CDI4Mup9ffWwgzBnjWsfiOejlVkXMOeV9xs7SnQ+BAAIAAEAAQABAAMAD2VjaC5leGFtcGxlLmNvbQAA } }
        proxy-groups:
            - { name: 自动选择, type: url-test, proxies: ['[vless]剩余流量：75.04 GB', '[anytls]新加坡测试-1X'], url: 'https://www.gstatic.com/generate_204' }
        """

        let nodes = ProxyNodeInfo.parsed(from: yaml)
        let groups = ProxyGroupItem.parsed(from: yaml)

        #expect(nodes.map(\.name) == ["[vless]剩余流量：75.04 GB", "[anytls]新加坡测试-1X"])
        #expect(nodes.map(\.type) == ["vless", "anytls"])
        #expect(nodes.map(\.server) == ["199.15.77.250", "sg.dickaws.top"])
        #expect(groups.first?.nodes.map(\.name) == ["[vless]剩余流量：75.04 GB", "[anytls]新加坡测试-1X"])
        #expect(groups.first?.testURL == "https://www.gstatic.com/generate_204")
    }

    @Test func proxyParserReadsBlockSubscriptionYAMLWhenNameIsNotFirstKey() {
        let yaml = """
        proxies:
        - alterId: 0
          cipher: auto
          name: "[vless]剩余流量：75.04 GB"
          port: 443
          server: 199.15.77.250
          type: vless
        - name: "[anytls]新加坡测试-1X"
          password: 2d25d6e8-225f-4983-b5f4-e25e24c85090
          port: 20034
          server: sg.dickaws.top
          type: anytls
        proxy-groups:
        - name: 自动选择
          proxies:
          - "[vless]剩余流量：75.04 GB"
          - "[anytls]新加坡测试-1X"
          type: url-test
          url: https://www.gstatic.com/generate_204
        """

        let nodes = ProxyNodeInfo.parsed(from: yaml)
        let groups = ProxyGroupItem.parsed(from: yaml)

        #expect(nodes.map(\.name) == ["[vless]剩余流量：75.04 GB", "[anytls]新加坡测试-1X"])
        #expect(nodes.map(\.type) == ["vless", "anytls"])
        #expect(groups.first?.nodes.map(\.name) == ["[vless]剩余流量：75.04 GB", "[anytls]新加坡测试-1X"])
    }

    @Test func proxyParserDecodesEscapedYAMLNodeNames() {
        let yaml = """
        proxies:
        - name: "[vless]\\u5269\\u4F59\\u6D41\\u91CF\\uFF1A75.04 GB"
          port: 443
          server: 199.15.77.250
          type: vless
        - name: "[vless]\\U0001F1ED\\U0001F1F0\\u9999\\u6E2FC08-1X(\\u79FB\\u52A8)"
          port: 22135
          server: xgaws.keyun520.dpdns.org
          type: vless
        proxy-groups:
        - name: "\\u81EA\\u52A8\\u9009\\u62E9"
          proxies:
          - "[vless]\\u5269\\u4F59\\u6D41\\u91CF\\uFF1A75.04 GB"
          - "[vless]\\U0001F1ED\\U0001F1F0\\u9999\\u6E2FC08-1X(\\u79FB\\u52A8)"
          type: url-test
        """

        let nodes = ProxyNodeInfo.parsed(from: yaml)
        let groups = ProxyGroupItem.parsed(from: yaml)

        #expect(nodes.map(\.name) == ["[vless]剩余流量：75.04 GB", "[vless]🇭🇰香港C08-1X(移动)"])
        #expect(groups.first?.name == "自动选择")
        #expect(groups.first?.nodes.map(\.name) == ["[vless]剩余流量：75.04 GB", "[vless]🇭🇰香港C08-1X(移动)"])
    }

    @Test func proxyDisplayNamesDecodeEscapedRuntimeNamesWithoutChangingRawName() {
        let rawName = "[anytls]\\u65B0\\u52A0\\u5761\\u6D4B\\u8BD5-1X"
        let node = ProxyGroupNode(name: rawName, type: "anytls", delay: nil, alive: nil)
        let group = ProxyGroupItem(
            id: "\\u81EA\\u52A8\\u9009\\u62E9",
            name: "\\u81EA\\u52A8\\u9009\\u62E9",
            type: "url-test",
            now: rawName,
            all: [rawName],
            nodes: [node],
            aliveCount: nil,
            testURL: nil
        )

        #expect(node.name == rawName)
        #expect(node.displayName == "[anytls]新加坡测试-1X")
        #expect(group.displayName == "自动选择")
        #expect(group.displayNow == "[anytls]新加坡测试-1X")
    }

    @Test func proxyNodeParserIgnoresNestedArraysInsideProxyItems() {
        let yaml = """
        proxies:
          - name: "tuic-node"
            type: tuic
            server: example.com
            port: 443
            alpn:
              - h3
          - name: "vless-node"
            type: vless
            server: example.org
            port: 2083
            alpn:
              - http/1.1
        proxy-groups:
          - name: "Proxy"
            type: select
            proxies:
              - "tuic-node"
              - "vless-node"
        """

        let nodes = ProxyNodeInfo.parsed(from: yaml)
        let groups = ProxyGroupItem.parsed(from: yaml)

        #expect(nodes.map(\.name) == ["tuic-node", "vless-node"])
        #expect(!nodes.map(\.name).contains("h3"))
        #expect(!nodes.map(\.name).contains("http/1.1"))
        #expect(groups.first?.nodes.map(\.type) == ["tuic", "vless"])
    }

    @Test func proxyGroupParserToleratesDuplicateProxyNodeNames() {
        let yaml = """
        proxies:
          - name: "same-node"
            type: vmess
            server: first.example.com
            port: 443
          - name: "same-node"
            type: trojan
            server: second.example.com
            port: 443
        proxy-groups:
          - name: "Proxy"
            type: select
            proxies:
              - "same-node"
        """

        let groups = ProxyGroupItem.parsed(from: yaml)

        #expect(groups.first?.nodes.first?.name == "same-node")
        #expect(groups.first?.nodes.first?.type == "trojan")
    }
}
