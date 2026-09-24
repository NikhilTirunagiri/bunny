import Testing
import CoreGraphics
import Foundation
@testable import BunnyCore

struct TaskMoveRulesTests {
    // MARK: - zone(y:height:)

    @Test func zoneBoundaries() {
        #expect(TaskMoveRules.zone(y: 0, height: 100) == .above)
        #expect(TaskMoveRules.zone(y: 29, height: 100) == .above)
        #expect(TaskMoveRules.zone(y: 30, height: 100) == .into)
        #expect(TaskMoveRules.zone(y: 50, height: 100) == .into)
        #expect(TaskMoveRules.zone(y: 70, height: 100) == .into)
        #expect(TaskMoveRules.zone(y: 71, height: 100) == .below)
        #expect(TaskMoveRules.zone(y: 100, height: 100) == .below)
    }

    // MARK: - Reorder top-level tasks (dense renumbering)

    @Test func reorderTopLevelAbove() {
        let a = UUID(), b = UUID(), c = UUID()
        let nodes = [
            TaskNode(id: a, parentID: nil, sortOrder: 0),
            TaskNode(id: b, parentID: nil, sortOrder: 1),
            TaskNode(id: c, parentID: nil, sortOrder: 2),
        ]
        // Drag C above A: expected order [C, A, B] -> sortOrders 0, 1, 2.
        let placements = TaskMoveRules.move(dragged: c, target: a, zone: .above, nodes: nodes)
        let byID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })
        #expect(byID.count == 3)
        #expect(byID[c] == TaskPlacement(id: c, parentID: nil, sortOrder: 0))
        #expect(byID[a] == TaskPlacement(id: a, parentID: nil, sortOrder: 1))
        #expect(byID[b] == TaskPlacement(id: b, parentID: nil, sortOrder: 2))
    }

    @Test func reorderTopLevelBelow() {
        let a = UUID(), b = UUID(), c = UUID()
        let nodes = [
            TaskNode(id: a, parentID: nil, sortOrder: 0),
            TaskNode(id: b, parentID: nil, sortOrder: 1),
            TaskNode(id: c, parentID: nil, sortOrder: 2),
        ]
        // Drag A below B: expected order [B, A, C] -> sortOrders 0, 1, 2.
        let placements = TaskMoveRules.move(dragged: a, target: b, zone: .below, nodes: nodes)
        let byID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })
        #expect(byID.count == 2)
        #expect(byID[b] == TaskPlacement(id: b, parentID: nil, sortOrder: 0))
        #expect(byID[a] == TaskPlacement(id: a, parentID: nil, sortOrder: 1))
        #expect(byID[c] == nil)
    }

    // MARK: - Into: top-level task without subtasks becomes a subtask

    @Test func intoTopLevelWithoutSubtasksBecomesLastChild() {
        let a = UUID(), a1 = UUID(), a2 = UUID(), c = UUID()
        let nodes = [
            TaskNode(id: a, parentID: nil, sortOrder: 0),
            TaskNode(id: a1, parentID: a, sortOrder: 0),
            TaskNode(id: a2, parentID: a, sortOrder: 1),
            TaskNode(id: c, parentID: nil, sortOrder: 1),
        ]
        #expect(TaskMoveRules.resolve(dragged: c, target: a, zone: .into, nodes: nodes) == .into)
        let placements = TaskMoveRules.move(dragged: c, target: a, zone: .into, nodes: nodes)
        #expect(placements == [TaskPlacement(id: c, parentID: a, sortOrder: 2)])
    }

    // MARK: - Into degrades to below when the dragged task has subtasks

    @Test func intoDegradesToBelowWhenDraggedHasSubtasks() {
        let a = UUID(), a1 = UUID(), a2 = UUID(), b = UUID(), c = UUID()
        let nodes = [
            TaskNode(id: a, parentID: nil, sortOrder: 0),
            TaskNode(id: b, parentID: nil, sortOrder: 1),
            TaskNode(id: c, parentID: nil, sortOrder: 2),
            TaskNode(id: a1, parentID: a, sortOrder: 0),
            TaskNode(id: a2, parentID: a, sortOrder: 1),
        ]
        #expect(TaskMoveRules.resolve(dragged: a, target: c, zone: .into, nodes: nodes) == .below)
        // A stays top-level, landing after C: [B, C, A] -> sortOrders 0, 1, 2.
        let placements = TaskMoveRules.move(dragged: a, target: c, zone: .into, nodes: nodes)
        let byID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })
        #expect(byID[a] == TaskPlacement(id: a, parentID: nil, sortOrder: 2))
        #expect(byID[b] == TaskPlacement(id: b, parentID: nil, sortOrder: 0))
        #expect(byID[c] == TaskPlacement(id: c, parentID: nil, sortOrder: 1))
        // A's own subtasks are untouched: they move with their parent.
        #expect(byID[a1] == nil)
        #expect(byID[a2] == nil)
    }

    // MARK: - Into degrades to below when the target is a subtask

    @Test func intoDegradesToBelowWhenTargetIsSubtask() {
        let a = UUID(), b = UUID(), b1 = UUID(), c = UUID()
        let nodes = [
            TaskNode(id: a, parentID: nil, sortOrder: 0),
            TaskNode(id: b, parentID: nil, sortOrder: 1),
            TaskNode(id: b1, parentID: b, sortOrder: 0),
            TaskNode(id: c, parentID: nil, sortOrder: 2),
        ]
        #expect(TaskMoveRules.resolve(dragged: c, target: b1, zone: .into, nodes: nodes) == .below)
        // C becomes a sibling of B1 under B, placed after it.
        let placements = TaskMoveRules.move(dragged: c, target: b1, zone: .into, nodes: nodes)
        #expect(placements == [TaskPlacement(id: c, parentID: b, sortOrder: 1)])
    }

    // MARK: - Un-nesting: subtask moved above/below a top-level task becomes top-level

    @Test func subtaskAboveTopLevelBecomesTopLevel() {
        let a = UUID(), a1 = UUID(), a2 = UUID(), b = UUID(), c = UUID()
        let nodes = [
            TaskNode(id: a, parentID: nil, sortOrder: 0),
            TaskNode(id: b, parentID: nil, sortOrder: 1),
            TaskNode(id: c, parentID: nil, sortOrder: 2),
            TaskNode(id: a1, parentID: a, sortOrder: 0),
            TaskNode(id: a2, parentID: a, sortOrder: 1),
        ]
        // Drag A2 above C: A2 un-nests, landing just before C: [A, B, A2, C].
        let placements = TaskMoveRules.move(dragged: a2, target: c, zone: .above, nodes: nodes)
        let byID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })
        #expect(byID[a2] == TaskPlacement(id: a2, parentID: nil, sortOrder: 2))
        #expect(byID[c] == TaskPlacement(id: c, parentID: nil, sortOrder: 3))
        #expect(byID[a] == nil)
        #expect(byID[b] == nil)
        // A1 is A's only remaining subtask and was already at sortOrder 0: unchanged.
        #expect(byID[a1] == nil)
        #expect(byID.count == 2)
    }

    // MARK: - Reorder within the same parent

    @Test func moveSubtaskWithinItsParent() {
        let a = UUID(), a1 = UUID(), a2 = UUID()
        let nodes = [
            TaskNode(id: a, parentID: nil, sortOrder: 0),
            TaskNode(id: a1, parentID: a, sortOrder: 0),
            TaskNode(id: a2, parentID: a, sortOrder: 1),
        ]
        // Drag A1 below A2: [A2, A1] -> sortOrders 0, 1.
        let placements = TaskMoveRules.move(dragged: a1, target: a2, zone: .below, nodes: nodes)
        let byID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })
        #expect(byID.count == 2)
        #expect(byID[a2] == TaskPlacement(id: a2, parentID: a, sortOrder: 0))
        #expect(byID[a1] == TaskPlacement(id: a1, parentID: a, sortOrder: 1))
    }

    // MARK: - No-ops

    @Test func droppingOnItselfIsNoOp() {
        let a = UUID()
        let nodes = [TaskNode(id: a, parentID: nil, sortOrder: 0)]
        #expect(TaskMoveRules.resolve(dragged: a, target: a, zone: .above, nodes: nodes) == nil)
        #expect(TaskMoveRules.move(dragged: a, target: a, zone: .above, nodes: nodes) == [])
    }

    @Test func droppingParentOntoOwnSubtaskIsNoOp() {
        let a = UUID(), a1 = UUID()
        let nodes = [
            TaskNode(id: a, parentID: nil, sortOrder: 0),
            TaskNode(id: a1, parentID: a, sortOrder: 0),
        ]
        #expect(TaskMoveRules.resolve(dragged: a, target: a1, zone: .into, nodes: nodes) == nil)
        #expect(TaskMoveRules.move(dragged: a, target: a1, zone: .into, nodes: nodes) == [])
    }

    // MARK: - Cross-parent move renumbers both sibling lists

    @Test func movingSubtaskToDifferentParentRenumbersBothParents() {
        let a = UUID(), a1 = UUID(), a2 = UUID()
        let b = UUID(), b1 = UUID()
        let nodes = [
            TaskNode(id: a, parentID: nil, sortOrder: 0),
            TaskNode(id: a1, parentID: a, sortOrder: 0),
            TaskNode(id: a2, parentID: a, sortOrder: 1),
            TaskNode(id: b, parentID: nil, sortOrder: 1),
            TaskNode(id: b1, parentID: b, sortOrder: 0),
        ]
        // Drag A1 below B1: A1 leaves A (A2 renumbers to 0) and joins B after B1.
        let placements = TaskMoveRules.move(dragged: a1, target: b1, zone: .below, nodes: nodes)
        let byID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0) })
        #expect(byID[a1] == TaskPlacement(id: a1, parentID: b, sortOrder: 1))
        #expect(byID[a2] == TaskPlacement(id: a2, parentID: a, sortOrder: 0))
        #expect(byID[b1] == nil)
    }
}
