//
//  ImageCommentsStateObject.swift
//  Picroup-iOS
//
//  Created by luojie on 2018/5/16.
//  Copyright © 2018年 luojie. All rights reserved.
//

import Foundation
import RealmSwift
import RxSwift
import RxCocoa
import RxRealm

final class ImageCommentsStateObject: PrimaryObject {
    
    @objc dynamic var session: UserSessionObject?
    
    @objc dynamic var medium: MediumObject?
    
    @objc dynamic var comments: CursorCommentsObject?
    @objc dynamic var commentsError: String?
    @objc dynamic var triggerCommentsQuery: Bool = false
    
    @objc dynamic var saveCommentContent: String = ""
    @objc dynamic var saveCommentVersion: String?
    @objc dynamic var saveCommentError: String?
    @objc dynamic var triggerSaveComment: Bool = false
    
    @objc dynamic var popRoute: PopRouteObject?
}

extension ImageCommentsStateObject {
    var mediumId: String { return _id }
    var commentsQuery: MediumCommentsQuery? {
        let next = MediumCommentsQuery(mediumId: mediumId, cursor: comments?.cursor.value)
        return triggerCommentsQuery ? next : nil
    }
    var shouldQueryMoreComments: Bool {
        return !triggerCommentsQuery && hasMoreComments
    }
    var hasMoreComments: Bool {
        return comments?.cursor.value != nil
    }
    var shouldSendComment: Bool {
        return !triggerSaveComment && !saveCommentContent.isEmpty
    }
    public var saveCommentQuery: SaveCommentMutation? {
        guard let userId = session?.currentUser?._id else { return nil }
        let next = SaveCommentMutation(userId: userId, mediumId: mediumId, content: saveCommentContent)
        return triggerSaveComment ? next : nil
    }
}

private let commentsId: (String) -> String = { "imageCommentsState.\($0).comments" }

extension ImageCommentsStateObject {
    
    static func create(mediumId: String) -> (Realm) throws -> ImageCommentsStateObject {
        return { realm in
            let _id = Config.realmDefaultPrimaryKey
            let value: Any = [
                "_id": mediumId,
                "session": ["_id": _id],
                "medium": ["_id": mediumId],
                "comments": ["_id": commentsId(mediumId)],
                "popRoute": ["_id": _id],
                ]
            return try realm.findOrCreate(ImageCommentsStateObject.self, forPrimaryKey: mediumId, value: value)
        }
    }
}

extension ImageCommentsStateObject {
    
    enum Event {
        case onTriggerReloadData
        case onTriggerGetMoreData
        case onGetReloadData(CursorCommentsFragment)
        case onGetMoreData(CursorCommentsFragment)
        case onGetDataError(Error)
        
        case onTriggerSaveComment
        case onSaveCommentSuccess(CommentFragment)
        case onSaveCommentError(Error)
        
        case onChangeCommentContent(String)

        case onTriggerPop
    }
}

extension ImageCommentsStateObject.Event {
    
    static func onGetData(isReload: Bool) -> (CursorCommentsFragment) -> ImageCommentsStateObject.Event {
        return { isReload ? .onGetReloadData($0) : .onGetMoreData($0) }
    }
}

extension ImageCommentsStateObject: IsFeedbackStateObject {
    
    func reduce(event: Event, realm: Realm) {
        switch event {
        case .onTriggerReloadData:
            comments?.cursor.value = nil
            commentsError = nil
            triggerCommentsQuery = true
        case .onTriggerGetMoreData:
            guard shouldQueryMoreComments else { return }
            commentsError = nil
            triggerCommentsQuery = true
        case .onGetReloadData(let data):
            comments = CursorCommentsObject.create(from: data, id: commentsId(_id))(realm)
            commentsError = nil
            triggerCommentsQuery = false
        case .onGetMoreData(let data):
            comments?.merge(from: data)(realm)
            commentsError = nil
            triggerCommentsQuery = false
        case .onGetDataError(let error):
            commentsError = error.localizedDescription
            triggerCommentsQuery = false
        case .onTriggerSaveComment:
            guard shouldSendComment else { return }
            saveCommentVersion = nil
            saveCommentError = nil
            triggerSaveComment = true
        case .onSaveCommentSuccess(let data):
            let comment = realm.create(CommentObject.self, value: data.snapshot, update: true)
            comments?.items.insert(comment, at: 0)
            medium?.commentsCount.value?.increase(1)
            saveCommentVersion = UUID().uuidString
            saveCommentError = nil
            triggerSaveComment = false
            saveCommentContent = ""
        case .onSaveCommentError(let error):
            saveCommentVersion = nil
            saveCommentError = error.localizedDescription
            triggerSaveComment = false
        case .onChangeCommentContent(let content):
            saveCommentContent = content
        case .onTriggerPop:
            popRoute?.version = UUID().uuidString
        }
    }
}

final class ImageCommentsStateStore {
    
    let states: Driver<ImageCommentsStateObject>
    private let _state: ImageCommentsStateObject
    private let mediumId: String
    
    init(mediumId: String) throws {
        let realm = try Realm()
        let _state = try ImageCommentsStateObject.create(mediumId: mediumId)(realm)
        let states = Observable.from(object: _state).asDriver(onErrorDriveWith: .empty())
        
        self.mediumId = mediumId
        self._state = _state
        self.states = states
    }
    
    func on(event: ImageCommentsStateObject.Event) {
        Realm.backgroundReduce(ofType: ImageCommentsStateObject.self, forPrimaryKey: mediumId, event: event)
    }
    
    func medium() -> Driver<MediumObject> {
        guard let medium = _state.medium else { return .empty() }
        return Observable.from(object: medium).asDriver(onErrorDriveWith: .empty())
    }
    
    func commentsItems() -> Driver<[CommentObject]> {
        guard let items = _state.comments?.items else { return .empty() }
        return Observable.collection(from: items).asDriver(onErrorDriveWith: .empty())
            .map { $0.toArray() }
    }
}
