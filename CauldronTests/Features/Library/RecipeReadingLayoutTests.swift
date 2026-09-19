import Foundation
import Testing
@testable import Cauldron

struct RecipeReadingLayoutTests {
    @Test(arguments: [320.0, 390.0, 466.0, 669.0, 759.0])
    func narrowWindowsKeepTheCompleteRecipeInOneColumn(width: Double) {
        #expect(!RecipeReadingLayout.usesColumns(availableWidth: width, accessibilityText: false))
    }

    @Test(arguments: [760.0, 900.0, 1_024.0, 1_366.0])
    func wideWindowsLeaveRoomForReadableInstructions(width: Double) {
        #expect(RecipeReadingLayout.usesColumns(availableWidth: width, accessibilityText: false))
        let workbench = RecipeReadingLayout.workbenchWidth(availableWidth: width)
        #expect(workbench >= 280 && workbench <= 360)
        #expect(width - workbench >= 440)
    }

    @Test(arguments: [466.0, 900.0, 1_366.0])
    func accessibilityTextNeverGetsSqueezedIntoColumns(width: Double) {
        #expect(!RecipeReadingLayout.usesColumns(availableWidth: width, accessibilityText: true))
    }
}
