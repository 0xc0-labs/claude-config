# Sources

Every bracketed key in `SKILL.md` and `example.md` resolves here. Links were
fetched on 2026-10-12. Claims marked "org convention; no source decides
this" are the org's choice, not any of these.

| Key | Source | What it backs |
|---|---|---|
| [Cockburn 2005] | Alistair Cockburn, "Hexagonal Architecture" (Ports and Adapters), HaT Technical Report 2005.02, 2005-09-04. <https://alistair.cockburn.us/hexagonal-architecture/> | The intent (run and test without UI or database), ports, adapters, primary (driving) and secondary (driven) sides, the test harness as a driver, configurable dependency, two to four ports |
| [Cockburn 2024] | Alistair Cockburn and Juan Manuel Garrido de Paz, "Hexagonal Architecture Explained", Humans and Technology, 2024 (updated 1st ed.). <https://alistaircockburn.company.site/Epub-Hexagonal-Architecture-Explained-Updated-1st-ed-p751233517> | The book-length treatment of the same pattern; the publisher page states its aim: simpler testing, no business-logic leakage, technologies swappable |
| [Martin 2011] | Robert C. Martin, "Screaming Architecture", 2011-09-30. <https://blog.cleancoder.com/uncle-bob/2011/09/30/Screaming-Architecture.html> | The top-level structure names the system's purpose; frameworks are tools; the web is a delivery detail; use cases testable without server or database |
| [Martin 2017] | Robert C. Martin, "Clean Architecture: A Craftsman's Guide to Software Structure and Design", Pearson, 2017, ISBN 978-0-13-449416-6. <https://www.informit.com/store/clean-architecture-a-craftsmans-guide-to-software-structure-9780134494166> | Ch. 11 dependency inversion; ch. 21 screaming architecture; ch. 22 the dependency rule and data crossing boundaries; ch. 26 the Main component; ch. 28 the test boundary; ch. 30–32 the database, the web and frameworks are details |

Chapter numbers refer to the first printing of [Martin 2017].
