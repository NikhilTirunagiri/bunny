import Testing
import Foundation
@testable import BunnyCore

struct AgentMarkersTests {
    @Test func markerChoices() {
        let text = "I need help.\n<bunny-question>{\"question\": \"Which env?\", \"options\": [\"dev\", \"prod\"]}</bunny-question>"
        let result = AgentMarkers.extractQuestion(from: text)
        #expect(result.text == "I need help.")
        #expect(result.question?.kind == .choices)
        #expect(result.question?.items.count == 1)
        #expect(result.question?.items.first?.key == "answer")
        #expect(result.question?.items.first?.question == "Which env?")
        #expect(result.question?.items.first?.options.map(\.label) == ["dev", "prod"])
        #expect(result.question?.items.first?.multiSelect == false)
        #expect(result.question?.items.first?.allowsOther == true)
    }

    @Test func markerFreeform() {
        let text = "Working on it.\n<bunny-question>{\"question\": \"What's the API key?\"}</bunny-question>"
        let result = AgentMarkers.extractQuestion(from: text)
        #expect(result.text == "Working on it.")
        #expect(result.question?.kind == .freeform)
        #expect(result.question?.items.count == 1)
        #expect(result.question?.items.first?.key == "answer")
        #expect(result.question?.items.first?.options.isEmpty == true)
        #expect(result.question?.items.first?.allowsOther == false)
    }

    @Test func markerInvalidJSONStripped() {
        let text = "Done.\n<bunny-question>not json</bunny-question>"
        let result = AgentMarkers.extractQuestion(from: text)
        #expect(result.text == "Done.")
        #expect(result.question == nil)
    }

    @Test func markerAbsent() {
        let text = "  Just plain text.  "
        let result = AgentMarkers.extractQuestion(from: text)
        #expect(result.text == "Just plain text.")
        #expect(result.question == nil)
    }

    @Test func subtasksDone() {
        let text = "Did it.\n<bunny-subtasks-done>1, 3,x</bunny-subtasks-done>"
        let result = AgentMarkers.extractCompletedSubtasks(from: text)
        #expect(result.text == "Did it.")
        #expect(result.numbers == [1, 3])
    }

    @Test func subtasksAbsent() {
        let text = "Nothing here."
        let result = AgentMarkers.extractCompletedSubtasks(from: text)
        #expect(result.text == "Nothing here.")
        #expect(result.numbers.isEmpty)
    }
}
