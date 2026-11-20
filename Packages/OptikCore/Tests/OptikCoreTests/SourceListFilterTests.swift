import OptikCore
import Testing

struct SourceListFilterTests {
    private func run(_ pieces: [String]) -> String {
        var filter = SourceListFilter()
        return pieces.map { filter.filter($0) }.joined()
    }

    @Test func dropsASourceListStreamedInPieces() {
        let text = run(["Maç cumartesi 20.00’de.", "\n\nKay", "naklar: [Aspor](https://", "example.com)", "\n- [GZT](x)"])
        #expect(text == "Maç cumartesi 20.00’de.")
    }

    @Test func dropsEnglishAndBoldMarkers() {
        #expect(run(["Yarın yağmurlu.\n\n**Sources:**\n- [a](b)"]) == "Yarın yağmurlu.")
        #expect(run(["Yarın yağmurlu.\nSources:", " [a](b)"]) == "Yarın yağmurlu.")
    }

    @Test func keepsOrdinaryLines() {
        #expect(run(["İki şey var.\nKahve ", "13.00’te.\nKaynak suyu al."]) == "İki şey var.\nKahve 13.00’te.\nKaynak suyu al.")
        #expect(run(["Kaynaklar: başta da olsa sadece satır başı sayılır."]) == "Kaynaklar: başta da olsa sadece satır başı sayılır.")
    }
}
