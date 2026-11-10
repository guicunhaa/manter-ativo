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
        let census = ProcessGrouper.group(records, rules: [])
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
        let rules = [AgentRule(match: ["fixture-worker", "colour-blue"], title: "Fila A", key: "fila-a")]
        let command = "node /example/fixture-worker --colour-blue"
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
        XCTAssertEqual(WakeParser.flags(from: " lowpowermode 0\n highpowermode 1").powermode, 2)
        XCTAssertNil(WakeParser.flags(from: " sleep 0").powermode)
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
        XCTAssertFalse(holders.contains { $0.detail.contains("Electron") || $0.detail.contains("/bin/bash") })
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

    func testDeskStateMarkdownOmitsPaths() throws {
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
            agentes: [
                DeskAgent(titulo: "Notes MCP", cpu: 1.2, ram: 8 << 20, copias: 1),
                DeskAgent(titulo: "/tmp/exemplo/pasta", cpu: 1, ram: 1 << 20, copias: 2),
            ],
            perfilSugerido: "Mesa",
            spotlight: false,
            versao: "2.1"
        )
        let text = DeskStateStore.markdown(state)
        XCTAssertTrue(text.contains("Vigília: Máquina"))
        XCTAssertTrue(text.contains("ChatGPT"))
        XCTAssertTrue(text.contains("After Effects MCP"))
        XCTAssertTrue(text.contains("iPhone"))
        XCTAssertTrue(text.contains("Notes MCP"))
        XCTAssertTrue(text.contains(PTFormat.percent(1.2, digits: 1)))
        XCTAssertTrue(text.contains("1 cópia"))
        XCTAssertFalse(text.contains("/tmp"))
        XCTAssertFalse(text.contains(".mjs"))
        XCTAssertFalse(text.contains("script.mjs"))
        XCTAssertFalse(text.contains("pasta"))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("manter-ativo-desk-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        DeskStateStore.write(state, to: directory)
        let json = try String(contentsOf: directory.appendingPathComponent("estado.json"), encoding: .utf8)
        XCTAssertTrue(json.contains("Notes MCP"))
        XCTAssertTrue(json.contains("\"cpu\""))
        XCTAssertTrue(json.contains("\"ram\""))
        XCTAssertTrue(json.contains("\"copias\""))
        XCTAssertFalse(json.contains("/tmp"))
        XCTAssertFalse(json.contains(".mjs"))
        XCTAssertFalse(json.contains("pasta"))
        XCTAssertFalse(json.contains("\"pid\""))
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

    func testAgentShapesAreMeasuredWithEmptyRules() {
        let census = ProcessGrouper.group(agentFixtures(), rules: [])
        let notes = census.agents.first { $0.title == "Servidor MCP" }
        let aider = census.agents.first { $0.title == "Aider" }
        let chatgpt = census.agents.first { $0.title == "ChatGPT" }

        XCTAssertNotNil(notes)
        XCTAssertEqual(notes?.cpuPercent ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(notes?.residentBytes, 8 << 20)
        XCTAssertEqual(notes?.copyCount, 1)
        XCTAssertLessThan(notes?.residentBytes ?? 0, 40 * 1024 * 1024)
        XCTAssertLessThan(notes?.cpuPercent ?? 0, 8)
        XCTAssertFalse(["After Effects MCP", "Asana MCP", "VPS MCP"].contains(notes?.title ?? ""))

        XCTAssertEqual(aider?.copyCount, 2)
        XCTAssertEqual(aider?.keepPID, 20)
        XCTAssertEqual(aider?.extraPIDs, [30])
        XCTAssertEqual(aider?.cpuPercent ?? -1, 2.5, accuracy: 0.001)
        XCTAssertEqual(aider?.residentBytes, 22 << 20)
        XCTAssertLessThan(aider?.residentBytes ?? 0, 40 * 1024 * 1024)
        XCTAssertLessThan(aider?.cpuPercent ?? 0, 8)

        XCTAssertEqual(chatgpt?.copyCount, 1)
        XCTAssertEqual(chatgpt?.cpuPercent ?? -1, 3, accuracy: 0.001)
        XCTAssertEqual(chatgpt?.residentBytes, 30 << 20)

        let titles = Set(census.agents.map(\.title))
        XCTAssertFalse(titles.contains("Safari"))
        XCTAssertFalse(titles.contains("Mail"))
        XCTAssertFalse(titles.contains("node"))
        XCTAssertFalse(titles.contains("serve-static"))
        XCTAssertNil(census.agents.first { $0.title == "Fila local" })

        for name in ["WindowServer", "kernel_task", "launchd", "loginwindow", "Manter Ativo", "peripheralctl", "caffeinate"] {
            let family = census.families.first { $0.name == name }
            XCTAssertNotNil(family, name)
            XCTAssertEqual(family?.userKillable, false, name)
        }

        let rules = [AgentRule(match: ["fila-local", "worker"], title: "Fila local", key: "fila-local")]
        let named = ProcessGrouper.group(agentFixtures(), rules: rules)
        let fila = named.agents.first { $0.title == "Fila local" }
        XCTAssertEqual(fila?.title, "Fila local")
        XCTAssertEqual(fila?.copyCount, 1)
        XCTAssertNotNil(named.agents.first { $0.title == "Servidor MCP" })
        XCTAssertNotNil(named.agents.first { $0.title == "Aider" })
        XCTAssertNotNil(named.agents.first { $0.title == "ChatGPT" })
    }

    func testAppHelpersAreNotExtraCopiesAndSecretsStayOutOfTheTitle() {
        var records = agentFixtures()
        records.append(ProcessRecord(
            pid: 51,
            parentPid: 50,
            residentBytes: 4 << 20,
            cpuPercent: 0.2,
            path: "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node",
            command: "node /opt/tools/mcp-server-notes --flag token=fixture-private-argument",
            ownedByUser: true
        ))
        records.append(ProcessRecord(
            pid: 52,
            parentPid: 50,
            residentBytes: 6 << 20,
            cpuPercent: 0.4,
            path: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT",
            command: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT",
            ownedByUser: true
        ))
        records.append(ProcessRecord(
            pid: 53,
            parentPid: 1,
            residentBytes: 3 << 20,
            cpuPercent: 0.2,
            path: "/opt/homebrew/bin/node",
            command: "node /tmp/bin/helper --mcp token=fixture-private-argument-mcp",
            ownedByUser: true
        ))
        let census = ProcessGrouper.group(records, rules: [])
        let chatgpt = census.agents.first { $0.title == "ChatGPT" }
        XCTAssertEqual(chatgpt?.copyCount, 1)
        XCTAssertEqual(chatgpt?.keepPID, 50)
        XCTAssertEqual(chatgpt?.residentBytes, 40 << 20)
        XCTAssertNil(census.duplicates.first { $0.title == "ChatGPT" })

        let notes = census.agents.first { $0.keepPID == 40 }
        XCTAssertEqual(notes?.title, "Servidor MCP")
        XCTAssertEqual(notes?.copyCount, 1)
        XCTAssertFalse(notes?.title.contains("fixture-private") ?? true)
        XCTAssertFalse(census.agents.contains { $0.title.contains("=") || $0.title.contains("fixture-private") })
        XCTAssertTrue(census.agents.contains { $0.title == "Servidor MCP" })
    }

    func testHelpersInsideAnAppStayWithTheAppAndUnnamedServersDoNotShareTheRuntime() {
        var records = agentFixtures()
        records.append(ProcessRecord(
            pid: 54,
            parentPid: 50,
            residentBytes: 20 << 20,
            cpuPercent: 0.5,
            path: "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node",
            command: "node /Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node --mcp helper",
            ownedByUser: true
        ))
        records.append(ProcessRecord(
            pid: 31,
            parentPid: 20,
            residentBytes: 4 << 20,
            cpuPercent: 0.2,
            path: "/usr/local/bin/aider",
            command: "aider",
            ownedByUser: true
        ))
        records.append(ProcessRecord(
            pid: 80,
            parentPid: 1,
            residentBytes: 2 << 20,
            cpuPercent: 0.1,
            path: "/opt/homebrew/bin/node",
            command: "node /tmp/bin/alpha-tool --mcp",
            ownedByUser: true
        ))
        records.append(ProcessRecord(
            pid: 81,
            parentPid: 1,
            residentBytes: 2 << 20,
            cpuPercent: 0.1,
            path: "/opt/homebrew/bin/node",
            command: "node /tmp/bin/beta-tool --mcp",
            ownedByUser: true
        ))

        let census = ProcessGrouper.group(records, rules: [])
        let chatgpt = census.agents.first { $0.title == "ChatGPT" }
        XCTAssertEqual(chatgpt?.copyCount, 1)
        XCTAssertEqual(chatgpt?.keepPID, 50)
        XCTAssertEqual(chatgpt?.residentBytes, 50 << 20)
        XCTAssertFalse(census.agents.contains { $0.residentBytes == (20 << 20) && $0.title == "Servidor MCP" })

        let unnamed = census.agents.filter { $0.title == "Servidor MCP" }
        XCTAssertEqual(unnamed.count, 3)
        XCTAssertEqual(Set(unnamed.map(\.id)).count, 3)
        XCTAssertEqual(unnamed.map(\.copyCount), [1, 1, 1])


        let aider = census.agents.first { $0.title == "Aider" }
        XCTAssertEqual(aider?.copyCount, 2)
        XCTAssertEqual(aider?.keepPID, 20)
        XCTAssertEqual(aider?.residentBytes, 26 << 20)
    }

    func testGenericIdentityOmitsPrivateArgumentsAndKeepsDifferentServersSeparate() {
        let base = "node /example/server --mcp"
        let first = FamilyNamer.duplicateKey(command: base + " --token example-one")
        XCTAssertNotNil(first)
        XCTAssertEqual(first, FamilyNamer.duplicateKey(command: base + " --token example-two"))
        XCTAssertNotEqual(first, FamilyNamer.duplicateKey(command: "node /example/other --mcp"))
        XCTAssertEqual(FamilyNamer.agentTitle(command: "node /example/mcp-server-private-project"), "Servidor MCP")
    }

    func testAgentBarSnapshotSharesMeasuresAndKeepsProtectedProcesses() {
        let census = ProcessGrouper.group(agentFixtures(), rules: [])
        let snapshot = AgentBar.snapshot(census)

        XCTAssertEqual(snapshot.sectionTitle, "Agentes")
        XCTAssertEqual(snapshot.openPanelTitle, "Abrir painel")
        XCTAssertEqual(snapshot.quitTitle, "Sair (vigília fica)")
        XCTAssertTrue(snapshot.quitLeavesWakeOn)
        XCTAssertTrue(snapshot.quitTitle.contains("vigília"))

        for title in ["Servidor MCP", "Aider", "ChatGPT"] {
            let row = snapshot.rows.first { $0.title == title }
            XCTAssertNotNil(row, title)
            XCTAssertGreaterThan(row?.cpuPercent ?? 0, 0, title)
            XCTAssertGreaterThan(row?.residentBytes ?? 0, 0, title)
            XCTAssertGreaterThan(row?.copyCount ?? 0, 0, title)
            XCTAssertFalse(row?.cpuText.isEmpty ?? true, title)
            XCTAssertFalse(row?.memoryText.isEmpty ?? true, title)
            XCTAssertTrue(row?.copiesText.contains("cópia") ?? false, title)
            XCTAssertFalse(row?.title.contains("/") ?? true, title)
        }

        let aider = snapshot.rows.first { $0.title == "Aider" }
        XCTAssertEqual(aider?.copyCount, 2)
        XCTAssertTrue(aider?.copiesText.contains("2") ?? false)

        for name in ["WindowServer", "kernel_task", "launchd", "loginwindow", "Manter Ativo", "peripheralctl", "caffeinate"] {
            XCTAssertFalse(snapshot.killableNames.contains(name), name)
        }
        XCTAssertFalse(snapshot.rows.contains { $0.title.contains("/") })
    }

    private func agentFixtures() -> [ProcessRecord] {
        [
            ProcessRecord(pid: 40, parentPid: 1, residentBytes: 8 << 20, cpuPercent: 1, path: "/opt/homebrew/bin/node", command: "node /opt/tools/mcp-server-notes", ownedByUser: true),
            ProcessRecord(pid: 30, parentPid: 1, residentBytes: 12 << 20, cpuPercent: 1.5, path: "/usr/local/bin/aider", command: "aider", ownedByUser: true),
            ProcessRecord(pid: 20, parentPid: 1, residentBytes: 10 << 20, cpuPercent: 1, path: "/usr/local/bin/aider", command: "aider", ownedByUser: true),
            ProcessRecord(pid: 50, parentPid: 1, residentBytes: 30 << 20, cpuPercent: 3, path: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT", command: "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT", ownedByUser: true),
            ProcessRecord(pid: 60, parentPid: 1, residentBytes: 200 << 20, cpuPercent: 5, path: "/Applications/Safari.app/Contents/MacOS/Safari", command: "/Applications/Safari.app/Contents/MacOS/Safari", ownedByUser: true),
            ProcessRecord(pid: 61, parentPid: 1, residentBytes: 50 << 20, cpuPercent: 1, path: "/System/Applications/Mail.app/Contents/MacOS/Mail", command: "/System/Applications/Mail.app/Contents/MacOS/Mail", ownedByUser: true),
            ProcessRecord(pid: 62, parentPid: 1, residentBytes: 5 << 20, cpuPercent: 0.4, path: "/opt/homebrew/bin/node", command: "node /usr/local/lib/serve-static preview", ownedByUser: true),
            ProcessRecord(pid: 63, parentPid: 1, residentBytes: 6 << 20, cpuPercent: 0.3, path: "/opt/homebrew/bin/node", command: "node /opt/tools/fila-local worker", ownedByUser: true),
            ProcessRecord(pid: 70, parentPid: 1, residentBytes: 80 << 20, cpuPercent: 1, path: "/usr/local/bin/peripheralctl", command: "peripheralctl", ownedByUser: true),
            ProcessRecord(pid: 71, parentPid: 1, residentBytes: 50 << 20, cpuPercent: 1, path: "/usr/bin/caffeinate", command: "caffeinate -di", ownedByUser: true),
            ProcessRecord(pid: 72, parentPid: 1, residentBytes: 50 << 20, cpuPercent: 1, path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", command: "WindowServer", ownedByUser: true),
            ProcessRecord(pid: 73, parentPid: 1, residentBytes: 50 << 20, cpuPercent: 1, path: "/kernel_task", command: "kernel_task", ownedByUser: true),
            ProcessRecord(pid: 74, parentPid: 1, residentBytes: 50 << 20, cpuPercent: 1, path: "/sbin/launchd", command: "launchd", ownedByUser: true),
            ProcessRecord(pid: 75, parentPid: 1, residentBytes: 50 << 20, cpuPercent: 1, path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow", command: "loginwindow", ownedByUser: true),
            ProcessRecord(pid: 76, parentPid: 1, residentBytes: 50 << 20, cpuPercent: 1, path: "/Applications/Manter Ativo.app/Contents/MacOS/ManterAtivo", command: "ManterAtivo", ownedByUser: true),
        ]
    }
}
