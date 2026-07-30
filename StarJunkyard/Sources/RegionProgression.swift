import Foundation

struct RegionProgression: Sendable {
    struct Transition: Equatable, Sendable {
        let fromRegionID: String
        let toRegionID: String
        let title: String
        let departureStory: String
        let arrivalStory: String
        let baseForm: String
    }

    static func region(
        containing stageNumber: Int,
        regions: [VerticalSliceContent.Region]
    ) -> VerticalSliceContent.Region? {
        regions.first { $0.stageStart <= stageNumber && stageNumber <= $0.stageEnd }
    }

    static func transition(
        from oldStage: Int,
        to newStage: Int,
        regions: [VerticalSliceContent.Region]
    ) -> Transition? {
        guard
            let oldRegion = region(containing: oldStage, regions: regions),
            let newRegion = region(containing: newStage, regions: regions),
            oldRegion.id != newRegion.id,
            oldRegion.nextRegionId == newRegion.id
        else { return nil }
        return Transition(
            fromRegionID: oldRegion.id,
            toRegionID: newRegion.id,
            title: "R\(newRegion.number) • \(newRegion.nameKo)",
            departureStory: oldRegion.completionStoryKo,
            arrivalStory: newRegion.arrivalStoryKo,
            baseForm: newRegion.baseFormKo
        )
    }
}
