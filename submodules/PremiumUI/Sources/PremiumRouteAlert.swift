//
//  PremiumRouteAlert.swift
//  PremiumUI
//
//  Created by basiliusic on 13.08.2024.
//

import Foundation
import UIKit
import Display
import ComponentFlow
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramPresentationData
import PresentationDataUtils
import ViewControllerComponent
import AccountContext
import SolidRoundedButtonComponent
import MultilineTextComponent
import MultilineTextWithEntitiesComponent
import BundleIconComponent
import BlurredBackgroundComponent
import Markdown
import InAppPurchaseManager
import ConfettiEffect
import TextFormat
import InstantPageCache
import UniversalMediaPlayer
import CheckNode
import AnimationCache
import MultiAnimationRenderer
import TelegramNotices
import UndoUI
import TelegramStringFormatting
import ListSectionComponent
import ListActionItemComponent
import EmojiStatusSelectionComponent
import EmojiStatusComponent
import EntityKeyboard
import EmojiActionIconComponent
import ScrollComponent
import PremiumStarComponent

public func premiumAlertController(
    context: AccountContext,
    source: PremiumSource,
    wasDismissed: @escaping () -> Void = {}
) -> AlertController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    
    return textAlertController(
        context: context,
        title: presentationData.strings.Premium_Unavailable_title,
        text: presentationData.strings.Premium_Unavailable_message,
        actions: [
            .init(
                type: .defaultDestructiveAction,
                title: presentationData.strings.Common_OK,
                action: { wasDismissed() }
            ),
        ]
    )
}
