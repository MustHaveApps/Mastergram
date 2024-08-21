import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import ContactListUI
import CallListUI
import ChatListUI
import SettingsUI
import AppBundle
import DatePickerNode
import DebugSettingsUI
import TabBarUI
import WallpaperBackgroundNode
import ChatPresentationInterfaceState
import CameraScreen
import MediaEditorScreen
import LegacyComponents
import LegacyMediaPickerUI
import LegacyCamera
import AvatarNode
import LocalMediaResources
import ImageCompression
import TextFormat
import MediaEditor
import PeerInfoScreen
import PeerInfoStoryGridScreen
import ShareWithPeersScreen
import ChatEmptyNode
import WebUI
import AttachmentUI
import WebsiteType
import UndoUI
import AlertUI
import TelegramNotices
import PresentationDataUtils

private class DetailsChatPlaceholderNode: ASDisplayNode, NavigationDetailsPlaceholderNode {
    private var presentationData: PresentationData
    private var presentationInterfaceState: ChatPresentationInterfaceState
    
    let wallpaperBackgroundNode: WallpaperBackgroundNode
    let emptyNode: ChatEmptyNode
    
    init(context: AccountContext) {
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationInterfaceState = ChatPresentationInterfaceState(chatWallpaper: self.presentationData.chatWallpaper, theme: self.presentationData.theme, strings: self.presentationData.strings, dateTimeFormat: self.presentationData.dateTimeFormat, nameDisplayOrder: self.presentationData.nameDisplayOrder, limitsConfiguration: context.currentLimitsConfiguration.with { $0 }, fontSize: self.presentationData.chatFontSize, bubbleCorners: self.presentationData.chatBubbleCorners, accountPeerId: context.account.peerId, mode: .standard(.default), chatLocation: .peer(id: context.account.peerId), subject: nil, peerNearbyData: nil, greetingData: nil, pendingUnpinnedAllMessages: false, activeGroupCallInfo: nil, hasActiveGroupCall: false, importState: nil, threadData: nil, isGeneralThreadClosed: nil, replyMessage: nil, accountPeerColor: nil, businessIntro: nil)
        
        self.wallpaperBackgroundNode = createWallpaperBackgroundNode(context: context, forChatDisplay: true, useSharedAnimationPhase: true)
        self.emptyNode = ChatEmptyNode(context: context, interaction: nil)
        
        super.init()
        
        self.addSubnode(self.wallpaperBackgroundNode)
        self.addSubnode(self.emptyNode)
    }
    
    func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData
        self.presentationInterfaceState = ChatPresentationInterfaceState(chatWallpaper: self.presentationData.chatWallpaper, theme: self.presentationData.theme, strings: self.presentationData.strings, dateTimeFormat: self.presentationData.dateTimeFormat, nameDisplayOrder: self.presentationData.nameDisplayOrder, limitsConfiguration: self.presentationInterfaceState.limitsConfiguration, fontSize: self.presentationData.chatFontSize, bubbleCorners: self.presentationData.chatBubbleCorners, accountPeerId: self.presentationInterfaceState.accountPeerId, mode: .standard(.default), chatLocation: self.presentationInterfaceState.chatLocation, subject: nil, peerNearbyData: nil, greetingData: nil, pendingUnpinnedAllMessages: false, activeGroupCallInfo: nil, hasActiveGroupCall: false, importState: nil, threadData: nil, isGeneralThreadClosed: nil, replyMessage: nil, accountPeerColor: nil, businessIntro: nil)
        
        self.wallpaperBackgroundNode.update(wallpaper: presentationData.chatWallpaper, animated: false)
    }
    
    func updateLayout(size: CGSize, needsTiling: Bool, transition: ContainedViewLayoutTransition) {
        let contentBounds = CGRect(origin: .zero, size: size)
        self.wallpaperBackgroundNode.updateLayout(size: size, displayMode: needsTiling ? .aspectFit : .aspectFill, transition: transition)
        transition.updateFrame(node: self.wallpaperBackgroundNode, frame: contentBounds)
        
        self.emptyNode.updateLayout(interfaceState: self.presentationInterfaceState, subject: .detailsPlaceholder, loadingNode: nil, backgroundNode: self.wallpaperBackgroundNode, size: contentBounds.size, insets: .zero, transition: transition)
        transition.updateFrame(node: self.emptyNode, frame: CGRect(origin: .zero, size: size))
        self.emptyNode.update(rect: contentBounds, within: contentBounds.size, transition: transition)
    }
}

public final class TelegramRootController: NavigationController, TelegramRootControllerInterface {
    private let context: AccountContext
    
    public var rootTabController: TabBarController?
    
    public var contactsController: ContactsController?
    public var callListController: CallListController?
    public var chatListController: ChatListController?
    public var accountSettingsController: PeerInfoScreen?
    
    private var permissionsDisposable: Disposable?
    private var presentationDataDisposable: Disposable?
    private var presentationData: PresentationData
    
    var updatedPresentationData: (PresentationData, Signal<PresentationData, NoError>) {
        return (self.presentationData, self.context.sharedContext.presentationData)
    }
    
    private var detailsPlaceholderNode: DetailsChatPlaceholderNode?
    
    private var applicationInFocusDisposable: Disposable?
    private var storyUploadEventsDisposable: Disposable?
    private let openWebAppDispossable = MetaDisposable()
    
    private let openMessageFromSearchDisposable: MetaDisposable = MetaDisposable()
    private let navigationActionDisposable = MetaDisposable()
    
    override public var minimizedContainer: MinimizedContainer? {
        didSet {
            self.minimizedContainer?.navigationController = self
            self.minimizedContainerUpdated(self.minimizedContainer)
        }
    }
    
    public var minimizedContainerUpdated: (MinimizedContainer?) -> Void = { _ in }
        
    public init(context: AccountContext) {
        self.context = context
        
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        super.init(mode: .automaticMasterDetail, theme: NavigationControllerTheme(presentationTheme: self.presentationData.theme))
        
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).startStrict(next: { [weak self] presentationData in
            if let strongSelf = self {
                strongSelf.detailsPlaceholderNode?.updatePresentationData(presentationData)
                
                let previousTheme = strongSelf.presentationData.theme
                strongSelf.presentationData = presentationData
                if previousTheme !== presentationData.theme {
                    (strongSelf.rootTabController as? TabBarControllerImpl)?.updateTheme(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData), theme: TabBarControllerTheme(rootControllerTheme: presentationData.theme))
                    strongSelf.rootTabController?.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
                }
            }
        })
        
        if context.sharedContext.applicationBindings.isMainApp {
            self.applicationInFocusDisposable = (context.sharedContext.applicationBindings.applicationIsActive
            |> distinctUntilChanged
            |> deliverOn(Queue.mainQueue())).startStrict(next: { value in
                context.sharedContext.mainWindow?.setForceBadgeHidden(!value)
            })
            
            self.storyUploadEventsDisposable = (context.engine.messages.allStoriesUploadEvents()
            |> deliverOnMainQueue).startStrict(next: { [weak self] event in
                guard let self else {
                    return
                }
                let (stableId, id) = event
                moveStorySource(engine: self.context.engine, peerId: self.context.account.peerId, from: Int64(stableId), to: Int64(id))
            })
        }
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.permissionsDisposable?.dispose()
        self.presentationDataDisposable?.dispose()
        self.applicationInFocusDisposable?.dispose()
        self.storyUploadEventsDisposable?.dispose()
    }
    
    public func getContactsController() -> ViewController? {
        return self.contactsController
    }
    
    public func getChatsController() -> ViewController? {
        return self.chatListController
    }
    
    public func getPrivacySettings() -> Promise<AccountPrivacySettings?>? {
        return self.accountSettingsController?.privacySettings
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let needsRootWallpaperBackgroundNode: Bool
        if case .regular = layout.metrics.widthClass {
            needsRootWallpaperBackgroundNode = true
        } else {
            needsRootWallpaperBackgroundNode = false
        }
        
        if needsRootWallpaperBackgroundNode {
            let detailsPlaceholderNode: DetailsChatPlaceholderNode
            if let current = self.detailsPlaceholderNode {
                detailsPlaceholderNode = current
            } else {
                detailsPlaceholderNode = DetailsChatPlaceholderNode(context: self.context)
                detailsPlaceholderNode.wallpaperBackgroundNode.update(wallpaper: self.presentationData.chatWallpaper, animated: false)
                self.detailsPlaceholderNode = detailsPlaceholderNode
            }
            self.updateDetailsPlaceholderNode(detailsPlaceholderNode)
        } else if let _ = self.detailsPlaceholderNode {
            self.detailsPlaceholderNode = nil
            self.updateDetailsPlaceholderNode(nil)
        }
    
        super.containerLayoutUpdated(layout, transition: transition)
    }
    
    public func addRootControllers(showCallsTab: Bool) {
        let tabBarController = TabBarControllerImpl(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData), theme: TabBarControllerTheme(rootControllerTheme: self.presentationData.theme))
        tabBarController.navigationPresentation = .master
        let chatListController = self.context.sharedContext.makeChatListController(context: self.context, location: .chatList(groupId: .root), controlsHistoryPreload: true, hideNetworkActivityStatus: false, previewing: false, enableDebugActions: !GlobalExperimentalSettings.isAppStoreBuild)
        if let sharedContext = self.context.sharedContext as? SharedAccountContextImpl {
            chatListController.tabBarItem.badgeValue = sharedContext.switchingData.chatListBadge
        }
        let callListController = CallListController(context: self.context, mode: .tab)
        
        var controllers: [ViewController] = []
        
        let contactsController = ContactsController(context: self.context)
        contactsController.switchToChatsController = {  [weak self] in
            self?.openChatsController(activateSearch: false)
        }
        controllers.append(contactsController)
        
//        if showCallsTab {
//            controllers.append(callListController)
//        }
        controllers.append(chatListController)
        
        var restoreSettignsController: (ViewController & SettingsController)?
        if let sharedContext = self.context.sharedContext as? SharedAccountContextImpl {
            restoreSettignsController = sharedContext.switchingData.settingsController
        }
        restoreSettignsController?.updateContext(context: self.context)
        if let sharedContext = self.context.sharedContext as? SharedAccountContextImpl {
            sharedContext.switchingData = (nil, nil, nil)
        }
        
        let accountSettingsController = PeerInfoScreenImpl(context: self.context, updatedPresentationData: nil, peerId: self.context.account.peerId, avatarInitiallyExpanded: false, isOpenedFromChat: false, nearbyPeerDistance: nil, reactionSourceMessageId: nil, callMessages: [], isSettings: true)
        accountSettingsController.tabBarItemDebugTapAction = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.pushViewController(debugController(sharedContext: strongSelf.context.sharedContext, context: strongSelf.context))
        }
        accountSettingsController.parentController = self
        controllers.append(accountSettingsController)
        
        tabBarController.appsItemAndAction = (
            UITabBarItem(title: presentationData.strings.TabBar_Apps, image: UIImage(named: "tab_apps", in: getAppBundle(), compatibleWith: nil), tag: 3),
            { [weak self] in
                self?.openApplication(url: "https://t.me/tapps_bot/center")
            }
        )
        tabBarController.cameraItemAndAction = (
            UITabBarItem(title: presentationData.strings.TabBar_Wallet, image: UIImage(named: "tab_wallet", in: getAppBundle(), compatibleWith: nil), tag: 4),
            { [weak self] in
                self?.openApplication(url: "https://t.me/wallet/start")
            }
        )
        
        tabBarController.setControllers(controllers, selectedIndex: restoreSettignsController != nil ? (controllers.count - 1) : (controllers.count - 2))
        
        self.contactsController = contactsController
        self.callListController = callListController
        self.chatListController = chatListController
        self.accountSettingsController = accountSettingsController
        self.rootTabController = tabBarController
        self.pushViewController(tabBarController, animated: false)
    }
        
    public func updateRootControllers(showCallsTab: Bool) {
        guard let rootTabController = self.rootTabController as? TabBarControllerImpl else {
            return
        }
        var controllers: [ViewController] = []
        controllers.append(self.contactsController!)
        if showCallsTab {
            controllers.append(self.callListController!)
        }
        controllers.append(self.chatListController!)
        controllers.append(self.accountSettingsController!)
        
        rootTabController.setControllers(controllers, selectedIndex: nil)
    }
    
    public func openChatsController(activateSearch: Bool, filter: ChatListSearchFilter = .chats, query: String? = nil) {
        guard let rootTabController = self.rootTabController else {
            return
        }
        
        if activateSearch {
            self.popToRoot(animated: false)
        }
        
        if let index = rootTabController.controllers.firstIndex(where: { $0 is ChatListController}) {
            rootTabController.selectedIndex = index
        }
        
        if activateSearch {
            self.chatListController?.activateSearch(filter: filter, query: query)
        }
    }
    
    public func openRootCompose() {
        self.chatListController?.activateCompose()
    }
    
    public func openRootCamera() {
        guard let controller = self.viewControllers.last as? ViewController else {
            return
        }
        controller.view.endEditing(true)
        presentedLegacyShortcutCamera(context: self.context, saveCapturedMedia: false, saveEditedPhotos: false, mediaGrouping: true, parentController: controller)
    }
    
    public func openAppIcon() {
        guard let rootTabController = self.rootTabController else {
            return
        }
        
        self.popToRoot(animated: false)
        
        if let index = rootTabController.controllers.firstIndex(where: { $0 is PeerInfoScreenImpl }) {
            rootTabController.selectedIndex = index
        }
        
        let themeController = themeSettingsController(context: self.context, focusOnItemTag: .icon)
        var controllers: [UIViewController] = Array(self.viewControllers.prefix(1))
        controllers.append(themeController)
        self.setViewControllers(controllers, animated: true)
    }
    
    @discardableResult
    public func openStoryCamera(customTarget: Stories.PendingTarget?, transitionIn: StoryCameraTransitionIn?, transitionedIn: @escaping () -> Void, transitionOut: @escaping (Stories.PendingTarget?, Bool) -> StoryCameraTransitionOut?) -> StoryCameraTransitionInCoordinator? {
        guard let controller = self.viewControllers.last as? ViewController else {
            return nil
        }
        controller.view.endEditing(true)
        
        let context = self.context
        
        let externalState = MediaEditorTransitionOutExternalState(
            storyTarget: nil,
            isForcedTarget: customTarget != nil,
            isPeerArchived: false,
            transitionOut: nil
        )
        
        var presentImpl: ((ViewController) -> Void)?
        var returnToCameraImpl: (() -> Void)?
        var dismissCameraImpl: (() -> Void)?
        var showDraftTooltipImpl: (() -> Void)?
        let cameraController = CameraScreen(
            context: context,
            mode: .story,
            transitionIn: transitionIn.flatMap {
                if let sourceView = $0.sourceView {
                    return CameraScreen.TransitionIn(
                        sourceView: sourceView,
                        sourceRect: $0.sourceRect,
                        sourceCornerRadius: $0.sourceCornerRadius
                    )
                } else {
                    return nil
                }
            },
            transitionOut: { finished in
                if let transitionOut = (externalState.transitionOut ?? transitionOut)(finished ? externalState.storyTarget : nil, externalState.isPeerArchived), let destinationView = transitionOut.destinationView {
                    return CameraScreen.TransitionOut(
                        destinationView: destinationView,
                        destinationRect: transitionOut.destinationRect,
                        destinationCornerRadius: transitionOut.destinationCornerRadius,
                        completion: transitionOut.completion
                    )
                } else {
                    return nil
                }
            },
            completion: { result, resultTransition, dismissed in
                let subject: Signal<MediaEditorScreen.Subject?, NoError> = result
                |> map { value -> MediaEditorScreen.Subject? in
                    func editorPIPPosition(_ position: CameraScreen.PIPPosition) -> MediaEditorScreen.PIPPosition {
                        switch position {
                        case .topLeft:
                            return .topLeft
                        case .topRight:
                            return .topRight
                        case .bottomLeft:
                            return .bottomLeft
                        case .bottomRight:
                            return .bottomRight
                        }
                    }
                    switch value {
                    case .pendingImage:
                        return nil
                    case let .image(image):
                        return .image(image.image, PixelDimensions(image.image.size), image.additionalImage, editorPIPPosition(image.additionalImagePosition))
                    case let .video(video):
                        return .video(video.videoPath, video.coverImage, video.mirror, video.additionalVideoPath, video.additionalCoverImage, video.dimensions, video.duration, video.positionChangeTimestamps, editorPIPPosition(video.additionalVideoPosition))
                    case let .asset(asset):
                        return .asset(asset)
                    case let .draft(draft):
                        return .draft(draft, nil)
                    }
                }
                
                var transitionIn: MediaEditorScreen.TransitionIn?
                if let resultTransition, let sourceView = resultTransition.sourceView {
                    transitionIn = .gallery(
                        MediaEditorScreen.TransitionIn.GalleryTransitionIn(
                            sourceView: sourceView,
                            sourceRect: resultTransition.sourceRect,
                            sourceImage: resultTransition.sourceImage
                        )
                    )
                } else {
                    transitionIn = .camera
                }
                
                let mediaEditorCustomTarget = customTarget.flatMap { value -> EnginePeer.Id? in
                    switch value {
                    case .myStories:
                        return nil
                    case let .peer(id):
                        return id
                    case let .botPreview(id, _):
                        return id
                    }
                }
                
                let controller = MediaEditorScreen(
                    context: context,
                    mode: .storyEditor,
                    subject: subject,
                    customTarget: mediaEditorCustomTarget,
                    transitionIn: transitionIn,
                    transitionOut: { finished, isNew in
                        if finished, let transitionOut = (externalState.transitionOut ?? transitionOut)(externalState.storyTarget, false), let destinationView = transitionOut.destinationView {
                            return MediaEditorScreen.TransitionOut(
                                destinationView: destinationView,
                                destinationRect: transitionOut.destinationRect,
                                destinationCornerRadius: transitionOut.destinationCornerRadius,
                                completion: transitionOut.completion
                            )
                        } else if !finished, let resultTransition, let (destinationView, destinationRect) = resultTransition.transitionOut(isNew) {
                            return MediaEditorScreen.TransitionOut(
                                destinationView: destinationView,
                                destinationRect: destinationRect,
                                destinationCornerRadius: 0.0,
                                completion: nil
                            )
                        } else {
                            return nil
                        }
                    }, completion: { [weak self] result, commit in
                        guard let self else {
                            dismissCameraImpl?()
                            commit({})
                            return
                        }
                        
                        if let customTarget, case .botPreview = customTarget {
                            externalState.storyTarget = customTarget
                            self.proceedWithStoryUpload(target: customTarget, result: result, existingMedia: nil, forwardInfo: nil, externalState: externalState, commit: commit)
                            
                            dismissCameraImpl?()
                            return
                         } else {
                             let target: Stories.PendingTarget
                             let targetPeerId: EnginePeer.Id
                             if let customTarget, case let .peer(id) = customTarget {
                                 target = .peer(id)
                                 targetPeerId = id
                             } else {
                                 if let sendAsPeerId = result.options.sendAsPeerId {
                                     target = .peer(sendAsPeerId)
                                     targetPeerId = sendAsPeerId
                                 } else {
                                     target = .myStories
                                     targetPeerId = context.account.peerId
                                 }
                             }
                             externalState.storyTarget = target
                             
                             let _ = (self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: targetPeerId))
                             |> deliverOnMainQueue).startStandalone(next: { [weak self] peer in
                                guard let self, let peer else {
                                    return
                                }
                                 
                                if case let .user(user) = peer {
                                    externalState.isPeerArchived = user.storiesHidden ?? false
                                } else if case let .channel(channel) = peer {
                                    externalState.isPeerArchived = channel.storiesHidden ?? false
                                }
                                 
                                self.proceedWithStoryUpload(target: target, result: result, existingMedia: nil, forwardInfo: nil, externalState: externalState, commit: commit)
                                
                                dismissCameraImpl?()
                            })
                        }
                    } as (MediaEditorScreen.Result, @escaping (@escaping () -> Void) -> Void) -> Void
                )
                controller.cancelled = { showDraftTooltip in
                    if showDraftTooltip {
                        showDraftTooltipImpl?()
                    }
                    returnToCameraImpl?()
                }
                controller.dismissed = {
                    dismissed()
                }
                presentImpl?(controller)
            }
        )
        cameraController.transitionedIn = transitionedIn
        controller.push(cameraController)
        presentImpl = { [weak cameraController] c in
            if let navigationController = cameraController?.navigationController as? NavigationController {
                var controllers = navigationController.viewControllers
                controllers.append(c)
                navigationController.setViewControllers(controllers, animated: false)
            }
        }
        dismissCameraImpl = { [weak cameraController] in
            cameraController?.dismiss(animated: false)
        }
        returnToCameraImpl = { [weak cameraController] in
            if let cameraController {
                cameraController.returnFromEditor()
            }
        }
        showDraftTooltipImpl = { [weak cameraController] in
            if let cameraController {
                cameraController.presentDraftTooltip()
            }
        }
        return StoryCameraTransitionInCoordinator(
            animateIn: { [weak cameraController] in
                if let cameraController {
                    cameraController.updateTransitionProgress(0.0, transition: .immediate)
                    cameraController.completeWithTransitionProgress(1.0, velocity: 0.0, dismissing: false)
                }
            },
            updateTransitionProgress: { [weak cameraController] transitionFraction in
                if let cameraController {
                    cameraController.updateTransitionProgress(transitionFraction, transition: .immediate)
                }
            },
            completeWithTransitionProgressAndVelocity: { [weak cameraController] transitionFraction, velocity in
                if let cameraController {
                    cameraController.completeWithTransitionProgress(transitionFraction, velocity: velocity, dismissing: false)
                }
            })
    }
    
    public func proceedWithStoryUpload(target: Stories.PendingTarget, result: MediaEditorScreenResult, existingMedia: EngineMedia?, forwardInfo: Stories.PendingForwardInfo?, externalState: MediaEditorTransitionOutExternalState, commit: @escaping (@escaping () -> Void) -> Void) {
        guard let result = result as? MediaEditorScreen.Result else {
            return
        }
        let context = self.context
        let targetPeerId: EnginePeer.Id?
        switch target {
        case let .peer(peerId):
            targetPeerId = peerId
        case .myStories:
            targetPeerId = context.account.peerId
        case .botPreview:
            targetPeerId = nil
        }

        if let rootTabController = self.rootTabController {
            if let index = rootTabController.controllers.firstIndex(where: { $0 is ChatListController}) {
                rootTabController.selectedIndex = index
            }
            if forwardInfo != nil {
                var viewControllers = self.viewControllers
                var dismissNext = false
                var range: Range<Int>?
                for i in (0 ..< viewControllers.count).reversed() {
                    let controller = viewControllers[i]
                    if controller is MediaEditorScreen {
                        dismissNext = true
                    }
                    if dismissNext {
                        if controller !== self.rootTabController {
                            if let current = range {
                                range = current.lowerBound - 1 ..< current.upperBound
                            } else {
                                range = i ..< i
                            }
                        } else {
                            break
                        }
                    }
                }
                if let range {
                    viewControllers.removeSubrange(range)
                    self.setViewControllers(viewControllers, animated: false)
                }
            } else if self.viewControllers.contains(where: { $0 is PeerInfoStoryGridScreen }) {
                var viewControllers: [UIViewController] = []
                for i in (0 ..< self.viewControllers.count) {
                    let controller = self.viewControllers[i]
                    if i == 0 {
                        viewControllers.append(controller)
                    } else if controller is MediaEditorScreen {
                        viewControllers.append(controller)
                    } else if controller is ShareWithPeersScreen {
                        viewControllers.append(controller)
                    }
                }
                self.setViewControllers(viewControllers, animated: false)
            }
        }
        
        let completionImpl: () -> Void = { [weak self] in
            guard let self else {
                return
            }
            
            var chatListController: ChatListControllerImpl?
            
            if externalState.isPeerArchived {
                var viewControllers = self.viewControllers
                
                let archiveController = ChatListControllerImpl(context: context, location: .chatList(groupId: .archive), controlsHistoryPreload: false, hideNetworkActivityStatus: false, previewing: false, enableDebugActions: false)
                if !externalState.isForcedTarget {
                    externalState.transitionOut = archiveController.storyCameraTransitionOut()
                }
                chatListController = archiveController
                viewControllers.insert(archiveController, at: 1)
                self.setViewControllers(viewControllers, animated: false)
            } else {
                chatListController = self.chatListController as? ChatListControllerImpl
                if !externalState.isForcedTarget {
                    externalState.transitionOut = chatListController?.storyCameraTransitionOut()
                }
            }
             
            if let chatListController {
                let _ = (chatListController.hasPendingStories
                |> filter { $0 }
                |> take(1)
                |> timeout(externalState.isPeerArchived ? 0.5 : 0.25, queue: .mainQueue(), alternate: .single(true))
                |> deliverOnMainQueue).startStandalone(completed: { [weak chatListController] in
                    guard let chatListController else {
                        return
                    }
                    
                    if let targetPeerId {
                        chatListController.scrollToStories(peerId: targetPeerId)
                    }
                    Queue.mainQueue().justDispatch {
                        commit({})
                    }
                })
            } else {
                Queue.mainQueue().justDispatch {
                    commit({})
                }
            }
        }
        
        if let _ = self.chatListController as? ChatListControllerImpl {
            var media: EngineStoryInputMedia?
            
            if let mediaResult = result.media {
                switch mediaResult {
                case let .image(image, dimensions):
                    let tempFile = TempBox.shared.tempFile(fileName: "file")
                    defer {
                        TempBox.shared.dispose(tempFile)
                    }
                    if let imageData = compressImageToJPEG(image, quality: 0.7, tempFilePath: tempFile.path) {
                        media = .image(dimensions: dimensions, data: imageData, stickers: result.stickers)
                    }
                case let .video(content, firstFrameImage, values, duration, dimensions):
                    let adjustments: VideoMediaResourceAdjustments
                    if let valuesData = try? JSONEncoder().encode(values) {
                        let data = MemoryBuffer(data: valuesData)
                        let digest = MemoryBuffer(data: data.md5Digest())
                        adjustments = VideoMediaResourceAdjustments(data: data, digest: digest, isStory: true)
                        
                        let resource: TelegramMediaResource
                        switch content {
                        case let .imageFile(path):
                            resource = LocalFileVideoMediaResource(randomId: Int64.random(in: .min ... .max), path: path, adjustments: adjustments)
                        case let .videoFile(path):
                            resource = LocalFileVideoMediaResource(randomId: Int64.random(in: .min ... .max), path: path, adjustments: adjustments)
                        case let .asset(localIdentifier):
                            resource = VideoLibraryMediaResource(localIdentifier: localIdentifier, conversion: .compress(adjustments))
                        }
                        let tempFile = TempBox.shared.tempFile(fileName: "file")
                        defer {
                            TempBox.shared.dispose(tempFile)
                        }
                        let imageData = firstFrameImage.flatMap { compressImageToJPEG($0, quality: 0.6, tempFilePath: tempFile.path) }
                        let firstFrameFile = imageData.flatMap { data -> TempBoxFile? in
                            let file = TempBox.shared.tempFile(fileName: "image.jpg")
                            if let _ = try? data.write(to: URL(fileURLWithPath: file.path)) {
                                return file
                            } else {
                                return nil
                            }
                        }
                        
                        var coverTime: Double?
                        if let coverImageTimestamp = values.coverImageTimestamp {
                            if let trimRange = values.videoTrimRange {
                                coverTime = min(duration, coverImageTimestamp - trimRange.lowerBound)
                            } else {
                                coverTime = min(duration, coverImageTimestamp)
                            }
                        }
                        
                        media = .video(dimensions: dimensions, duration: duration, resource: resource, firstFrameFile: firstFrameFile, stickers: result.stickers, coverTime: coverTime)
                    }
                default:
                    break
                }
            } else if let existingMedia {
                media = .existing(media: existingMedia._asMedia())
            }
            
            if let media {
                let _ = (context.engine.messages.uploadStory(
                    target: target,
                    media: media,
                    mediaAreas: result.mediaAreas,
                    text: result.caption.string,
                    entities: generateChatInputTextEntities(result.caption),
                    pin: result.options.pin,
                    privacy: result.options.privacy,
                    isForwardingDisabled: result.options.isForwardingDisabled,
                    period: result.options.timeout,
                    randomId: result.randomId,
                    forwardInfo: forwardInfo
                )
                |> deliverOnMainQueue).startStandalone(next: { stableId in
                    moveStorySource(engine: context.engine, peerId: context.account.peerId, from: result.randomId, to: Int64(stableId))
                })
            }
            completionImpl()
        }
    }
    
    public func openSettings() {
        guard let rootTabController = self.rootTabController else {
            return
        }
        
        self.popToRoot(animated: false)
    
        if let index = rootTabController.controllers.firstIndex(where: { $0 is PeerInfoScreenImpl }) {
            rootTabController.selectedIndex = index
        }
    }
    
    public func openBirthdaySetup() {
        self.accountSettingsController?.openBirthdaySetup()
    }
    
    private func openBotAppFromURL(
        context: AccountContext,
        url: String,
        navigationController: NavigationController?,
        dismissInput: @escaping () -> Void
    ) {
        guard let navigationController = navigationController else { return }
        
        let _ = (
            context.sharedContext.resolveUrl(
                context: context,
                peerId: nil,
                url: url,
                skipUrlAuth: true
            )
            |> deliverOnMainQueue
        ).startStandalone(next: { resolved in
            context.sharedContext.openResolvedUrl(
                resolved,
                context: context,
                urlContext: .generic,
                navigationController: navigationController,
                forceExternal: false,
                openPeer: { [weak self] peer, navigation in
                    guard let self else { return }
                    switch navigation {
                    case let .withBotApp(botAppStart):
                        if let botApp = botAppStart.botApp {
                            context.sharedContext.applicationBindings.dismissNativeController()
                            
                            self.presentBotApp(
                                botApp: botApp,
                                botPeer: peer,
                                peerId: peer.id,
                                payload: botAppStart.payload,
                                compact: false
                            )
                        }
                    default:
                        break
                    }
                },
                sendFile: nil,
                sendSticker: nil,
                sendEmoji: nil,
                requestMessageActionUrlAuth: nil,
                joinVoiceChat: { peerId, invite, call in
                    
                }, present: { c, a in
                    context.sharedContext.applicationBindings.dismissNativeController()
                    
                    c.presentationArguments = a
                    
                    context.sharedContext.applicationBindings.getWindowHost()?.present(c, on: .root, blockInteraction: false, completion: {})
                }, dismissInput: {
                    dismissInput()
                }, contentContext: nil, progress: nil, completion: nil)
        })
    }
    
    private func presentBotApp(
        botApp: BotApp,
        botPeer: EnginePeer,
        peerId: PeerId,
        payload: String?,
        compact: Bool,
        concealed: Bool = false,
        commit: @escaping () -> Void = {}
    ) {
        if let navigationController = self.rootTabController?.currentController?.navigationController as? NavigationController,
           let minimizedContainer = navigationController.minimizedContainer
        {
            for controller in minimizedContainer.controllers {
                if let controller = controller as? AttachmentController,
                    let mainController = controller.mainController as? WebAppController,
                   mainController.botId == peerId
                {
                    navigationController.maximizeViewController(controller, animated: true)
                    commit()
                    return
                }
            }
        }
        
        let openBotApp: (Bool, Bool) -> Void = { [weak self] allowWrite, justInstalled in
            guard let self else { return }
            commit()
            
            //            let botAddress = botPeer.addressName ?? ""
            self.openWebAppDispossable.set(
                (self.context.engine.messages.requestAppWebView(
                    peerId: peerId,
                    appReference: .id(id: botApp.id, accessHash: botApp.accessHash),
                    payload: payload,
                    themeParams: generateWebAppThemeParams(self.presentationData.theme),
                    compact: compact,
                    allowWrite: allowWrite
                )
                 |> deliverOnMainQueue)
                .startStrict(next: { [weak self] result in
                    guard let self else { return }
                    
                    let params = WebAppParameters(
                        source: .generic,
                        peerId: peerId,
                        botId: botPeer.id,
                        botName: botApp.title,
                        botVerified: botPeer.isVerified,
                        url: result.url,
                        queryId: 0,
                        payload: payload,
                        buttonText: "",
                        keepAliveSignal: nil,
                        forceHasSettings: botApp.flags.contains(.hasSettings),
                        fullSize: result.flags.contains(.fullSize)
                    )
                    
                    let controller = standaloneWebAppController(
                        context: self.context,
                        updatedPresentationData: self.updatedPresentationData,
                        params: params,
                        threadId: nil,
                        openUrl: { [weak self] url, concealed, commit in
                            self?.openUrl(
                                url,
                                concealed: concealed,
                                forceExternal: true,
                                commit: commit
                            )
                        },
                        requestSwitchInline: { query, chatTypes, completion in
                        }, completion: {},
                        getNavigationController: { [weak self] in
                            self?.navigationController as? NavigationController
                        }
                    )
                    
                    controller.navigationPresentation = .flatModal
                    
                    self.rootTabController?.currentController?.push(controller)
                }, error: { [weak self] error in
                    guard let self else { return }
                    
                    self.currentWindow?.present(
                        textAlertController(
                            context: self.context,
                            updatedPresentationData: self.updatedPresentationData,
                            title: nil,
                            text: self.presentationData.strings.Login_UnknownError,
                            actions: [
                                TextAlertAction(
                                    type: .defaultAction,
                                    title: self.presentationData.strings.Common_OK,
                                    action: {}
                                )
                            ]
                        ),
                        on: .root,
                        blockInteraction: false,
                        completion: {}
                    )
                })
            )
        }
        
        let _ = combineLatest(
            queue: Queue.mainQueue(),
            ApplicationSpecificNotice.getBotGameNotice(
                accountManager: self.context.sharedContext.accountManager,
                peerId: botPeer.id
            ),
            self.context.engine.messages.attachMenuBots(),
            self.context.engine.messages.getAttachMenuBot(botId: botPeer.id, cached: true)
            |> map(Optional.init)
            |> `catch` { _ -> Signal<AttachMenuBot?, NoError> in return .single(nil) }
        ).startStandalone(next: { [weak self] noticed, attachMenuBots, attachMenuBot in
            guard let self else { return }
            
            var isAttachMenuBotInstalled: Bool?
            if let _ = attachMenuBot {
                if let _ = attachMenuBots.first(where: { $0.peer.id == botPeer.id && !$0.flags.contains(.notActivated) }) {
                    isAttachMenuBotInstalled = true
                } else {
                    isAttachMenuBotInstalled = false
                }
            }
            
            let context = self.context
            if !noticed || botApp.flags.contains(.notActivated) || isAttachMenuBotInstalled == false {
                if let isAttachMenuBotInstalled,
                   let attachMenuBot {
                    if !isAttachMenuBotInstalled {
                        let controller = webAppTermsAlertController(
                            context: context,
                            updatedPresentationData: self.updatedPresentationData,
                            bot: attachMenuBot,
                            completion: {
                                allowWrite in
                                let _ = ApplicationSpecificNotice.setBotGameNotice(
                                    accountManager: context.sharedContext.accountManager,
                                    peerId: botPeer.id
                                ).startStandalone()
                                let _ = (
                                    context.engine.messages.addBotToAttachMenu(
                                        botId: botPeer.id,
                                        allowWrite: allowWrite
                                    )
                                    |> deliverOnMainQueue
                                ).startStandalone(error: { _ in
                                }, completed: {
                                    openBotApp(allowWrite, true)
                                })
                            }
                        )
                        self.rootTabController?.currentController?
                            .present(controller, in: .window(.root))
                    } else {
                        openBotApp(false, false)
                    }
                } else {
                    let controller = webAppLaunchConfirmationController(
                        context: context,
                        updatedPresentationData: self.updatedPresentationData,
                        peer: botPeer,
                        requestWriteAccess: botApp.flags.contains(.notActivated) && botApp.flags.contains(.requiresWriteAccess),
                        completion: { allowWrite in
                            let _ = ApplicationSpecificNotice.setBotGameNotice(
                                accountManager: context.sharedContext.accountManager,
                                peerId: botPeer.id
                            ).startStandalone()
                            
                            openBotApp(allowWrite, false)
                        }, showMore: { //[weak self] in
                            //                            if let self {
                            //                                self.openResolved(result: .peer(botPeer._asPeer(), .info(nil)), sourceMessageId: nil)
                            //                            }
                        },
                        openTerms: {}
                    )
                    self.rootTabController?.currentController?
                        .present(controller, in: .window(.root))
                }
            } else {
                openBotApp(false, false)
            }
        })
        
    }
    
    private func openUrl(
        _ url: String,
        concealed: Bool,
        forceExternal: Bool = false,
        skipUrlAuth: Bool = false,
        skipConcealedAlert: Bool = false,
        message: Message? = nil,
        allowInlineWebpageResolution: Bool = false,
        progress: Promise<Bool>? = nil,
        commit: @escaping () -> Void = {}
    ) {
        if allowInlineWebpageResolution,
            let message,
           let webpage = message.media.first(where: { $0 is TelegramMediaWebpage }) as? TelegramMediaWebpage,
           case let .Loaded(content) = webpage.content,
           content.url == url
        {
            if content.instantPage != nil {
                if let navigationController = self.navigationController as? NavigationController {
                    switch instantPageType(of: content) {
                    case .album:
                        break
                    default:
                        progress?.set(.single(false))
                        
                        if let controller = self.context.sharedContext.makeInstantPageController(context: self.context, message: message, sourcePeerType: nil) {
                            navigationController.pushViewController(controller)
                        }
                        
                        return
                    }
                }
            }
        }
        
        let disposable = openUserGeneratedUrl(
            context: self.context,
            peerId: nil,
            url: url,
            concealed: concealed,
            skipUrlAuth: skipUrlAuth,
            skipConcealedAlert: skipConcealedAlert,
            present: { [weak self] c in
                self?.currentWindow?.present(
                    c,
                    on: .root,
                    blockInteraction: false,
                    completion: {}
                )
            }, openResolved: { [weak self] resolved in
                guard let self else { return }
                
                self.context.sharedContext.openResolvedUrl(
                    resolved,
                    context: self.context,
                    urlContext: .generic,
                    navigationController: self.navigationController as? NavigationController,
                    forceExternal: forceExternal,
                    openPeer: { [weak self] peerId, navigation in
                        guard let self else { return }
                        
                        let dismissWebAppControllers: () -> Void = {
                        }
                        
                        switch navigation {
                        case let .chat(textInputState, subject, peekData):
                            dismissWebAppControllers()
                            if let navigationController = self.navigationController as? NavigationController {
                                if case let .channel(channel) = peerId, channel.flags.contains(.isForum) {
                                    self.context.sharedContext.navigateToForumChannel(context: self.context, peerId: peerId.id, navigationController: navigationController)
                                } else {
                                    self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: self.context, chatLocation: .peer(peerId), subject: subject, updateTextInputState: !peerId.id.isGroupOrChannel ? textInputState : nil, keepStack: .always, peekData: peekData))
                                }
                            }
                            commit()
                        case .info:
                            dismissWebAppControllers()
                            self.navigationActionDisposable.set((self.context.account.postbox.loadedPeerWithId(peerId.id)
                                                                       |> take(1)
                                                                       |> deliverOnMainQueue).startStrict(next: { [weak self] peer in
                                if let self = self, peer.restrictionText(platform: "ios", contentSettings: self.context.currentContentSettings.with { $0 }) == nil {
                                    if let infoController = self.context.sharedContext.makePeerInfoController(context: self.context, updatedPresentationData: self.updatedPresentationData, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
                                        (self.navigationController as? NavigationController)?.pushViewController(infoController)
                                    }
                                }
                            }))
                            commit()
                        case let .withBotStartPayload(startPayload):
                            dismissWebAppControllers()
                            if let navigationController = self.navigationController as? NavigationController {
                                self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: self.context, chatLocation: .peer(peerId), botStart: startPayload, keepStack: .always))
                            }
                            commit()
                        case let .withAttachBot(attachBotStart):
                            dismissWebAppControllers()
                            if let navigationController = self.navigationController as? NavigationController {
                                self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: self.context, chatLocation: .peer(peerId), attachBotStart: attachBotStart))
                            }
                            commit()
                        case let .withBotApp(botAppStart):
                            let _ = (
                                self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId.id))
                                |> deliverOnMainQueue
                            ).startStandalone(next: { [weak self] peer in
                                if let self = self,
                                   let peer,
                                   let botApp = botAppStart.botApp
                                {
                                    self.presentBotApp(
                                        botApp: botApp,
                                        botPeer: peer,
                                        peerId: peer.id,
                                        payload: botAppStart.payload,
                                        compact: botAppStart.compact,
                                        concealed: concealed,
                                        commit: {
                                            dismissWebAppControllers()
                                            commit()
                                        }
                                    )
                                }
                            })
                        default:
                            break
                        }
                    },
                    sendFile: nil,
                    sendSticker: nil,
                    sendEmoji: nil,
                    requestMessageActionUrlAuth: nil,
                    joinVoiceChat: nil,
                    present: { [weak self] c, a in
                        if c is UndoOverlayController {
                            self?.rootTabController?.currentController?.present(c, in: .current)
                        } else {
                            self?.rootTabController?.currentController?.present(c, in: .window(.root), with: a)
                        }
                    },
                    dismissInput: { [weak self] in
                        self?.view.endEditing(true)
                    },
                    contentContext: nil,
                    progress: progress,
                    completion: nil
                )
            },
            progress: progress
        )
        
        self.navigationActionDisposable.set(disposable)
    }
    
    func openApplication(url: String) {
        self.openBotAppFromURL(
            context: self.context,
            url: url,
            navigationController: self.rootTabController?.currentController?.navigationController as? NavigationController,
            dismissInput: { [weak self] in
                self?.view.endEditing(true)
            }
        )
    }
}

//Xcode 16
#if canImport(ContactProvider)
extension MediaEditorScreen.Result: @retroactive MediaEditorScreenResult {
    public var target: Stories.PendingTarget {
        if let sendAsPeerId = self.options.sendAsPeerId {
            return .peer(sendAsPeerId)
        } else {
            return .myStories
        }
    }
}
#else
extension MediaEditorScreen.Result: MediaEditorScreenResult {
    public var target: Stories.PendingTarget {
        if let sendAsPeerId = self.options.sendAsPeerId {
            return .peer(sendAsPeerId)
        } else {
            return .myStories
        }
    }
}
#endif
