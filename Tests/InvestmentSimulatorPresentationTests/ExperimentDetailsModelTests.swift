import Foundation
import InvestmentSimulatorPresentation
import Testing

@MainActor
struct ExperimentDetailsModelTests {
    @Test func `fields start with the experiment's name and notes`() {
        let model = ExperimentDetailsModel(name: "Index funds", notes: "Hold")

        #expect(model.name == "Index funds")
        #expect(model.notes == "Hold")
    }

    @Test func `missing name and notes start empty`() {
        let model = ExperimentDetailsModel(name: nil, notes: nil)

        #expect(model.name.isEmpty)
        #expect(model.notes.isEmpty)
    }

    @Test func `saved name and notes are trimmed, keeping inner line breaks`() {
        let model = ExperimentDetailsModel(name: nil, notes: nil)
        model.name = "  Index funds \n"
        model.notes = "\n Buy and hold.\nRebalance yearly.  \n"

        #expect(model.savedName == "Index funds")
        #expect(model.savedNotes == "Buy and hold.\nRebalance yearly.")
    }

    @Test(arguments: ["", "   ", " \n\t "])
    func `blank name and notes are saved as none`(text: String) {
        let model = ExperimentDetailsModel(name: "Index funds", notes: "Hold")
        model.name = text
        model.notes = text

        #expect(model.savedName == nil)
        #expect(model.savedNotes == nil)
    }
}
