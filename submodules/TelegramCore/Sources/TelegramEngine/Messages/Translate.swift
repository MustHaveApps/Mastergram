import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

func _internal_translate(network: Network, text: String, fromLang: String?, toLang: String) -> Signal<String?, NoError> {
    #if DEBUG
    return .single(nil)
    #else
    
    var flags: Int32 = 0
    flags |= (1 << 1)

    return network.request(Api.functions.messages.translateText(flags: flags, peer: nil, id: nil, text: [.textWithEntities(text: text, entities: [])], toLang: toLang))
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.messages.TranslatedText?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<String?, NoError> in
        guard let result = result else {
            return .complete()
        }
        switch result {
        case .translateNoResult:
            return .single(nil)
        case let .translateResultText(text):
            return .single(text)
        case let .translateResult(results):
            if case let .textWithEntities(text, _) = results.first {
                return .single(text)
            } else {
                return .single(nil)
            }
        }
    }
    #endif
}

func _internal_translateMessages(postbox: Postbox, network: Network, messageIds: [EngineMessage.Id], toLang: String) -> Signal<Void, NoError> {
    guard let peerId = messageIds.first?.peerId else {
        return .never()
    }
    return postbox.transaction { transaction -> Api.InputPeer? in
        return transaction.getPeer(peerId).flatMap(apiInputPeer)
    }
    |> mapToSignal { inputPeer -> Signal<Void, NoError> in
        guard let inputPeer = inputPeer else {
            return .never()
        }
        
        var flags: Int32 = 0
        flags |= (1 << 0)
        
        let id: [Int32] = messageIds.map { $0.id }
        return network.request(Api.functions.messages.translateText(flags: flags, peer: inputPeer, id: id, text: nil, toLang: toLang))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.messages.TranslatedText?, NoError> in
            return .single(nil)
        }
        |> mapToSignal { result -> Signal<Void, NoError> in
            guard let result = result, case let .translateResult(results) = result else {
                return .complete()
            }
            return postbox.transaction { transaction in
                var index = 0
                for result in results {
                    let messageId = messageIds[index]
                    if case let .textWithEntities(text, entities) = result {
                        let updatedAttribute: TranslationMessageAttribute = TranslationMessageAttribute(text: text, entities: messageTextEntitiesFromApiEntities(entities), toLang: toLang)
                        transaction.updateMessage(messageId, update: { currentMessage in
                            let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                            var attributes = currentMessage.attributes.filter { !($0 is TranslationMessageAttribute) }
                            
                            attributes.append(updatedAttribute)
                            
                            return .update(StoreMessage(id: currentMessage.id, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                        })
                    }
                    index += 1
                }
            }
        }
    }
}

public enum EngineAudioTranscriptionResult {
    case success
    case error
}

func _internal_transcribeAudio(postbox: Postbox, network: Network, messageId: MessageId) -> Signal<EngineAudioTranscriptionResult, NoError> {
    return postbox.transaction { transaction -> Api.InputPeer? in
        return transaction.getPeer(messageId.peerId).flatMap(apiInputPeer)
    }
    |> mapToSignal { inputPeer -> Signal<EngineAudioTranscriptionResult, NoError> in
        guard let inputPeer = inputPeer else {
            return .single(.error)
        }
        return network.request(Api.functions.messages.transcribeAudio(peer: inputPeer, msgId: messageId.id))
        |> map { result -> Result<Api.messages.TranscribedAudio, AudioTranscriptionMessageAttribute.TranscriptionError> in
            return .success(result)
        }
        |> `catch` { error -> Signal<Result<Api.messages.TranscribedAudio, AudioTranscriptionMessageAttribute.TranscriptionError>, NoError> in
            let mappedError: AudioTranscriptionMessageAttribute.TranscriptionError
            if error.errorDescription == "MSG_VOICE_TOO_LONG" {
                mappedError = .tooLong
            } else {
                mappedError = .generic
            }
            return .single(.failure(mappedError))
        }
        |> mapToSignal { result -> Signal<EngineAudioTranscriptionResult, NoError> in
            return postbox.transaction { transaction -> EngineAudioTranscriptionResult in
                let updatedAttribute: AudioTranscriptionMessageAttribute
                switch result {
                case let .success(transcribedAudio):
                    switch transcribedAudio {
                    case let .transcribedAudio(flags, transcriptionId, text):
                        let isPending = (flags & (1 << 0)) != 0
                        
                        updatedAttribute = AudioTranscriptionMessageAttribute(id: transcriptionId, text: text, isPending: isPending, didRate: false, error: nil)
                    }
                case let .failure(error):
                    updatedAttribute = AudioTranscriptionMessageAttribute(id: 0, text: "", isPending: false, didRate: false, error: error)
                }
                    
                transaction.updateMessage(messageId, update: { currentMessage in
                    let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                    var attributes = currentMessage.attributes.filter { !($0 is AudioTranscriptionMessageAttribute) }
                    
                    attributes.append(updatedAttribute)
                    
                    return .update(StoreMessage(id: currentMessage.id, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                })
                
                if updatedAttribute.error == nil {
                    return .success
                } else {
                    return .error
                }
            }
        }
    }
}

func _internal_rateAudioTranscription(postbox: Postbox, network: Network, messageId: MessageId, id: Int64, isGood: Bool) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> Api.InputPeer? in
        transaction.updateMessage(messageId, update: { currentMessage in
            var storeForwardInfo: StoreMessageForwardInfo?
            if let forwardInfo = currentMessage.forwardInfo {
                storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
            }
            var attributes = currentMessage.attributes
            for i in 0 ..< attributes.count {
                if let attribute = attributes[i] as? AudioTranscriptionMessageAttribute {
                    attributes[i] = attribute.withDidRate()
                }
            }
            return .update(StoreMessage(
                id: currentMessage.id,
                globallyUniqueId: currentMessage.globallyUniqueId,
                groupingKey: currentMessage.groupingKey,
                threadId: currentMessage.threadId,
                timestamp: currentMessage.timestamp,
                flags: StoreMessageFlags(currentMessage.flags),
                tags: currentMessage.tags,
                globalTags: currentMessage.globalTags,
                localTags: currentMessage.localTags,
                forwardInfo: storeForwardInfo,
                authorId: currentMessage.author?.id,
                text: currentMessage.text,
                attributes: attributes,
                media: currentMessage.media
            ))
        })
        
        return transaction.getPeer(messageId.peerId).flatMap(apiInputPeer)
    }
    |> mapToSignal { inputPeer -> Signal<Never, NoError> in
        guard let inputPeer = inputPeer else {
            return .complete()
        }
        return network.request(Api.functions.messages.rateTranscribedAudio(peer: inputPeer, msgId: messageId.id, transcriptionId: id, good: isGood ? .boolTrue : .boolFalse))
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> ignoreValues
    }
}
