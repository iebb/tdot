import AccountContext
import Display
import Foundation
import ItemListUI
import NagramStrings
import SwiftSignalKit
import TelegramPresentationData
import UIKit

// MARK: NEXTGRAM — t. settings navigation; preferences and controls remain shared with Nagram.
enum TDotSettingsCategory: Int32, CaseIterable {
    case appearance
    case chats
    case messages
    case translation
    case privacy
    case history
    case automation
    case advanced

    var key: String {
        switch self {
        case .appearance: return "Appearance"
        case .chats: return "Chats"
        case .messages: return "Messages"
        case .translation: return "Translation"
        case .privacy: return "Privacy"
        case .history: return "History"
        case .automation: return "Automation"
        case .advanced: return "Advanced"
        }
    }

    var titleKey: String { "TDot.Settings.\(self.key)" }
    var summaryKey: String { "\(self.titleKey).Summary" }

    var section: Int32 {
        switch self {
        case .appearance, .chats, .messages, .translation: return 0
        case .privacy, .history: return 1
        case .automation, .advanced: return 2
        }
    }

    private var symbol: String {
        switch self {
        case .appearance: return "paintbrush.fill"
        case .chats: return "folder.fill"
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .translation: return "globe"
        case .privacy: return "hand.raised.fill"
        case .history: return "clock.arrow.circlepath"
        case .automation: return "arrow.triangle.2.circlepath"
        case .advanced: return "slider.horizontal.3"
        }
    }

    private var color: UIColor {
        switch self {
        case .appearance: return UIColor(rgb: 0xAF52DE)
        case .chats: return UIColor(rgb: 0x007AFF)
        case .messages: return UIColor(rgb: 0x34A759)
        case .translation: return UIColor(rgb: 0x00A6B5)
        case .privacy: return UIColor(rgb: 0x007AFF)
        case .history: return UIColor(rgb: 0xFF9500)
        case .automation: return UIColor(rgb: 0x5856D6)
        case .advanced: return UIColor(rgb: 0x8E8E93)
        }
    }

    func icon() -> UIImage {
        return UIGraphicsImageRenderer(size: CGSize(width: 29.0, height: 29.0)).image { _ in
            self.color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0.0, y: 0.0, width: 29.0, height: 29.0), cornerRadius: 6.0).fill()
            let image = UIImage(systemName: self.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16.0, weight: .semibold))?.withTintColor(.white, renderingMode: .alwaysOriginal)
            if let image {
                image.draw(at: CGPoint(x: floor((29.0 - image.size.width) / 2.0), y: floor((29.0 - image.size.height) / 2.0)))
            }
        }
    }
}

private enum TDotSettingsCategoryEntry: ItemListNodeEntry {
    case header(Int32, String)
    case category(TDotSettingsCategory, String, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _): return section
        case let .category(category, _, _): return category.section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(section, _): return 100 + section
        case let .category(category, _, _): return category.rawValue
        }
    }

    private var sortIndex: Int32 {
        switch self {
        case let .header(section, _): return [-1, 7, 11][Int(section)]
        case let .category(category, _, _): return category.rawValue * 2
        }
    }

    static func < (lhs: TDotSettingsCategoryEntry, rhs: TDotSettingsCategoryEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let open = arguments as! (TDotSettingsCategory) -> Void
        switch self {
        case let .header(section, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: section)
        case let .category(category, title, summary):
            let attributedTitle = NSAttributedString(string: title, font: Font.regular(presentationData.fontSize.itemListBaseFontSize), textColor: presentationData.theme.list.itemPrimaryTextColor)
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: category.icon(), title: title, attributedTitle: attributedTitle, label: summary, labelStyle: .multilineDetailText, sectionId: category.section, style: .blocks, action: {
                open(category)
            })
        }
    }
}

func tdotSettingsCategoriesController(context: AccountContext) -> ViewController {
    var openCategory: ((TDotSettingsCategory) -> Void)?
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let headers = ["Personalize", "PrivacyAndHistory", "Tools"]
        var entries: [TDotSettingsCategoryEntry] = []
        for section in 0 ... 2 {
            entries.append(.header(Int32(section), ngI18n("TDot.Settings.Section.\(headers[section])", lang)))
            for category in TDotSettingsCategory.allCases where category.section == Int32(section) {
                entries.append(.category(category, ngI18n(category.titleKey, lang), ngI18n(category.summaryKey, lang)))
            }
        }
        let open: (TDotSettingsCategory) -> Void = { openCategory?($0) }
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("t."), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), open)
        )
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    openCategory = { [weak controller] category in
        (controller?.navigationController as? NavigationController)?.pushViewController(nagramSettingsPageController(context: context, category: category), animated: true)
    }
    return controller
}
