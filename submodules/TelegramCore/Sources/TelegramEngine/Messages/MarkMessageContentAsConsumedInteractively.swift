import Foundation
import NagramSettings // MARK: NEXTGRAM
import Postbox
import TelegramApi
import SwiftSignalKit

func _internal_markMessageContentAsConsumedInteractively(postbox: Postbox, messageId: MessageId) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        if let message = transaction.getMessage(messageId), message.flags.contains(.Incoming) {
            var updateMessage = false
            var updatedAttributes = message.attributes
            var updatedTags = message.tags // MARK: NEXTGRAM
            
            for i in 0 ..< updatedAttributes.count {
                if let attribute = updatedAttributes[i] as? ConsumableContentMessageAttribute {
                    if !attribute.consumed {
                        updatedAttributes[i] = ConsumableContentMessageAttribute(consumed: true)
                        updateMessage = true
                        
                        if message.id.peerId.namespace == Namespaces.Peer.SecretChat && !NagramSettings.shared.suppressReadReceipts { // MARK: NEXTGRAM
                            if let state = transaction.getPeerChatState(message.id.peerId) as? SecretChatState {
                                var layer: SecretChatLayer?
                                switch state.embeddedState {
                                    case .terminated, .handshake:
                                        break
                                    case .basicLayer:
                                        layer = .layer8
                                    case let .sequenceBasedLayer(sequenceState):
                                        layer = sequenceState.layerNegotiationState.activeLayer.secretChatLayer
                                }
                                if let layer = layer {
                                    var globallyUniqueIds: [Int64] = []
                                    if let globallyUniqueId = message.globallyUniqueId {
                                        globallyUniqueIds.append(globallyUniqueId)
                                        let updatedState = addSecretChatOutgoingOperation(transaction: transaction, peerId: message.id.peerId, operation: SecretChatOutgoingOperationContents.readMessagesContent(layer: layer, actionGloballyUniqueId: Int64.random(in: Int64.min ... Int64.max), globallyUniqueIds: globallyUniqueIds), state: state)
                                        if updatedState != state {
                                            transaction.setPeerChatState(message.id.peerId, state: updatedState)
                                        }
                                    }
                                }
                            }
                        } else if !NagramSettings.shared.suppressReadReceipts { // MARK: NEXTGRAM
                            addSynchronizeConsumeMessageContentsOperation(transaction: transaction, messageIds: [message.id])
                        }
                    }
                } else if let attribute = updatedAttributes[i] as? ConsumablePersonalMentionMessageAttribute, !attribute.consumed {
                    // MARK: NEXTGRAM — Local mention state is independent of its read receipt.
                    if NagramSettings.shared.suppressReadReceipts {
                        updatedAttributes[i] = ConsumablePersonalMentionMessageAttribute(consumed: true, pending: false)
                        updatedTags.remove(.unseenPersonalMessage)
                        updateMessage = true
                    } else {
                        transaction.setPendingMessageAction(type: .consumeUnseenPersonalMessage, id: messageId, action: ConsumePersonalMessageAction())
                        updatedAttributes[i] = ConsumablePersonalMentionMessageAttribute(consumed: attribute.consumed, pending: true)
                    }
                }
            }
            
            let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
            for i in 0 ..< updatedAttributes.count {
                if let attribute = updatedAttributes[i] as? AutoremoveTimeoutMessageAttribute {
                    if attribute.countdownBeginTime == nil || attribute.countdownBeginTime == 0 {
                        var timeout = attribute.timeout
                        if let duration = message.secretMediaDuration {
                            timeout = max(timeout, Int32(duration))
                        }
                        updatedAttributes[i] = AutoremoveTimeoutMessageAttribute(timeout: timeout, countdownBeginTime: timestamp)
                        updateMessage = true
                        
                        if messageId.peerId.namespace == Namespaces.Peer.SecretChat && !NagramSettings.shared.suppressReadReceipts { // MARK: NEXTGRAM
                            var layer: SecretChatLayer?
                            let state = transaction.getPeerChatState(message.id.peerId) as? SecretChatState
                            if let state = state {
                                switch state.embeddedState {
                                    case .terminated, .handshake:
                                        break
                                    case .basicLayer:
                                        layer = .layer8
                                    case let .sequenceBasedLayer(sequenceState):
                                        layer = sequenceState.layerNegotiationState.activeLayer.secretChatLayer
                                }
                            }
                            
                            if let state = state, let layer = layer, let globallyUniqueId = message.globallyUniqueId {
                                let updatedState = addSecretChatOutgoingOperation(transaction: transaction, peerId: messageId.peerId, operation: .readMessagesContent(layer: layer, actionGloballyUniqueId: Int64.random(in: Int64.min ... Int64.max), globallyUniqueIds: [globallyUniqueId]), state: state)
                                if updatedState != state {
                                    transaction.setPeerChatState(messageId.peerId, state: updatedState)
                                }
                            }
                        }
                    }
                } else if let attribute = updatedAttributes[i] as? AutoclearTimeoutMessageAttribute {
                    if attribute.countdownBeginTime == nil || attribute.countdownBeginTime == 0 {
                        var timeout = attribute.timeout
                        if let duration = message.secretMediaDuration, timeout != viewOnceTimeout {
                            timeout = max(timeout, Int32(duration))
                        }
                        updatedAttributes[i] = AutoclearTimeoutMessageAttribute(timeout: timeout, countdownBeginTime: timestamp)
                        updateMessage = true
                        
                        if messageId.peerId.namespace == Namespaces.Peer.SecretChat && !NagramSettings.shared.suppressReadReceipts { // MARK: NEXTGRAM
                            var layer: SecretChatLayer?
                            let state = transaction.getPeerChatState(message.id.peerId) as? SecretChatState
                            if let state = state {
                                switch state.embeddedState {
                                    case .terminated, .handshake:
                                        break
                                    case .basicLayer:
                                        layer = .layer8
                                    case let .sequenceBasedLayer(sequenceState):
                                        layer = sequenceState.layerNegotiationState.activeLayer.secretChatLayer
                                }
                            }
                            
                            if let state = state, let layer = layer, let globallyUniqueId = message.globallyUniqueId {
                                let updatedState = addSecretChatOutgoingOperation(transaction: transaction, peerId: messageId.peerId, operation: .readMessagesContent(layer: layer, actionGloballyUniqueId: Int64.random(in: Int64.min ... Int64.max), globallyUniqueIds: [globallyUniqueId]), state: state)
                                if updatedState != state {
                                    transaction.setPeerChatState(messageId.peerId, state: updatedState)
                                }
                            }
                        }
                    }
                }
            }
            
            if updateMessage {
                transaction.updateMessage(message.id, update: { currentMessage in
                    var storeForwardInfo: StoreMessageForwardInfo?
                    if let forwardInfo = currentMessage.forwardInfo {
                        storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                    }
                    return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: updatedTags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: currentMessage.media))
                })
            }
        }
    }
}

func _internal_markReactionsOrPollVotesAsSeenInteractively(postbox: Postbox, messageId: MessageId) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        if let message = transaction.getMessage(messageId), (message.tags.contains(.unseenReaction) || message.tags.contains(.unseenPollVote)) {
            var updateMessage = false
            var updatedAttributes = message.attributes
            var updatedMedia = message.media
            
            for i in 0 ..< updatedAttributes.count {
                if let attribute = updatedAttributes[i] as? ReactionsMessageAttribute, attribute.hasUnseen {
                    updatedAttributes[i] = attribute.withAllSeen()
                    updateMessage = true
                    
                    if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                    } else {
                        if !NagramSettings.shared.suppressReadReceipts { // MARK: NEXTGRAM
                            transaction.setPendingMessageAction(type: .readReactionOrPollVote, id: messageId, action: ReadReactionAction())
                        }
                    }
                }
            }
            for i in 0 ..< updatedMedia.count {
                if let poll = updatedMedia[i] as? TelegramMediaPoll {
                    updatedMedia[i] = poll.withoutUnreadResults()
                    updateMessage = true
                    
                    if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                    } else {
                        if !NagramSettings.shared.suppressReadReceipts { // MARK: NEXTGRAM
                            transaction.setPendingMessageAction(type: .readReactionOrPollVote, id: messageId, action: ReadReactionAction())
                        }
                    }
                }
            }
            
            if updateMessage {
                transaction.updateMessage(message.id, update: { currentMessage in
                    var storeForwardInfo: StoreMessageForwardInfo?
                    if let forwardInfo = currentMessage.forwardInfo {
                        storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                    }
                    var tags = currentMessage.tags
                    tags.remove(.unseenReaction)
                    tags.remove(.unseenPollVote)
                    return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: updatedMedia))
                })
            }
        }
    }
}

func markMessageContentAsConsumedRemotely(transaction: Transaction, messageId: MessageId, consumeDate: Int32?) {
    if let message = transaction.getMessage(messageId) {
        var updateMessage = false
        var updatedAttributes = message.attributes
        var updatedMedia = message.media
        var updatedTags = message.tags
        
        for i in 0 ..< updatedAttributes.count {
            if let attribute = updatedAttributes[i] as? ConsumableContentMessageAttribute {
                if !attribute.consumed {
                    updatedAttributes[i] = ConsumableContentMessageAttribute(consumed: true)
                    updateMessage = true
                }
            } else if let attribute = updatedAttributes[i] as? ConsumablePersonalMentionMessageAttribute, !attribute.consumed {
                if attribute.pending {
                    transaction.setPendingMessageAction(type: .consumeUnseenPersonalMessage, id: messageId, action: nil)
                }
                updatedAttributes[i] = ConsumablePersonalMentionMessageAttribute(consumed: true, pending: false)
                updatedTags.remove(.unseenPersonalMessage)
                updateMessage = true
            }
        }
        
        let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        let countdownBeginTime = consumeDate ?? timestamp
        
        for i in 0 ..< updatedAttributes.count {
            if let attribute = updatedAttributes[i] as? AutoremoveTimeoutMessageAttribute {
                if (attribute.countdownBeginTime == nil || attribute.countdownBeginTime == 0) && message.containsSecretMedia {
                    updatedAttributes[i] = AutoremoveTimeoutMessageAttribute(timeout: attribute.timeout, countdownBeginTime: countdownBeginTime)
                    updateMessage = true
                                 
                    if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                    } else {
                        if attribute.timeout == viewOnceTimeout || timestamp >= autoremoveExpiryTimestamp(countdownBeginTime: countdownBeginTime, timeout: attribute.timeout) {
                            for i in 0 ..< updatedMedia.count {
                                if let _ = updatedMedia[i] as? TelegramMediaImage {
                                    updatedMedia[i] = TelegramMediaExpiredContent(data: .image)
                                } else if let file = updatedMedia[i] as? TelegramMediaFile {
                                    if file.isInstantVideo {
                                        updatedMedia[i] = TelegramMediaExpiredContent(data: .videoMessage)
                                    } else if file.isVoice {
                                        updatedMedia[i] = TelegramMediaExpiredContent(data: .voiceMessage)
                                    } else {
                                        updatedMedia[i] = TelegramMediaExpiredContent(data: .file)
                                    }
                                }
                            }
                        }
                    }
                }
            } else if let attribute = updatedAttributes[i] as? AutoclearTimeoutMessageAttribute {
                if (attribute.countdownBeginTime == nil || attribute.countdownBeginTime == 0) && message.containsSecretMedia {
                    updatedAttributes[i] = AutoclearTimeoutMessageAttribute(timeout: attribute.timeout, countdownBeginTime: countdownBeginTime)
                    updateMessage = true
                    
                    if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                    } else {
                        for i in 0 ..< updatedMedia.count {
                            if attribute.timeout == viewOnceTimeout || timestamp >= autoremoveExpiryTimestamp(countdownBeginTime: countdownBeginTime, timeout: attribute.timeout) {
                                if let _ = updatedMedia[i] as? TelegramMediaImage {
                                    updatedMedia[i] = TelegramMediaExpiredContent(data: .image)
                                } else if let file = updatedMedia[i] as? TelegramMediaFile {
                                    if file.isInstantVideo {
                                        updatedMedia[i] = TelegramMediaExpiredContent(data: .videoMessage)
                                    } else if file.isVoice {
                                        updatedMedia[i] = TelegramMediaExpiredContent(data: .voiceMessage)
                                    } else {
                                        updatedMedia[i] = TelegramMediaExpiredContent(data: .file)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        if updateMessage {
            transaction.updateMessage(message.id, update: { currentMessage in
                var storeForwardInfo: StoreMessageForwardInfo?
                if let forwardInfo = currentMessage.forwardInfo {
                    storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                }
                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: updatedTags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: updatedMedia))
            })
        }
    }
}


// MARK: NEXTGRAM — Use the normal expiry pipeline, and never expire ordinary media.
func _internal_expireMessageMediaLocally(postbox: Postbox, network: Network, messageId: MessageId) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        guard let message = transaction.getMessage(messageId),
              message.autoclearAttribute != nil || message.autoremoveAttribute != nil,
              message.media.contains(where: { media in
                  media is TelegramMediaImage || (media as? TelegramMediaFile)?.isVideo == true
              }) else {
            return
        }
        let timestamp = Int32(clamping: Int64(Date().timeIntervalSince1970 + network.globalTimeDifference)) - 1
        transaction.updateMessage(messageId, update: { currentMessage in
            let attributes: [MessageAttribute] = currentMessage.attributes.map { attribute in
                if attribute is AutoclearTimeoutMessageAttribute {
                    return AutoclearTimeoutMessageAttribute(timeout: 1, countdownBeginTime: timestamp)
                } else if attribute is AutoremoveTimeoutMessageAttribute {
                    return AutoremoveTimeoutMessageAttribute(timeout: 1, countdownBeginTime: timestamp)
                }
                return attribute
            }
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
        })
    }
}
