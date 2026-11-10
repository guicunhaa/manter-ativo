import XCTest
@testable import ManterAtivoCore

final class CoreTests: XCTestCase {
    func testPhraseNamesSwapBeforeCallingMemoryAWarning() {
        let phrase = PhraseBuilder.make(
            PhraseInput(
                memory: MemorySample(
                    physicalBytes: 24 << 30,
                    freeBytes: 240 << 20,
                    usedBytes: 23 << 30,
                    compressorBytes: 11 << 30,
                    wiredBytes: 5 << 30,
                    swapUsedBytes: 11 << 30,
                    swapTotalBytes: 12 << 30,
                    swapEncrypted: true,
                    pressure: .normal
                ),
                topFamilyName: "ChatGPT",
                topFamilyBytes: 4 << 30,
                spotlightCPU: 100,
                afterEffectsCacheBytes: nil,
                battery: nil,
                displayCount: 1,
                wake: .machine,
                wakeKnown: true
            )
        )
        XCTAssertTrue(phrase.contains("Swap"))
        XCTAssertTrue(phrase.contains("ChatGPT"))
        XCTAssertTrue(phrase.contains("Spotlight"))
        XCTAssertFalse(phrase.lowercased().contains("aviso"))
    }

    func testBatterySoftwareHold() {
        let battery = BatterySample(
            percent: 85,
            designmAh: 6249,
            fullmAh: 5484,
            currentmAh: 4593,
            cycleCount: 189,
            isCharging: false,
            externalConnected: true,
            amperageMilliAmps: 0,
            voltageMilliVolts: 12458,
            adapterWatts: 68,
            adapterName: "70W USB-C Power Adapter",
            systemLoadMilliWatts: 33059,
            thermallyLimited: false,
            condition: "Normal"
        )
        XCTAssertTrue(battery.isSoftwareHold)
        XCTAssertEqual(battery.healthRatio.map { Int(($0 * 100).rounded()) }, 88)
    }

    func testGrouperCollapsesAppAndFindsDuplicateAgents() {
        let records = [
            ProcessRecord(pid: 10, parentPid: 1, residentBytes: 400 << 20, cpuPercent: 4, path: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT", command: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT", ownedByUser: true),
            ProcessRecord(pid: 11, parentPid: 10, residentBytes: 500 << 20, cpuPercent: 6, path: "/Applications/ChatGPT.app/Contents/Helpers/Codex.app/Contents/MacOS/Codex", command: "Codex", ownedByUser: true),
            ProcessRecord(pid: 3, parentPid: 1, residentBytes: 20 << 20, cpuPercent: 0, path: "/opt/homebrew/bin/node", command: "node /tmp/after-effects-mcp", ownedByUser: true),
            ProcessRecord(pid: 4, parentPid: 1, residentBytes: 20 << 20, cpuPercent: 0, path: "/opt/homebrew/bin/node", command: "node /tmp/after-effects-mcp", ownedByUser: true),
            ProcessRecord(pid: 5, parentPid: 1, residentBytes: 80 << 20, cpuPercent: 0, path: "/usr/local/bin/peripheralctl", command: "peripheralctl", ownedByUser: true),
            ProcessRecord(pid: 6, parentPid: 1, residentBytes: 900 << 20, cpuPercent: 80, path: "/System/Library/mds_stores", command: "mds_stores", ownedByUser: false),
        ]
        let census = ProcessGrouper.group(records)
        let chatgpt = census.families.first { $0.name == "ChatGPT" }
        XCTAssertEqual(chatgpt?.processCount, 2)
        XCTAssertEqual(chatgpt?.userKillable, true)
        XCTAssertEqual(census.families.first { $0.name == "peripheralctl" }?.userKillable, false)
        XCTAssertEqual(census.families.first { $0.name == "Spotlight" }?.userKillable, false)
        let dup = census.duplicates.first { $0.id == "after-effects-mcp" }
        XCTAssertEqual(dup?.count, 2)
        XCTAssertEqual(dup?.keepPID, 3)
        XCTAssertEqual(dup?.extraPIDs, [4])
        let apple = FamilyNamer.name(
            path: "/System/Library/Frameworks/CoreMediaIO.framework/Versions/A/Resources/com.apple.cmio.registerassistantservice",
            command: ""
        )
        XCTAssertNotEqual(apple, "com")
    }

    func testLocalAgentRuleRenamesARepeatWithoutAHardcodedClient() {
        let rules = [AgentRule(match: ["agente.mjs", "flux"], title: "Fila A", key: "fila-a")]
        let command = "node /tmp/agente.mjs --fila flux"
        XCTAssertEqual(FamilyNamer.agentTitle(command: command, rules: rules), "Fila A")
        XCTAssertEqual(FamilyNamer.duplicateKey(command: command, rules: rules), "fila-a")
        XCTAssertNil(FamilyNamer.agentTitle(command: command, rules: []))
        XCTAssertNil(FamilyNamer.duplicateKey(command: command, rules: []))
    }

    func testReclaimGuardRejectsEscape() {
        let home = URL(fileURLWithPath: "/tmp/manter-home")
        let evil = ReclaimCategory(id: "x", title: "x", detail: "x", relativePath: "Library/Caches/../../.ssh")
        XCTAssertNil(ReclaimGuard.authorizedURL(home: home, category: evil))
        let parent = ReclaimCategory(id: "y", title: "y", detail: "y", relativePath: "Library")
        XCTAssertNil(ReclaimGuard.authorizedURL(home: home, category: parent))
        let ok = ReclaimGuard.authorizedURL(home: home, category: ReclaimCatalog.categories[0])
        XCTAssertEqual(ok?.path, "/tmp/manter-home/Library/Caches/Adobe/After Effects")
        XCTAssertNil(ReclaimGuard.vetDelete(home: home, categoryID: "nao-existe"))
    }

    func testAssertionAndWakeParsers() {
        let pmset = """
        SleepDisabled\t\t1
        womp                 1
        powermode            0
        """
        let flags = WakeParser.flags(from: pmset)
        XCTAssertTrue(flags.sleepDisabled)
        XCTAssertTrue(flags.wakeOnLAN)
        XCTAssertEqual(flags.powermode, 0)
        let observation = WakeParser.observation(pmsetOutput: pmset, agentLoaded: true, helperInstalled: true)
        XCTAssertEqual(observation.mode, .machine)
        XCTAssertFalse(WakeParser.agentIsLoaded("Could not find service \"com.guicunha.keepawake\" in domain"))

        let assertions = """
        Listed by owning process:
           pid 13598(caffeinate): [0x1] 11:14:47 PreventSystemSleep named: "caffeinate command-line tool"
            Details: caffeinate asserting on behalf of '/bin/bash'
           pid 561(mds_stores): [0x2] 00:00:54 BackgroundTask named: "com.apple.metadata.mds_stores.power"
           pid 52197(ChatGPT): [0x3] 11:12:32 NoIdleSleepAssertion named: "Electron"
           pid 361(powerd): [0x4] 11:15:02 UserIsActive named: "lidopen"
        Kernel Assertions: 0x104=USB,MAGICWAKE
           id=747  level=255 0x4=USB creat=10/11/2026 description=usb owner=iPhone
           id=591  level=255 0x100=MAGICWAKE creat=07/11/2026 description=en0 owner=en0
        """
        let holders = AssertionParser.holders(from: assertions)
        XCTAssertTrue(holders.contains { $0.title == "Manter Ativo" })
        XCTAssertTrue(holders.contains { $0.title == "Spotlight" })
        XCTAssertTrue(holders.contains { $0.title == "ChatGPT" })
        XCTAssertTrue(holders.contains { $0.title == "iPhone" })
        XCTAssertFalse(holders.contains { $0.title == "powerd" })
    }

    func testMenuTitleLimit() {
        XCTAssertEqual(MenuTitle.short("Sair (vigília fica)").count, "Sair (vigília fica)".count)
        XCTAssertLessThanOrEqual(MenuTitle.short(String(repeating: "a", count: 80)).count, 30)
    }

    func testUSBAndSpotlightParsers() {
        let usb = USBListing.devices(from: """
              "USB Product Name" = "iPhone"
              "USB Product Name" = "MAD60"
              "USB Product Name" = "iPhone"
        """)
        XCTAssertEqual(usb.map(\.name), ["iPhone", "MAD60"])
        XCTAssertEqual(SpotlightStatus.indexing(from: "/:\n\tIndexing enabled."), true)
        XCTAssertEqual(SpotlightStatus.indexing(from: "Indexing disabled."), false)
    }

    func testShellTimesOutAndReadsLargeProcessList() {
        let started = Date()
        let timed = Shell.run(executable: "/bin/sleep", arguments: ["5"], timeout: 0.4)
        XCTAssertEqual(timed.status, 124)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        let listed = Shell.run(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,comm="],
            environment: ["LC_ALL": "C"],
            timeout: 3
        )
        XCTAssertEqual(listed.status, 0)
        XCTAssertGreaterThan(listed.stdout.split(whereSeparator: \.isNewline).count, 100)
    }

    func testDeskStateMarkdownOmitsPaths() {
        let state = DeskState(
            atualizado: Date(timeIntervalSince1970: 1_700_000_000),
            frase: "Swap alto.",
            vigilia: "Máquina",
            vigiliaConhecida: true,
            cpuTotal: 12,
            cpuSuper: 4,
            cpuPerformance: 16,
            carga: 3.2,
            memoriaUsada: 23 << 30,
            memoriaLivre: 500 << 20,
            compressor: 6 << 30,
            pressao: "Normal",
            swapUsado: 8 << 30,
            swapTotal: 9 << 30,
            swapCriptografado: true,
            bateriaPercent: 85,
            ciclos: 189,
            saude: 0.88,
            cargaSegurada: true,
            adaptadorWatts: 68,
            cargaSistema: "34 W",
            termico: "Nominal",
            discoLivre: 90 << 30,
            telas: ["Tela interna 3024×1964 Hz — interna"],
            usb: ["iPhone", "/tmp/exemplo/script.mjs"],
            segurandoSono: ["Manter Ativo: vigília"],
            familias: [DeskFamily(nome: "ChatGPT", ram: 4 << 30, cpu: 8, processos: 80, podeEncerrar: true)],
            agentesRepetidos: [DeskDuplicate(titulo: "After Effects MCP", copias: 24, ram: 400 << 20)],
            perfilSugerido: "Mesa",
            spotlight: false,
            versao: "2.1"
        )
        let text = DeskStateStore.markdown(state)
        XCTAssertTrue(text.contains("Vigília: Máquina"))
        XCTAssertTrue(text.contains("ChatGPT"))
        XCTAssertTrue(text.contains("After Effects MCP"))
        XCTAssertTrue(text.contains("iPhone"))
        XCTAssertFalse(text.contains("/tmp"))
        XCTAssertFalse(text.contains(".mjs"))
        XCTAssertFalse(text.contains("script.mjs"))
    }

    func testCPUScaleConvertsMachTicksOnAppleSilicon() {
        let silicon = CPUScale.percent(
            deltaTicks: 24_000_000,
            wallNanoseconds: 1_000_000_000,
            numer: 125,
            denom: 3
        )
        XCTAssertEqual(silicon, 100, accuracy: 0.01)
        let intel = CPUScale.percent(
            deltaTicks: 1_000_000_000,
            wallNanoseconds: 1_000_000_000,
            numer: 1,
            denom: 1
        )
        XCTAssertEqual(intel, 100, accuracy: 0.01)
        XCTAssertEqual(CPUScale.percent(deltaTicks: 24_000_000, wallNanoseconds: 0, numer: 125, denom: 3), 0)
    }

    func testPSSnapshotParsesSystemProcessLine() {
        let rows = PSSnapshot.parse("""
          418  41.6  2048000 88 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
        """)
        XCTAssertEqual(rows[418]?.cpuPercent ?? 0, 41.6, accuracy: 0.01)
        XCTAssertEqual(rows[418]?.residentBytes, 2048000 * 1024)
        XCTAssertEqual(rows[418]?.uid, 88)
        let comma = PSSnapshot.parse("418 12,5 10 501 WindowServer extra\n")
        XCTAssertEqual(comma[418]?.cpuPercent ?? 0, 12.5, accuracy: 0.01)
        XCTAssertEqual(comma[418]?.command, "WindowServer extra")
    }
}
